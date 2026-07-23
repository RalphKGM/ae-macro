# First assisted live test

This test validates Milestone 0 only: permissions, Roblox-window discovery, capture quality, Retina coordinate mapping, and one optional harmless click. It does not start a run or navigate menus automatically.

Status: the capture, resize, normalization, chrome-cropping, and dry-run marker portions passed on July 23, 2026. The optional single-click round trip was not performed; input remained unarmed throughout.

## 1. Start safely

1. Launch Roblox and join Anime Expeditions. Stay in the lobby.
2. Launch Hammerspoon.
3. Run `./scripts/request_permissions.sh` and grant Hammerspoon both Accessibility and Screen Recording permissions. This path works even before global hotkeys are authorized. After Accessibility is enabled, `Control+Option+Command+P` can be used to recheck or reopen the permission panes.
4. Confirm the Hammerspoon alert reports both permissions as `true`.
5. Run `./scripts/doctor.sh`; it should report the Hammerspoon bootstrap and vision worker as ready.

At any point, `Control+Option+Command+Escape` disarms input and stops the automation state machine.

## 2. Capture and normalization test

1. Press `Control+Option+Command+L` to center Roblox at the 816×638 reference aspect ratio.
2. Press `Control+Option+Command+C` to capture and normalize the Roblox window.
3. Repeat after moving or resizing Roblox once.

Expected result:

- Hammerspoon reports `Capture ready` rather than `blank/solid`.
- A `raw-*.png`, matching metadata JSON, and `normalized-*.png` appear in `runtime/captures/`.
- The normalized image is exactly 816×638, shows the full expected Roblox content, and is not stretched or offset by a title bar.
- A JSON diagnostic appears in `runtime/diagnostics/` and records capture dimensions and brightness statistics.

If a frame is blank, make sure Hammerspoon—not Terminal—has Screen Recording permission. If content is clipped or includes window chrome, do not proceed to the optional click; the profile insets need calibration first.

## 3. Dry-run coordinate test

1. Put the mouse over a harmless visible target inside Roblox. Do not use a purchase, summon, teleport, delete, or premium-currency control.
2. Press `Control+Option+Command+M`.
3. Verify the red crosshair is centered exactly under the pointer.
4. Move/resize Roblox, use the alignment hotkey again, return to the same game target, and repeat.

This step never clicks. If the marker is offset, stop and retain the latest capture/metadata pair.

## 4. Optional single-click round trip

Only perform this after the marker is aligned and the chosen target is harmless.

1. Hover the harmless target and press `Control+Option+Command+M` to save it.
2. Press `Control+Option+Command+A` to arm input for 15 seconds.
3. Keep Roblox frontmost and press `Control+Option+Command+Return`.

Exactly one click should be sent, followed by immediate disarming. If Roblox is not frontmost, the point is outside the window, the target was not saved, or 15 seconds elapsed, the click is rejected.

## Evidence to return

Send the newest files from `runtime/captures/` and `runtime/diagnostics/`, plus whether the marker and optional click were aligned. Once this gate passes, those captures become the fixtures for King's Tomb navigation and the team/strategy calibration.

The doctor report is safe to include. It contains readiness flags and local paths, not credentials, cookies, or the Discord webhook URL.
