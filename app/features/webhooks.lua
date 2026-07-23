local Webhooks = {}
Webhooks.__index = Webhooks

local function jsonEscape(value)
  return tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
end

local function validDiscordURL(url)
  local allowedHosts = {
    ["discord.com"] = true,
    ["canary.discord.com"] = true,
    ["ptb.discord.com"] = true,
    ["discordapp.com"] = true,
  }
  local host = type(url) == "string"
    and url:match("^https://([^/]+)/api/webhooks/%d+/[%w_%-]+$")
    or nil
  return host ~= nil and allowedHosts[host:lower()] == true
end

function Webhooks.new(options)
  return setmetatable({
    config = options.config or {},
    logger = options.logger,
    capture = options.capture,
    tasks = {},
  }, Webhooks)
end

function Webhooks:_service()
  return self.config.keychain_service or "anime-expeditions-mac-discord-webhook"
end

function Webhooks:_keychain(arguments, callback)
  local task
  task = hs.task.new("/usr/bin/security", function(code, stdout, stderr)
    self.tasks[task] = nil
    callback(code == 0 and stdout:gsub("%s+$", "") or nil, code == 0 and nil or stderr)
  end, arguments)
  if not task or not task:start() then return nil, "could not run macOS Keychain command" end
  self.tasks[task] = true
  return true
end

function Webhooks:configured(callback)
  return self:_keychain({ "find-generic-password", "-s", self:_service(), "-w" }, function(value)
    callback(validDiscordURL(value))
  end)
end

function Webhooks:setURL(url, callback)
  if not validDiscordURL(url) then
    callback(nil, "that does not look like a Discord webhook URL")
    return
  end
  self:_keychain({
    "add-generic-password", "-U", "-a", "anime-expeditions-mac", "-s", self:_service(), "-w", url,
  }, function(_, err)
    callback(err == nil, err)
  end)
end

function Webhooks:_payload(event, fields)
  fields = fields or {}
  local title = "ae macro · " .. tostring(event)
  local lines = {}
  for _, key in ipairs({
    "task", "result", "duration", "attempt", "task_progress",
    "runs", "victories", "defeats", "rewards", "message",
  }) do
    if fields[key] ~= nil then table.insert(lines, key .. ": " .. tostring(fields[key])) end
  end
  return string.format('{"username":"ae macro","embeds":[{"title":"%s","description":"%s","color":%d}]}',
    jsonEscape(title), jsonEscape(table.concat(lines, "\n")), event == "victory" and 4905610 or 16750848)
end

function Webhooks:send(event, fields, screenshotPath, callback)
  callback = callback or function() end
  if not self.config.enabled then callback(true, "disabled") return end
  local allowed = false
  for _, name in ipairs(self.config.events or {}) do
    if name == event then allowed = true break end
  end
  if not allowed then callback(true, "event disabled") return end
  self:_keychain({ "find-generic-password", "-s", self:_service(), "-w" }, function(url, keychainError)
    if not url then callback(nil, keychainError or "webhook is not configured") return end
    if not validDiscordURL(url) then callback(nil, "stored webhook is not a Discord webhook URL") return end
    local payload = self:_payload(event, fields)
    if screenshotPath and self.config.include_screenshot then
      local file = io.open(screenshotPath, "rb")
      if file then
        local bytes = file:read("*a")
        file:close()
        local boundary = "ae-macro-" .. tostring(math.floor(hs.timer.secondsSinceEpoch() * 1000))
        local body = "--" .. boundary .. "\r\n"
          .. 'Content-Disposition: form-data; name="payload_json"\r\n'
          .. "Content-Type: application/json\r\n\r\n" .. payload .. "\r\n"
          .. "--" .. boundary .. "\r\n"
          .. 'Content-Disposition: form-data; name="file"; filename="roblox.png"\r\n'
          .. "Content-Type: image/png\r\n\r\n" .. bytes .. "\r\n"
          .. "--" .. boundary .. "--\r\n"
        hs.http.asyncPost(url, body, { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary }, function(status)
          local ok = status >= 200 and status < 300
          if not ok then self.logger:warn("webhook_failed", { event = event, status = status }) end
          callback(ok, ok and nil or ("Discord returned " .. tostring(status)))
        end)
        return
      end
    end
    hs.http.asyncPost(url, payload, { ["Content-Type"] = "application/json" }, function(status)
      local ok = status >= 200 and status < 300
      if not ok then self.logger:warn("webhook_failed", { event = event, status = status }) end
      callback(ok, ok and nil or ("Discord returned " .. tostring(status)))
    end)
  end)
end

function Webhooks:stop()
  for task in pairs(self.tasks) do task:terminate() end
  self.tasks = {}
end

return Webhooks
