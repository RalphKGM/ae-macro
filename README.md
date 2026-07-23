# anime expeditions mac

a mac port of the anime expeditions v0.4 flow, built around hammerspoon, a small swift helper, and local opencv detection.

the included profile has king's tomb act 1 mastery and a school grounds test task. placements and timing are team-specific, so check the strategy against the equipped units before leaving it unattended.

## what works

- dashboard with a real 816x638 roblox window dock, start, pause, stop, status, logs, and run stats
- unlimited ordered tasks with duplicate, reorder, enable, finite, infinite, and queue-loop controls
- story, raid, challenge, and expedition task types
- built-in v0.4 navigation for story, spirit city raids, regular/hourly/daily/weekly challenges, and expeditions
- custom lobby and team navigation actions for anything outside the v0.4 catalog
- visual position editor using a saved 816x638 bird's-eye map
- place, auto upgrade, upgrade, ability, target, sell, and wait actions
- result detection, repeat, return to lobby, retries, and checkpoints
- regular, hourly, daily, and weekly challenge counters
- macos vision ocr fallback when digit templates are missing
- guarded rainbow sprite auto craft after a configurable number of mastery wins
- discord webhooks stored in macos keychain, with selectable events, reward text, attempt counts, task progress, and optional result screenshots
- emergency stop from the gui, menu bar, or hotkey

live testing on july 23, 2026 covered afk chamber to lobby, story/map/stage selection, private party creation, load detection, bird's-eye setup, confirmed placement, auto upgrade, defeat detection, reward parsing, and image-located repeat. the low-level alt team reached the school grounds result twice but could not win the stage. king's tomb mastery still needs a clean victory run with a capable equipped team.

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
2. click the `ae` menu bar item, then click `open ae`. the gui hotkey is optional.
3. check the task, strategy, and positions tabs.
4. leave `start from` on `auto detect`.
5. press `start selected task`.

the dashboard cuts out a transparent dock for the real roblox window. the game content stays 816x638 and the macos title bar sits inside the dock above it. this is not a screenshot or video preview. clicks in the dashboard cutout are forwarded to roblox; forwarding turns off on the task, strategy, positions, and settings pages. the positions tab is separate and shows the saved bird's-eye image for the selected mode, map, stage, and difficulty.

the default profile uses the current equipped team. the king's tomb strategy is a starting layout, not a universal team preset. use the positions and strategy tabs to match unit costs, placement limits, and timing.

## tasks and maps

there is no task limit. every task can use a finite repetition count, infinite repetitions, or the queue-loop option.

setup downloads the 21 compatible 816x638 map images from the upstream v0.4 release. these cover the five story maps, spirit city raid acts 1-3, and three expedition maps. a map image provides the placement canvas; it does not provide the lobby navigation route or unit strategy.

the v0.4 story maps, spirit city raid acts, challenge categories, and expedition maps have built-in routes. a newer map can use custom lobby actions in the task editor. actions use the same 816x638 reference canvas:

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

supported route actions are `click`, `drag`, `scroll`, `key`, and `wait`. off-screen points are rejected when the profile is saved.

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

the regular counter can be read through native macos ocr. local counters are kept as a fallback and only increment after a detected victory.

## discord

paste the webhook in settings and save it. the url is stored in macos keychain and is not written to the profile or logs. only discord webhook hosts are accepted. enable the events you want, then use `send test`.

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
