local Schema = require("app.config.schema")
local Profiles = {}

function Profiles.load(path, json)
  local file, err = io.open(path, "r")
  if not file then return nil, "cannot open profile: " .. tostring(err) end
  local text = file:read("*a")
  file:close()
  local ok, profile = pcall(json.decode, text)
  if not ok then return nil, "profile JSON is invalid: " .. tostring(profile) end
  local valid, errors = Schema.validate(profile)
  if not valid then return nil, table.concat(errors, "; ") end
  return profile
end

function Profiles.defaults(profile)
  profile.runtime = profile.runtime or {}
  if profile.runtime.start_action == nil then profile.runtime.start_action = "auto" end
  if profile.runtime.align_before_run == nil then profile.runtime.align_before_run = true end
  if profile.runtime.auto_camera == nil then profile.runtime.auto_camera = true end
  if profile.runtime.save_diagnostics == nil then profile.runtime.save_diagnostics = true end
  if profile.runtime.timing_multiplier == nil then profile.runtime.timing_multiplier = 1 end
  if profile.runtime.allow_return_to_lobby == nil then profile.runtime.allow_return_to_lobby = true end
  if profile.runtime.queue_start_over == nil then profile.runtime.queue_start_over = false end
  profile.camera = profile.camera or {
    zoom_in_presses = 18,
    pitch_drags = 2,
    pitch_from = { x = 408, y = 540 },
    pitch_to = { x = 408, y = 80 },
    pitch_duration_ms = 900,
    zoom_out_delta = -20,
    settle_ms = 1800,
  }
  profile.teams = profile.teams or {
    { id = "current", name = "current equipped team" },
    { id = "1", name = "team 1" },
  }
  profile.navigation = profile.navigation or {}
  if profile.navigation.load_wait_ms == nil then profile.navigation.load_wait_ms = 4500 end
  if profile.navigation.load_timeout_ms == nil then profile.navigation.load_timeout_ms = 90000 end
  if profile.navigation.stage_start_timeout_ms == nil then profile.navigation.stage_start_timeout_ms = 45000 end
  if profile.navigation.lobby_load_wait_ms == nil then profile.navigation.lobby_load_wait_ms = 18000 end
  if profile.navigation.lobby_load_timeout_ms == nil then profile.navigation.lobby_load_timeout_ms = 90000 end
  if profile.navigation.result_timeout_ms == nil then profile.navigation.result_timeout_ms = 600000 end
  profile.webhooks = profile.webhooks or {}
  profile.webhooks.events = profile.webhooks.events or { "victory", "defeat", "stopped", "error", "craft", "challenge" }
  profile.crafting = profile.crafting or { enabled = false, recipes = {} }
  profile.crafting.trigger = profile.crafting.trigger or { type = "mastery_victories", every = 20 }
  profile.crafting.recipes = profile.crafting.recipes or {}
  profile.crafting.on_failure = profile.crafting.on_failure or "stop"
  profile.challenges = profile.challenges or { enabled = false, fallback_counters = true }
  profile.challenges.fallback_counters = profile.challenges.fallback_counters ~= false
  profile.challenges.safe_checkpoints_only = profile.challenges.safe_checkpoints_only ~= false
  profile.challenges.check_interval_minutes = profile.challenges.check_interval_minutes or 30
  profile.challenges.regular_cap = profile.challenges.regular_cap or 10
  profile.challenges.caps = profile.challenges.caps or {
    regular_side = profile.challenges.regular_cap,
    hourly = 1,
    daily = 1,
    weekly = 1,
  }
  return profile
end

return Profiles
