# Tatami — Specification

Tatami is a keyboard-driven window manager for macOS. It lives in the menu bar,
moves windows through the Accessibility (AX) API, and is driven by global
hotkeys with vim-style `hjkl` navigation.

## 1. Model

- **On-demand, not tiling.** Windows move only in response to a command. Tatami
  does not observe window creation or keep windows in a persistent tree.
- **Pure layout engine.** All geometry (grid math, snapping, layouts,
  boundaries) lives in `TatamiCore` as pure functions over value types:
  `(windows, screen rect, settings) -> frames`. This keeps it testable without
  AX permission and reusable if a tiling mode is ever added.
- All commands act on the **focused window** unless stated otherwise.

## 2. Grid

- Each display has its own grid of `columns × rows`. Default: **4×2**.
- Grids are persisted per display, keyed by a stable display identifier
  (`CGDisplayCreateUUIDFromDisplayID`), and survive restarts and replugging.
- The grid covers the display's **visible frame** (excluding menu bar and Dock),
  inset by the outer gap.
- A window's position is expressed as a **cell span**: a rectangle of whole
  cells `(col, row, colSpan, rowSpan)`.
- **Snapping:** if the focused window is not aligned to the grid, the first
  grid command snaps it to the nearest cell span, then applies the command.
- **Changing the grid** (columns/rows ±) affects only the focused window's
  display and never moves existing windows; it only affects later commands.
  The new grid flashes briefly on that display (also when already at a limit).
- **Gaps:** outer margin and inner gap, configurable, default 8pt each.

## 3. Commands and default bindings

Base modifier is `⌃⌥` (Control+Option). All bindings are configurable; `null`
disables a binding.

| Command | Default | Notes |
|---|---|---|
| Move one cell ←↓↑→ | `⌃⌥ h/j/k/l` | Crossing a display edge jumps to the adjacent display (§6) |
| Joined resize | `⌃⌥⇧ h/j/k/l` | Moves a boundary; see §4 |
| Separate resize | `⌃⌥⌘ h/j/k/l` | Same tmux-style rule as joined resize; neighbours ignored |
| Grow / shrink named edge | unbound | `growLeft`… / `shrinkLeft`…; bindable in config |
| Left / right half | `⌃⌥ [` / `⌃⌥ ]` | Preset, grid-independent |
| Maximize | `⌃⌥ Return` | Preset |
| Center | `⌃⌥ c` | Preset: keeps size, centers on display |
| Split in place | `⌃⌥ s` | Halve the longer side of the span; keep the half nearer the screen center; no-op on a 1-cell span |
| Grid columns − / + | `⌃⌥ -` / `⌃⌥ =` | Focused window's display |
| Grid rows − / + | `⌃⌥⇧ -` / `⌃⌥⇧ =` | |
| Grid mode | `⌃⌥ g` | §5.1 |
| Boundary mode | `⌃⌥ b` | §5.2 |
| Arrange this display / next layout | `⌃⌥ a` | §7 |
| Previous layout | `⌃⌥⇧ a` | |
| Arrange all displays | `⌃⌥⌘ a` | |
| Send to next / previous display | `⌃⌥ .` / `⌃⌥ ,` | §6 |
| Window mode | `⌃⌥ w` | §7.1: select windows, `r`/`R` rotate, `hjkl` swap, `m` swap with main |
| Focus neighbour | `⌃⌘ h/j/k/l` | §7.2 |
| Focus by label | `⌃⌥ f` | §7.2 |

Grid limits: columns and rows are clamped to `1...24`.

## 4. Boundaries and joined resize

- **Adjacency:** two windows are *joined* when their facing edges are within
  `innerGap + 2pt` of each other and they overlap along that edge.
- **Boundary:** the maximal collinear line shared by joined windows. E.g. in
  `A | (B / C)` the vertical boundary separates A from both B and C; moving it
  changes A's right edge and B's and C's left edges together.
- **Crosspoint:** a point where a vertical and a horizontal boundary meet (T or
  +). Moving it in x moves the vertical boundary through it; in y, the
  horizontal one.
- **Step:** one grid column/row by default; a fine step (default 10pt) is
  available in boundary mode.
- **Limits:** a move is refused (or clamped) if any affected window would go
  below its minimum size (default 100×60pt) or if an app refuses the resize.
  After applying, Tatami reads frames back; windows that did not comply are
  reverted so the group stays consistent.
- **Joined resize (`⌃⌥⇧ hjkl`) — tmux-style rule:** the key is the direction
  the boundary moves.
  - `h`/`l`: move the focused window's **right** boundary if it lies inside the
    display, otherwise its **left** boundary.
  - `j`/`k`: move the **bottom** boundary if inside the display, otherwise the
    **top**.
  - A window spanning the whole axis shrinks from the far edge: `h` pulls the
    right edge left, `l` the left edge right (likewise `k`/`j`).
  - If the chosen edge has no joined neighbour, only the focused window's edge
    moves.
