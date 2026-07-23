local Checkpoint = require("app.core.checkpoint")
local StateMachine = require("app.core.state_machine")
local TaskQueue = require("app.core.task_queue")
local Stats = require("app.core.stats")

local Automation = {}
Automation.__index = Automation

local function sameStage(left, right)
  return left and right
    and left.mode == right.mode
    and left.map == right.map
    and left.stage == right.stage
    and left.difficulty == right.difficulty
end

function Automation.new(options)
  local checkpoint = options.checkpoint or {}
  return setmetatable({
    root = options.root,
    profile = options.profile,
    strategyStore = options.strategyStore,
    input = options.input,
    roblox = options.roblox,
    navigation = options.navigation,
    camera = options.camera,
    runner = options.runner,
    watcher = options.watcher,
    crafting = options.crafting,
    challenges = options.challenges,
    webhooks = options.webhooks,
    logger = options.logger,
    machine = options.machine or StateMachine.new(options.logger),
    queue = TaskQueue.new(options.profile.tasks, checkpoint),
    stats = Stats.new(checkpoint.stats),
    checkpoint_path = options.root .. "/runtime/checkpoint.json",
    emit = options.emit or function() end,
    active = false,
    paused = false,
    timer = nil,
    battle_started_at = nil,
    current_strategy = nil,
    consecutive_failures = 0,
    selected_task_index = nil,
  }, Automation)
end

function Automation:setEmitter(callback)
  self.emit = callback or function() end
end

function Automation:setProfile(profile)
  self.profile = profile
  self.navigation.profile = profile
  self.camera.profile = profile
  self.watcher.timeout_ms = profile.navigation.result_timeout_ms or 600000
  self.crafting.config = profile.crafting or {}
  self.challenges.config = profile.challenges or {}
  self.webhooks.config = profile.webhooks or {}
end

function Automation:_event(event, payload)
  payload = payload or {}
  payload.state = self.machine.state
  payload.stats = self.stats:snapshot()
  payload.challenges = self.challenges:snapshot()
  payload.crafting = self.crafting:snapshot()
  self.emit(event, payload)
end

function Automation:_progress(area, message, action)
  self.logger:info("automation_progress", { area = area, message = message })
  self:_event("progress", { area = area, message = message, action = action })
end

function Automation:_checkpoint()
  Checkpoint.save(self.checkpoint_path, hs.json, {
    task_index = self.queue.index,
    repetition = self.queue.repetition,
    stats = self.stats:snapshot(),
    crafting = self.crafting:snapshot(),
    challenges = self.challenges:snapshot(),
    saved_at = os.time(),
  })
end

function Automation:_advanceMachineToStage()
  local states = {
    { "MODE_SELECT", "navigation ready" },
    { "MAP_SELECT", "mode selected" },
    { "STAGE_SELECT", "map selected" },
    { "TEAM_SELECT", "stage selected" },
    { "MATCHMAKING", "team ready" },
    { "LOAD_WAIT", "party started" },
    { "IN_STAGE", "stage loaded" },
  }
  for _, entry in ipairs(states) do self.machine:transition(entry[1], entry[2]) end
end

function Automation:_fail(message)
  if not self.active then return end
  self.logger:error("automation_failed", { error = message, state = self.machine.state })
  self.navigation:stop()
  self.camera:stop()
  self.runner:stop("automation error")
  self.watcher:stop()
  self.crafting:stop()
  self.challenges:stop()
  if self.machine.state ~= "IDLE" and self.machine.state ~= "RECOVERY" then
    local ok = pcall(function() self.machine:transition("RECOVERY", message) end)
    if not ok then self.machine:stop(message) end
  end
  self.webhooks:send("error", { task = self.queue:current() and self.queue:current().name, message = message })
  self:_event("error", { message = message })
  self:stop("error")
end

function Automation:_loadStrategy(task)
  local strategy, err = self.strategyStore:load(task.strategy)
  if not strategy then return nil, err or ("strategy not found: " .. tostring(task.strategy)) end
  return strategy
end

