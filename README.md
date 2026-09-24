# Tatami

A keyboard-driven window manager for macOS. Tatami lives in the menu bar and
lets you move, resize, split and auto-arrange windows on a per-display grid
using vim-style `hjkl` bindings.

> Status: early development. See [SPEC.md](SPEC.md) for the design and
> [PLAN.md](PLAN.md) for the roadmap.

## Requirements

- macOS 26 or later
- Xcode 27 (Swift 6)

## Build

```sh
make build   # debug build
make test    # run tests
make run     # build Tatami.app and launch it
```

On first launch, grant Tatami access in **System Settings → Privacy &
Security → Accessibility**. To keep that permission across rebuilds, sign in
to Xcode with your Apple ID and create an *Apple Development* certificate;
the build script uses it automatically.

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
| `⌃⌥ w` then `h/j/k/l` | Swap the window with its neighbour in that direction |
| `⌃⌥ w` then `r` / `R` | Rotate the display's windows clockwise / counter-clockwise |
| `⌃⌥ w` then `m` | Swap the window with the main (largest) window |

Joined resize follows tmux: the key is the direction the boundary moves. It
uses the window's right (bottom) boundary when that lies inside the display,
otherwise its left (top) one; a full-width (full-height) window shrinks from
the far edge, so `h` pulls its right edge left. Windows whose edges meet within `innerGap + 2pt`
are joined, and collinear boundaries (like the middle line of a 2×2 layout)
move as one.

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

### Boundary mode

`⌃⌥ b` shows every line where windows meet on the focused window's display,
split into the smallest pieces that can move on their own (the middle lines of
a 2×2 are four segments), plus the crosspoints where lines meet, each with a
label. Moving a crosspoint moves every line touching it. The line nearest the
focused window starts selected.

- Type a label (or `Tab` / `⇧Tab`) to select a line or crosspoint.
- `hjkl` moves it to the next grid line, `HJKL` by `fineStep` points (default
  10). A vertical line ignores `j`/`k`; a crosspoint moves both ways. All
  windows on the line resize together, live.
- `Return` or `Esc` leaves.

Unbound by default: `growLeft/Down/Up/Right` and `shrinkLeft/Down/Up/Right`
move one named edge of the focused window, for when you need the left or top
edge of a window that does not touch the display's side. Bind them in
`config.json` if you want them.

## Configuration

Tatami writes `~/.config/tatami/config.json` with all defaults on first launch.
Edit it, then choose **Reload Config** from the menu-bar icon. Every field is
optional; a binding set to `null` is disabled.

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
    "center": null
  }
}
```

Hotkeys are written as `modifier+…+key`. Modifiers: `ctrl`, `alt`/`opt`,
`shift`, `cmd`. Keys: letters, digits, punctuation (`- = [ ] ; ' , . / \ ``),
`return`, `tab`, `space`, `escape`, `delete`, arrows, `f1`–`f12`.

Per-display grid sizes are saved in `~/.config/tatami/state.json`.

## License

MIT — see [LICENSE](LICENSE).