- **Separate resize (`⌃⌥⌘ hjkl`)** uses the same tmux-style edge choice but
  moves only the focused window's edge, ignoring neighbours (may create gaps or
  overlaps); the edge may reach the display border. So one modifier set both
  grows and shrinks.
- **Per-edge grow/shrink** (`growLeft`…, `shrinkLeft`…) move one named edge
  outward/inward. Unbound by default; they cover the left/top edge of a window
  that does not touch the display's side.

## 5. Modal overlays

Both modes draw a translucent, non-activating overlay panel on the relevant
display, capture keys while active, and act on the window that was focused
when the mode was entered. `Esc` or a mouse click cancels.

### 5.1 Grid mode (`⌃⌥ g`)

- Draws the display's grid; each cell shows a hint label. Labels never use
  `h j k l`, `-`, `=` or the control keys. Grids up to 5×3 use the keyboard's
  shape (`q w e r t` / `a s d f g` / `z x c v b`); larger grids use single
  characters from `asdfgqwertyuiopzxcvbnm1234567890` while they suffice, then
  two-character labels.
- **Labels:** the first label selects that cell (and marks it as a corner);
  the second label selects the span between the two cells and applies
  immediately. `Return` after one label applies that cell.
- **Cursor:** selection starts at the window's current (snapped) span. `hjkl`
  moves it one cell; `HJKL` resizes it with the same tmux-style rule as
  resize commands. `Return` applies. Cursor input clears a pending corner.
- `-`/`=` change columns, `_`/`+` (⇧) change rows live (persisted); the
  selection is remapped proportionally.
- `Tab` moves the selection to the next display (physical order),
  proportionally.
- `Esc`, a click, or focusing another window cancels.

### 5.2 Boundary mode (`⌃⌥ b`)

- Draws every **minimal** joined boundary and every crosspoint on the focused
  window's display with hint labels (same alphabet as grid mode). A minimal
  boundary is the smallest group of windows that can move without moving
  part of a window's edge: a window joins only if its edge faces a window
  already on the other side. In a 2×2 the middle lines split into four
  segments; in `A | (B / C)` the vertical line stays whole because A's edge
  faces both B and C. (Keyboard joined resize, §4, still moves full lines.)
- A crosspoint is a point where vertical and horizontal segments meet;
  moving it moves every segment touching it along that axis.
- A boundary is **not offered** when a crosspoint already moves exactly that
  boundary along its axis (the crosspoint does the same and more). In
  `A | (B / C)` only the dot is selectable; in a 2×2 the four segments stay,
  because the dot moves both halves of a line at once.
- Boundary labels sit mid-way along a boundary's longest stretch between
  crosspoints, never on a crosspoint.
- The boundary of the focused window nearest its center is selected
  initially. If no windows meet, the mode does not open (beep).
- Typing a label selects it; `Tab`/`⇧Tab` cycles.
- `hjkl` moves the selection to the next grid line (a vertical boundary
  ignores `j/k`, a horizontal one ignores `h/l`; a crosspoint accepts all
  four). `HJKL` moves by the fine step (`fineStep`, default 10pt).
- Moves are applied live with the same read-back/revert as joined resize; the
  overlay then redraws from the windows' real frames.
- `Return` or `Esc` exits.

## 6. Multi-monitor

- Displays are ordered by physical arrangement: left→right, then top→bottom.
- **Send to next/previous display** (wrapping) maps the window's cell span
  proportionally into the target display's grid (left half stays left half).
- **Edge crossing:** moving past the display edge with `⌃⌥ hjkl` jumps to the
  physically adjacent display in that direction: one that lies beyond that
  edge and shares part of it (nearest first). The window enters at the near
  edge of the new grid keeping its size in cells (clamped), with the other
  axis mapped proportionally. No adjacent display → the window only snaps.

## 7. Auto-arrange

- **Eligible windows:** standard windows (`AXStandardWindow`), visible, not
  minimized, app not hidden, on the current Space, resizable, larger than a
  minimum size, app not in the ignore list.
- **Scope:** `⌃⌥ a` arranges the focused window's display using the windows
  already on it. `⌃⌥⌘ a` arranges every display independently. Windows never
  move between displays.
- **Order:** the focused window is the master (slot 0); the rest follow
  front-to-back z-order.
- **Layouts** (pure functions `(count, rect, gaps) -> [CGRect]`):
  1. **Balanced grid** (default) — choose `cols × rows` whose cell aspect is
     closest to the display aspect; the last row's windows widen to fill.
  2. **Master + stack** — master takes left 60%, others stacked right.
  3. **Columns** — n equal columns.
  4. **Rows** — n equal rows.
  5. **Master + grid** — master left, balanced grid right.
  6. **Centered master** — only offered on displays wider than 21:9; master
     centered, stacks on both sides.
- **Cycling:** pressing `⌃⌥ a` again within `cycleTimeout` (3 s) on the same
  display with the same window set advances to the next layout; `⌃⌥⇧ a` goes
  back. The last layout used per display is remembered for the session; a
  later `⌃⌥ a` reuses it. The layout's name flashes on the display.
- **Arrange all displays** (`⌃⌥⌘ a`) uses each display's remembered layout
  and does not cycle.
