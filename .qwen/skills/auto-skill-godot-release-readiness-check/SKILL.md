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

## Update the GitHub Pages landing page download link

When the user asks to update the public download button, edit `docs/index.html` because this project serves GitHub Pages from the `docs/` folder on `main`.

Procedure:

1. Search/read `docs/index.html` around the `#download` section. The primary download card is an `<a class="dl-card" ...>` link.
2. Prefer the exact release asset URL the user gives over guessed tag names. GitHub release tags may not match the display version; for example the visible version may be `v0.07` while the actual tag is `v0.07-on-publish`.
3. If the user gives only the release page URL, derive the ZIP asset URL by changing `/releases/tag/<tag>` to `/releases/download/<tag>/CardGame-Windows.zip`.
4. Update both links if applicable:
   - primary ZIP asset link: `https://github.com/Chai-maomao/Card-UGC-Game/releases/download/<tag>/CardGame-Windows.zip`
   - release page link: `https://github.com/Chai-maomao/Card-UGC-Game/releases/tag/<tag>`
5. Also update nearby visible text so the page does not contradict the link, e.g. `当前提供 Windows v0.07 版本`, the ZIP note `v0.07 · 压缩包 · ZIP · x86_64`, and `查看 v0.07 发布页面`.
6. Run a targeted search such as `rg "v0\\.06|v0\\.07|releases/download" docs/index.html` to confirm the old visible version/link is gone and the new asset link is present.
7. Run `git diff -- docs/index.html` to verify only the landing-page change is staged.
8. Commit only `docs/index.html`, then push `main` so GitHub Pages updates:

```bat
git add docs/index.html
git commit -m "Fix landing page v0.07 download link"
git push origin main
```

Important cautions:

- Do not read or use stored personal access tokens from memory. Let Git use existing credential-manager authentication.
- Check `git status` first. This repo often has many unrelated uncommitted Godot changes; stage only `docs/index.html` for a link-only update.
- If local `main` is already ahead of `origin/main`, pushing will publish those prior commits too. Tell the user before pushing if this matters.
- If `git fetch origin` shows local `main` has diverged from `origin/main` and the user wants only the web page published, use a temporary worktree based on `origin/main` instead of pushing the dirty/diverged local branch:

```bat
git fetch origin
git worktree add .qwen\worktrees\pages-v007 origin/main
cd .qwen\worktrees\pages-v007
rem edit only docs\index.html here
git status --short
git diff -- docs/index.html
git add docs/index.html
git commit -m "Update download link to v0.07"
git push origin HEAD:main
cd ..\..\..
git worktree remove .qwen\worktrees\pages-v007
```

- After a worktree push, verify the remote page file from the main checkout without merging local code: `git fetch origin` then `git show origin/main:docs/index.html | findstr /C:"v0.07" /C:"releases/download"`.
- GitHub Pages may take tens of seconds to a few minutes to reflect the pushed change.
- If `read_file` shows a newer local version than `git diff`'s removed lines, treat it as an already-dirty file and avoid overwriting unrelated edits; verify the final file content rather than assuming the diff base is current.

## Report as blockers vs polish

Keep the final release report short and actionable:

- State whether the project loaded, imported, key scenes started, and release export succeeded.
- Separate blockers from non-blocking polish items.
- Include file references for concrete settings or UI code, such as `export_presets.cfg:21` for console wrapper or `Main.gd:1231` for debug UI.
- Mention if git status could not be checked because the directory is not a Git repository.
