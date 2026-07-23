local Checkpoint = require("app.core.checkpoint")
local Catalog = require("app.config.catalog")

local Challenges = {}
Challenges.__index = Challenges

local function periodKey(kind, timestamp)
  if kind == "hourly" then return os.date("%Y-%m-%d-%H", timestamp) end
  if kind == "weekly" then return os.date("%Y-W%W", timestamp) end
  return os.date("%Y-%m-%d", timestamp)
end

local function normalizedKind(value)
  local kind = tostring(value or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  local aliases = {
    regular = "regular_side",
    regular_challenge = "regular_side",
    regular_side_challenge = "regular_side",
    hourly_challenge = "hourly",
    daily_challenge = "daily",
    weekly_challenge = "weekly",
  }
  return aliases[kind] or (kind ~= "" and kind or "regular_side")
end

function Challenges.new(options)
  local json = options.json or (hs and hs.json)
  local snapshot = Checkpoint.load(options.path, json) or {}
  return setmetatable({
    config = options.config or {},
    path = options.path,
    capture = options.capture,
    vision = options.vision,
    profile = options.profile,
    logger = options.logger,
    input = options.input,
    json = json,
    counters = snapshot.counters or {},
    last_check_at = snapshot.last_check_at,
    timer = nil,
    cancelled = false,
  }, Challenges)
end

function Challenges:_after(milliseconds, callback)
  if self.timer then self.timer:stop() end
  self.timer = hs.timer.doAfter(math.max(0, milliseconds or 0) / 1000, function()
    self.timer = nil
    if not self.cancelled then callback() end
  end)
end

function Challenges:_maximum(kind)
  local caps = self.config.caps or {}
  if caps[kind] ~= nil then return math.max(1, tonumber(caps[kind]) or 1) end
  if kind == "regular_side" then return math.max(1, tonumber(self.config.regular_cap) or 10) end
  return 1
end

function Challenges:_entry(kind, timestamp)
  kind = normalizedKind(kind)
  timestamp = timestamp or os.time()
  local period = periodKey(kind, timestamp)
  local entry = self.counters[kind]
  if type(entry) ~= "table" or entry.period ~= period then
    entry = {
      current = 0,
      maximum = self:_maximum(kind),
      period = period,
      updated_at = timestamp,
      source = "counter",
    }
    self.counters[kind] = entry
  else
    entry.maximum = self:_maximum(kind)
  end
  return entry, kind
end

function Challenges:_save()
  Checkpoint.save(self.path, self.json, {
    counters = self.counters,
    last_check_at = self.last_check_at,
    updated_at = os.time(),
  })
end

function Challenges:taskKind(task)
  if not task or task.mode ~= "Challenge" then return nil end
  return normalizedKind(task.challenge_kind or task.map or task.stage)
end

function Challenges:status(kind, timestamp)
  local entry, normalized = self:_entry(kind, timestamp)
  local capped = entry.current >= entry.maximum
  return {
    kind = normalized,
    current = entry.current,
    maximum = entry.maximum,
    available = not capped,
    state = capped and "capped" or "available",
    source = entry.source or "counter",
    period = entry.period,
    updated_at = entry.updated_at,
  }
end

function Challenges:recordVictory(kind)
  if type(kind) == "table" then kind = self:taskKind(kind) end
  if not kind then return nil end
  local entry, normalized = self:_entry(kind)
  entry.current = math.min(entry.maximum, entry.current + 1)
  entry.updated_at = os.time()
  entry.source = "recorded_result"
  self:_save()
  return self:status(normalized)
end

function Challenges:allowsTask(task)
  if not self.config.enabled then return true, nil end
  local kind = self:taskKind(task)
  if not kind then return true, nil end
  local status = self:status(kind)
  return status.available, status
end

function Challenges:dueForCheck(timestamp)
  if not self.config.enabled then return false end
  timestamp = timestamp or os.time()
  local interval = math.max(5, tonumber(self.config.check_interval_minutes) or 30) * 60
  return not self.last_check_at or timestamp - self.last_check_at >= interval
end

function Challenges:check(kind, roi, callback)
  kind = normalizedKind(kind)
  if not self.config.enabled then
    callback({ available = false, state = "disabled", source = "settings", kind = kind })
    return
  end
  roi = roi or (self.config.rois and self.config.rois[kind])
  if type(roi) ~= "table" then
    local fallback = self:status(kind)
    fallback.source = "fallback_counter"
    self.last_check_at = os.time()
    self:_save()
    callback(fallback)
    return
  end
  local output = self.path:gsub("%.json$", "-" .. tostring(kind) .. ".png")
  local id, err = self.capture:normalized(self.vision, self.profile, output, function(result, captureError)
    if not result then callback(nil, captureError) return end
    local requestId, requestError = self.vision:request("challenge_counter", {
      image_path = result.output_path,
      roi = roi,
      templates_dir = "assets/challenge/digits",
    }, function(detection, detectionError)
      self.last_check_at = os.time()
      local availability = detection and detection.availability
      local counter = detection and detection.counter
      if availability and availability.state ~= "unknown" and counter and counter.readable then
        local entry = self:_entry(kind)
        entry.current = math.max(0, tonumber(counter.current) or 0)
        entry.maximum = math.max(1, tonumber(counter.maximum) or self:_maximum(kind))
        entry.updated_at = os.time()
        entry.source = availability.source
        self:_save()
        local status = self:status(kind)
        status.source = availability.source
        callback(status, nil, detection)
        return
      end
      if self.config.fallback_counters then
        local fallback = self:status(kind)
        fallback.source = "fallback_counter"
        self:_save()
        callback(fallback, nil, detection)
        return
      end
      self:_save()
      callback(nil, detectionError or "challenge counter is unreadable")
    end)
    if not requestId then callback(nil, requestError) end
  end)
  if not id then callback(nil, err) end
end

function Challenges:checkFromLobby(kind, progress, callback)
  kind = normalizedKind(kind)
  if not self.config.enabled then
    callback({ available = true, state = "disabled", source = "settings", kind = kind })
    return
  end
  if not self.input then callback(nil, "challenge lobby workflow has no input service") return end
  self.cancelled = false
  local panel = Catalog.challenge_panel
  local finished = false
  local function done(result, err, detection)
    if finished then return end
    finished = true
    callback(result, err, detection)
  end
  local function closePanel(result, checkError, detection)
    progress("challenges", "closing challenge panel")
    local closed, closeError = self.input:click(panel.close, "close challenge cap panel", function(closeSuccess, helperError)
      if not closeSuccess then done(nil, helperError) return end
      self:_after(450, function()
        local backed, backError = self.input:click(panel.back_to_lobby, "return from challenge panel", function(backSuccess, backHelperError)
          if not backSuccess then done(nil, backHelperError) return end
          self:_after(450, function() done(result, checkError, detection) end)
        end)
        if not backed then done(nil, backError) end
      end)
    end)
    if not closed then done(nil, closeError) end
  end
  progress("challenges", "opening challenge cap panel")
  local opened, openError = self.input:click(panel.open_play, "open play for challenge cap check", function(playSuccess, playError)
    if not playSuccess then done(nil, playError) return end
    self:_after(750, function()
      local selected, selectError = self.input:click(panel.open_challenges, "open challenge cap panel", function(challengeSuccess, challengeError)
        if not challengeSuccess then done(nil, challengeError) return end
        self:_after(750, function()
          local category = panel.categories[kind] or panel.categories.regular_side
          local categoryClicked, categoryError = self.input:click(category, "select " .. kind .. " challenge category", function(categorySuccess, categoryHelperError)
            if not categorySuccess then done(nil, categoryHelperError) return end
            self:_after(600, function()
              progress("challenges", "reading challenge cap")
              self:check(kind, panel.counter_roi, closePanel)
            end)
          end)
          if not categoryClicked then done(nil, categoryError) end
        end)
      end)
      if not selected then done(nil, selectError) end
    end)
  end)
  if not opened then done(nil, openError) end
end

function Challenges:stop()
  self.cancelled = true
  if self.timer then self.timer:stop() self.timer = nil end
end

function Challenges:snapshot()
  local result = {}
  for _, kind in ipairs({ "regular_side", "hourly", "daily", "weekly" }) do
    result[kind] = self:status(kind)
  end
  return result
end

return Challenges
