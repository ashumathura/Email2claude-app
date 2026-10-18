# Email2Claude

Menu-bar app for Apple Silicon Macs. Select an email in Mail, press **⌥⌘C**, and the email
(text, headers, attachments) is pasted into a Claude desktop chat chosen by the recipient address.

## Setup
1. Install the DMG, open the app (it lives in the menu bar, no Dock icon).
2. Grant **Accessibility** (System Settings → Privacy & Security) so it can read Claude's chat list and paste.
3. First hotkey press asks for **Automation** access to Mail. Allow it.
4. Menu bar icon → **Routes…** to map To addresses (or `@domain.com`) to Claude chats. Pick a chat from
   the list read from Claude's sidebar, or paste a chat link (more reliable; it wins over the list).
5. If you press ⌥⌘C on an email whose To address has no route, the app asks which chat to use and remembers it.

Only the To addresses are matched. Config lives in `~/Library/Application Support/Email2Claude/config.json`
(routes, instruction text, `autoSend`, `openDelay`).

## Build
- `swift test` — routing/formatting tests (macOS)
- `./scripts/package.sh` — builds `dist/Email2Claude.dmg`
- CI (`.github/workflows/build.yml`) does the same on an Apple Silicon runner. For a notarized DMG
  set secrets `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `MACOS_SIGN_IDENTITY`, `APPLE_ID`,
  `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`. Without them the DMG is ad-hoc signed (right-click → Open).

## Unverified assumptions (check on a Mac first)
- Claude desktop bundle id `com.anthropic.claudefordesktop` and `claude://claude.ai/chat/<id>` deep links.
- Claude's sidebar can be read via Accessibility (`ClaudeSidebar.swift` heuristics, likely needs tuning); chats are opened by pressing the row with the saved title, so titles must be unique and visible.
- Claude's input box is focused after the chat opens, and ⌘V of a file attaches it.
- Mail allows `save attachment` into the temp folder.
