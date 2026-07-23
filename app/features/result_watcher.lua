local ResultWatcher = {}
ResultWatcher.__index = ResultWatcher

function ResultWatcher.new(options)
  return setmetatable({
    detector = options.detector,
    logger = options.logger,
    interval_ms = options.interval_ms or 3000,
    timeout_ms = options.timeout_ms or 600000,
    timer = nil,
    started_at = nil,
    callback = nil,
    running = false,
  }, ResultWatcher)
end

function ResultWatcher:_schedule(milliseconds)
  if self.timer then self.timer:stop() end
  self.timer = hs.timer.doAfter(milliseconds / 1000, function()
    self.timer = nil
    self:_poll()
  end)
end

function ResultWatcher:_poll()
  if not self.running then return end
  local elapsed = (hs.timer.secondsSinceEpoch() * 1000) - self.started_at
  if elapsed >= self.timeout_ms then
    self.running = false
    self.callback(nil, "result detection timed out")
    return
  end
  local id, err = self.detector:detect(function(result, detectError)
    if not self.running then return end
    if not result then
      self.logger:warn("result_detection_failed", { error = detectError })
      self:_schedule(self.interval_ms)
      return
    end
    if result.state == "victory" or result.state == "defeat" then
      self.running = false
      self.callback(result.state, nil, result)
      return
    end
    self:_schedule(self.interval_ms)
  end, "battle result")
  if not id then
    self.logger:warn("result_detection_request_failed", { error = err })
    self:_schedule(self.interval_ms)
  end
end

function ResultWatcher:start(callback)
  self:stop()
  self.callback = callback
  self.started_at = hs.timer.secondsSinceEpoch() * 1000
  self.running = true
  self:_schedule(self.interval_ms)
end

function ResultWatcher:stop()
  self.running = false
  if self.timer then self.timer:stop() self.timer = nil end
end

return ResultWatcher
