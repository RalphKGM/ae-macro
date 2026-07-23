local Schema = require("app.config.schema")
local Profiles = {}

function Profiles.load(path, json)
  local file, err = io.open(path, "r")
  if not file then return nil, "cannot open profile: " .. tostring(err) end
  local text = file:read("*a")
  file:close()
  local ok, profile = pcall(json.decode, text)
  if not ok then return nil, "profile JSON is invalid: " .. tostring(profile) end
  local valid, errors = Schema.validate(profile)
  if not valid then return nil, table.concat(errors, "; ") end
  return profile
end

return Profiles
