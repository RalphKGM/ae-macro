local Stats = {}
Stats.__index = Stats

function Stats.new(snapshot)
  snapshot = snapshot or {}
  return setmetatable({
    runs = snapshot.runs or 0,
    victories = snapshot.victories or 0,
    defeats = snapshot.defeats or 0,
    started_at = snapshot.started_at,
    current_started_at = nil,
    last_result = snapshot.last_result,
    last_duration = snapshot.last_duration,
    total_runtime = snapshot.total_runtime or 0,
  }, Stats)
end

function Stats:startRun(now)
  self.runs = self.runs + 1
  self.current_started_at = now or os.time()
  if not self.started_at then self.started_at = self.current_started_at end
end

function Stats:record(result, now)
  now = now or os.time()
  local duration = self.current_started_at and math.max(0, now - self.current_started_at) or 0
  self.last_duration = duration
  self.total_runtime = self.total_runtime + duration
  self.current_started_at = nil
  self.last_result = result
  if result == "victory" then self.victories = self.victories + 1 end
  if result == "defeat" then self.defeats = self.defeats + 1 end
  return duration
end

function Stats:snapshot()
  local completed = self.victories + self.defeats
  return {
    runs = self.runs,
    victories = self.victories,
    defeats = self.defeats,
    win_rate = completed > 0 and math.floor((self.victories / completed) * 1000 + 0.5) / 10 or 0,
    started_at = self.started_at,
    last_result = self.last_result,
    last_duration = self.last_duration,
    total_runtime = self.total_runtime,
  }
end

return Stats
