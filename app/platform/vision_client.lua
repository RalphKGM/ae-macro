local VisionClient = {}
VisionClient.__index = VisionClient

function VisionClient.new(options)
  return setmetatable({
    root = options.root,
    python = options.python,
    port = options.port or 47681,
    token = options.token,
    logger = options.logger,
    task = nil,
    next_id = 1,
    callbacks = {},
    request_timeout_ms = options.request_timeout_ms or 10000,
    retry_timer = nil,
    ready = false,
  }, VisionClient)
end

function VisionClient:_finish(id, result, err)
  local pending = self.callbacks[id]
  if not pending then return end
  self.callbacks[id] = nil
  if pending.timer then pending.timer:stop() end
  if pending.socket then pending.socket:disconnect() end
  pending.callback(result, err)
end

function VisionClient:_request(operation, payload, callback, allowBeforeReady, timeoutMs)
  if not self.ready and not allowBeforeReady then return nil, "vision worker is disconnected" end
  local id = self.next_id
  self.next_id = self.next_id + 1
  local request = { id = id, token = self.token, op = operation, payload = payload or {} }
  local pending = { callback = callback }
  local socket
  socket = hs.socket.new(function(data)
    local ok, response = pcall(hs.json.decode, data)
    if not ok or not response then
      self.logger:error("vision_invalid_response", { data = data, operation = operation })
      self:_finish(id, nil, "vision worker returned invalid JSON")
      return
    end
    if response.ok then
      self:_finish(id, response.result, nil)
    else
      self:_finish(id, nil, response.error)
    end
  end)
  pending.socket = socket
  pending.timer = hs.timer.doAfter((timeoutMs or self.request_timeout_ms) / 1000, function()
    if self.callbacks[id] ~= pending then return end
    self.logger:warn("vision_request_timeout", { id = id, operation = operation })
    self:_finish(id, nil, "vision request timed out: " .. tostring(operation))
  end)
  self.callbacks[id] = pending
  local connected = socket:connect("127.0.0.1", self.port, function()
    if self.callbacks[id] ~= pending then return end
    socket:read("\n")
    socket:write(hs.json.encode(request) .. "\n")
  end)
  if not connected then
    self.callbacks[id] = nil
    if pending.timer then pending.timer:stop() end
    socket:disconnect()
    return nil, "could not connect to the vision worker"
  end
  return id
end

function VisionClient:_connectWithRetry(attempt, onReady)
  if attempt >= 120 then
    self.logger:error("vision_connect_timeout", { port = self.port })
    if onReady then onReady(nil, "vision worker did not accept connections") end
    return
  end
  if self.retry_timer then self.retry_timer:stop() end
  self.retry_timer = hs.timer.doAfter(attempt == 0 and 0.35 or 0.5, function()
    self.retry_timer = nil
    local id, err = self:_request("ping", {}, function(result, pingError)
      if result then
        self.ready = true
        if onReady then onReady(result) end
        return
      end
      self.logger:warn("vision_ping_failed", { error = pingError, attempt = attempt + 1 })
      self:_connectWithRetry(attempt + 1, onReady)
    end, true, 1200)
    if not id then
      self.logger:warn("vision_connect_failed", { error = err, attempt = attempt + 1 })
      self:_connectWithRetry(attempt + 1, onReady)
    end
  end)
end

function VisionClient:start(onReady)
  local function spawn()
    local task
    task = hs.task.new(self.python, function(exitCode, stdout, stderr)
      if self.task == task then
        self.ready = false
        self.task = nil
      end
      self.logger:error("vision_worker_exit", { exit_code = exitCode, stdout = stdout, stderr = stderr })
    end, function(_, stdout, stderr)
      if stdout and stdout ~= "" then self.logger:info("vision_stdout", { text = stdout }) end
      if stderr and stderr ~= "" then self.logger:warn("vision_stderr", { text = stderr }) end
      return true
    end, {
      "-m", "vision.server", "--host", "127.0.0.1", "--port", tostring(self.port),
      "--token", self.token, "--root", self.root,
    })
    self.task = task
    if not self.task then
      if onReady then onReady(nil, "could not create vision worker task") end
      return
    end
    self.task:setWorkingDirectory(self.root)
    if not self.task:start() then
      self.task = nil
      if onReady then onReady(nil, "could not start vision worker") end
      return
    end
    self:_connectWithRetry(0, onReady)
  end

  -- A hard Hammerspoon restart can leave the local worker alive. Reuse it when
  -- it has the install's persistent token instead of racing a second bind.
  local id = self:_request("ping", {}, function(result)
    if result then
      self.ready = true
      self.logger:info("vision_worker_reused", { port = self.port })
      if onReady then onReady(result) end
      return
    end
    spawn()
  end, true, 700)
  if id then return true end

  spawn()
  return true
end

-- kept separate from task ownership because a hard-restart recovery may reuse
-- a worker spawned by the previous Hammerspoon process.
function VisionClient:isConnected()
  return self.ready
end

function VisionClient:request(operation, payload, callback)
  return self:_request(operation, payload, callback, false)
end

function VisionClient:stop()
  self.ready = false
  if self.retry_timer then self.retry_timer:stop() self.retry_timer = nil end
  for id, pending in pairs(self.callbacks) do
    self.callbacks[id] = nil
    if pending.timer then pending.timer:stop() end
    if pending.socket then pending.socket:disconnect() end
  end
  if self.task and self.task:isRunning() then self.task:terminate() end
  self.task = nil
end

return VisionClient
