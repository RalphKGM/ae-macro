# live test record

date: july 23, 2026

machine: apple m1, macos 26, native roblox client

reference canvas: 816x638

## passed

- hammerspoon accessibility permission
- hammerspoon screen recording permission
- roblox discovery, focus, alignment, and retina-normalized capture
- cliclick mouse input inside roblox
- hammerspoon keyboard input
- native right-drag and scroll camera input in the lobby
- king's tomb act 1 mastery lobby navigation
- private party start and battle confirmation
- six strategy placements
- upgrades and circular-arrow auto upgrade on dps
- victory detection
- result stats and checkpoint save
- return-to-lobby button and confirmation
- lobby update-overlay detection and close
- regular challenge panel navigation
- native macos ocr of the visible `10/10` daily limit
- non-destructive crafting route inspection through rainbow sprite selection
- gui dashboard, task duplication, task removal, positions, settings, and saved map rendering

## run result

- result: victory
- duration: 4m17s
- health remaining: 3
- reward: 5 sprite grey
- runs: 1
- victories: 1
- defeats: 0
- win rate: 100%

the victory capture stays local under `runtime/captures/` and is ignored by git.

## crafting boundary

the live inspection opened areas, teleported to crafting, opened the station, selected sprite rainbow, and mapped the minimum-amount, normal-craft, quick-craft, and close controls.

no craft button was pressed. no material, premium currency, purchase, summon, or server leave was used during calibration.

auto craft remains disabled in the default profile. quick craft is blocked in code.

## challenge result

the regular challenge panel showed `daily limit 10/10`. the detector returned:

```json
{
  "kind": "regular_side",
  "current": 10,
  "maximum": 10,
  "available": false,
  "state": "capped",
  "source": "visible_counter"
}
```

the value came from the visible panel through the native macos vision ocr fallback, not the persisted counter.

## safe rerun

1. join the anime expeditions lobby.
2. open the gui with `control + option + command + g`.
3. keep the default king's tomb task selected.
4. leave auto craft and challenge checks off unless those flows are being tested.
5. press start.
6. use `control + option + command + escape` at any time to stop.
