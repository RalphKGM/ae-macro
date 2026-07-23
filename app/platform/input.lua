local Coordinates = require("app.core.coordinates")
local Input = {}
Input.__index = Input

function Input.new(robloxWindow, reference, logger, root)
  local clickBinary
  for _, candidate in ipairs({ "/opt/homebrew/bin/cliclick", "/usr/local/bin/cliclick" }) do
    if hs.fs.attributes(candidate) then clickBinary = candidate break end
  end
  return setmetatable({
    roblox = robloxWindow,
    reference = reference,
    logger = logger,
    click_binary = clickBinary,
    click_tasks = {},
    native_binary = root and (root .. "/runtime/bin/ae-input") or nil,
    armed_until = 0,
    arm_timer = nil,
    session_active = false,
    session_label = nil,
    overlays = {},
  }, Input)
end

function Input:isArmed()
  return hs.timer.secondsSinceEpoch() < self.armed_until
end

function Input:disarm(reason)
  self.armed_until = 0
  if self.arm_timer then self.arm_timer:stop() self.arm_timer = nil end
  self.logger:info("input_disarmed", { reason = reason or "manual" })
  if not self.session_active then
    hs.alert.closeAll()
    hs.alert.show("Anime Expeditions input DISARMED", 1.2)
  end
end

function Input:arm(seconds)
  seconds = math.min(math.max(seconds or 15, 3), 60)
  self.armed_until = hs.timer.secondsSinceEpoch() + seconds
  if self.arm_timer then self.arm_timer:stop() end
  self.arm_timer = hs.timer.doAfter(seconds, function() self:disarm("timeout") end)
  self.logger:warn("input_armed", { seconds = seconds })
  hs.alert.show("INPUT ARMED for " .. seconds .. "s — Ctrl+Alt+Cmd+Esc stops", 2)
end

function Input:beginSession(label)
  self.session_active = true
  self.session_label = label or "automation"
  self.logger:warn("input_session_started", { label = self.session_label })
  return true
end

function Input:endSession(reason)
  self.session_active = false
  self.session_label = nil
  self:disarm(reason or "session ended")
  self.logger:info("input_session_ended", { reason = reason or "session ended" })
end

function Input:isAllowed()
  return self.session_active or self:isArmed()
end

function Input:referencePoint(point)
  local window, err = self.roblox:find()
  if not window then return nil, err end
  local frame = self.roblox:contentFrame(window)
  local screenPoint = Coordinates.referenceToScreen(point, frame, self.reference)
  if not Coordinates.contains(frame, screenPoint, 1) then return nil, "mapped point is outside Roblox" end
  return screenPoint, window, frame
end

function Input:showMarker(point, label, duration)
  local screenPoint, _, frameOrErr = self:referencePoint(point)
  if not screenPoint then return nil, frameOrErr end
  local size = 34
  local canvas = hs.canvas.new({ x = screenPoint.x - size / 2, y = screenPoint.y - size / 2, w = size, h = size })
  canvas:appendElements({
    type = "circle", action = "stroke", strokeWidth = 4,
    strokeColor = { red = 1, green = 0.16, blue = 0.15, alpha = 0.95 },
    frame = { x = 2, y = 2, w = size - 4, h = size - 4 },
  }, {
    type = "segments", action = "stroke", strokeWidth = 2,
    strokeColor = { white = 1, alpha = 0.95 },
    coordinates = { { x = size / 2, y = 3 }, { x = size / 2, y = size - 3 }, { x = 3, y = size / 2 }, { x = size - 3, y = size / 2 } },
  })
  canvas:level("overlay"):show()
  table.insert(self.overlays, canvas)
  hs.timer.doAfter(duration or 1.5, function()
    canvas:delete()
    for index, item in ipairs(self.overlays) do
      if item == canvas then table.remove(self.overlays, index) break end
    end
  end)
  self.logger:info("dry_run_marker", { reference_x = point.x, reference_y = point.y, label = label })
  return true
end

function Input:_ready()
  if not self:isAllowed() then return nil, "input is not armed and no run session is active" end
  local window, err = self.roblox:find()
  if not window then return nil, err end
  if not self.roblox:isFrontmost(window) then
    if not self.session_active then return nil, "Roblox is not frontmost" end
    local focused, focusError = self.roblox:focus()
    if not focused then return nil, focusError end
    hs.timer.usleep(120000)
    window = focused
    if not self.roblox:isFrontmost(window) then return nil, "Roblox could not be focused" end
    self.logger:info("roblox_refocused_for_input", { label = self.session_label })
  end
  return window
end

function Input:_task(path, arguments, reason, callback)
  local task
  task = hs.task.new(path, function(exitCode, stdout, stderr)
    self.click_tasks[task] = nil
    if exitCode ~= 0 then
      self.logger:error("input_helper_failed", {
        exit_code = exitCode, stdout = stdout, stderr = stderr, reason = reason or "unspecified",
      })
    end
    if callback then
      local helperError = nil
      if exitCode ~= 0 then helperError = stderr ~= "" and stderr or "input helper failed" end
      callback(exitCode == 0, helperError)
    end
  end, arguments)
  if not task or not task:start() then return nil, "could not start native input helper" end
  self.click_tasks[task] = true
  return true
