# Tatami — Phased Plan

Each phase is one branch (`phase-N/<slug>`) and one PR with a manual test
checklist. Work stops after each PR until it is merged. See `SPEC.md` for
behaviour details.

## Phase 0 — Repository (on `main`)

- `git init`, noreply commit email, `.gitignore`, `LICENSE` (MIT), `README.md`,
  `SPEC.md`, `PLAN.md`.
- Create private `ys-math/tatami` via `gh` and push.

## Phase 1 — Scaffold (`phase-1/scaffold`)

- SwiftPM package: `TatamiCore` library, `Tatami` executable, test targets
  (Swift Testing), macOS 26, Swift 6 mode.
- Menu-bar app: status item with Accessibility status and Quit.
- Accessibility check and prompt (`AXIsProcessTrustedWithOptions`), with a
  menu item to open the System Settings pane.
- Carbon global hotkey registration; one hard-coded binding
  `⌃⌥ Return` → maximize focused window (end-to-end proof).
- `WindowSystem` protocol + AX implementation (focused window, frame get/set,
  screen visible frames with coordinate conversion).
- `Resources/Info.plist`, `scripts/bundle.sh`, `Makefile`, signing with
  Apple Development identity or ad-hoc.
- GitHub Actions CI: build, test, `make app`, advisory lint.
- **Test:** `make run`, grant Accessibility, `⌃⌥ Return` maximizes; CI green.

## Phase 2 — Grid commands (`phase-2/grid-commands`)

- Core: `Grid`, `CellSpan`, rect↔span conversion with gaps, snapping, move,
  presets (halves, maximize, center), split-in-place.
- Per-display grids keyed by display UUID, persisted in `state.json`;
  columns/rows ± commands.
- Hotkey string parser; JSON config with defaults written on first launch;
  reload from menu; error display.
- Bindings: `⌃⌥ hjkl` move (within a display), presets, split, grid ±.
- **Test:** every single-window command on one display.

## Phase 3 — Boundaries & resize (`phase-3/boundaries`)

- Core: adjacency detection, boundary and crosspoint extraction, boundary
  moves with min-size clamping, tmux-style edge selection.
- Joined resize `⌃⌥⇧ hjkl`; separate grow/shrink `⌃⌥⌘(⇧) hjkl`.
- Read-back and revert when an app refuses a resize.
- **Test:** tile 2–4 windows, resize joined and separate.

## Phase 4 — Grid mode (`phase-4/grid-mode`)

- Non-activating key-capturing overlay panel.
- Hint-label generation (single and two-character), label selection,
  cursor/extend selection, live grid ±, `Tab` to next display, `Esc`/click
  cancel.
- **Test:** `⌃⌥ g` flows.

## Phase 5 — Boundary mode (`phase-5/boundary-mode`)

- Overlay rendering of boundaries/crosspoints with labels, initial selection,
  `Tab` cycling, `hjkl` grid steps, `HJKL` fine steps.
- **Test:** `⌃⌥ b` flows on 2×2 and `A | (B / C)` layouts.

## Phase 6 — Auto-arrange (`phase-6/auto-arrange`)

- Eligible-window filter and ordering (focused first, then z-order).
- Layouts: balanced grid, master+stack, columns, rows, master+grid,
  centered master (ultrawide only); property tests (no overlap, in bounds,
  gaps respected).
- Cycling state (3 s window, same display and window set), previous layout,
  arrange-all-displays.
- **Test:** `⌃⌥ a` repeatedly, `⌃⌥⇧ a`, `⌃⌥⌘ a`.

## Phase 7 — Multi-monitor (`phase-7/multi-monitor`)

- Physical display ordering and adjacency.
- Send to next/previous display with proportional span mapping.
- Edge crossing for `⌃⌥ hjkl`; grid-mode `Tab` across displays verified.
- **Test:** with a second display.

## Phase 8 — Segments, swap and rotate (`phase-8/segments-and-swap`)

Added after Phase 7 at the owner's request.

- Boundary mode selects minimal boundaries (segments) and merged crosspoints;
  labels never sit on crosspoints.
- Boundaries that a crosspoint already moves exactly are not offered (a T
  shape shows only its dot).
- `⌃⌥ w` window mode (open until Esc): labels select windows; `r`/`R` rotate
  the selection (or all), `hjkl` swap with neighbour, `m` swap with main.
  Unbound actions for each.
- Focus: `⌃⌘ hjkl` directional (crossing displays), `⌃⌥ f` hint labels on
  every window of every display.
- **Test:** 2×2 segments move independently; T-shape labels are separate;
  swap/rotate/main keep the layout.

## Phase 9 — Polish (`phase-9/polish`)

- Launch at login (`SMAppService`) toggle in the menu, including the
  "approve in System Settings" state.
- Config file watching: the config directory is watched (atomic saves replace
  the file), events are debounced, and a reload happens only when
  `config.json`'s contents changed.
- README: install, troubleshooting, settings reference.
- `swift format lint --strict` is blocking in CI and `make lint`.
- Menu error display already exists since Phase 2.
- **Test:** daily use.
