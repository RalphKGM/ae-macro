local Logger = {}
Logger.__index = Logger

local function encodeFallback(value)
  if type(value) == "table" then
    local parts = {}
    for key, item in pairs(value) do
      table.insert(parts, tostring(key) .. "=" .. tostring(item))
    end
    table.sort(parts)
    return table.concat(parts, " ")
  end
  return tostring(value)
end

function Logger.new(path, json)
  return setmetatable({ path = path, json = json }, Logger)
end

function Logger:write(level, event, fields)
  local record = fields or {}
  record.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
  record.level = level
  record.event = event
  local line = self.json and self.json.encode(record) or encodeFallback(record)
  local file = io.open(self.path, "a")
  if file then
    file:write(line, "\n")
    file:close()
  end
  print(string.format("[AnimeExpeditionsMac] %s %s", level, event))
end

function Logger:info(event, fields) self:write("info", event, fields) end
function Logger:warn(event, fields) self:write("warn", event, fields) end
function Logger:error(event, fields) self:write("error", event, fields) end

return Logger