end

function Input:click(point, reason, callback)
  local ready, readyError = self:_ready()
  if not ready then return nil, readyError end
  local screenPoint, windowOrErr = self:referencePoint(point)
  if not screenPoint then return nil, windowOrErr end
  local window = windowOrErr
  if not self.roblox:isFrontmost(window) then return nil, "Roblox is not frontmost" end
  local x = math.floor(screenPoint.x + 0.5)
  local y = math.floor(screenPoint.y + 0.5)
  if not self.click_binary then return nil, "cliclick is missing; run scripts/setup.sh" end
  local ok, err = self:_task(self.click_binary, { "-w", "150", string.format("m:%d,%d", x, y), "c:." }, reason, callback)
  if not ok then return nil, err end
  self.logger:warn("input_click", { x = x, y = y, reference_x = point.x, reference_y = point.y, reason = reason or "unspecified", backend = "cliclick" })
  return true
end

function Input:key(key, repeats, intervalMs)
  local ready, err = self:_ready()
  if not ready then return nil, err end
  repeats = math.max(1, math.floor(repeats or 1))
  intervalMs = math.max(0, intervalMs or 35)
  for _ = 1, repeats do
    hs.eventtap.keyStroke({}, key, 0)
    if intervalMs > 0 then hs.timer.usleep(intervalMs * 1000) end
  end
  self.logger:warn("input_key", { key = key, repeats = repeats })
  return true
end

function Input:drag(fromPoint, toPoint, durationMs, reason, callback)
  local ready, err = self:_ready()
  if not ready then return nil, err end
  local fromScreen, fromError = self:referencePoint(fromPoint)
  if not fromScreen then return nil, fromError end
  local toScreen, toError = self:referencePoint(toPoint)
  if not toScreen then return nil, toError end
  if not self.click_binary then return nil, "cliclick is missing; run scripts/setup.sh" end
  local wait = math.max(20, math.floor((durationMs or 500) / 3))
  return self:_task(self.click_binary, {
    "-w", tostring(wait),
    string.format("m:%d,%d", math.floor(fromScreen.x + 0.5), math.floor(fromScreen.y + 0.5)),
    "dd:.",
    string.format("dm:%d,%d", math.floor(toScreen.x + 0.5), math.floor(toScreen.y + 0.5)),
    "du:.",
  }, reason, callback)
end

function Input:rightDrag(fromPoint, toPoint, durationMs, reason, callback)
  local ready, err = self:_ready()
  if not ready then return nil, err end
  if not self.native_binary or not hs.fs.attributes(self.native_binary) then
    return nil, "native camera helper is missing; run scripts/setup.sh"
  end
  local fromScreen, fromError = self:referencePoint(fromPoint)
  if not fromScreen then return nil, fromError end
  local toScreen, toError = self:referencePoint(toPoint)
  if not toScreen then return nil, toError end
  return self:_task(self.native_binary, {
    "right-drag",
    tostring(math.floor(fromScreen.x + 0.5)), tostring(math.floor(fromScreen.y + 0.5)),
    tostring(math.floor(toScreen.x + 0.5)), tostring(math.floor(toScreen.y + 0.5)),
    tostring(math.floor(durationMs or 900)),
  }, reason, callback)
end

function Input:move(fromPoint, toPoint, durationMs, reason, callback)
  local ready, err = self:_ready()
  if not ready then return nil, err end
  if not self.native_binary or not hs.fs.attributes(self.native_binary) then
    return nil, "native camera helper is missing; run scripts/setup.sh"
  end
  local fromScreen, fromError = self:referencePoint(fromPoint)
  if not fromScreen then return nil, fromError end
  local toScreen, toError = self:referencePoint(toPoint)
  if not toScreen then return nil, toError end
  return self:_task(self.native_binary, {
    "move",
    tostring(math.floor(fromScreen.x + 0.5)), tostring(math.floor(fromScreen.y + 0.5)),
    tostring(math.floor(toScreen.x + 0.5)), tostring(math.floor(toScreen.y + 0.5)),
    tostring(math.floor(durationMs or 900)),
  }, reason, callback)
end

function Input:scroll(delta, reason, callback)
  local ready, err = self:_ready()
  if not ready then return nil, err end
  if not self.native_binary or not hs.fs.attributes(self.native_binary) then
    return nil, "native camera helper is missing; run scripts/setup.sh"
  end
  return self:_task(self.native_binary, { "scroll", tostring(math.floor(delta or 0)) }, reason, callback)
end

function Input:scrollAt(point, delta, reason, callback)
  local ready, err = self:_ready()
  if not ready then return nil, err end
  local screenPoint, pointError = self:referencePoint(point)
  if not screenPoint then return nil, pointError end
  hs.mouse.absolutePosition(screenPoint)
  hs.timer.usleep(80000)
  return self:scroll(delta, reason, callback)
end

function Input:stop()
  self:endSession("shutdown")
  for task in pairs(self.click_tasks) do task:terminate() end
  self.click_tasks = {}
  for _, canvas in ipairs(self.overlays) do canvas:delete() end
  self.overlays = {}
end

return Input
