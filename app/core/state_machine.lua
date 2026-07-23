local StateMachine = {}
StateMachine.__index = StateMachine

local allowed = {
  IDLE = { ATTACH_ROBLOX = true },
  ATTACH_ROBLOX = { CALIBRATE = true, RECOVERY = true, IDLE = true },
  CALIBRATE = { LOBBY_DETECT = true, RECOVERY = true, IDLE = true },
  LOBBY_DETECT = { MODE_SELECT = true, AUTO_CRAFT = true, SIDE_CHALLENGE_SELECT = true, RECOVERY = true, IDLE = true },
  MODE_SELECT = { MAP_SELECT = true, RECOVERY = true, IDLE = true },
  MAP_SELECT = { STAGE_SELECT = true, RECOVERY = true, IDLE = true },
  STAGE_SELECT = { TEAM_SELECT = true, RECOVERY = true, IDLE = true },
  TEAM_SELECT = { MATCHMAKING = true, RECOVERY = true, IDLE = true },
  MATCHMAKING = { LOAD_WAIT = true, RECOVERY = true, IDLE = true },
  LOAD_WAIT = { IN_STAGE = true, RECOVERY = true, IDLE = true },
  IN_STAGE = { EXECUTE_STRATEGY = true, RECOVERY = true, IDLE = true },
  EXECUTE_STRATEGY = { IN_BATTLE = true, RECOVERY = true, IDLE = true },
  IN_BATTLE = { RESULTS = true, RECOVERY = true, IDLE = true },
  RESULTS = { LOBBY_DETECT = true, COMPLETE = true, RECOVERY = true, IDLE = true },
  AUTO_CRAFT = { LOBBY_DETECT = true, RECOVERY = true, IDLE = true },
  SIDE_CHALLENGE_SELECT = { TEAM_SELECT = true, LOBBY_DETECT = true, RECOVERY = true, IDLE = true },
  RECOVERY = { ATTACH_ROBLOX = true, LOBBY_DETECT = true, COMPLETE = true, IDLE = true },
  COMPLETE = { IDLE = true },
}

function StateMachine.new(logger)
  return setmetatable({ state = "IDLE", paused = false, history = {}, logger = logger }, StateMachine)
end

function StateMachine:transition(nextState, reason)
  assert(allowed[self.state] and allowed[self.state][nextState],
    string.format("invalid transition %s -> %s", self.state, nextState))
  local entry = { from = self.state, to = nextState, reason = reason or "unspecified", at = os.time() }
  self.state = nextState
  table.insert(self.history, entry)
  if self.logger then self.logger:info("state_transition", entry) end
  return entry
end

function StateMachine:pause()
  self.paused = true
end

function StateMachine:resume()
  self.paused = false
end

function StateMachine:stop(reason)
  if self.state ~= "IDLE" then self:transition("IDLE", reason or "stop") end
end

return StateMachine

