# Fires of Olympus

Godot 4.7 card/board game (Catan / King of Tokyo complexity). GDScript only, no C#
(C# can't export to Web in Godot 4). Renderer: GL Compatibility (required for Web, fine on iOS).
Targets: Web (primary for playtesting) and iOS. Landscape 1920x1080 base, `canvas_items` stretch.

## Toolchain
- Godot: `/Applications/Godot.app` (4.7.2-stable), CLI `godot` on PATH
- Export templates: `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`
- Xcode for iOS builds

## Commands
- `tools/build.sh check`  — headless import; catches script parse errors
- `tools/build.sh web`    — static site in `build/web/` (single-threaded: no COOP/COEP headers needed, works on itch.io / GitHub Pages)
- `tools/build.sh serve`  — build web and serve on http://localhost:8060
- `tools/build.sh ios`    — Xcode project in `build/ios/`; open it in Xcode to sign and run
- `tools/build.sh sim`    — build + install + launch on an iPad Simulator (no signing needed; uses the x86_64 sim slice under Rosetta)
- Add `debug` as a 2nd arg for debug builds.

## Conventions
- Commit `*.import` and `*.uid` files; only `.godot/` and `build/` are ignored.
- Keep game rules (pure logic, no Nodes) separate from presentation so rules can be unit-tested headless.
