local Logger = require("app.core.logger")
local StateMachine = require("app.core.state_machine")
local TaskQueue = require("app.core.task_queue")
local Checkpoint = require("app.core.checkpoint")
local Profiles = require("app.config.profiles")
local StrategyStore = require("app.config.strategy_store")
local Permissions = require("app.platform.permissions")
local RobloxWindow = require("app.platform.roblox_window")
local Input = require("app.platform.input")
local Capture = require("app.platform.capture")
local VisionClient = require("app.platform.vision_client")
local Calibration = require("app.features.calibration")
local StrategyController = require("app.ui.controller")

local Bootstrap = {}
Bootstrap.__index = Bootstrap

local function bind(spec, fn)
  return hs.hotkey.bind(spec.modifiers, spec.key, fn)
end

local function token()
  local output = hs.execute("/usr/bin/uuidgen", true) or ""
  return output:gsub("[^%w]", "") .. tostring(math.floor(hs.timer.secondsSinceEpoch() * 1000))
end

function Bootstrap.new(options)
  return setmetatable({ root = assert(options.root), hotkeys = {}, started = false }, Bootstrap)
end

function Bootstrap:start()
  if self.started then return true end
  hs.window.animationDuration = 0
  local logPath = self.root .. "/runtime/logs/session-" .. os.date("!%Y%m%d") .. ".jsonl"
  self.logger = Logger.new(logPath, hs.json)

  local profile, err = Profiles.load(self.root .. "/profiles/default.json", hs.json)
  if not profile then
    self.logger:error("profile_load_failed", { error = err })
    hs.showError("Anime Expeditions profile error: " .. tostring(err))
    return nil, err
  end
  self.profile = profile
  self.permissions = Permissions.check(false)
  self.roblox = RobloxWindow.new(profile.roblox, self.logger)
  self.input = Input.new(self.roblox, profile.reference_resolution, self.logger)
  self.capture = Capture.new(self.root, self.roblox, self.logger)
  self.machine = StateMachine.new(self.logger)
  local checkpoint = Checkpoint.load(self.root .. "/runtime/checkpoint.json", hs.json)
  self.queue = TaskQueue.new(profile.tasks, checkpoint)

  local python = self.root .. "/.venv/bin/python3"
  if not hs.fs.attributes(python) then
    local message = "Python environment missing. Run scripts/setup.sh first."
    self.logger:error("python_missing", { path = python })
    hs.showError(message)
    return nil, message
  end
  self.vision = VisionClient.new({
    root = self.root,
    python = python,
    port = profile.vision.port,
    token = token(),
    logger = self.logger,
  })
  self.calibration = Calibration.new({
    root = self.root, profile = profile, roblox = self.roblox,
    capture = self.capture, input = self.input, vision = self.vision, logger = self.logger,
  })
  self.strategyStore = StrategyStore.new(self.root .. "/profiles/strategies", hs.json)
  self.strategyUI = StrategyController.new({
    root = self.root, profile = profile, store = self.strategyStore,
    roblox = self.roblox, capture = self.capture, vision = self.vision,
    input = self.input, logger = self.logger,
  })

  local ok, visionErr = self.vision:start(function(result, readyErr)
    if result then
      self.logger:info("vision_ready", result)
      hs.alert.show("Anime Expeditions Mac ready — capture-only mode", 2)
    else
      self.logger:error("vision_not_ready", { error = readyErr })
      hs.alert.show("Vision worker failed: " .. tostring(readyErr), 3)
    end
  end)
  if not ok then return nil, visionErr end

  self:_bindHotkeys()
  self.strategyUI:startMenu()
  self.started = true
  self.logger:info("bootstrap_ready", {
    accessibility = self.permissions.accessibility,
    screen_recording = self.permissions.screen_recording,
    task_count = #profile.tasks,
  })
  if not Permissions.ready(self.permissions) then
    hs.notify.new({
      title = "Anime Expeditions Mac",
      informativeText = "Accessibility and Screen Recording permissions are required before the live test.",
    }):send()
  end
  return true
end

function Bootstrap:_bindHotkeys()
  local keys = self.profile.hotkeys
  self.hotkeys.stop = bind(keys.stop, function() self:stopAutomation("emergency hotkey") end)
  self.hotkeys.permissions = bind(keys.permissions, function()
    self.permissions = Permissions.check(true)
    hs.alert.show(string.format("Accessibility: %s\nScreen Recording: %s",
      tostring(self.permissions.accessibility), tostring(self.permissions.screen_recording)), 3)
  end)
  self.hotkeys.align = bind(keys.align, function()
    local _, err = self.roblox:align(self.profile.reference_resolution)
    if err then hs.alert.show("Align failed: " .. err, 2) end
  end)
  self.hotkeys.capture = bind(keys.capture, function() self.calibration:captureAndNormalize() end)
  self.hotkeys.mark = bind(keys.mark, function() self.calibration:markPointer() end)
  self.hotkeys.arm = bind(keys.arm, function() self.input:arm(15) end)
  self.hotkeys.click = bind(keys.click, function() self.calibration:clickTarget() end)
  self.hotkeys.gui = bind(keys.gui, function() self.strategyUI:toggle() end)
end

function Bootstrap:startAutomation()
  if not Permissions.ready(Permissions.check(false)) then return nil, "permissions are missing" end
  if self.machine.state == "IDLE" then self.machine:transition("ATTACH_ROBLOX", "manual start") end
  local window, err = self.roblox:focus()
  if not window then self.machine:transition("RECOVERY", err) return nil, err end
  self.machine:transition("CALIBRATE", "Roblox attached")
  return true
end

function Bootstrap:status()
  local permissionStatus = Permissions.check(false)
  local window, windowError = self.roblox:find()
  return {
    started = self.started,
    capture_only = true,
    input_armed = self.input and self.input:isArmed() or false,
    accessibility = permissionStatus.accessibility,
    screen_recording = permissionStatus.screen_recording,
    vision_connected = self.vision and self.vision.socket and self.vision.socket:connected() or false,
    roblox_window_found = window ~= nil,
    roblox_window_error = windowError,
    state = self.machine and self.machine.state or "UNINITIALIZED",
    current_task = self.queue and self.queue:current() and self.queue:current().name or nil,
    strategy_gui_visible = self.strategyUI and self.strategyUI.webview and self.strategyUI.webview:isVisible() or false,
  }
end

function Bootstrap:stopAutomation(reason)
  if self.input then self.input:disarm(reason or "stop") end
  if self.machine then self.machine:stop(reason or "stop") end
  hs.alert.show("Anime Expeditions automation stopped", 1.5)
end

function Bootstrap:stop(reason)
  if not self.started and not self.logger then return end
  self:stopAutomation(reason or "shutdown")
  for _, hotkey in pairs(self.hotkeys) do hotkey:delete() end
  self.hotkeys = {}
  if self.strategyUI then self.strategyUI:stop() end
  if self.vision then self.vision:stop() end
  self.started = false
  if self.logger then self.logger:info("bootstrap_stopped", { reason = reason or "shutdown" }) end
end

return Bootstrap
