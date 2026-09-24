# Tatami

A keyboard-driven window manager for macOS. Tatami lives in the menu bar and
lets you move, resize, split, swap, focus and auto-arrange windows on a
per-display grid using vim-style `hjkl` bindings. Windows only move when you
ask; nothing tiles behind your back.

See [SPEC.md](SPEC.md) for the full design and [PLAN.md](PLAN.md) for how it
was built.

## Requirements

- macOS 26 or later
- Xcode 27 (Swift 6) to build

## Install

```sh
make install   # builds Tatami.app, copies it to ~/Applications and opens it
```

Then:

1. Grant access in **System Settings → Privacy & Security → Accessibility**
   (Tatami asks on first launch; the menu-bar icon shows the status).
2. Optionally choose **Launch at Login** from the menu-bar icon.

For development: `make build`, `make test`, `make lint`, `make format`, and
`make run` (build and launch from `dist/`).

## Troubleshooting

- **Nothing happens on a hotkey:** open the menu-bar icon. If it says
  *Accessibility: Not Granted*, open the settings pane from there. If Tatami is
  listed but still not working after a rebuild, remove it with **−** and add
  it again.
- **Accessibility must be re-granted after every rebuild:** the build is
  signed ad-hoc. Sign in to Xcode with your Apple ID (Settings → Accounts →
  Manage Certificates → **+ Apple Development**); `make app` then signs with
  that identity and the grant sticks. If `security find-identity -v -p
  codesigning` still lists 0 valid identities, install Apple's
  [WWDR G3 intermediate](https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer).
- **A ⚠︎ line in the menu:** either the config has an error (the previous
  config stays active) or another app already owns that hotkey; rebind it in
  `config.json`.
- **A window refuses to move or resize:** some apps have minimum sizes or fixed
  sizes. Tatami reverts multi-window changes when an app refuses, so nothing is
  left half-done.

## Default key bindings

| Keys | Action |
|---|---|
| `⌃⌥ h/j/k/l` | Move the window one grid cell left/down/up/right; past the edge, onto the adjacent display |
| `⌃⌥ [` / `⌃⌥ ]` | Left / right half |
| `⌃⌥ Return` | Maximize |
| `⌃⌥ c` | Center |
| `⌃⌥ s` | Split the window's cells in half, in place |
| `⌃⌥⇧ h/j/k/l` | Joined resize: move the window's boundary left/down/up/right, resizing the windows on the other side with it |
| `⌃⌥⌘ h/j/k/l` | Separate resize: same rule as joined resize, but only the focused window changes |
| `⌃⌥ -` / `⌃⌥ =` | Fewer / more grid columns on this display |
| `⌃⌥⇧ -` / `⌃⌥⇧ =` | Fewer / more grid rows on this display |
| `⌃⌥ g` | Grid mode (see below) |
| `⌃⌥ b` | Boundary mode (see below) |
| `⌃⌥ a` | Auto-arrange this display; press again within 3 s for the next layout |
| `⌃⌥⇧ a` | Previous layout |
| `⌃⌥⌘ a` | Auto-arrange every display (each with its last layout) |
| `⌃⌥ .` / `⌃⌥ ,` | Send the window to the next / previous display, keeping its relative cells |
| `⌃⌥ w` | Window mode: swap and rotate windows (see below) |
| `⌃⌘ h/j/k/l` | Focus the window to the left/below/above/right (crosses displays) |
| `⌃⌥ f` | Label every window; type a label to focus that window |

Joined resize follows tmux: the key is the direction the boundary moves. It
uses the window's right (bottom) boundary when that lies inside the display,
otherwise its left (top) one; a full-width (full-height) window shrinks from
the far edge, so `h` pulls its right edge left. Windows whose edges meet within
`innerGap + 2pt` are joined, and collinear boundaries (like the middle line of
a 2×2 layout) move as one. To move just part of a line, use boundary mode.

### Grid mode

`⌃⌥ g` shows the grid over the focused window's display with a label in
every cell (`q w e r` / `a s d f` on the default 4×2 grid).

