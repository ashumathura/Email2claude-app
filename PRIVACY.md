# Privacy policy: eMail to Claude (draft)

> This is a starting point written from how the app works. It is not legal advice. Have it reviewed, fill in
> the controller's details, and publish it at a public URL; then set `BackendConfig.privacyPolicyURL`
> so the app links to it.

**Controller:** [Name, address, contact email]

## Your emails
eMail to Claude reads the email you select in Apple Mail and pastes it into the Claude desktop app on your
Mac. Your emails and attachments are not sent to the developer or to any server operated by the developer.
Once an email is in Claude it is handled under Claude's own terms and privacy settings.
Attachments are saved briefly in a temporary folder on your Mac, readable only by you, and deleted after use.
An optional activity log (date, subject, sender, route, prompt) is kept on your Mac only.

## What the app sends to the developer
About once a week, and when it opens, the app contacts a server hosted with Supabase in the EU (Ireland).

| Information | If you share analytics | If you don't |
| --- | --- | --- |
| Random device ID, first-use and last-use dates | Stored | Stored |
| App version, macOS version, language | Stored | Sent, not stored |
| IP address, and the country and city it points to | Stored | Not stored |
| License key | Stored | Sent to check it, not stored |

- **Why:** to check for updates and your license, to offer a compatible update, and (with your consent)
  to understand how the app is used and give support.
- **Legal basis:** checking updates and your license, and the device ID and dates: needed to provide the
  service you licensed (and our legitimate interest in running it). Analytics: your consent, which you can
  withdraw at any time.
- **Choice:** the app asks on first launch. Change it at any time in Settings → License & Privacy. Switching
  to "Don't share" removes the analytics fields from the server immediately.
- **Erasure:** Settings → License & Privacy → Erase My Data on the Server deletes everything stored for your
  install. You can also write to [contact email].
- **Processors:** Supabase (hosting, EU region) and ipinfo.io (looks up country and city from your IP address).
- **Retention:** [decide, for example: analytics fields are deleted after 24 months of inactivity].
- **Your rights:** access, correction, erasure, restriction, portability, objection, and complaint to your
  data protection authority.
