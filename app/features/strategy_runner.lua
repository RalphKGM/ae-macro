local Catalog = require("app.config.catalog")
local Strategy = require("app.core.strategy")

local StrategyRunner = {}
StrategyRunner.__index = StrategyRunner

local function nowMilliseconds()
  return hs.timer.secondsSinceEpoch() * 1000
end

local function timeline(actions)
  local result = {}
  local cursor = 0
  for _, action in ipairs(actions or {}) do
    local copy = {}
    for key, value in pairs(action) do copy[key] = value end
    if copy.at_ms ~= nil then
      cursor = copy.at_ms
    elseif copy.type == "wait" then
      cursor = cursor + (copy.duration_ms or 0)
    else
      cursor = cursor + (copy.delay_ms or 0)
    end
    copy._at_ms = cursor
    table.insert(result, copy)
  end
  table.sort(result, function(left, right)
    if left._at_ms == right._at_ms then return tostring(left.id) < tostring(right.id) end
    return left._at_ms < right._at_ms
  end)
  return result
end

function StrategyRunner.new(options)
  return setmetatable({
    input = options.input,
    logger = options.logger,
    timer = nil,
    actions = {},
    placements = {},
    index = 1,
    started_at = nil,
    paused_at = nil,
    paused_total = 0,
    running = false,
    progress = nil,
    callback = nil,
  }, StrategyRunner)
end

function StrategyRunner:_after(milliseconds, callback)
  if self.timer then self.timer:stop() end
  self.timer = hs.timer.doAfter(math.max(0, milliseconds) / 1000, function()
    self.timer = nil
    if self.running and not self.paused_at then callback() end
  end)
end

function StrategyRunner:_elapsed()
  if not self.started_at then return 0 end
  local endpoint = self.paused_at or nowMilliseconds()
  return math.max(0, endpoint - self.started_at - self.paused_total)
end

function StrategyRunner:_clickThen(point, reason, delay, callback)
  local ok, err = self.input:click(point, reason, function(success, clickError)
    if not success then callback(nil, clickError) return end
    self:_after(delay or 320, function() callback(true) end)
  end)
  if not ok then callback(nil, err) end
end

function StrategyRunner:_placement(action)
  if action.type == "place" then return action end
  return self.placements[action.placement_id]
end

function StrategyRunner:_place(action, callback)
  local slot = Catalog.unit_bar[action.unit_slot]
  if not slot then callback(nil, "unit slot is outside 1-6") return end
  self:_clickThen(slot, "select unit slot " .. tostring(action.unit_slot), 360, function(selected, selectError)
    if not selected then callback(nil, selectError) return end
    self:_clickThen({ x = action.x, y = action.y }, "place " .. tostring(action.id), 420, function(placed, placeError)
      if placed then self.placements[action.id] = action end
      callback(placed, placeError)
    end)
  end)
end

function StrategyRunner:_unitPanelAction(action, control, callback)
  local placement = self:_placement(action)
  if not placement then callback(nil, "placement not found for " .. tostring(action.id)) return end
  self:_clickThen({ x = placement.x, y = placement.y }, "select placed unit " .. tostring(placement.id), 350, function(selected, selectError)
    if not selected then callback(nil, selectError) return end
    self:_clickThen(control, action.type .. " " .. tostring(placement.id), 380, callback)
  end)
end

function StrategyRunner:_upgrade(action, callback)
  local levels = action.levels == "max" and 12 or math.max(1, tonumber(action.levels) or 1)
  local placement = self:_placement(action)
  if not placement then callback(nil, "upgrade placement was not found") return end
  self:_clickThen({ x = placement.x, y = placement.y }, "select unit for upgrade", 350, function(selected, selectError)
    if not selected then callback(nil, selectError) return end
    local function clickLevel(remaining)
      if remaining <= 0 then callback(true) return end
      self:_clickThen(Catalog.unit_panel.upgrade, "upgrade unit", 420, function(upgraded, upgradeError)
        if not upgraded then callback(nil, upgradeError) return end
        clickLevel(remaining - 1)
      end)
    end
    clickLevel(levels)
  end)
end

function StrategyRunner:_execute(action, callback)
  if action.type == "place" then self:_place(action, callback) return end
  if action.type == "auto_upgrade" then
    self:_unitPanelAction(action, Catalog.unit_panel.auto_upgrade, callback)
    return
  end
  if action.type == "upgrade" then self:_upgrade(action, callback) return end
  if action.type == "ability" then
    self:_unitPanelAction(action, Catalog.unit_panel.ability, callback)
    return
  end
  if action.type == "target" then
    self:_unitPanelAction(action, Catalog.unit_panel.priority, callback)
    return
  end
  if action.type == "sell" then
    self:_unitPanelAction(action, Catalog.unit_panel.sell, callback)
    return
  end
  if action.type == "wait" then callback(true) return end
  if action.type == "conditional" then
    if action.condition == "never" then callback(true) return end
    callback(true)
    return
  end
  callback(nil, "unsupported strategy action: " .. tostring(action.type))
end

function StrategyRunner:_next()
  if not self.running or self.paused_at then return end
  local action = self.actions[self.index]
  if not action then
    self.running = false
    if self.callback then self.callback(true) end
    return
  end
  local wait = math.max(0, action._at_ms - self:_elapsed())
  self:_after(wait, function()
    if self.progress then
      self.progress("strategy", string.format("%s (%d/%d)", action.type, self.index, #self.actions), action)
    end
    self.logger:info("strategy_action_started", {
      id = action.id, type = action.type, at_ms = action._at_ms, elapsed_ms = self:_elapsed(),
    })
    local function completed(success, err)
      if not self.running and not success then return end
      if not success then
        self.running = false
        self.logger:error("strategy_action_failed", { id = action.id, type = action.type, error = err })
        if self.callback then self.callback(nil, err) end
        return
      end
      self.logger:info("strategy_action_completed", { id = action.id, type = action.type })
      self.index = self.index + 1
      self:_next()
    end
    local executed, thrown = xpcall(function()
      self:_execute(action, completed)
    end, debug.traceback)
    if not executed then
      self.running = false
      self.logger:error("strategy_action_exception", {
        id = action.id, type = action.type, error = tostring(thrown),
      })
      if self.callback then self.callback(nil, tostring(thrown)) end
    end
  end)
end

function StrategyRunner:start(strategy, battleStartedAt, progress, callback)
  local valid, errors = Strategy.validate(strategy)
  if not valid then callback(nil, table.concat(errors, "; ")) return nil end
  self:stop("restart")
  self.actions = timeline(strategy.actions)
  self.placements = {}
  for _, action in ipairs(strategy.actions) do
    if action.type == "place" then self.placements[action.id] = action end
  end
  self.index = 1
  self.started_at = battleStartedAt or nowMilliseconds()
  self.paused_at = nil
  self.paused_total = 0
  self.progress = progress
  self.callback = callback
  self.running = true
  self:_next()
  return true
end

function StrategyRunner:pause()
  if not self.running or self.paused_at then return false end
  self.paused_at = nowMilliseconds()
  if self.timer then self.timer:stop() self.timer = nil end
  return true
end

function StrategyRunner:resume()
  if not self.running or not self.paused_at then return false end
  self.paused_total = self.paused_total + (nowMilliseconds() - self.paused_at)
  self.paused_at = nil
  self:_next()
  return true
end

function StrategyRunner:stop(reason)
  if self.timer then self.timer:stop() self.timer = nil end
  if self.running and reason then self.logger:info("strategy_runner_stopped", { reason = reason }) end
  self.running = false
  self.paused_at = nil
end

return StrategyRunner
