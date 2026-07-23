local Catalog = require("app.config.catalog")

local Navigation = {}
Navigation.__index = Navigation

function Navigation.new(options)
  return setmetatable({
    input = options.input,
    roblox = options.roblox,
    detector = options.detector,
    profile = options.profile,
    logger = options.logger,
    timer = nil,
    cancelled = false,
    before_start = nil,
  }, Navigation)
end

function Navigation:_after(milliseconds, callback)
  if self.timer then self.timer:stop() end
  self.timer = hs.timer.doAfter(math.max(0, milliseconds) / 1000, function()
    self.timer = nil
    if not self.cancelled then callback() end
  end)
end

function Navigation:_runActions(actions, index, progress, callback)
  if self.cancelled then return end
  local action = actions[index]
  if not action then callback(true) return end
  progress("navigation", action.label or action.type)
  local function nextAction(success, err)
    if not success then callback(nil, err) return end
    self:_after(action.wait_ms or 250, function()
      self:_runActions(actions, index + 1, progress, callback)
    end)
  end
  if action.type == "click" then
    local ok, err = self.input:click(action.point, action.label, nextAction)
    if not ok then callback(nil, err) end
  elseif action.type == "drag" then
    local ok, err = self.input:drag(action.from, action.to, action.duration_ms, action.label, nextAction)
    if not ok then callback(nil, err) end
  elseif action.type == "key" then
    local ok, err = self.input:key(action.key, action.repeats or 1, action.interval_ms)
    nextAction(ok, err)
  elseif action.type == "scroll" then
    local point = action.point or { x = 408, y = 319 }
    local ok, err = self.input:scrollAt(point, action.delta or 0, action.label, nextAction)
    if not ok then callback(nil, err) end
  elseif action.type == "wait" then
    nextAction(true)
  else
    callback(nil, "unsupported navigation action: " .. tostring(action.type))
  end
end

function Navigation:_route(task)
  if type(task.navigation_actions) == "table" then
    return {
      lobby = task.navigation_actions,
      team = task.team_actions or {},
      afk_return_to_lobby = task.afk_return_to_lobby or Catalog.routes.kings_tomb_act_1_mastery.afk_return_to_lobby,
      start_private_party = task.start_private_party or { x = 451, y = 420 },
      start_game = task.start_game or { x = 408, y = 193 },
      repeat_stage = task.repeat_stage or Catalog.results.repeat_stage,
    }
  end
  return Catalog.routeFor(task)
end

function Navigation:_fromLobby(route, progress, callback)
  local teamActions = route.team or {}
  self:_runActions(teamActions, 1, progress, function(teamSuccess, teamError)
    if not teamSuccess then callback(nil, teamError) return end
    self:_runActions(route.lobby, 1, progress, function(routeSuccess, routeError)
      if not routeSuccess then callback(nil, routeError) return end
      self:_waitForPartyReady(route, progress, callback)
    end)
  end)
end

function Navigation:_fromModeSelect(route, progress, callback)
  self:_runActions(route.lobby, 2, progress, function(routeSuccess, routeError)
    if not routeSuccess then callback(nil, routeError) return end
    self:_waitForPartyReady(route, progress, callback)
  end)
end

function Navigation:_waitForPartyReady(route, progress, callback, startedAt)
  startedAt = startedAt or (hs.timer.secondsSinceEpoch() * 1000)
  if (hs.timer.secondsSinceEpoch() * 1000) - startedAt >= 15000 then
    callback(nil, "navigation did not reach the private party screen")
    return
  end
  progress("navigation", "confirming private party")
  local id, err = self.detector:detect(function(result, detectError)
    if self.cancelled then return end
    if result and result.state == "party_ready" then
      self:_startParty(route, progress, callback)
      return
    end
    if result and result.state == "stage_select" then
      local match = result.templates and result.templates.select_stage
      local point = match and { x = match.center_x, y = match.center_y }
        or Catalog.v4_navigation.select_stage
      progress("navigation", "select stage is still visible; retrying")
      local clicked, clickError = self.input:click(point, "retry select stage", function(success, helperError)
        if not success then callback(nil, helperError) return end
        self:_after(850, function() self:_waitForPartyReady(route, progress, callback, startedAt) end)
      end)
      if not clicked then callback(nil, clickError) end
      return
    end
    if detectError then self.logger:warn("party_ready_detection_failed", { error = detectError }) end
    self:_after(900, function() self:_waitForPartyReady(route, progress, callback, startedAt) end)
  end, "party ready")
  if not id then
    if err then self.logger:warn("party_ready_request_failed", { error = err }) end
    self:_after(900, function() self:_waitForPartyReady(route, progress, callback, startedAt) end)
  end
