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

## License

MIT — see [LICENSE](LICENSE).
