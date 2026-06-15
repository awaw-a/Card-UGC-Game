---
name: godot-release-readiness-check
description: Run a practical pre-release audit for a Godot Windows project, including export validation and common release polish risks.
source: auto-skill
extracted_at: '2026-06-13T16:11:12.998Z'
---

# Godot Release Readiness Check

Use this when a Godot project is about to ship and the user wants a quick release-readiness pass rather than a code change.

## Inspect release configuration first

Read these files before running expensive checks:

- `project.godot`: confirm `config/name`, `run/main_scene`, autoloads, renderer settings, and unexpected debug-only configuration.
- `export_presets.cfg`: confirm the target preset, output path, `export_filter`, `include_filter`/`exclude_filter`, `script_export_mode`, and platform options.
- `.gitignore`: verify generated folders like `.godot/` and temporary exports are ignored.

Flag release polish risks even if they are not blockers:

- `debug/export_console_wrapper=1` on Windows creates a console wrapper executable and exposes `print()` output.
- Empty app metadata such as icon, product name, version, company, file description, or copyright.
- `export_filter="all_resources"` packaging dev/test scenes and scripts such as `spawn_test.tscn`, `repro_client.tscn`, `server.tscn`, or probe utilities.
- In-game debug UI that is reachable by players, such as a visible "Debug State" button.
- Many runtime `print()` calls in shipped gameplay paths.

## Search for obvious release hazards

Use ripgrep/glob-style scans for:

```text
TODO|FIXME|print\(|push_error|assert\(|OS\.is_debug_build|debug|test|localhost|127\.0\.0\.1
```

Also list top-level `.tscn`/`.gd` files and assets to spot test scenes, prototype assets, or generated files that might be included by `all_resources`.

## Validate with the actual Godot executable

If `where godot` fails, ask/use the user's explicit Godot console executable path. On Windows, paths with spaces or nested `.exe` folder names can confuse `cmd`; invoking through `call` is more reliable for commands with scene arguments:

```bat
call "D:\path\to\Godot_v4.x_console.exe" --headless --quit
call "D:\path\to\Godot_v4.x_console.exe" --headless --import --quit
call "D:\path\to\Godot_v4.x_console.exe" --headless --quit-after 2 MainMenu.tscn
call "D:\path\to\Godot_v4.x_console.exe" --headless --quit-after 2 Main.tscn
```

Prefer running from the project directory. In this environment, `--path "C:\..."` and `--scene "res://..."` produced `文件名、目录名或卷标语法不正确。`, while running in the project directory with relative scene paths and `call` worked.

## Interpret `--check-only --script` carefully

`godot --headless --check-only --script SomeScript.gd` may report `Identifier not found` for autoload singletons such as `Locale`, `EventBus`, `NetworkManager`, or `PlayerData` when checking individual scripts. Treat this as a limitation of per-script checking unless full project load/scene startup/export also fails.

Do not present those autoload-only check failures as release blockers if these pass:

- `--headless --quit`
- `--headless --import --quit`
- representative scene startup with `--quit-after`
- release export

## Prove export without overwriting the user's build

Export to a temporary ignored folder in the project, then delete it after the check:

```bat
if not exist build_check mkdir build_check && call "D:\path\to\Godot_console.exe" --headless --export-release "Windows Desktop" "build_check\CardGame.exe"
rmdir /s /q build_check
```

Use the exact preset name from `export_presets.cfg`. Report whether the export succeeded and whether the temporary directory was removed.

## Report as blockers vs polish

Keep the final release report short and actionable:

- State whether the project loaded, imported, key scenes started, and release export succeeded.
- Separate blockers from non-blocking polish items.
- Include file references for concrete settings or UI code, such as `export_presets.cfg:21` for console wrapper or `Main.gd:1231` for debug UI.
- Mention if git status could not be checked because the directory is not a Git repository.