end

function Navigation:_waitForBattle(route, progress, callback, startedAt, attempts)
  startedAt = startedAt or (hs.timer.secondsSinceEpoch() * 1000)
  attempts = attempts or 1
  local elapsed = (hs.timer.secondsSinceEpoch() * 1000) - startedAt
  local timeout = self.profile.navigation.stage_start_timeout_ms or 45000
  if elapsed >= timeout then
    callback(nil, "the stage did not enter battle before the start timeout")
    return
  end
  progress("navigation", "confirming battle started")
  local id, err = self.detector:detect(function(result, detectError)
    if self.cancelled then return end
    if not result then
      if detectError then self.logger:warn("battle_start_detection_failed", { error = detectError }) end
      self:_after(1200, function() self:_waitForBattle(route, progress, callback, startedAt, attempts) end)
      return
    end
    if result.state == "battle" then
      callback(true)
      return
    end
    if result.state == "unknown" and elapsed >= 1000 then
      self.logger:info("battle_started_after_start_disappeared", { elapsed_ms = elapsed })
      callback(true)
      return
    end
    if result.state == "stage_ready" and attempts < 4 then
      progress("navigation", "start game still visible; retrying")
      local clicked, clickError = self.input:click(route.start_game, "retry start game", function(success, helperError)
        if not success then callback(nil, helperError) return end
        self:_after(900, function()
          self:_waitForBattle(route, progress, callback, startedAt, attempts + 1)
        end)
      end)
      if not clicked then callback(nil, clickError) end
      return
    end
    if result.state == "victory" or result.state == "defeat" then
      callback(nil, "the previous result screen is still open after starting the stage")
      return
    end
    self:_after(1200, function() self:_waitForBattle(route, progress, callback, startedAt, attempts) end)
  end, "battle start")
  if not id then
    if err then self.logger:warn("battle_start_request_failed", { error = err }) end
    self:_after(1200, function() self:_waitForBattle(route, progress, callback, startedAt, attempts) end)
  end
end

function Navigation:_startGame(route, progress, callback)
  local function clickStart()
    progress("navigation", "starting stage")
    local ok, err = self.input:click(route.start_game, "start game", function(success, clickError)
      if not success then callback(nil, clickError) return end
      self:_after(1200, function() self:_waitForBattle(route, progress, callback) end)
    end)
    if not ok then callback(nil, err) end
  end
  if self.before_start then
    local prepare = self.before_start
    self.before_start = nil
    prepare(function(prepared, prepareError)
      if not prepared then callback(nil, prepareError) return end
      clickStart()
    end)
    return
  end
  clickStart()
end

function Navigation:_waitForStageReady(route, progress, callback, startedAt)
  startedAt = startedAt or (hs.timer.secondsSinceEpoch() * 1000)
  local elapsed = (hs.timer.secondsSinceEpoch() * 1000) - startedAt
  if elapsed >= (self.profile.navigation.load_timeout_ms or 90000) then
    callback(nil, "stage did not become ready before the load timeout")
    return
  end
  progress("navigation", "waiting for the stage")
  local id, err = self.detector:detect(function(result, detectError)
    if self.cancelled then return end
    if not result then
      self:_after(1800, function() self:_waitForStageReady(route, progress, callback, startedAt) end)
      return
    end
    if result.state == "stage_ready" then
      self:_startGame(route, progress, callback)
      return
    end
    self:_after(1800, function() self:_waitForStageReady(route, progress, callback, startedAt) end)
  end, "stage load")
  if not id then
    if err then self.logger:warn("stage_ready_detection_failed", { error = err }) end
    self:_after(1800, function() self:_waitForStageReady(route, progress, callback, startedAt) end)
  end
