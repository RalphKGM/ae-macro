local Strategy = {}

local actionTypes = {
  place = true,
  upgrade = true,
  ability = true,
  target = true,
  sell = true,
  wait = true,
}

local targetModes = {
  first = true,
  last = true,
  strongest = true,
  weakest = true,
  closest = true,
  flying = true,
}

local abilityModes = { once = true, auto = true, off = true }

local function add(errors, path, message)
  table.insert(errors, path .. " " .. message)
end

local function finiteNumber(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function nonempty(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

function Strategy.new(options)
  options = options or {}
  return {
    schema_version = 1,
    id = options.id or "new-strategy",
    name = options.name or "New Strategy",
    map = options.map or "King's Tomb",
    stage = options.stage or "Act 1",
    difficulty = options.difficulty or "Mastery",
    team = options.team or "current",
    reference_resolution = options.reference_resolution or { w = 816, h = 638 },
    actions = {},
  }
end

function Strategy.slug(value)
  local slug = tostring(value or ""):lower():gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", "")
  return slug ~= "" and slug:sub(1, 64) or "strategy"
end

function Strategy.validate(strategy)
  local errors = {}
  if type(strategy) ~= "table" then return nil, { "strategy must be a table" } end
  if strategy.schema_version ~= 1 then add(errors, "schema_version", "must be 1") end
  if not nonempty(strategy.id) then add(errors, "id", "is required") end
  if not nonempty(strategy.name) then add(errors, "name", "is required") end
  if not nonempty(strategy.map) then add(errors, "map", "is required") end
  if not nonempty(strategy.stage) then add(errors, "stage", "is required") end
  if not nonempty(strategy.difficulty) then add(errors, "difficulty", "is required") end
  if not nonempty(strategy.team) then add(errors, "team", "is required") end

  local reference = strategy.reference_resolution
  if type(reference) ~= "table" or not finiteNumber(reference.w) or reference.w <= 0
      or not finiteNumber(reference.h) or reference.h <= 0 then
    add(errors, "reference_resolution", "must contain positive w and h")
    reference = { w = 816, h = 638 }
  end

  if type(strategy.actions) ~= "table" then
    add(errors, "actions", "must be an array")
    return nil, errors
  end

  local ids = {}
  local placements = {}
  for index, action in ipairs(strategy.actions) do
    local path = "actions[" .. index .. "]"
    if type(action) ~= "table" then
      add(errors, path, "must be an object")
    else
      if not nonempty(action.id) then
        add(errors, path .. ".id", "is required")
      elseif ids[action.id] then
        add(errors, path .. ".id", "must be unique")
      else
        ids[action.id] = true
      end
      if not actionTypes[action.type] then add(errors, path .. ".type", "is unsupported") end
      if action.delay_ms ~= nil and (not finiteNumber(action.delay_ms) or action.delay_ms < 0) then
        add(errors, path .. ".delay_ms", "must be zero or greater")
      end

      if action.type == "place" then
        if not finiteNumber(action.unit_slot) or action.unit_slot < 1 or action.unit_slot > 6 or action.unit_slot % 1 ~= 0 then
          add(errors, path .. ".unit_slot", "must be an integer from 1 to 6")
        end
        if not finiteNumber(action.x) or action.x < 0 or action.x > reference.w then
          add(errors, path .. ".x", "is outside the reference canvas")
        end
        if not finiteNumber(action.y) or action.y < 0 or action.y > reference.h then
          add(errors, path .. ".y", "is outside the reference canvas")
        end
        if action.target_mode and not targetModes[action.target_mode] then add(errors, path .. ".target_mode", "is unsupported") end
        if action.ability_mode and not abilityModes[action.ability_mode] then add(errors, path .. ".ability_mode", "is unsupported") end
        if action.upgrade_target ~= nil and action.upgrade_target ~= "max"
            and (not finiteNumber(action.upgrade_target) or action.upgrade_target < 0 or action.upgrade_target % 1 ~= 0) then
          add(errors, path .. ".upgrade_target", "must be max or a non-negative integer")
        end
        if nonempty(action.id) then placements[action.id] = true end
      elseif action.type == "wait" then
        if not finiteNumber(action.duration_ms) or action.duration_ms < 0 then
          add(errors, path .. ".duration_ms", "must be zero or greater")
        end
      elseif action.type and actionTypes[action.type] then
        if not nonempty(action.placement_id) then
          add(errors, path .. ".placement_id", "is required")
        elseif not placements[action.placement_id] then
          add(errors, path .. ".placement_id", "must reference an earlier placement")
        end
        if action.type == "upgrade" and action.levels ~= "max"
            and (not finiteNumber(action.levels) or action.levels < 1 or action.levels % 1 ~= 0) then
          add(errors, path .. ".levels", "must be max or a positive integer")
        end
        if action.type == "ability" and not abilityModes[action.mode] then add(errors, path .. ".mode", "is unsupported") end
        if action.type == "target" and not targetModes[action.mode] then add(errors, path .. ".mode", "is unsupported") end
      end
    end
  end

  if #errors > 0 then return nil, errors end
  return true, {}
end

function Strategy.summary(strategy)
  local placements = 0
  for _, action in ipairs(strategy.actions or {}) do
    if action.type == "place" then placements = placements + 1 end
  end
  return {
    id = strategy.id,
    name = strategy.name,
    map = strategy.map,
    stage = strategy.stage,
    difficulty = strategy.difficulty,
    team = strategy.team,
    actions = #(strategy.actions or {}),
    placements = placements,
  }
end

return Strategy

