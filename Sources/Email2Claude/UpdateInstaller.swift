import AppKit
import CryptoKit
import Security
import Email2ClaudeCore

enum UpdateError: LocalizedError {
    case badChecksum
    case noApp
    case wrongApp(String)
    case invalidSignature
    case cannotVerifyPublisher
    case publisherMismatch
    case cannotInstallHere(String)
    case tool(String)

    var errorDescription: String? {
        switch self {
        case .badChecksum: return "The download is damaged (its checksum doesn't match). Try again later."
        case .noApp: return "The download doesn't contain the app."
        case .wrongApp(let why): return "The download isn't the expected update: \(why)."
        case .invalidSignature: return "The downloaded app's code signature is not valid."
        case .cannotVerifyPublisher:
            return "This copy of the app isn't signed with the developer certificate, so it can't verify that the update comes from the same publisher."
        case .publisherMismatch: return "The downloaded app was signed by a different publisher than this one."
        case .cannotInstallHere(let why): return why
        case .tool(let what): return "Something went wrong while installing: \(what)."
        }
    }

    /// Cases where the DMG is fine but can't be swapped in automatically; the user can install it by hand.
    var allowsManualInstall: Bool {
        switch self {
        case .cannotVerifyPublisher, .cannotInstallHere: return true
        default: return false
        }
    }
}

/// Download, verification and replacement of the app. Everything here runs off the main actor.
enum UpdateInstaller {
    // MARK: Download

    final class Downloader: NSObject, URLSessionDownloadDelegate {
        private var continuation: CheckedContinuation<URL, Error>?
        private let progress: @Sendable (Double) -> Void

        private init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

        static func download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
            let downloader = Downloader(progress: progress)
            let session = URLSession(configuration: .ephemeral, delegate: downloader, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            return try await withCheckedThrowingContinuation { continuation in
                downloader.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        }

        func urlSession(
            _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 0 else { return }
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status != 200 {
                finish(.failure(CheckinClient.ServerError(status: status)))
                return
            }
            // The system deletes `location` when this method returns, so move the file first.
            let kept = FileManager.default.temporaryDirectory.appendingPathComponent("E2C-\(UUID().uuidString).dmg")
            do {
                try FileManager.default.moveItem(at: location, to: kept)
                finish(.success(kept))
            } catch {
                finish(.failure(error))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { finish(.failure(error)) }
        }

        private func finish(_ result: Result<URL, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    // MARK: Verification

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Checks that the code signature is intact and returns the signing team, or nil for ad-hoc signatures.
    static func signingTeam(of app: URL) throws -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode
        else { throw UpdateError.invalidSignature }
        let checks = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSStrictValidate) | UInt32(kSecCSCheckNestedCode))
        guard SecStaticCodeCheckValidity(code, checks, nil) == errSecSuccess else { throw UpdateError.invalidSignature }
        var info: CFDictionary?
        let infoFlags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(code, infoFlags, &info) == errSecSuccess, let dict = info as? [String: Any]
        else { throw UpdateError.invalidSignature }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// The update must be the same app (bundle ID), the version we were promised, newer than this one,
    /// and signed by the same developer team as the running app. A tampered download fails here
    /// even if the checksum and the link were both swapped.
    static func verify(staged app: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: app) else { throw UpdateError.noApp }
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier else { throw UpdateError.wrongApp("different app") }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard version == expectedVersion else { throw UpdateError.wrongApp("version \(version), expected \(expectedVersion)") }
        guard AppVersion.isNewer(version, than: BackendConfig.appVersion) else { throw UpdateError.wrongApp("not newer") }

        let newTeam = try signingTeam(of: app)
        // `try?` flattens the optional: nil here means "unsigned or ad-hoc", whether or not the check threw.
        guard let currentTeam = try? signingTeam(of: Bundle.main.bundleURL) else {
            throw UpdateError.cannotVerifyPublisher
        }
        guard newTeam == currentTeam else { throw UpdateError.publisherMismatch }
    }

    // MARK: Staging

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Mounts the DMG, copies the app out, verifies the copy and unmounts. Returns the staged app.
    static func stage(dmg: URL, expectedVersion: String) async throws -> URL {
        try await Task.detached {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("E2C-update-\(UUID().uuidString)")
            let mount = work.appendingPathComponent("mount")
            try fm.createDirectory(at: mount, withIntermediateDirectories: true)

            guard try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]) == 0
            else { throw UpdateError.tool("couldn't open the disk image") }
            defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

            guard let source = try fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
            else { throw UpdateError.noApp }

            let staged = work.appendingPathComponent(source.lastPathComponent)
            guard try run("/usr/bin/ditto", [source.path, staged.path]) == 0
            else { throw UpdateError.tool("couldn't copy the app") }

            try verify(staged: staged, expectedVersion: expectedVersion)
            return staged
        }.value
    }

    // MARK: Replacement

    /// Starts a helper that waits for this app to quit, swaps the bundle in place (keeping the old
    /// one until the copy succeeds) and reopens it. The caller must quit right after.
    static func startReplacement(with staged: URL) throws {
        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent()
        if destination.path.hasPrefix("/Volumes/") || destination.path.contains("/AppTranslocation/") {
            throw UpdateError.cannotInstallHere("Move MailtoChat to your Applications folder first, then update.")
        }
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.cannotInstallHere("This app can't replace itself in \(parent.path).")
        }

        // The update may carry a new app name (the file is renamed along with it), unless another
        // app of that name already sits next to this one; then the old file name is kept.
        let renamed = parent.appendingPathComponent(staged.lastPathComponent)
        let target = FileManager.default.fileExists(atPath: renamed.path) ? destination : renamed

        let script = """
        #!/bin/bash
        PID="$1"; SRC="$2"; DEST="$3"; TARGET="$4"
        for _ in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        BACKUP="${DEST}.old"
        OPEN="$DEST"
        rm -rf "$BACKUP"
        if mv "$DEST" "$BACKUP"; then
          if ditto "$SRC" "$TARGET"; then
            rm -rf "$BACKUP" "$SRC"
            OPEN="$TARGET"
          else
            rm -rf "$TARGET"; mv "$BACKUP" "$DEST"
          fi
        fi
        open "$OPEN"
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("E2C-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/bash", scriptURL.path, String(ProcessInfo.processInfo.processIdentifier), staged.path, destination.path, target.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }
}
