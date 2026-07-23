local Schema = {}

local modes = { Story = true, Raid = true, Challenge = true, Expedition = true }

local function requireType(errors, value, expected, path)
  if type(value) ~= expected then
    table.insert(errors, path .. " must be " .. expected)
    return false
  end
  return true
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
      if not task.infinite and (type(task.repetitions) ~= "number" or task.repetitions < 1) then
        table.insert(errors, prefix .. ".repetitions must be >= 1 unless infinite")
      end
    end
  end
  if #errors > 0 then return nil, errors end
  return true, {}
end

return Schema