end

function Navigation:_startParty(route, progress, callback)
  progress("navigation", "starting private party")
  local ok, err = self.input:click(route.start_private_party, "start private party", function(success, clickError)
    if not success then callback(nil, clickError) return end
    self:_after(2200, function() self:_waitForStageReady(route, progress, callback) end)
  end)
  if not ok then callback(nil, err) end
end

function Navigation:_clickRepeat(route, detection, progress, callback)
  progress("navigation", "repeating stage")
  local match = detection and detection.templates and detection.templates.retry
  local point = route.repeat_stage or Catalog.results.repeat_stage
  if match and match.center_x and match.center_y then
    point = { x = match.center_x, y = match.center_y }
  end
  local ok, err = self.input:click(point, "repeat stage", function(success, clickError)
    if not success then callback(nil, clickError) return end
    self:_after(1800, function() self:_waitForStageReady(route, progress, callback) end)
  end)
  if not ok then callback(nil, err) end
end

function Navigation:_waitForRepeatControl(route, progress, callback, startedAt, resultsOpened)
  startedAt = startedAt or (hs.timer.secondsSinceEpoch() * 1000)
  if (hs.timer.secondsSinceEpoch() * 1000) - startedAt >= 18000 then
    callback(nil, "repeat stage did not become available")
    return
  end
  progress("navigation", resultsOpened and "waiting for repeat stage" or "checking result screen")
  local id, err = self.detector:detect(function(result, detectError)
    if self.cancelled then return end
    if not result then
      if detectError then self.logger:warn("repeat_detection_failed", { error = detectError }) end
      self:_after(700, function()
        self:_waitForRepeatControl(route, progress, callback, startedAt, resultsOpened)
      end)
      return
    end
    if result.state == "victory" or result.state == "defeat" then
      self:_clickRepeat(route, result, progress, callback)
      return
    end
    if result.state == "finished_stage" and not resultsOpened then
      progress("navigation", "opening game results")
      local clicked, clickError = self.input:click(Catalog.results.open_results, "open game results", function(success, helperError)
        if not success then callback(nil, helperError) return end
        self:_after(700, function()
          self:_waitForRepeatControl(route, progress, callback, startedAt, true)
        end)
      end)
      if not clicked then callback(nil, clickError) end
      return
    end
    if result.state == "stage_ready" then
      self:_startGame(route, progress, callback)
      return
    end
    self:_after(700, function()
      self:_waitForRepeatControl(route, progress, callback, startedAt, resultsOpened)
    end)
  end, "repeat stage")
  if not id then
    if err then self.logger:warn("repeat_request_failed", { error = err }) end
    self:_after(700, function()
      self:_waitForRepeatControl(route, progress, callback, startedAt, resultsOpened)
    end)
  end
end

function Navigation:_repeat(route, progress, callback)
  self:_waitForRepeatControl(route, progress, callback)
end

function Navigation:_waitForLobby(progress, callback, startedAt)
  startedAt = startedAt or (hs.timer.secondsSinceEpoch() * 1000)
  local timeout = self.profile.navigation.lobby_load_timeout_ms
    or self.profile.navigation.load_timeout_ms
    or 90000
  if (hs.timer.secondsSinceEpoch() * 1000) - startedAt >= timeout then
    callback(nil, "lobby did not load after leaving the results screen")
    return
  end
  progress("navigation", "waiting for lobby")
  local id, err = self.detector:detect(function(result, detectError)
    if self.cancelled then return end
    if result and result.state == "lobby" then
      callback(true)
      return
    end
    if result and result.state == "lobby_overlay" then
      progress("navigation", "closing lobby update window")
      local clicked, clickError = self.input:click(Catalog.overlays.lobby_modal_close, "close lobby overlay", function(closeSuccess, helperError)
        if not closeSuccess then callback(nil, helperError) return end
        self:_after(700, function() self:_waitForLobby(progress, callback, startedAt) end)
      end)
      if not clicked then callback(nil, clickError) end
      return
    end
    if detectError then self.logger:warn("lobby_return_detection_failed", { error = detectError }) end
    self:_after(1500, function() self:_waitForLobby(progress, callback, startedAt) end)
  end, "return to lobby")
  if not id then
    if err then self.logger:warn("lobby_return_request_failed", { error = err }) end
    self:_after(1500, function() self:_waitForLobby(progress, callback, startedAt) end)
  end
