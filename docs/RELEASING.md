# Releasing MailtoChat

How a new version gets from this repo to users' Macs, and how licenses work.

## One-time setup

### 1. Apple Developer ID (signing and notarization)
A Developer ID signature is what lets updates keep their macOS permissions (Accessibility, Automation)
and install without Gatekeeper warnings. It also lets the app verify that an update comes from you.
Without it the build is ad-hoc signed and every update asks for the permissions again.

1. Join the Apple Developer Program (developer.apple.com/programs).
2. In Certificates, Identifiers & Profiles, create a **Developer ID Application** certificate. Download it,
   open it in Keychain Access, and export it with its private key as a `.p12` file with a strong password.
3. Create an **app-specific password** at appleid.apple.com (for notarization).
4. Add these GitHub repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12` | the `.p12` file, base64-encoded: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | the `.p12` password |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | the 10-character team ID |
| `APPLE_APP_PASSWORD` | the app-specific password |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase → Project Settings → API → the `service_role` secret key |

The service-role key can read and write everything in the project. It lives only in GitHub secrets;
never put it in the app or the repo.

### 2. Geolocation (country and city)
The `checkin` function looks up country and city for users who share analytics. Create a free account at
ipinfo.io, copy the access token, and store it as a function secret named `IPINFO_TOKEN`
(Supabase → Edge Functions → Secrets). Without it, country and city stay empty.
The lookup sends the user's IP to ipinfo.io, so name them in the privacy policy as a processor.

## Cutting a release

1. Decide the version and tag it: `git tag v1.1 && git push origin v1.1`. Versions have two numbers, `1.0`, `1.1`, `1.2`, and only the number after the dot goes up for a normal release (1.0 is the first public version; before it the app used `0.1.x`). The update check and the server compare versions number by number, so `1.0` is newer than `0.1.12` and `1.10` is newer than `1.9`.
   Or run the **Release** workflow by hand and fill in the version and release notes.
2. The workflow tests, builds, signs, notarizes, uploads the DMG to the private `releases` storage bucket
   and records it in the `releases` table as **unpublished**.
3. Install that build yourself from the workflow artifact and try it.
4. Publish it, which makes the app offer it: tick "publish" when running the workflow, or run
   `update public.releases set published = true where version = '1.1';` in the Supabase SQL editor.
   To pull a release, set `published = false`.

Users with a valid license are offered the update at their next weekly check (or Check for Updates…).
The first Developer-ID-signed version has to be installed by hand once; from then on updates install themselves.

## Licenses

Keys look like `EMC-XXXXX-XXXXX-XXXXX-XXXXX` (100 random bits). They are checked online, once a week,
when the app asks for updates. A valid key lets the app download updates; the app works without one.

**Self-service (current):** on first launch the app asks for an email address and the `checkin` function's
`register` action issues a key that never expires (`expires_at` is null), one per address, saved in the app
automatically. The key is returned to the app only, not emailed. Revoke one with
`update public.licenses set status = 'revoked' where key = '...';` or set `expires_at` to end it. If someone
loses their key, look it up by email in `public.licenses` and send it to them yourself.

To issue keys by hand instead:

```sql
select public.issue_license('buyer@example.com');        -- a key that never expires
select public.issue_license('buyer@example.com', 365);   -- valid for a year
update public.licenses set status = 'revoked' where key = 'EMC-...';   -- e.g. after a refund
select * from public.licenses order by created_at desc;
```

### How to hand keys out in practice
Common approaches, from least to most work:
- **Merchant of record with built-in license keys** (Lemon Squeezy, Gumroad, FastSpring). They take payment,
  handle EU VAT and invoices, generate the key and email it. Copy their keys into the `licenses` table, or have
  a webhook insert them. Simplest for a first paid launch.
- **A payment provider plus your own keys** (Stripe or Paddle). A webhook calls an Edge Function that runs
  `issue_license` and emails the buyer. More control, more to build and maintain, and you handle VAT questions.
- **A licensing service** (Keygen). Adds device activation limits, trials and offline licenses.

Practices worth following whichever you pick: random keys validated by the server (not keys that carry a
secret formula, which get cracked); show the key once and send it by email; one key per customer with the
ability to revoke it; keep a trial path (a 30-day key from `issue_license(email, 30)`); and decide what an
expired license does. Here it only blocks new updates.
During the free launch period, issue free keys the same way so the update path is already exercised.

## Checking the backend

Actions → **Backend smoke test** calls the live function with a reserved test device ID
(`00000000-0000-4000-8000-000000000001`). `analytics`, `minimal` and `erase` choose what it leaves in the
`installs` table, so you can inspect the stored row.
