# eMail to Claude

Menu-bar app for Apple Silicon Macs (see BRAND.md for colors and icons). Select an email in Mail, press a shortcut, and the email
(text, headers, attachments) is pasted into the right Claude desktop chat, with an instruction
telling Claude what to do with it.

## Actions

Menu bar icon → **Send to Claude**, or the global shortcuts. Each of the six slots has an editable
name and a mode; the three presets and Paste Only come ready-made, the two custom slots start empty
(they appear in the menu once named). Shortcuts are fixed.

| Slot | Shortcut | Default |
| --- | --- | --- |
| Draft a Reply | ⌥⌘R | Drafts a reply to the thread |
| Summary & Next Steps | ⌥⌘S | Summary, action items, proposed next steps |
| Deep Dive & Research | ⌥⌘D | Same, plus web research for extra context |
| Custom action 1 / 2 | ⌥⌘1 / ⌥⌘2 | Yours: any name and prompt |
| Paste Only | ⌥⌘C | Pastes the email and stops, so you add your own request |

Mode per slot: **paste the email only** (nothing is sent) or **add a prompt** (the prompt goes above the
email and, with auto-send on in General, it is submitted so Claude acts at once). Settings → Prompts
explains the effect of each mode.

## Routing

A route sends an email to a place in Claude based on **who it was sent to** (the To field):

- **An email domain** — `company.com` covers you and every colleague there (subdomains too).
- **A full address** — `me@company.com` for one person; it wins over a domain route.

Each route sends to one of: an **existing chat**, a **new chat in a project**, a **new chat**, or an
**incognito chat**. If an email's To has no route, a window asks where it should go (save it, use it once,
or "don't ask again, always start a new chat" — reversible in Settings → Routes).

## Activity log

Every email sent to Claude is logged on this Mac (date, subject, sender, route, prompt): Settings →
Activity, searchable. Click a subject to open the email in Mail; click a route to open its chat or
project in Claude. Claude has no way to jump to a message inside a chat. Turn it off in General.

## Updates, license and privacy

About once a week (and when it opens) the app checks in with the Supabase backend in `supabase/`:

- **Updates.** If a newer release is published and the license key is valid, the app asks, downloads the
  DMG over a short-lived signed link, verifies its checksum and that it is signed by the same developer team
  as the running app, replaces itself and reopens. Releases are cut with the Release workflow
  ([docs/RELEASING.md](docs/RELEASING.md), which also covers licenses).
- **Privacy.** On first launch the user chooses to share analytics or not. Not sharing stores only a random
  device ID and the first and last use dates; sharing also stores versions, language, IP, country, city and
  the license key. Opting out clears the analytics fields; users can erase everything. See
  [PRIVACY.md](PRIVACY.md) (a draft to have reviewed).
- **Backend.** `supabase/migrations` holds the schema (all tables locked by row-level security) and
  `supabase/functions/checkin` the Edge Function. The Backend smoke test workflow checks it.

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
