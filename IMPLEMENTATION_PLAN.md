# Anime Expeditions macOS Implementation Plan

## Objective

Build a customizable macOS automation client for Anime Expeditions using the behavior and assets in the v0.4 Windows release as a reference. The initial target is this machine (Apple M1, macOS 26), running the native Roblox client.

Required capabilities:

- Unlimited ordered tasks spanning Story, Raid, Challenge, and Expedition.
- Configurable teams, placement coordinates, strategies, repetitions, retry behavior, and timing.
- Auto-craft with configurable recipes and cadence, followed by exact task resumption.
- Real challenge-cap detection from the game UI, with a persistent counter only as a fallback.
- Side-challenge scheduling without interrupting an active battle.
- Discord notifications, optionally including a Roblox-window screenshot.
- Importable/exportable profiles so configuration is not embedded in code.

## Current status

The default King's Tomb Act 1 Mastery path is implemented and passed a full live run on July 23, 2026. The dashboard, unlimited queue, strategy/position editor, result handling, guarded Rainbow Sprite workflow, challenge-panel OCR, and Discord Keychain integration are implemented. King's Tomb has a built-in route; other maps and modes use task-level navigation actions until their live routes are calibrated.

## Findings from v0.4

The v0.4 release was published on July 22, 2026 and contains a 64-bit compiled AutoHotkey v2 executable plus image assets. Static inspection recovered a 6,158-line embedded script.

The Windows build already contains early versions of the requested features:

- Auto-craft runs after a configurable number of successful Mastery runs, but its recipe interaction is a fixed coordinate sequence.
- Side challenges are checked around every 30 minutes. Their daily usage is tracked locally up to 10 and reset using a remote HTTP `Date` header. It does not inspect the visible in-game cap.
- Multi-mode tasks support Story, Raid, Challenge, and Expedition, but the UI is capped at 12 tasks for Premium and 3 for Free.
- Team configuration and per-map strategies support placement counts, upgrades, abilities, targeting, selling, and coordinate capture.
- The included setup README is stale and still labels the package a v0.1 scaffold, so every navigation template and coordinate must be verified in the current Mac client.

The macOS client will retain the useful behavior but will not retain the license gates, fixed task limit, hard-coded crafting recipe, Windows registry usage, updater batch files, or Roblox window embedding.

## Confirmed reference scope

The first assisted end-to-end target is **King's Tomb (Act 1) in Mastery mode**. The profile will preserve `Act 1` and `Mastery` as separate fields until the live selector is calibrated, so the implementation does not collapse two distinct UI choices. If the game exposes Mastery as the stage rather than a modifier, the adapter can map the same profile to that selector without changing the task engine.

The initial auto-craft recipe is **Sprite (Rainbow)** from **Sprite (Grey)** earned by the Mastery runs. The supplied 2082x1228 Crafting screenshot shows `17/30` Grey Sprites, so the provisional recipe cost is 30 Grey Sprites per Rainbow Sprite. That cost and the final craft action must be confirmed once with a craftable inventory before unattended use.

Challenge detection covers the complete requested scope:

- Regular side-challenge usage and cap.
- Hourly challenge availability, completion, lock, and reset state.
- Daily challenge availability, completion, lock, and reset state.
- Weekly challenge availability, completion, lock, and reset state.

The current equipped team can be used for the first navigation/capture spike. A named team and placement strategy remain profile data and can be supplied before the first live battle test.

## Architecture

### Runtime split

Use Hammerspoon 1.1.1 as the macOS host and a small persistent Python/OpenCV vision worker.

Hammerspoon responsibilities:

- Locate, focus, move, and resize the native Roblox window.
- Register global start, stop, pause, debug-capture, and calibration hotkeys.
- Generate keyboard and mouse events.
- Run the timer-driven state machine and task scheduler.
- Host the configuration UI in a local `hs.webview`.
- Persist profiles and runtime checkpoints.
- Send Discord webhooks.

Vision worker responsibilities:

- Normalize each Roblox capture to the 816×638 reference coordinate space.
- Match templates within named regions of interest.
- Sample colors and classify simple UI states.
- Detect challenge counters/cap messages using digit templates first and OCR as a fallback.
- Save annotated diagnostic frames showing matches, thresholds, and click targets.

