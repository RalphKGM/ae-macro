local Schema = require("app.config.schema")

local ProfileStore = {}
ProfileStore.__index = ProfileStore

local function ensureDirectory(path)
  local directory = path:match("^(.*)/[^/]+$")
  if directory then hs.fs.mkdir(directory) end
end

function ProfileStore.new(path, json)
  return setmetatable({ path = path, json = json }, ProfileStore)
end

function ProfileStore:save(profile)
  local valid, errors = Schema.validate(profile)
  if not valid then return nil, table.concat(errors, "; ") end
  ensureDirectory(self.path)
  local temporary = self.path .. ".tmp"
  local file, err = io.open(temporary, "w")
  if not file then return nil, "cannot write profile: " .. tostring(err) end
  file:write(self.json.encode(profile, true))
  file:write("\n")
  file:close()
  local ok, renameError = os.rename(temporary, self.path)
  if not ok then
    os.remove(temporary)
    return nil, "cannot replace profile: " .. tostring(renameError)
  end
  return profile, self.path
end

return ProfileStore
