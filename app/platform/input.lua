local Coordinates = require("app.core.coordinates")
local Input = {}
Input.__index = Input

function Input.new(robloxWindow, reference, logger)
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
    armed_until = 0,
    arm_timer = nil,
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
  hs.alert.closeAll()
  hs.alert.show("Anime Expeditions input DISARMED", 1.2)
end

function Input:arm(seconds)
  seconds = math.min(math.max(seconds or 15, 3), 60)
  self.armed_until = hs.timer.secondsSinceEpoch() + seconds
  if self.arm_timer then self.arm_timer:stop() end
  self.arm_timer = hs.timer.doAfter(seconds, function() self:disarm("timeout") end)
  self.logger:warn("input_armed", { seconds = seconds })
  hs.alert.show("INPUT ARMED for " .. seconds .. "s — Ctrl+Alt+Cmd+Esc stops", 2)
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

function Input:click(point, reason)
  if not self:isArmed() then return nil, "input is not armed" end
  local screenPoint, windowOrErr = self:referencePoint(point)
  if not screenPoint then return nil, windowOrErr end
  local window = windowOrErr
  if not self.roblox:isFrontmost(window) then return nil, "Roblox is not frontmost" end
  if not self.click_binary then return nil, "cliclick is missing; run scripts/setup.sh" end

  local x = math.floor(screenPoint.x + 0.5)
  local y = math.floor(screenPoint.y + 0.5)
  local task
  task = hs.task.new(self.click_binary, function(exitCode, stdout, stderr)
    self.click_tasks[task] = nil
    if exitCode ~= 0 then
      self.logger:error("input_click_failed", {
        exit_code = exitCode, stdout = stdout, stderr = stderr,
        x = x, y = y, reason = reason or "unspecified",
      })
    end
  end, { "-w", "150", string.format("m:%d,%d", x, y), "c:." })
  if not task or not task:start() then return nil, "could not start native click helper" end
  self.click_tasks[task] = true
  self.logger:warn("input_click", { x = x, y = y, reference_x = point.x, reference_y = point.y, reason = reason or "unspecified", backend = "cliclick" })
  return true
end

function Input:stop()
  self:disarm("shutdown")
  for task in pairs(self.click_tasks) do task:terminate() end
  self.click_tasks = {}
  for _, canvas in ipairs(self.overlays) do canvas:delete() end
  self.overlays = {}
end

return Input
