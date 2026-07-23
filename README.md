# anime expeditions mac

a native mac version of the anime expeditions macro

hammerspoon for the gui, window control, screenshots, guarded input. native helper for roblox camera movement, opencv handles image matching

## what works

- roblox window detection and alignment
- retina-safe screenshots at a fixed `816x638` reference size
- guarded clicks that only work while roblox is focused
- camera zoom, pitch, and map capture
- strategy editor with placements and action ordering
- saved strategy json files
- emergency stop

the full dashboard, task runner, automatic navigation, auto upgrade, auto craft, challenge detection, and webhooks are still being finished

## setup

run:

```sh
./scripts/setup.sh --install-hammerspoon
```

then add this to `~/.hammerspoon/init.lua`:

```lua
dofile("/Users/ralph/Documents/anime-expeditions-mac/init.lua")
```

open hammerspoon and grant accessibility and screen recording permissions when macos asks

if the prompts do not appear, run:

```sh
./scripts/request_permissions.sh
```

## controls

- `control + option + command + g` opens the strategy gui
- `control + option + command + l` aligns the roblox window
- `control + option + command + c` captures roblox
- `control + option + command + escape` stops and disarms everything

the menu bar also has an `ae` menu with the main controls

## checks

```sh
./scripts/run_checks.sh
./scripts/doctor.sh
```

## folders

- `app/` hammerspoon code and gui
- `native/` mac input helper
- `vision/` image matching worker
- `profiles/` settings, tasks, and strategies
- `assets/` map images and templates
- `tests/` automated checks

runtime screenshots, logs, caches, and local python files are ignored by git

## safety

input is blocked unless roblox is focused and the macro was armed first

`control + option + command + escape` is the emergency stop.
