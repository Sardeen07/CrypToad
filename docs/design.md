# Design system

CrypToad should feel like a real financial product: calm, legible, and trustworthy. Every
visual decision serves a purpose; nothing is there only to look modern.

All tokens live in [`CrypToad/Support/Theme.swift`](../CrypToad/Support/Theme.swift).
Shared components live in `CrypToad/Views/Components/`.

## Color

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | system grouped background | | Page background |
| `surface` | secondary grouped background | | Cards and rows |
| `fill` | tertiary system fill | | Icon tiles, tracks, secondary buttons |
| `border` | `#E3E3E8` | `#2C2C2F` | 1px hairlines around cards and between rows |
| `textPrimary/Secondary/Tertiary` | system label colors | | Text hierarchy |
| `brand` | `#2D5BE3` | `#6B8CFF` | The one brand color: links, tint, selected states, active tab |
| `brandFill` | `#2D5BE3` | `#3558E0` | Behind white text (primary buttons) |
| `positive` | `#167A37` | `#3DD06C` | Money in, gains |
| `negative` | `#D1352B` | `#FF6259` | Losses, failures, destructive actions (sparingly) |
| `warning` | `#A86400` | `#F2A93B` | Skipped or pending items |
| Asset colors | BTC `#F7931A`, ETH `#627EEA`, USDC `#2775CA` | | Only to identify an asset |

Neutrals are iOS semantic colors, so app screens and native sheets/forms match exactly in both
modes. Every text/background pair meets WCAG AA (4.5:1) for its size.

**Rules:** no gradients, no glows, no translucent "glass" cards, no shadows. Card purchases show
in the primary text color, not red; red means something went wrong or value went down.

## Type

System font (SF Pro) with Dynamic Type everywhere. All money uses monospaced digits so columns
of figures line up.

| Role | Style |
|---|---|
| Hero figure (balance, totals) | 44pt semibold, scales with `.largeTitle` |
| Section title | `.headline` |
| Row title / amount | `.body` / `.body.semibold` |
| Secondary detail | `.footnote` |

At accessibility text sizes rows stack (value under title) and amounts never wrap mid-number.

## Shape and spacing

- Radius: cards 12, controls 10, icon tiles 8.
- Spacing scale: 4, 8, 12, 16, 24, 32. Pages use 16pt margins (20pt on iPad) and 24pt between sections.
- Buttons are 48pt tall. One primary (filled) button per screen at most.
- Rows are at least 56pt, separated by inset 1px hairlines inside a single card. No cards inside cards.
- Motion: state changes ease out over 180ms. Nothing animates for decoration.

## Components

`CardSection` (titled card), `InfoRow`, `ToggleRow`, `TransactionRow`, `HoldingRow`, `HeroFigure`,
`ActionButton`, `AllocationStrip`, `IconTile`, `AssetIcon`, `PrimaryButtonStyle`,
`SecondaryButtonStyle`, `ScreenScroll`.

## Layout

- **iPhone:** native tab bar (Home, Invest, Round-Ups, Card), large titles, single column.
- **iPad:** top tab bar; Home becomes two columns (what you have / what happened); other screens
  center at a 640pt reading width. All orientations are supported.

## Checking a change

`ScreenTourUITests` visits every screen and attaches screenshots in light mode, dark mode, and an
accessibility text size (see `docs/screenshots/README.md`).