Communication will use newline-delimited JSON over a loopback TCP socket protected by a per-launch random token. The worker remains running, caches the current frame, and can answer several match queries without recapturing the window.

### Capture strategy

The first implementation spike must benchmark `hs.window:snapshot()` on macOS 26 with Roblox. If it reliably captures the native Roblox window, Hammerspoon will write one frame per state tick for the vision worker. If it returns blank/stale frames or is too slow, replace only the capture layer with a small ScreenCaptureKit helper; the rest of the architecture remains unchanged.

Screen Recording permission is required for capture. Accessibility permission is required for input and window management.

### Reference-coordinate model

All templates, regions, placements, and strategies use the v0.4 reference canvas of 816×638.

At runtime:

1. Find the visible Roblox content rectangle.
2. Capture it without the macOS title bar and shadow.
3. Measure the actual pixel dimensions and Retina scale.
4. Normalize the frame to 816×638 for detection.
5. Convert reference click coordinates back to screen points immediately before input.
6. Reject any click outside the current Roblox content rectangle.

Each profile may override the content inset, timing multiplier, click jitter, match threshold, and per-template search region.

## Proposed repository layout

```text
macro-port/
  init.lua
  app/
    bootstrap.lua
    core/
      state_machine.lua
      scheduler.lua
      task_queue.lua
      checkpoint.lua
    platform/
      roblox_window.lua
      capture.lua
      input.lua
      permissions.lua
    features/
      navigation.lua
      teams.lua
      strategies.lua
      crafting.lua
      challenges.lua
      recovery.lua
      webhooks.lua
    config/
      schema.lua
      profiles.lua
      migrations.lua
    ui/
      controller.lua
      index.html
      app.js
      styles.css
  vision/
    server.py
    capture.py
    matching.py
    challenge_counter.py
    diagnostics.py
    requirements.txt
  assets/
    nav/
    maps/
    challenge/
    crafting/
    results/
  profiles/
    default.json
  tests/
    fixtures/
    lua/
    python/
```

## Configuration model

Use versioned JSON profiles instead of INI files. Profiles are human-readable, validated before use, and importable/exportable.

A profile contains:

- Roblox window title/bundle matching and reference resolution.
- Hotkeys, timing multiplier, focus policy, and click jitter.
- Detection thresholds and regions of interest.
- An unlimited task array.
- Team definitions and per-map team selection.
- Placement coordinates and ordered strategy actions.
- Craft recipes and triggering rules.
- Challenge selection, caps, reset behavior, interval, and team mapping.
- Recovery limits, private-server URL, and disconnect behavior.
- Enabled webhook event types. The webhook URL itself is stored in macOS Keychain, not exported with the profile.

Every task can define:

- `enabled`, `name`, `mode`, `map`, `stage`, `difficulty`, and `team`.
- Finite repetitions or an explicit infinite-repeat flag.
- Strategy profile and optional task-level overrides.
- Retry policy, maximum consecutive failures, and skip/stop behavior.
- Pre-task and post-task actions.

There will be no task-count limit. The UI will use an HTML list with drag reordering instead of allocating a fixed set of native controls.

## State machine

The engine must remain non-blocking. Long `Sleep` chains from the AHK version will be represented as timed actions so Pause and Stop remain immediate.

Primary states:

```text
IDLE
ATTACH_ROBLOX
CALIBRATE
LOBBY_DETECT
AUTO_CRAFT
TEAM_SELECT
MODE_SELECT
MAP_SELECT
STAGE_SELECT
MATCHMAKING
LOAD_WAIT
IN_STAGE
EXECUTE_STRATEGY
IN_BATTLE
RESULTS
SIDE_CHALLENGE_SELECT
RECOVERY
COMPLETE
```

Each transition records the reason, source detection, retry count, elapsed time, and current task checkpoint. Recovery must be bounded; it may retry, return to the lobby, rejoin a private server, skip the task, or stop according to profile policy.

## Requested features

### Unlimited multi-mode tasks

- Store tasks as an unbounded JSON array.
- Support Story, Raid, regular Challenge, Expedition, and scheduled hourly/daily/weekly challenges.
- Allow drag reordering, duplication, enable/disable, grouped presets, finite/infinite repetitions, and import/export.
- Persist current task index, repetition, challenge interruption, and strategy progress so a reload can resume safely.
- Validate maps/stages against the current catalog, while allowing custom catalog entries for game updates.

