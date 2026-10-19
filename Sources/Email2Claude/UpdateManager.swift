import AppKit
import Email2ClaudeCore

/// Weekly update and license check, plus the check-in that records usage.
///
/// On launch it checks in; if a week has passed since the last update check it also asks for updates.
/// The server only returns a download link when the license passes.
@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var busy = false
    /// The latest result, shown in Settings.
    @Published private(set) var status = ""

    private let store: ConfigStore
    private var timer: Timer?
    private let interval: TimeInterval = 7 * 24 * 3600
    private let notifiedBlockedKey = "notifiedBlockedVersion"

    init(store: ConfigStore) { self.store = store }

    private var updateCheckDue: Bool {
        store.config.lastUpdateCheck.map { Date().timeIntervalSince($0) >= interval } ?? true
    }

    // MARK: Entry points

    func start() {
        guard BackendConfig.isPackagedApp else { return }
        Task { await run(event: .open, manual: false) }
        // The app can stay open for weeks, so re-check whether the weekly check is due.
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.run(event: .updateCheck, manual: false) }
        }
    }

    func checkNow() {
        Task { await run(event: .updateCheck, manual: true) }
    }

    /// Tell the server about a changed analytics choice right away, so opting out clears the data now.
    func syncConsent() {
        guard BackendConfig.isPackagedApp else { return }
        Task { await run(event: .consentChange, manual: false, wantsUpdate: false) }
    }

    /// Deletes everything stored for this install on the server, and starts a new random ID.
    func erase() async {
        guard BackendConfig.isPackagedApp else { return }
        var request = makeRequest(event: .consentChange, wantsUpdate: false)
        request.action = "erase"
        do {
            _ = try await CheckinClient.send(request)
            DeviceID.reset()
            status = "Your data was erased from the server."
        } catch {
            status = "Couldn't erase your data: \(error.localizedDescription)"
            alert("Couldn't erase your data", error.localizedDescription)
        }
    }

    // MARK: Check-in

    private func makeRequest(event: CheckinRequest.Event, wantsUpdate: Bool) -> CheckinRequest {
        let config = store.config
        return CheckinRequest(
            deviceId: DeviceID.current(), event: event, analytics: config.analyticsChoice == .shared,
            wantsUpdate: wantsUpdate, appVersion: BackendConfig.appVersion,
            macosVersion: BackendConfig.systemVersion, osLanguage: Locale.preferredLanguages.first ?? "",
            licenseKey: config.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func run(event: CheckinRequest.Event, manual: Bool, wantsUpdate: Bool? = nil) async {
        guard !busy else { return }
        let wants = wantsUpdate ?? (manual || updateCheckDue)
        // Timer ticks only matter when the weekly check has come due.
        if event == .updateCheck && !manual && !wants { return }

        busy = true
        defer { busy = false }
        do {
            let response = try await CheckinClient.send(makeRequest(event: event, wantsUpdate: wants))
            guard wants else { return }
            store.config.lastUpdateCheck = Date()
            store.config.lastLicenseStatus = response.license
            await handle(response, manual: manual)
        } catch {
            Log.write("check-in failed: \(error.localizedDescription)")
            if wants { status = "Couldn't check for updates: \(error.localizedDescription)" }
            if manual { alert("Couldn't check for updates", error.localizedDescription) }
        }
    }

    private func handle(_ response: CheckinResponse, manual: Bool) async {
        if let update = response.update {
            guard Checkin.meetsMinimum(system: BackendConfig.systemVersion, minimum: update.minMacos) else {
                status = "Version \(update.version) needs macOS \(update.minMacos ?? "")."
                if manual { alert("Update not available", "Version \(update.version) needs macOS \(update.minMacos ?? "a newer version").") }
                return
            }
            status = "Version \(update.version) is available."
            if confirmInstall(update) { await install(update) }
        } else if let blocked = response.updateBlocked {
            status = "Version \(blocked.version) is available, but \(Checkin.explain(licenseStatus: blocked.reason))."
            let seen = UserDefaults.standard.string(forKey: notifiedBlockedKey)
            if manual || seen != blocked.version {
                UserDefaults.standard.set(blocked.version, forKey: notifiedBlockedKey)
                alert(
                    "Version \(blocked.version) is available",
                    "It can't be downloaded because \(Checkin.explain(licenseStatus: blocked.reason)). Enter a valid license key in Settings → License & Privacy.")
            }
        } else {
            status = "You're up to date (version \(BackendConfig.appVersion))."
            if manual { alert("You're up to date", "eMail to Claude \(BackendConfig.appVersion) is the latest version.") }
        }
    }

    // MARK: Installing

    private func confirmInstall(_ update: UpdateInfo) -> Bool {
        let panel = NSAlert()
        panel.messageText = "eMail to Claude \(update.version) is available"
        var text = "You have version \(BackendConfig.appVersion)."
        if let notes = update.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            text += "\n\n" + String(notes.prefix(800))
        }
        panel.informativeText = text
        panel.addButton(withTitle: "Update and Restart")
        panel.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .alertFirstButtonReturn
    }

    private func install(_ update: UpdateInfo) async {
        let progress = UpdateProgressWindow(version: update.version)
        progress.show()
        var downloaded: URL?
        do {
            let dmg = try await UpdateInstaller.Downloader.download(update.url) { fraction in
                Task { @MainActor in progress.set(fraction: fraction, text: "Downloading…") }
            }
            downloaded = dmg
            progress.set(fraction: nil, text: "Verifying…")
            let sha = try await Task.detached { try UpdateInstaller.sha256(of: dmg) }.value
            guard sha.lowercased() == update.sha256.lowercased() else { throw UpdateError.badChecksum }

            progress.set(fraction: nil, text: "Preparing…")
            let staged = try await UpdateInstaller.stage(dmg: dmg, expectedVersion: update.version)

            progress.set(fraction: nil, text: "Restarting…")
            try UpdateInstaller.startReplacement(with: staged)
            try? FileManager.default.removeItem(at: dmg)
            NSApp.terminate(nil)
        } catch {
            progress.close()
            status = "Update failed: \(error.localizedDescription)"
            if let failure = error as? UpdateError, failure.allowsManualInstall, let dmg = downloaded {
                offerManualInstall(dmg: dmg, update: update, reason: failure.localizedDescription)
            } else {
                if let dmg = downloaded { try? FileManager.default.removeItem(at: dmg) }
                alert("The update couldn't be installed", error.localizedDescription)
            }
        }
    }

    /// The download is verified but can't replace the running app by itself: save it where the user can open it.
    private func offerManualInstall(dmg: URL, update: UpdateInfo, reason: String) {
        let panel = NSAlert()
        panel.messageText = "Install version \(update.version) yourself"
        panel.informativeText = "\(reason)\n\nThe update was downloaded. Open it, then drag eMail to Claude into Applications."
        panel.addButton(withTitle: "Open Installer")
        panel.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .alertFirstButtonReturn else {
            try? FileManager.default.removeItem(at: dmg)
            return
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let target = downloads.appendingPathComponent("eMail-to-Claude-\(update.version).dmg")
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.moveItem(at: dmg, to: target)
            NSWorkspace.shared.open(target)
        } catch {
            alert("Couldn't save the installer", error.localizedDescription)
        }
    }

    private func alert(_ title: String, _ message: String) {
        let panel = NSAlert()
        panel.messageText = title
        panel.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        panel.runModal()
    }
}

/// A small progress window shown while an update downloads.
@MainActor
final class UpdateProgressWindow {
    private let panel: NSPanel
    private let bar = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")

    init(version: String) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 96), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Updating eMail to Claude"
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        label.stringValue = "Downloading version \(version)…"
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1

        let stack = NSStackView(views: [label, bar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        panel.contentView = stack
        bar.widthAnchor.constraint(equalToConstant: 320).isActive = true
    }

    func show() {
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Pass nil for steps with no measurable progress.
    func set(fraction: Double?, text: String) {
        label.stringValue = text
        if let fraction {
            bar.isIndeterminate = false
            bar.doubleValue = fraction
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
    }

    func close() { panel.orderOut(nil) }
}
