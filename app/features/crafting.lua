local Catalog = require("app.config.catalog")

local Crafting = {}
Crafting.__index = Crafting

function Crafting.new(options)
  local snapshot = options.snapshot or {}
  return setmetatable({
    config = options.config or {},
    input = options.input,
    logger = options.logger,
    completed_mastery = math.max(0, tonumber(snapshot.completed_mastery) or 0),
    completed_crafts = math.max(0, tonumber(snapshot.completed_crafts) or 0),
    last_crafted_at = snapshot.last_crafted_at,
    timer = nil,
    cancelled = false,
    running = false,
  }, Crafting)
end

function Crafting:recordVictory(task)
  if task and task.difficulty == "Mastery" then self.completed_mastery = self.completed_mastery + 1 end
end

function Crafting:due(task)
  if not self.config.enabled then return false end
  local trigger = self.config.trigger or {}
  if trigger.type == "mastery_victories" then
    return self.completed_mastery > 0 and self.completed_mastery % math.max(1, trigger.every or 1) == 0
  end
  if trigger.type == "after_task" then return trigger.task == task.name end
  return false
end

function Crafting:snapshot()
  return {
    completed_mastery = self.completed_mastery,
    completed_crafts = self.completed_crafts,
    last_crafted_at = self.last_crafted_at,
  }
end

function Crafting:_workflow()
  if type(self.config.workflow) == "table" and #self.config.workflow > 0 then
    return self.config.workflow
  end
  return Catalog.crafting.rainbow_sprite.workflow
end

function Crafting:plan()
  if not self.config.enabled then return nil, "auto craft is disabled" end
  if not self.config.live_confirmation then
    return nil, "auto craft needs the live-confirmation setting before it can click"
  end
  local actions = self:_workflow()
  if type(actions) ~= "table" or #actions == 0 then
    return nil, "crafting workflow has not been calibrated"
  end
  local enabledRecipe = nil
  for _, recipe in ipairs(self.config.recipes or {}) do
    if recipe.enabled then
      if enabledRecipe then return nil, "only one auto-craft recipe can be enabled at a time" end
      enabledRecipe = recipe
      if recipe.allow_quick_craft then
        return nil, "quick craft is blocked because it can spend premium currency"
      end
      if recipe.requires_live_confirmation ~= false and not self.config.live_confirmation then
        return nil, "the selected recipe still needs live confirmation"
      end
    end
  end
  if not enabledRecipe then return nil, "no auto-craft recipe is enabled" end
  for index, action in ipairs(actions) do
    if type(action) ~= "table" then return nil, "crafting action " .. index .. " is invalid" end
    if action.type == "click" then
      if type(action.point) ~= "table" or type(action.point.x) ~= "number" or type(action.point.y) ~= "number" then
        return nil, "crafting click " .. index .. " has no calibrated point"
      end
    elseif action.type == "key" then
      if type(action.key) ~= "string" or action.key == "" then
        return nil, "crafting key " .. index .. " is invalid"
      end
    elseif action.type ~= "wait" then
      return nil, "unsupported crafting action: " .. tostring(action.type)
    end
  end
  return actions, nil, enabledRecipe
end

function Crafting:run(progress, callback)
  if self.running then callback(nil, "auto craft is already running") return end
  local actions, err, recipe = self:plan()
  if not actions then callback(nil, err) return end
  self.cancelled = false
  self.running = true
  local finished = false
  local function done(success, finishError)
    if finished then return end
    finished = true
    self.running = false
    if success then
      self.completed_crafts = self.completed_crafts + 1
      self.last_crafted_at = os.time()
      self.logger:info("crafting_completed", {
        recipe = recipe.name,
        completed_crafts = self.completed_crafts,
      })
    else
      self.logger:error("crafting_failed", { recipe = recipe.name, error = finishError })
    end
    callback(success, finishError, recipe)
  end
  local function later(milliseconds, fn)
    self.timer = hs.timer.doAfter(math.max(0, milliseconds or 0) / 1000, function()
      self.timer = nil
      if not self.cancelled then fn() end
    end)
  end
  local function step(index)
    if self.cancelled then return end
    local action = actions[index]
    if not action then done(true) return end
    progress("crafting", action.label or action.type)
    if action.type == "wait" then
      later(action.wait_ms or 500, function() step(index + 1) end)
      return
    end
    if action.type == "key" then
      local ok, keyError = self.input:key(action.key, action.repeats or 1, action.interval_ms)
      if not ok then done(nil, keyError) return end
      later(action.wait_ms or 500, function() step(index + 1) end)
      return
    end
    local ok, clickError = self.input:click(action.point, "crafting: " .. tostring(action.label), function(success, helperError)
      if not success then done(nil, helperError) return end
      later(action.wait_ms or 500, function() step(index + 1) end)
    end)
    if not ok then done(nil, clickError) end
  end
  step(1)
end

function Crafting:stop()
  self.cancelled = true
  self.running = false
  if self.timer then self.timer:stop() self.timer = nil end
end

return Crafting