### Auto-craft

Auto-craft is a resumable subroutine, not a terminal state.

Trigger options:

- Every N completed Mastery runs.
- Every N total victories.
- Time interval.
- After a named task.
- Manual “craft now” action.

Workflow:

1. Save a resume token containing task, repetition, and challenge state.
2. Finish the active battle and return to the lobby.
3. Detect and open Areas, then navigate to Crafting.
4. Confirm the crafting screen using templates, not timing alone.
5. For each enabled recipe, locate its row/card, determine whether it is craftable, select the configured quantity, craft, and confirm success.
6. Stop that recipe on insufficient materials, daily cap, inventory limit, or configured maximum.
7. Close the crafting UI and restore the saved task exactly.

Recipes are data-driven. Each recipe may provide templates, search region, select/open actions, quantity behavior, craft/confirm actions, and stop conditions. A generic coordinate-only workflow is available during initial calibration, but image confirmation is required before unattended use.

Initial Rainbow Sprite recipe behavior:

1. Trigger after the configured number of successful King's Tomb Mastery runs.
2. Open Crafting and locate `Sprite (Rainbow)` by a cropped card template, with visible title text as secondary confirmation.
3. Read the Grey Sprite requirement and owned count from the selected recipe panel.
4. Craft only when the normal craft path is visibly enabled and the owned count satisfies the detected requirement.
5. Select the configured quantity (`one`, `maximum affordable`, or a numeric cap), then confirm the resulting inventory change or success state.
6. Stop safely on `Insufficient Items`, an unchanged count, a confirmation mismatch, or an inventory/cap message.
7. Return to the exact saved King's Tomb task and repetition.

The screenshot's blue `Quick Craft` control is not assumed to be equivalent to the normal material craft action. It will remain disabled in automation until a live assisted test establishes its effect and whether it spends any premium currency or bypass resource.

### Challenge-cap detection

The v0.4 local counter becomes a fallback rather than the source of truth.

Before starting a side challenge:

1. Capture the challenge panel.
2. Inspect the counter/limit region for `current / maximum`.
3. Detect explicit locked, completed, or daily-limit messages.
4. If the cap is reached, mark that challenge unavailable until its detected reset time.
5. If the UI is unreadable, consult the persisted counter and log that fallback was used.
6. Increment the fallback counter only after a confirmed victory.

Counter recognition order:

1. Templates for the small set of digits and separators used in the counter.
2. macOS Vision OCR or Tesseract fallback on the cropped region.
3. Persisted count with a warning.

The scheduler checks challenges only at safe checkpoints after a result or while in the lobby. It never interrupts a battle or a placement sequence. Daily reset state uses the visible UI when available and a server `Date` header only as a secondary fallback.

Hourly, daily, and weekly challenges use the same detector framework but keep independent availability records. Their adapters inspect visible timer, completed, locked, claimable, and limit states rather than treating all of them as a numeric side-challenge counter. Each detected reset time includes its source and confidence so the scheduler can recheck uncertain states instead of sleeping blindly until a presumed reset.

### Custom strategies

Preserve and expand the v0.4 strategy model:

- Per mode/map/stage placement coordinates.
- Per team: unit slot, placement cap, upgrade target, auto-upgrade, ability mode, auto-ability, and targeting priority.
- Ordered actions: place, upgrade, use ability, change target, sell, wait, and conditional branch.
- Screenshot-based coordinate editor with clickable reference-map capture.
- Dry-run overlay that marks intended clicks without sending input.
- Strategy import/export independent of the rest of the profile.

### Discord webhooks

Configurable events:

- Macro started/stopped/paused.
- Task started/completed/skipped.
- Victory/defeat and run duration.
- Challenge capped/reset/completed.
- Craft summary.
- Disconnect/reconnect and fatal recovery failure.
- Entire queue completed.

Messages may include the current task, run counters, elapsed time, challenge counts, crafted items, and a Roblox-window screenshot. Webhook failures are logged and retried with backoff but never block the automation engine.

## Implementation milestones

### Milestone 0 — Capture and input spike

- Bootstrap Hammerspoon and permission checks.
- Locate and align Roblox.
- Validate capture on macOS 26 and Retina coordinate conversion.
- Click a harmless calibration target and verify round-trip coordinates.
- Produce a debug hotkey that saves the raw and normalized frame.

