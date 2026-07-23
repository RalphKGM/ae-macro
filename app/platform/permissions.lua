local Permissions = {}

function Permissions.check(prompt)
  return {
    accessibility = hs.accessibilityState(prompt == true),
    screen_recording = hs.screenRecordingState(prompt == true),
  }
end

function Permissions.ready(status)
  return status.accessibility and status.screen_recording
end

return Permissions

