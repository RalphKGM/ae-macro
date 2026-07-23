local Strategy = require("app.core.strategy")

local StrategyStore = {}
StrategyStore.__index = StrategyStore

function StrategyStore.new(directory, json)
  return setmetatable({ directory = directory, json = json }, StrategyStore)
end

function StrategyStore:path(id)
  return self.directory .. "/" .. Strategy.slug(id) .. ".json"
end

function StrategyStore:load(id)
  local path = self:path(id)
  local file, err = io.open(path, "r")
  if not file then return nil, "cannot open strategy: " .. tostring(err) end
  local text = file:read("*a")
  file:close()
  local ok, strategy = pcall(self.json.decode, text)
  if not ok then return nil, "strategy JSON is invalid: " .. tostring(strategy) end
  local valid, errors = Strategy.validate(strategy)
  if not valid then return nil, table.concat(errors, "; ") end
  return strategy
end

function StrategyStore:save(strategy)
  local copy = self.json.decode(self.json.encode(strategy))
  copy.id = Strategy.slug(copy.id or copy.name)
  local valid, errors = Strategy.validate(copy)
  if not valid then return nil, table.concat(errors, "; ") end
  local path = self:path(copy.id)
  local temporary = path .. ".tmp"
  local file, err = io.open(temporary, "w")
  if not file then return nil, tostring(err) end
  file:write(self.json.encode(copy, true), "\n")
  file:close()
  local ok, renameError = os.rename(temporary, path)
  if not ok then return nil, tostring(renameError) end
  return copy, path
end

function StrategyStore:list()
  local results = {}
  for filename in hs.fs.dir(self.directory) do
    if filename:match("%.json$") then
      local id = filename:gsub("%.json$", "")
      local strategy = self:load(id)
      if strategy then table.insert(results, Strategy.summary(strategy)) end
    end
  end
  table.sort(results, function(left, right) return left.name:lower() < right.name:lower() end)
  return results
end

function StrategyStore:delete(id)
  local path = self:path(id)
  if not hs.fs.attributes(path) then return nil, "strategy does not exist" end
  local ok, err = os.remove(path)
  if not ok then return nil, tostring(err) end
  return true
end

function StrategyStore:import(path)
  local file, err = io.open(path, "r")
  if not file then return nil, tostring(err) end
  local text = file:read("*a")
  file:close()
  local ok, strategy = pcall(self.json.decode, text)
  if not ok then return nil, "import JSON is invalid" end
  return self:save(strategy)
end

return StrategyStore