end

function Navigation:returnToLobby(progress, callback)
  self.cancelled = false
  local _, focusError = self.roblox:focus()
  if focusError then callback(nil, focusError) return end
  progress("navigation", "returning to lobby")
  local ok, err = self.input:click(Catalog.results.return_to_lobby, "return to lobby", function(success, clickError)
    if not success then callback(nil, clickError) return end
    self:_after(450, function()
      local confirmed, confirmError = self.input:click(
        Catalog.results.confirm_return_to_lobby,
        "confirm return to lobby",
        function(confirmSuccess, helperError)
          if not confirmSuccess then callback(nil, helperError) return end
          self:_after(900, function() self:_waitForLobby(progress, callback) end)
        end
      )
      if not confirmed then callback(nil, confirmError) end
    end)
  end)
  if not ok then callback(nil, err) end
end

function Navigation:_fromFinishedStage(route, progress, callback)
  self:_repeat(route, progress, callback)
end

function Navigation:_fromAfkChamber(route, progress, callback)
  progress("navigation", "returning from the afk chamber")
  local ok, err = self.input:click(route.afk_return_to_lobby, "return from afk chamber to lobby", function(success, clickError)
    if not success then callback(nil, clickError) return end
    self:_after(900, function()
      self:_waitForLobby(progress, function(lobbyReady, lobbyError)
        if not lobbyReady then callback(nil, lobbyError) return end
        self:_fromLobby(route, progress, callback)
      end)
    end)
  end)
  if not ok then callback(nil, err) end
end

function Navigation:start(task, startMode, progress, callback, beforeStart)
  self.cancelled = false
  self.before_start = beforeStart
  local route = self:_route(task)
  if not route then callback(nil, "no navigation route for " .. tostring(task.name)) return end
  local _, focusError = self.roblox:focus()
  if focusError then callback(nil, focusError) return end

  local function useMode(mode)
    if mode == "stage_ready" then self:_startGame(route, progress, callback) return end
    if mode == "battle" then callback(true) return end
    if mode == "party_ready" then self:_startParty(route, progress, callback) return end
    if mode == "stage_select" then self:_waitForPartyReady(route, progress, callback) return end
    if mode == "repeat" then self:_repeat(route, progress, callback) return end
    if mode == "finished_stage" then self:_fromFinishedStage(route, progress, callback) return end
    if mode == "afk_chamber" then self:_fromAfkChamber(route, progress, callback) return end
    if mode == "lobby_overlay" then
      progress("navigation", "closing lobby update window")
      local clicked, clickError = self.input:click(Catalog.overlays.lobby_modal_close, "close lobby overlay", function(success, helperError)
        if not success then callback(nil, helperError) return end
        self:_after(700, function() useMode("lobby") end)
      end)
      if not clicked then callback(nil, clickError) end
      return
    end
    if mode == "lobby" then
      self:_fromLobby(route, progress, callback)
      return
    end
    if mode == "mode_select" then
      self:_fromModeSelect(route, progress, callback)
      return
    end
    callback(nil, "cannot start from detected screen: " .. tostring(mode))
  end

  if startMode and startMode ~= "auto" then useMode(startMode) return end
  progress("navigation", "checking current screen")
  local id, err = self.detector:detect(function(result, detectError)
    if not result then callback(nil, detectError) return end
    local state = result.state
    if state == "victory" or state == "defeat" then state = "repeat" end
    if state == "unknown" then
      callback(nil, "current screen is not a safe navigation checkpoint")
      return
    end
    useMode(state)
  end, "navigation start")
  if not id then callback(nil, err) end
end

function Navigation:stop()
  self.cancelled = true
  self.before_start = nil
  if self.timer then self.timer:stop() self.timer = nil end
end

return Navigation