function Automation:_beginBattle(task, startMode, challengeChecked)
  local challengeKind = self.challenges:taskKind(task)
  if challengeKind and self.challenges.config.enabled and startMode == "lobby" and not challengeChecked then
    self.challenges:checkFromLobby(
      challengeKind,
      function(area, message) self:_progress(area, message) end,
      function(status, challengeError)
        if not self.active then return end
        if not status then self:_fail(challengeError) return end
        self:_event("challenge_checked", { task = task.name, challenge = status })
        if not status.available then
          self.queue:skip()
          self:_checkpoint()
          self:_continue(task, { already_in_lobby = true })
          return
        end
        self:_beginBattle(task, startMode, true)
      end
    )
    return
  end
  self:_progress("run", "starting " .. task.name)
  self.navigation:start(task, startMode, function(area, message)
    self:_progress(area, message)
  end, function(success, navigationError)
    if not self.active then return end
    if not success then self:_fail(navigationError) return end
    self:_advanceMachineToStage()
    self.stats:startRun()
    self.battle_started_at = hs.timer.secondsSinceEpoch() * 1000 - 900
    self:_checkpoint()
    self:_event("run_started", { task = task.name })

    local function execute()
      if not self.active then return end
      self.machine:transition("EXECUTE_STRATEGY", "camera ready")
      self.watcher:start(function(result, resultError, detection)
        if resultError then self:_fail(resultError) return end
        self:_handleResult(result, detection)
      end)
      local started, runnerError = self.runner:start(
        self.current_strategy,
        self.battle_started_at,
        function(area, message, action) self:_progress(area, message, action) end,
        function(strategyComplete, strategyError)
          if strategyError then self:_fail(strategyError) return end
          if strategyComplete then self:_event("strategy_complete", { task = task.name }) end
        end
      )
      if not started then self:_fail(runnerError) return end
      self.machine:transition("IN_BATTLE", "strategy running")
    end

    if self.profile.runtime.auto_camera then
      self.camera:setup(task, function(area, message) self:_progress(area, message) end, function(result, cameraError)
        if not result then self:_fail(cameraError) return end
        self:_event("camera_ready", { path = result.output_path, task = task.name, reused_map = result.reused_map })
        execute()
      end)
    else
      execute()
    end
  end)
end

function Automation:_nextStartMode(previous, nextTask)
  if sameStage(previous, nextTask) then return "repeat" end
  return "lobby"
end

