local Checkpoint = {}

function Checkpoint.load(path, json)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  local ok, data = pcall(json.decode, text)
  if not ok or type(data) ~= "table" then return nil, "invalid checkpoint JSON" end
  return data
end

function Checkpoint.save(path, json, data)
  local temp = path .. ".tmp"
  local file, err = io.open(temp, "w")
  if not file then return nil, err end
  file:write(json.encode(data, true))
  file:close()
  local ok, renameErr = os.rename(temp, path)
  if not ok then return nil, renameErr end
  return true
end

return Checkpoint