Exit criterion: repeated screenshots and dry-run click markers remain aligned after moving and resizing Roblox.

**Live-test result (July 23, 2026): passed.** Hammerspoon obtained Accessibility and Screen Recording permission, found the native Roblox window, and kept input unarmed. The first 1680x921-point capture exposed a macOS title-bar inset and an unaligned content aspect. The implementation was corrected to fit the game-content rectangle to 816x638 and crop an 18-point title bar at Retina scale. A second capture at 1013x810 points produced a 2026x1620 raw frame and a clean 816x638 normalized frame with no blank/solid warning. A dry-run marker placed at reference center `(408, 319)` was measured at physical pixel `(1012.73, 791.35)` against expected `(1013, 792)`, an error below one pixel. No mouse event was sent; the optional armed-click test remains deliberately deferred until a harmless target is chosen by the user.

### Milestone 1 — Vision and engine foundation

- Start the persistent vision worker.
- Implement template matching, color sampling, regions, scale sweeps, and diagnostic annotations.
- Implement the timer-driven state machine, structured logs, pause/stop, checkpoints, and dry-run mode.
- Port lobby/result/disconnect detection.

Exit criterion: the engine can identify lobby, in-stage, victory, defeat, and disconnect fixtures without clicking.

### Milestone 2 — King's Tomb Mastery reference flow

- Navigate lobby → the appropriate mode → King's Tomb → Act 1 → Mastery → team → start, adjusting the selector order to match the live UI.
- Execute one calibrated placement strategy.
- Detect the result and either repeat or return to lobby.
- Send a test webhook.

Exit criterion: King's Tomb (Act 1) Mastery completes repeatedly with bounded recovery and produces a reliable completed-run signal for auto-craft cadence.

**Live result (July 23, 2026): passed.** One run finished in 4m17s with six placements, upgrades, DPS auto-upgrade, a detected victory, 5 Grey Sprite rewards, and a verified result-to-lobby transition.

### Milestone 3 — Custom UI and unlimited queue

- Build the WebView profile editor and unlimited task list.
- Add validation, drag reorder, duplication, enable/disable, JSON import/export, and resume behavior.
- Add Raid, Challenge, and Expedition navigation adapters.

Exit criterion: a mixed-mode queue survives Hammerspoon reload and resumes at the correct task/repetition.

**Implementation result (July 23, 2026): passed for the data-driven queue.** The WebView supports an unbounded ordered task array, duplication, enable/disable, finite/infinite repetitions, queue looping, all four mode types, task-level challenge kinds, and custom click/drag/key/wait lobby routes. Only King's Tomb currently ships with a live-calibrated built-in route.

### Milestone 4 — Teams and strategy editor

- Port team selection and map-bucket strategy lookup.
- Add coordinate capture, dry-run overlay, unit placement caps, upgrades, abilities, targeting, and selling.
- Add strategy import/export and diagnostic traces.

Exit criterion: selected strategies execute deterministically across the prioritized maps.

**Editor result (July 23, 2026): passed.** The native Hammerspoon WebView Strategy Studio now captures the Roblox content frame at 816×638, supports six unit slots, click and one-shot in-game coordinate recording, draggable markers, placement delays, upgrade/ability/target defaults, explicit wait/upgrade/ability/target/sell actions, drag reordering, validation, JSON import/export, save/load/delete, and input-free dry previews. A disposable two-placement strategy survived a complete GUI save/reload round trip, record mode cancelled cleanly with Escape, and its dry preview displayed both mapped markers while input remained disarmed. Runtime execution and team selection remain pending the assisted King's Tomb stage capture.

### Milestone 5 — Auto-craft

- Implement resume tokens and craft triggers.
- Calibrate the crafting navigation and first recipe.
- Add data-driven recipe workflows and craft summaries.

Exit criterion: crafting can succeed or safely abort and then resume the exact interrupted task.

**Implementation result (July 23, 2026): guarded and calibrated.** The complete Rainbow Sprite coordinate path was checked live without pressing Craft. It is opt-in, requires an explicit material-use confirmation, blocks Quick Craft, persists cadence, and resumes the queue from the lobby. A material-spending craft was intentionally not executed during the safety-limited live test.

