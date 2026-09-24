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

- Draws every boundary and crosspoint on the display with hint labels. The
  boundary nearest the focused window is selected initially.
- Typing a label selects it; `Tab`/`⇧Tab` cycles.
- `hjkl` moves the selection by one grid step (a vertical boundary ignores
  `j/k`, a horizontal one ignores `h/l`; a crosspoint accepts all four).
  `HJKL` moves by the fine step.
- `Return` or `Esc` exits (moves are applied live).

## 6. Multi-monitor

- Displays are ordered by physical arrangement: left→right, then top→bottom.
- **Send to next/previous display** maps the window's cell span proportionally
  into the target display's grid (left half stays left half).
- **Edge crossing:** moving past the display edge with `⌃⌥ hjkl` jumps to the
  physically adjacent display in that direction, landing in the nearest
  column/row with the same proportional position on the other axis. No
  adjacent display → no-op.
- Directional focus (`⌥ hjkl` etc.) is **out of scope for v1**.

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
- **Cycling:** pressing `⌃⌥ a` again within 3 seconds on the same display with
  the same window set advances to the next layout; `⌃⌥⇧ a` goes back. The last
  layout used per display is remembered for the session.

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
