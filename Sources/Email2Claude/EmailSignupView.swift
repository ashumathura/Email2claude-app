import AppKit
import SwiftUI
import Email2ClaudeCore

/// First-run screen: an email address in exchange for a free license key, saved in the app automatically.
struct EmailSignupView: View {
    let register: (String) async throws -> Void
    let onDone: () -> Void

    @State private var email = ""
    @State private var working = false
    @State private var errorText: String?

    private var valid: Bool { EmailAddress.isPlausible(email) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Get your free license key").font(.title2.weight(.semibold))
                        Text("Enter your email address and the app issues your license key and saves it for you. The key lets the app download updates.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .disabled(working)
                    .onSubmit(submit)
                    .onChange(of: email) { _ in errorText = nil }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(Brand.accent)
                    Text(PrivacyText.emailNote)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Brand.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("Without a key the app keeps working, but it can't download updates. You can get a key later in Settings → License & Privacy.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            Spacer(minLength: 0)
            Divider()

            HStack(spacing: 14) {
                Button("Skip for Now", action: onDone)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(working)
                    .keyboardShortcut(.cancelAction)
                Button(action: submit) {
                    if working { ProgressView().controlSize(.small) } else { Text("Get My License Key") }
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)
                .disabled(!valid || working)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 470)
        .tint(Brand.accent)
    }

    private func submit() {
        guard valid, !working else { return }
        working = true
        errorText = nil
        Task {
            do {
                try await register(email)
                onDone()
            } catch {
                errorText = error.localizedDescription
                working = false
            }
        }
    }
}

@MainActor
enum EmailSignup {
    /// Blocks until a key was issued or the user skips.
    static func run(updates: UpdateManager) {
        let view = EmailSignupView(
            register: { try await updates.registerLicense(email: $0) },
            onDone: { NSApp.stopModal() })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled]
        window.title = "eMail to Claude"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
        window.orderOut(nil)
    }
}