### Milestone 6 — Challenge scheduling and cap detection

- Calibrate challenge-panel states and counter recognition.
- Add safe-checkpoint scheduling, map detection, per-map teams, reset handling, and fallback counters.
- Add capped/locked/error diagnostics and webhook events.

**Live result (July 23, 2026): passed for the visible regular cap.** The macro opened the challenge panel and read the current `10/10` limit with native macOS Vision OCR, then closed the panel and returned to the lobby. Regular, hourly, daily, and weekly counters keep separate periods and fallback state.

Exit criterion: capped challenges are skipped without wasting a run, and available challenges resume the interrupted task afterward.

### Milestone 7 — Hardening

- Exercise disconnects, delayed loads, missed templates, focus loss, full-screen changes, UI scaling, and private-server rejoin.
- Add retry budgets and clear terminal errors.
- Run a long mixed-mode soak test.
- Document installation, permissions, profile editing, asset capture, and recovery.

## Verification strategy

- Python unit tests for matching, digit/cap recognition, coordinate normalization, and diagnostics.
- Pure-Lua tests for queue behavior, scheduling, reset handling, checkpoint migration, and state transitions.
- Fixture-driven state-machine tests using captured screenshots and scripted detector responses.
- Dry-run mode that records intended actions without clicking.
- Live assisted tests for each navigation adapter and recovery path.
- Long-run test with a mixed queue, crafting interruption, challenge interruption, and webhook verification.

Every failed detection should save an annotated frame and a machine-readable trace. This makes user-supplied testing actionable instead of relying on descriptions such as “it clicked the wrong place.”

## User-supplied calibration material

The debug-capture tool from Milestone 0 should be used wherever possible so screenshots include exact window geometry and metadata.

Initial capture set:

- Clean lobby with no modal open.
- Mode-selection screen.
- Story map selection and one selected stage.
- Team-selection screen.
- In-stage frame before placement.
- Victory and defeat result screens.
- Disconnect/reconnect dialog if available.

Feature capture set:

- Full crafting trip from lobby to the crafting menu.
- Rainbow Sprite selected with fewer than 30 Grey Sprites: the supplied 2082x1228 screenshot is the initial insufficient-material fixture (`17/30`).
- Rainbow Sprite with at least 30 Grey Sprites, followed by quantity selected, confirmation (if any), success, and resulting inventory-count states.
- The result of `Quick Craft`, if that path should be supported; it will not be clicked by unattended automation until its resource/currency behavior is known.
- Challenge panel showing an available challenge and its counter.
- Challenge panel at or near the cap, plus any explicit “limit reached” state.
- Regular side-challenge plus hourly, daily, and weekly challenge names, timers, completed, locked, unavailable, and reset states.
- Raid and Expedition navigation screens for the modes prioritized after Story.

For live tests, provide the expected action and observed result together with the generated diagnostic bundle. No account credentials or Roblox cookies are needed.

## Confirmed decisions and remaining live-test input

Confirmed:

1. First reference flow: King's Tomb (Act 1), Mastery mode.
2. First recipe: Sprite (Rainbow), provisionally requiring 30 Sprite (Grey).
3. Challenge coverage: regular side challenges and hourly/daily/weekly challenges.

Still needed before the first live battle test:

1. Team number/loadout and the intended placement/upgrade strategy, or explicit approval to calibrate with the currently equipped team.
2. A Rainbow Sprite crafting capture with at least 30 Grey Sprites, plus the screen immediately after the normal craft action.
3. Screens from the King's Tomb selector path showing where Act 1 and Mastery appear, so their exact UI relationship is encoded correctly.

## Research references

- v0.4 release: https://github.com/QuantumMacro/anime-expeditions/releases/tag/v0.4
- Hammerspoon releases: https://github.com/Hammerspoon/hammerspoon/releases
- Hammerspoon event injection: https://www.hammerspoon.org/docs/hs.eventtap.html
- Hammerspoon WebView: https://www.hammerspoon.org/docs/hs.webview.html
- Hammerspoon WebView JavaScript bridge: https://www.hammerspoon.org/docs/hs.webview.usercontent.html
- Hammerspoon settings: https://www.hammerspoon.org/docs/hs.settings.html
- Apple ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Discord incoming webhooks: https://docs.discord.com/developers/platform/webhooks
