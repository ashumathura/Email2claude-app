# Email2Claude

Menu-bar app for Apple Silicon Macs. Select an email in Mail, press **⌥⌘C**, and the email
(text, headers, attachments) is pasted into a Claude desktop chat chosen by the recipient address.

## Setup
1. Install the DMG, open the app (it lives in the menu bar, no Dock icon).
2. Grant **Accessibility** (System Settings → Privacy & Security) so it can paste into Claude.
3. First hotkey press asks for **Automation** access to Mail. Allow it.
4. In Claude, open the chat you want for an address, copy its link (`https://claude.ai/chat/…`),
   then menu bar icon → **Add Route…**. Unrouted emails go to the default chat, or a new chat.

Config lives in `~/Library/Application Support/Email2Claude/config.json`
(routes, default chat, instruction text, `autoSend`, `openDelay`).
Rules match recipients (To, then Cc) by exact address or `@domain.com`.

## Build
- `swift test` — routing/formatting tests (macOS)
- `./scripts/package.sh` — builds `dist/Email2Claude.dmg`
- CI (`.github/workflows/build.yml`) does the same on an Apple Silicon runner. For a notarized DMG
  set secrets `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `MACOS_SIGN_IDENTITY`, `APPLE_ID`,
  `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`. Without them the DMG is ad-hoc signed (right-click → Open).

## Unverified assumptions (check on a Mac first)
- Claude desktop bundle id `com.anthropic.claudefordesktop` and `claude://claude.ai/chat/<id>` deep links.
- Claude's input box is focused after the chat opens, and ⌘V of a file attaches it.
- Mail allows `save attachment` into the temp folder.
