local VisionClient = {}
VisionClient.__index = VisionClient

function VisionClient.new(options)
  return setmetatable({
    root = options.root,
    python = options.python,
    port = options.port or 47681,
    token = options.token,
    logger = options.logger,
    socket = nil,
    task = nil,
    next_id = 1,
    callbacks = {},
  }, VisionClient)
end

function VisionClient:start(onReady)
  local arguments = {
    "-m", "vision.server", "--host", "127.0.0.1", "--port", tostring(self.port),
    "--token", self.token, "--root", self.root,
  }
  self.task = hs.task.new(self.python, function(exitCode, stdout, stderr)
    self.logger:error("vision_worker_exit", { exit_code = exitCode, stdout = stdout, stderr = stderr })
  end, function(_, stdout, stderr)
    if stdout and stdout ~= "" then self.logger:info("vision_stdout", { text = stdout }) end
    if stderr and stderr ~= "" then self.logger:warn("vision_stderr", { text = stderr }) end
    return true
  end, arguments)
  if not self.task then return nil, "could not create vision worker task" end
  self.task:setWorkingDirectory(self.root)
  if not self.task:start() then return nil, "could not start vision worker" end
  self:_connectWithRetry(0, onReady)
  return true
end

function VisionClient:_connectWithRetry(attempt, onReady)
  if attempt >= 20 then
    self.logger:error("vision_connect_timeout", { port = self.port })
    if onReady then onReady(nil, "vision worker did not accept connections") end
    return
  end
  hs.timer.doAfter(attempt == 0 and 0.15 or 0.25, function()
    self.socket = hs.socket.new(function(data)
      local ok, response = pcall(hs.json.decode, data)
      if ok and response then
        local callback = self.callbacks[response.id]
        self.callbacks[response.id] = nil
        if callback then callback(response.ok and response.result or nil, response.ok and nil or response.error) end
      else
        self.logger:error("vision_invalid_response", { data = data })
      end
      if self.socket and self.socket:connected() then self.socket:read("\n") end
    end)
    local socket = self.socket
    local connected = socket:connect("127.0.0.1", self.port, function()
      self.socket:read("\n")
      self:request("ping", {}, function(result, err)
        if onReady then onReady(result, err) end
      end)
    end)
    if not connected then
      self:_connectWithRetry(attempt + 1, onReady)
      return
    end
    hs.timer.doAfter(0.2, function()
      if self.socket == socket and not socket:connected() then
        socket:disconnect()
        self:_connectWithRetry(attempt + 1, onReady)
      end
    end)
  end)
end

function VisionClient:request(operation, payload, callback)
  if not self.socket or not self.socket:connected() then return nil, "vision worker is disconnected" end
  local id = self.next_id
  self.next_id = self.next_id + 1
  self.callbacks[id] = callback
  local request = { id = id, token = self.token, op = operation, payload = payload or {} }
  self.socket:write(hs.json.encode(request) .. "\n")
  return id
end

function VisionClient:stop()
  if self.socket then self.socket:disconnect() self.socket = nil end
  if self.task and self.task:isRunning() then self.task:terminate() end
  self.task = nil
  self.callbacks = {}
end

return VisionClient
