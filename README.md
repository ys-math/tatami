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
| `⌃⌥ h/j/k/l` | Move the window one grid cell left/down/up/right |
| `⌃⌥ [` / `⌃⌥ ]` | Left / right half |
| `⌃⌥ Return` | Maximize |
| `⌃⌥ c` | Center |
| `⌃⌥ s` | Split the window's cells in half, in place |
| `⌃⌥ -` / `⌃⌥ =` | Fewer / more grid columns on this display |
| `⌃⌥⇧ -` / `⌃⌥⇧ =` | Fewer / more grid rows on this display |

## Configuration

Tatami writes `~/.config/tatami/config.json` with all defaults on first launch.
Edit it, then choose **Reload Config** from the menu-bar icon. Every field is
optional; a binding set to `null` is disabled.

```json
{
  "defaultGrid": { "columns": 4, "rows": 2 },
  "outerGap": 8,
  "innerGap": 8,
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
