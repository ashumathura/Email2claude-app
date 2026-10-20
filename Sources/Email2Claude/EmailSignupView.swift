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

                FormSection(
                    nil,
                    note: errorText ?? PrivacyText.emailNote,
                    noteIsWarning: errorText != nil) {
                    FormRow("Email address") {
                        TextField("", text: $email, prompt: Text("you@example.com"))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 300)
                            .disabled(working)
                            .onSubmit(submit)
                            .onChange(of: email) { _ in errorText = nil }
                    }
                }

                Text("Without a key the app keeps working, but it can't download updates. You can get a key later in Settings → License.")
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
        .frame(width: 560, height: 440)
        .background(Look.page)
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
                Log.write("license sign-up failed: \(error.localizedDescription)")
                errorText = error.localizedDescription
                working = false
            }
        }
        // Never leave the screen spinning: if nothing came back, say so and let the user try again or skip.
        Task {
            try? await Task.sleep(for: .seconds(25))
            if working {
                Log.write("license sign-up: no answer after 25 s")
                errorText = "The server didn't answer. Check your internet connection and try again, or skip for now and get a key later in Settings."
                working = false
            }
        }
    }
}

@MainActor
enum EmailSignup {
    private static var window: NSWindow?

    /// Shows the screen as an ordinary window (not a blocking modal, whose run loop can starve the
    /// network request) and calls `onClose` once a key was issued or the user skipped.
    static func show(updates: UpdateManager, onClose: @escaping () -> Void) {
        let view = EmailSignupView(
            register: { try await updates.registerLicense(email: $0) },
            onDone: {
                window?.orderOut(nil)
                window = nil
                onClose()
            })
        let panel = NSWindow(contentViewController: NSHostingController(rootView: view))
        panel.styleMask = [.titled]
        panel.title = "MailtoChat"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.center()
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
