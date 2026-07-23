local Schema = {}

local modes = { Story = true, Raid = true, Challenge = true, Expedition = true }

local function requireType(errors, value, expected, path)
  if type(value) ~= expected then
    table.insert(errors, path .. " must be " .. expected)
    return false
  end
  return true
end

local function validPoint(value, reference)
  local valid = type(value) == "table"
    and type(value.x) == "number" and value.x >= 0
    and type(value.y) == "number" and value.y >= 0
  if not valid then return false end
  if type(reference) == "table" then
    return value.x <= reference.w and value.y <= reference.h
  end
  return true
end

local function validateActions(errors, actions, path, reference)
  if type(actions) ~= "table" then
    table.insert(errors, path .. " must be table")
    return
  end
  for index, action in ipairs(actions) do
    local prefix = path .. "[" .. index .. "]"
    if type(action) ~= "table" then
      table.insert(errors, prefix .. " must be table")
    elseif action.type == "click" then
      if not validPoint(action.point, reference) then
        table.insert(errors, prefix .. ".point must be inside the reference canvas")
      end
    elseif action.type == "drag" then
      if not validPoint(action.from, reference) or not validPoint(action.to, reference) then
        table.insert(errors, prefix .. " drag points must be inside the reference canvas")
      end
    elseif action.type == "key" then
      if type(action.key) ~= "string" or action.key == "" then table.insert(errors, prefix .. ".key is required") end
    elseif action.type ~= "wait" then
      table.insert(errors, prefix .. ".type is unsupported")
    end
    if action.wait_ms ~= nil and (type(action.wait_ms) ~= "number" or action.wait_ms < 0) then
      table.insert(errors, prefix .. ".wait_ms must be zero or greater")
    end
  end
end

function Schema.validate(profile)
  local errors = {}
  if not requireType(errors, profile, "table", "profile") then return nil, errors end
  if profile.schema_version ~= 1 then table.insert(errors, "schema_version must be 1") end
  if requireType(errors, profile.reference_resolution, "table", "reference_resolution") then
    if not (profile.reference_resolution.w and profile.reference_resolution.w > 0) then table.insert(errors, "reference_resolution.w must be positive") end
    if not (profile.reference_resolution.h and profile.reference_resolution.h > 0) then table.insert(errors, "reference_resolution.h must be positive") end
  end
  if requireType(errors, profile.tasks, "table", "tasks") then
    for index, task in ipairs(profile.tasks) do
      local prefix = "tasks[" .. index .. "]"
      if type(task.name) ~= "string" or task.name == "" then table.insert(errors, prefix .. ".name is required") end
      if not modes[task.mode] then table.insert(errors, prefix .. ".mode is unsupported") end
      if type(task.map) ~= "string" or task.map == "" then table.insert(errors, prefix .. ".map is required") end
      if type(task.stage) ~= "string" or task.stage == "" then table.insert(errors, prefix .. ".stage is required") end
      if type(task.difficulty) ~= "string" or task.difficulty == "" then table.insert(errors, prefix .. ".difficulty is required") end
      if not task.infinite and (type(task.repetitions) ~= "number" or task.repetitions < 1) then
        table.insert(errors, prefix .. ".repetitions must be >= 1 unless infinite")
      end
      if task.navigation_actions ~= nil then
        validateActions(errors, task.navigation_actions, prefix .. ".navigation_actions", profile.reference_resolution)
      end
      if task.team_actions ~= nil then
        validateActions(errors, task.team_actions, prefix .. ".team_actions", profile.reference_resolution)
      end
      if task.mode == "Challenge" and task.challenge_kind ~= nil and type(task.challenge_kind) ~= "string" then
        table.insert(errors, prefix .. ".challenge_kind must be string")
      end
    end
  end
  if profile.runtime ~= nil and type(profile.runtime) ~= "table" then table.insert(errors, "runtime must be table") end
  if profile.camera ~= nil and type(profile.camera) ~= "table" then table.insert(errors, "camera must be table") end
  if profile.crafting ~= nil and type(profile.crafting) ~= "table" then table.insert(errors, "crafting must be table") end
  if profile.challenges ~= nil and type(profile.challenges) ~= "table" then table.insert(errors, "challenges must be table") end
  if profile.webhooks ~= nil and type(profile.webhooks) ~= "table" then table.insert(errors, "webhooks must be table") end
  if type(profile.crafting) == "table" and profile.crafting.workflow ~= nil then
    validateActions(errors, profile.crafting.workflow, "crafting.workflow", profile.reference_resolution)
  end
  if #errors > 0 then return nil, errors end
  return true, {}
end

return Schema
