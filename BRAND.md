# eMail to Claude — brand

The app is called **eMail to Claude** (capital M, as written). The icon is a white envelope with an
arrow and a spark on a navy squircle. Source artwork lives in `Resources/`:
`AppIcon.png` (1024 px, transparent corners) and `MenuBarIcon.png` (black template glyph with alpha,
tinted by macOS for light and dark menu bars).

## Colors

| Role | Name | Hex | RGB |
| --- | --- | --- | --- |
| Primary — app icon background | Navy blue (cobalt) | `#0D47A1` (brighter alternatives `#0C4BBA`, `#1976D2`) | 13, 71, 161 |
| Graphic and accents | White | `#FFFFFF` | 255, 255, 255 |
| Active state / accent on dark | Sky blue | `#42A5F5` | 66, 165, 245 |
| Card backgrounds, secondary accents | Alice blue | `#E3F2FD` | 227, 242, 253 |
| Primary text | Dark slate | `#1E1E1E` (alt `#0F172A`) | 30, 30, 30 |
| Borders and dividers | Cool gray | `#E2E8F0` (alt `#F8FAFC`) | 226, 232, 240 |

## Usage
- Navy carries structure and authority: icon background, primary buttons, headers.
- White is for the glyph and for text or marks placed on navy.
- Light blues keep the interface friendly: backgrounds, hover and active states.
- Neutrals are for text, borders and app frames.
- In the app, `Brand.accent` (Sources/Email2Claude/Brand.swift) is navy on light surfaces and sky blue on dark ones.