- The current Space and front-to-back order come from the on-screen window
  list (`CGWindowListCopyWindowInfo`, matched to AX windows by process and
  frame; no Screen Recording permission needed). Each window is placed on its
  own: an app refusing its slot does not undo the others.

### 7.1 Window mode: swap and rotate (`⌃⌥ w`)

Windows trade frames; nothing is resized to new sizes, so the layout stays.
`⌃⌥ w` opens a mode (like vim's `<C-w>`) on the focused window's display that
**stays open until `Esc`** (or a click / `⌃⌥ w` again):

- Every eligible window shows a label (labels skip `h j k l r m`). Typing a
  label toggles that window's **selection**. Labels stay with their window as
  it moves; the selection survives commands.
- `r` / `R`: with two or more windows selected, rotate **just the selection**
  one slot clockwise / counter-clockwise around its own center (two windows:
  a swap). With none selected, rotate every eligible window. One selected:
  beep.
- `h`/`j`/`k`/`l`: swap the focused window with its neighbour in that
  direction — a window whose center lies beyond that edge and which shares
  part of it (nearest, then longest shared stretch). None → beep.
- `m`: swap the focused window with the main window (the largest; if the
  focused window is the largest, the next largest).
- Eligible windows are the auto-arrange set on the focused window's display.
  A refused size reverts every window (same read-back as joined resize).
- `swapLeft`…, `rotateClockwise`, `rotateCounterclockwise`, `swapWithMain`
  are also actions, unbound by default. Swapping across displays is out of
  scope.

### 7.2 Focus

- **Directional** (`⌃⌘ hjkl`): focus the neighbour in that direction on the
  same display (same rule as swap). At the display's edge, focus the adjacent
  display's window nearest the entering edge, then nearest the focused
  window's center along it. Nothing there → beep-free no-op.
- **Hints** (`⌃⌥ f`): a label on every window of the current Space on every
  display (display by display in physical order, reading order within).
  Typing a label focuses that window; `Esc`, a click or an unknown label
  cancels. Labels of stacked windows are nudged apart.
- Focusing makes the window its app's main window, raises it
  (`AXRaise`) and brings the app to the front (`AXFrontmost`, falling back to
  `NSRunningApplication.activate`). Windows are never moved.

## 8. Configuration

- File: `~/.config/tatami/config.json`. Written with all defaults on first
  launch if missing. Parsed with `Codable`; no third-party dependencies.
- Contents: bindings (strings like `"ctrl+alt+shift+h"`, or `null`), default
  grid, gaps, minimum window size, fine step, ignore list (bundle IDs), cycle
  timeout.
- Per-display grids are stored separately in `~/.config/tatami/state.json`.
- Reload: on file change and via the menu. Parse errors are shown in the menu
  and the previous valid config stays active.
- Menu bar: Open Config, Reload Config, Launch at Login (`SMAppService`),
  Accessibility status, Quit.

## 9. Platform and architecture

- **macOS 26+**, Swift 6 language mode (strict concurrency), Swift Package
  Manager, no third-party dependencies.
- AppKit for the status item and overlay panels; SwiftUI only where it helps.
- Global hotkeys via Carbon `RegisterEventHotKey` (no Input Monitoring
  permission needed). Overlay modes capture keys through a key-capable,
  non-activating panel.
- **Targets:**
  - `TatamiCore` — library; pure value types, no AppKit/AX. Grid, snapping,
    layouts, boundaries, display mapping, hotkey-string parsing, config model.
  - `Tatami` — executable; AX, hotkeys, overlays, menu bar. Window access goes
    through a `WindowSystem` protocol so command execution can be tested
    against a fake.
  - `TatamiCoreTests`, `TatamiTests` — Swift Testing.
- AX code runs on `@MainActor`; core types are `Sendable`.

## 10. Build, signing, CI

- `make build`, `make test`, `make app`, `make run`, `make install`
  (`~/Applications`). `scripts/bundle.sh` assembles `Tatami.app` from the
  SwiftPM release binary and `Resources/Info.plist` (`LSUIElement`, bundle ID
  `io.github.ys-math.tatami`).
- **Signing:** uses the first "Apple Development" identity in the keychain so
  the Accessibility grant survives rebuilds; falls back to ad-hoc. No identity
  names or team IDs are committed.
- **CI:** GitHub Actions on `macos-26`, pinned Xcode, triggered on pull requests
  and `workflow_dispatch`, with concurrency cancel-in-progress. Steps: build,
  test, `make app`. `swift format lint` runs as advisory.
- No distribution builds or notarization in v1.

## 11. Repository conventions

- Private repo `ys-math/tatami`, prepared to go public (MIT license, commits use
  the GitHub noreply email).
- Conventional Commits. One branch per phase: `phase-N/<slug>`. One PR per
  phase with a manual test checklist; work stops after each PR until the owner
  merges (squash) and asks for the next phase.

## 12. Out of scope for v1

Continuous tiling, directional focus, Spaces management, mouse-driven
resizing, settings GUI, notarized releases.