- Type two labels to place the window over the span between those cells
  (`q` then `s` → top-left two-by-two block). One label and `Return` fills a
  single cell.
- `hjkl` moves the highlighted selection, `HJKL` resizes it, `Return` applies.
- `-` / `=` change columns, `_` / `+` change rows, `Tab` jumps to the next
  display, `Esc` cancels.

### Auto-arrange

`⌃⌥ a` lays out the resizable windows on the focused window's display. The
focused window gets the main slot, the rest follow front-to-back order. Press
again within `cycleTimeout` seconds to cycle: **Balanced grid → Master + stack
→ Columns → Rows → Master + grid** (plus **Centered master** on displays wider
than 21:9); the layout's name flashes on screen. Windows never move to another
display. Apps listed in `ignoredApps` (bundle IDs) are left alone.

### Window mode

`⌃⌥ w` labels every window on the focused display and stays open until `Esc`.

- Type labels to select windows (type again to deselect).
- `r` / `R` rotates the selected windows one slot clockwise / counter-clockwise
  (two selected: they swap). With nothing selected, all windows rotate.
- `h/j/k/l` swaps the focused window with its neighbour; `m` swaps it with the
  largest window.

Windows only trade places, so the layout stays the same.

### Boundary mode

`⌃⌥ b` shows every line where windows meet on the focused window's display,
split into the smallest pieces that can move on their own (the middle lines of
a 2×2 are four segments), plus the crosspoints where lines meet, each with a
label. Moving a crosspoint moves every line touching it; a line that a
crosspoint already moves exactly is not listed (a T shape shows just its dot).
The line nearest the focused window starts selected.

- Type a label (or `Tab` / `⇧Tab`) to select a line or crosspoint.
- `hjkl` moves it to the next grid line, `HJKL` by `fineStep` points (default
  10). A vertical line ignores `j`/`k`; a crosspoint moves both ways. All
  windows on the line resize together, live.
- `Return` or `Esc` leaves.

## Configuration

Tatami writes `~/.config/tatami/config.json` with all defaults on first launch
and **reloads it automatically when you save** (or choose **Reload Config**).
Every field is optional; a missing binding uses its default and a binding set
to `null` is disabled.

```json
{
  "defaultGrid": { "columns": 4, "rows": 2 },
  "outerGap": 8,
  "innerGap": 8,
  "minimumWindowSize": { "width": 100, "height": 60 },
  "fineStep": 10,
  "ignoredApps": ["com.apple.finder"],
  "cycleTimeout": 3,
  "bindings": {
    "maximize": "ctrl+alt+return",
    "center": null,
    "swapWithMain": "ctrl+alt+m"
  }
}
```

| Setting | Default | Meaning |
|---|---|---|
| `defaultGrid` | 4 × 2 | Grid for displays you have not changed with `⌃⌥ -`/`=` |
| `outerGap` | 8 | Points between the screen edge and the grid |
| `innerGap` | 8 | Points between neighbouring windows |
| `minimumWindowSize` | 100 × 60 | Resizes never go below this; smaller windows are skipped by auto-arrange |
| `fineStep` | 10 | Points per `HJKL` step in boundary mode |
| `ignoredApps` | `[]` | Bundle IDs that auto-arrange, swap and rotate leave alone |
| `cycleTimeout` | 3 | Seconds within which `⌃⌥ a` moves to the next layout |

Hotkeys are written as `modifier+…+key`. Modifiers: `ctrl`, `alt`/`opt`,
`shift`, `cmd`. Keys: letters, digits, punctuation (`- = [ ] ; ' , . / \ ``),
`return`, `tab`, `space`, `escape`, `delete`, arrows, `f1`–`f12`.

Every action name, bound or not, is listed in the generated `config.json`.
Unbound by default: `growLeft/Down/Up/Right`, `shrinkLeft/Down/Up/Right`,
`swapLeft/Down/Up/Right`, `rotateClockwise`, `rotateCounterclockwise` and
`swapWithMain` (the last seven are also reachable through window mode).

Per-display grid sizes are saved in `~/.config/tatami/state.json`.

## License

MIT — see [LICENSE](LICENSE).
