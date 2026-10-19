# eMail to Claude

Menu-bar app for Apple Silicon Macs (see BRAND.md for colors and icons). Select an email in Mail, press a shortcut, and the email
(text, headers, attachments) is pasted into the right Claude desktop chat, with an instruction
telling Claude what to do with it.

## Actions

Menu bar icon → **Send to Claude**, or the global shortcuts:

| Action | Shortcut | What Claude does |
| --- | --- | --- |
| Draft a Reply | ⌥⌘R | Drafts a reply to the thread |
| Summary & Next Steps | ⌥⌘S | Summary, action items, proposed next steps |
| Deep Dive & Research | ⌥⌘D | Same, plus web research for extra context |
| Paste Only | ⌥⌘C | Pastes the email and stops, so you add your own request |

The instruction for each action is editable in **Settings → Prompts**.

## Routing

Emails are routed by the **domain in the To field**: `company.com` covers mail to you or to any
colleague there (subdomains too). A full address (`jane@gmail.com`) overrides its domain, for
shared domains like gmail.com. Each route sends to one of:

- **Existing chat** — one conversation that accumulates context (pick from Claude's sidebar, or paste a link)
- **New chat in a project** — a fresh chat inside a Claude project (name, or link)
- **New chat**
- **Incognito chat**

If an email's To domain has no route, a window asks where it should go: save it as a rule, or use it
just this once. Everything is configured in **Settings** (menu bar icon → Settings…, ⌘,).

## Setup
1. Install the DMG and open the app (menu bar only, no Dock icon).
2. Grant **Accessibility** (System Settings → Privacy & Security) so it can read Claude's chat list and paste.
3. The first shortcut press asks for **Automation** access to Mail. Allow it.

## Speed
Timings for each step are appended to `~/Library/Logs/Email2Claude.log`. Settings → General has a
"wait for Claude to load a chat" slider; lower is faster but can paste before the chat has opened.

## Build
- `swift test` — routing, actions and config tests (macOS)
- `./scripts/package.sh` — builds `dist/eMail-to-Claude.dmg`
- CI (`.github/workflows/build.yml`) does the same on an Apple Silicon runner. For a notarized DMG
  set secrets `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `MACOS_SIGN_IDENTITY`, `APPLE_ID`,
  `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`. Without them the DMG is ad-hoc signed (right-click → Open).

## Unverified assumptions (check on a Mac)
- Claude desktop bundle id `com.anthropic.claudefordesktop` and `claude://claude.ai/chat/<id>` links.
- `claude://claude.ai/new?incognito` opens an incognito chat.
- A project opened by link or by name (Projects page) leaves its message box focused, and a message sent there starts a new chat in that project.
- Claude's sidebar can be read via Accessibility (`ClaudeSidebar.swift` heuristics); chats are opened by pressing the row with the saved title, so titles must be unique and visible.
- Mail allows `save attachment` into the temp folder. Inline images under 15 KB are skipped on purpose.