function Automation:_runnableTask(allowRestart)
  local maximum = math.max(1, #self.queue.tasks)
  local inspected = 0
  local restarted = false
  while inspected < maximum do
    local task = self.queue:current()
    if not task and allowRestart and self.profile.runtime.queue_start_over and not restarted then
      restarted = true
      task = self.queue:restart()
    end
    if not task then return nil end
    local allowed, challenge = self.challenges:allowsTask(task)
    if allowed then return task end
    self:_event("challenge_skipped", {
      task = task.name,
      challenge = challenge,
      message = string.format("%s is capped at %d/%d", task.name, challenge.current, challenge.maximum),
    })
    self.webhooks:send("challenge", {
      task = task.name,
      result = "capped",
      current = challenge.current,
      maximum = challenge.maximum,
    })
    self.queue:skip()
    inspected = inspected + 1
  end
  return nil
end

function Automation:_complete()
  self.machine:transition("COMPLETE", "task queue completed")
  self:_event("complete", { message = "task queue complete" })
  self.webhooks:send("stopped", {
    message = "task queue complete",
    runs = self.stats.runs,
    victories = self.stats.victories,
    defeats = self.stats.defeats,
  })
  self:stop("complete")
end

function Automation:_scheduleBattle(task, mode)
  local strategy, err = self:_loadStrategy(task)
  if not strategy then self:_fail(err) return end
  self.current_strategy = strategy
  self.timer = hs.timer.doAfter(2, function()
    self.timer = nil
    self:_beginBattle(task, mode)
  end)
end

function Automation:_continue(previousTask, options)
  options = options or {}
  local nextTask = self:_runnableTask(true)
  if not nextTask then
    self:_complete()
    return
  end

  if options.already_in_lobby then
    if self.machine.state ~= "LOBBY_DETECT" then self.machine:transition("LOBBY_DETECT", "next run from lobby") end
    self:_scheduleBattle(nextTask, "lobby")
    return
  end

  local mode = self:_nextStartMode(previousTask, nextTask)
  if mode == "repeat" then
    self.machine:transition("LOBBY_DETECT", "repeat current stage")
    self:_scheduleBattle(nextTask, "repeat")
    return
  end

  if not self.profile.runtime.allow_return_to_lobby then
    self:_fail("next task needs the lobby; enable explicit return-to-lobby in settings")
    return
  end
  self.machine:transition("LOBBY_DETECT", "returning for next task")
  self.navigation:returnToLobby(function(area, message) self:_progress(area, message) end, function(success, lobbyError)
    if not self.active then return end
    if not success then self:_fail(lobbyError) return end
    self:_scheduleBattle(nextTask, "lobby")
  end)
end

function Automation:_craftThenContinue(previousTask)
  self.machine:transition("LOBBY_DETECT", "auto craft due")
  self.navigation:returnToLobby(function(area, message) self:_progress(area, message) end, function(success, lobbyError)
    if not self.active then return end
    if not success then self:_fail(lobbyError) return end
    self.machine:transition("AUTO_CRAFT", "lobby ready for crafting")
    self.crafting:run(function(area, message) self:_progress(area, message) end, function(crafted, craftError, recipe)
      if not self.active then return end
      if not crafted then
        if self.crafting.config.on_failure == "continue" then
          self:_event("craft_skipped", { message = craftError })
          self.machine:transition("LOBBY_DETECT", "craft skipped")
          self:_checkpoint()
          self:_continue(previousTask, { already_in_lobby = true })
          return
        end
        self:_fail(craftError)
        return
      end
      self:_event("craft", { recipe = recipe and recipe.name, message = "auto craft complete" })
      self.webhooks:send("craft", { recipe = recipe and recipe.name, result = "complete" })
      self.machine:transition("LOBBY_DETECT", "auto craft complete")
      self:_checkpoint()
      self:_continue(previousTask, { already_in_lobby = true })
    end)
  end)
end

function Automation:_handleResult(result, detection)
  if not self.active then return end
  local task = self.queue:current()
  self.runner:stop("result detected")
  self.watcher:stop()
  self.machine:transition("RESULTS", result)
  local duration = self.stats:record(result)
  local screenshot = detection and detection.image_path
  self:_event("result", {
    result = result,
    task = task and task.name,
    duration = duration,
    screenshot = screenshot,
  })
  self.webhooks:send(result, {
    task = task and task.name,
    result = result,
    duration = duration .. "s",
    runs = self.stats.runs,
    victories = self.stats.victories,
    defeats = self.stats.defeats,
  }, screenshot)

  if result == "victory" then
    self.consecutive_failures = 0
    self.crafting:recordVictory(task)
    local challenge = self.challenges:recordVictory(task)
    if challenge then
      self:_event("challenge", { task = task.name, challenge = challenge })
    end
    self.queue:recordSuccess()
    self:_checkpoint()
    if self.crafting:due(task) then
      self:_craftThenContinue(task)
      return
    end
    self:_continue(task)
    return
  end

  self.consecutive_failures = self.consecutive_failures + 1
  local retry = task.retry or {}
  if self.consecutive_failures <= (retry.maximum_consecutive_failures or 0) then
    self:_checkpoint()
    self.machine:transition("LOBBY_DETECT", "retry after defeat")
    self.timer = hs.timer.doAfter(2, function()
      self.timer = nil
      self:_beginBattle(task, "repeat")
    end)
    return
  end
  if retry.on_exhausted == "skip" then
    self.queue:skip()
    self:_checkpoint()
    self:_continue(task)
    return
  end
  self:_fail("retry limit reached")
end

function Automation:start(options)
  options = options or {}
  if self.active then return nil, "the macro is already running" end
  local permissions = require("app.platform.permissions").check(false)
  if not require("app.platform.permissions").ready(permissions) then return nil, "macOS permissions are missing" end
  local startIndex = math.max(1, math.floor(options.task_index or 1))
  self.queue = TaskQueue.new(self.profile.tasks, { task_index = startIndex, repetition = 0 })
  local task = self:_runnableTask(false)
  if not task then return nil, "there are no enabled tasks to run" end
  local strategy, strategyError = self:_loadStrategy(task)
  if not strategy then return nil, strategyError end
  local window, focusError = self.roblox:focus()
  if not window then return nil, focusError end
  if self.profile.runtime.align_before_run then
    local _, alignError = self.roblox:align(self.profile.reference_resolution)
    if alignError then return nil, alignError end
    self.roblox:focus()
  end

  self.active = true
  self.paused = false
  self.current_strategy = strategy
  self.selected_task_index = startIndex
  self.consecutive_failures = 0
  self.input:beginSession("ae run")
  self.machine:transition("ATTACH_ROBLOX", "gui start")
  self.machine:transition("CALIBRATE", "roblox attached")
  self.machine:transition("LOBBY_DETECT", "ready to navigate")
  self:_event("started", { task = task.name })
  self.webhooks:send("started", { task = task.name })
  self:_beginBattle(task, options.start_action or self.profile.runtime.start_action or "auto")
  return true
end

function Automation:pause()
  if not self.active or self.paused then return false end
  self.paused = true
  self.machine:pause()
  self.runner:pause()
  self.watcher:stop()
  self.input:endSession("paused")
  self:_event("paused", { message = "macro paused" })
  return true
end

function Automation:resume()
  if not self.active or not self.paused then return false end
  self.paused = false
  self.machine:resume()
  self.input:beginSession("ae run resumed")
  self.runner:resume()
  self.watcher:start(function(result, resultError, detection)
    if resultError then self:_fail(resultError) return end
    self:_handleResult(result, detection)
  end)
  self:_event("resumed", { message = "macro resumed" })
  return true
end

function Automation:stop(reason)
  local wasActive = self.active
  self.active = false
  self.paused = false
  if self.timer then self.timer:stop() self.timer = nil end
  self.navigation:stop()
  self.camera:stop()
  self.runner:stop(reason or "stopped")
  self.watcher:stop()
  self.crafting:stop()
  self.challenges:stop()
  self.input:endSession(reason or "stopped")
  if self.machine.state ~= "IDLE" then
    local ok = pcall(function() self.machine:stop(reason or "stopped") end)
    if not ok then
      self.machine.state = "IDLE"
      self.machine.paused = false
    end
  end
  self:_checkpoint()
  if wasActive then self:_event("stopped", { message = reason or "stopped" }) end
  return true
end

function Automation:status()
  return {
    active = self.active,
    paused = self.paused,
    state = self.machine.state,
    task = self.queue:current() and self.queue:current().name,
    task_index = self.queue.index,
    repetition = self.queue.repetition,
    stats = self.stats:snapshot(),
    challenges = self.challenges:snapshot(),
    crafting = self.crafting:snapshot(),
  }
end

return Automation
