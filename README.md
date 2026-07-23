# anime expeditions mac

a mac version of the anime expeditions v0.4 macro, built around hammerspoon, a small swift helper, and local opencv detection.

the included default is ready for king's tomb act 1 mastery. other modes can be added as normal tasks with their own lobby navigation json and strategy.

## what works

- dashboard with a continuous live roblox preview, start, pause, stop, status, logs, and run stats
- unlimited ordered tasks with duplicate, reorder, enable, finite, infinite, and queue-loop controls
- story, raid, challenge, and expedition task types
- king's tomb act 1 mastery lobby navigation
- custom lobby navigation for maps and modes not built in yet
- visual position editor using a saved 816x638 bird's-eye map
- place, auto upgrade, upgrade, ability, target, sell, and wait actions
- result detection, repeat, return to lobby, retries, and checkpoints
- regular, hourly, daily, and weekly challenge counters
- macos vision ocr fallback when digit templates are missing
- guarded rainbow sprite auto craft after a configurable number of mastery wins
- discord webhooks stored in macos keychain, with optional result screenshots
- emergency stop from the gui, menu bar, or hotkey

the first full live run passed on july 23, 2026: king's tomb act 1 mastery finished in 4m17s with one victory, no defeats, automatic placements, upgrades, and dps auto upgrade. return-to-lobby and the visible `10/10` regular challenge cap were also checked live.

## setup

install the local dependencies:

```sh
./scripts/setup.sh --install-hammerspoon
```

add the project to `~/.hammerspoon/init.lua`:

```lua
dofile("/absolute/path/to/anime-expeditions-mac/init.lua")
```

reload hammerspoon, then grant it accessibility and screen recording permission. if macos does not show the prompts:

```sh
./scripts/request_permissions.sh
```

check the install:

```sh
./scripts/doctor.sh
```

## basic use

1. open roblox and join anime expeditions.
2. press `control + option + command + g`.
3. check the task, strategy, and positions tabs.
4. leave `start from` on `auto detect`.
5. press `start selected task`.

the dashboard preview mirrors the current roblox window twice per second. the positions tab is separate: it shows the saved bird's-eye image for the selected mode, map, stage, and difficulty.

the default profile uses the current equipped team. the default king's tomb strategy has six placements and adds auto upgrade to the dps placements.

## tasks and maps

there is no task limit. every task can use a finite repetition count, infinite repetitions, or the queue-loop option.

setup downloads the 21 compatible 816x638 map images from the upstream v0.4 release. these cover the five story maps, spirit city raid acts 1-3, and three expedition maps. a map image provides the placement canvas; it does not provide the lobby navigation route or unit strategy.

king's tomb act 1 mastery has a built-in route. a different map or mode needs a custom lobby route in the task editor until its route is added to the catalog. actions use the same 816x638 reference canvas:

```json
[
  {
    "type": "click",
    "point": { "x": 80, "y": 390 },
    "wait_ms": 800,
    "label": "open play"
  }
]
```

supported route actions are `click`, `drag`, `key`, and `wait`. off-screen points are rejected when the profile is saved.

the current equipped team needs no extra setup. if a task should switch teams, put that task's menu sequence in `custom team selection actions`; it runs in the lobby before the map route.

each mode, map, stage, and difficulty can have its own saved bird's-eye image. in the positions tab, load or capture the image, click to add placements, drag markers to adjust them, and save the strategy.

## auto craft

auto craft is off by default.

the bundled workflow opens areas, travels to crafting, selects sprite rainbow, sets the minimum amount, uses the normal material craft button, and closes the menu. it is set to one rainbow sprite for 30 grey sprites. quick craft is always blocked because it can involve premium currency.

to use it:

1. set the mastery win interval.
2. enable auto craft.
3. check the material-use confirmation.
4. save settings.

the task checkpoint advances before crafting. after the craft workflow, the queue resumes from the correct next task. a failed workflow stops the macro unless `on_failure` is changed to `continue` in the profile.

## challenge caps

challenge checks only run from the lobby before a challenge task. the macro opens the challenge panel, reads the visible counter, closes the panel, and either starts or skips that task.

the regular `10/10` cap was read live through native macos ocr. local counters are kept as a fallback and only increment after a detected victory.

## discord

paste the webhook in settings and save it. the url is stored in macos keychain and is not written to the profile or logs. only discord webhook hosts are accepted.

enabled events can include start, victory, defeat, stop, error, craft, and challenge. result screenshots are optional.

## controls

- `f1` starts or stops
- `f5` pauses or resumes
- `control + option + command + g` opens the gui
- `control + option + command + l` aligns roblox
- `control + option + command + c` saves a diagnostic capture
- `control + option + command + escape` stops and disarms everything

the menu bar also has an `ae` menu.

## checks

```sh
./scripts/run_checks.sh
./scripts/doctor.sh
```

## folders

- `app/` hammerspoon runtime and gui
- `native/` camera and macos vision helper
- `vision/` local image worker
- `profiles/` tasks, settings, and strategies
- `assets/` map images and templates
- `tests/` lua and python checks

runtime screenshots, ocr output, logs, binaries, checkpoints, and the local python environment are ignored by git.

## safety

run input only works during an active macro session, or during the short manual calibration arm window. roblox is focused again before a run click and mapped points must stay inside its content area.

quick craft is blocked. auto craft and challenge checks are off until enabled. the default workflow does not summon, purchase, or spend premium currency.
