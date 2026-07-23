local root = arg[1] or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Coordinates = require("app.core.coordinates")
local TaskQueue = require("app.core.task_queue")
local StateMachine = require("app.core.state_machine")
local Schema = require("app.config.schema")
local Strategy = require("app.core.strategy")

local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    io.stderr:write("FAIL ", name, ": ", tostring(err), "\n")
    os.exit(1)
  end
  passed = passed + 1
  print("PASS " .. name)
end

test("coordinate round trip", function()
  local frame = { x = 100, y = 50, w = 1632, h = 1276 }
  local reference = { w = 816, h = 638 }
  local screen = Coordinates.referenceToScreen({ x = 408, y = 319 }, frame, reference)
  assert(screen.x == 916 and screen.y == 688)
  local point = Coordinates.screenToReference(screen, frame, reference)
  assert(point.x == 408 and point.y == 319)
end)

test("content insets", function()
  local result = Coordinates.contentFrame({ x = 10, y = 20, w = 100, h = 80 }, { left = 2, right = 3, top = 4, bottom = 5 })
  assert(result.x == 12 and result.y == 24 and result.w == 95 and result.h == 71)
end)

test("window fit preserves content aspect", function()
  local target = Coordinates.fitContentWindow(
    { x = 0, y = 25, w = 1680, h = 995 },
    { w = 816, h = 638 },
    { left = 0, right = 0, top = 18, bottom = 0 },
    0.88
  )
  local content = Coordinates.contentFrame(target, { top = 18 })
  assert(math.abs((content.w / content.h) - (816 / 638)) < 0.000001)
  assert(target.x >= 0 and target.y >= 25)
  assert(target.x + target.w <= 1680 and target.y + target.h <= 1020)
end)

test("unlimited queue and disabled tasks", function()
  local tasks = {}
  for index = 1, 30 do
    tasks[index] = { name = "Task " .. index, enabled = index ~= 1, repetitions = 1 }
  end
  local queue = TaskQueue.new(tasks)
  assert(queue:current().name == "Task 2")
  for _ = 2, 29 do queue:recordSuccess() end
  assert(queue:current().name == "Task 30")
  queue:recordSuccess()
  assert(queue:current() == nil)
end)

test("queue checkpoint resume", function()
  local queue = TaskQueue.new({ { name = "A", repetitions = 3 } }, { task_index = 1, repetition = 2 })
  queue:recordSuccess()
  assert(queue:current() == nil)
end)

test("state transition validation", function()
  local machine = StateMachine.new()
  machine:transition("ATTACH_ROBLOX", "test")
  machine:transition("CALIBRATE", "test")
  local ok = pcall(function() machine:transition("RESULTS", "invalid") end)
  assert(ok == false)
  machine:stop("test")
  assert(machine.state == "IDLE")
end)

test("profile schema accepts unbounded task list", function()
  local tasks = {}
  for index = 1, 100 do
    tasks[index] = { name = "T" .. index, mode = "Story", repetitions = 1 }
  end
  local ok, errors = Schema.validate({ schema_version = 1, reference_resolution = { w = 816, h = 638 }, tasks = tasks })
  assert(ok == true and #errors == 0)
end)

test("strategy validates placement automation", function()
  local strategy = Strategy.new({ id = "kings-tomb", name = "King's Tomb" })
  strategy.actions = {
    { id = "p1", type = "place", unit_slot = 1, x = 408, y = 319, delay_ms = 500, upgrade_target = "max", ability_mode = "auto", target_mode = "first" },
    { id = "u1", type = "upgrade", placement_id = "p1", levels = "max", delay_ms = 0 },
    { id = "a1", type = "ability", placement_id = "p1", mode = "auto", delay_ms = 0 },
    { id = "t1", type = "target", placement_id = "p1", mode = "strongest", delay_ms = 0 },
    { id = "w1", type = "wait", duration_ms = 1000, delay_ms = 0 },
    { id = "s1", type = "sell", placement_id = "p1", delay_ms = 0 },
  }
  local ok, errors = Strategy.validate(strategy)
  assert(ok == true and #errors == 0)
  local summary = Strategy.summary(strategy)
  assert(summary.actions == 6 and summary.placements == 1)
end)

test("strategy rejects unsafe coordinates and dangling actions", function()
  local strategy = Strategy.new({ id = "bad", name = "Bad" })
  strategy.actions = {
    { id = "p1", type = "place", unit_slot = 7, x = 900, y = -1 },
    { id = "u1", type = "upgrade", placement_id = "missing", levels = 1 },
  }
  local ok, errors = Strategy.validate(strategy)
  assert(ok == nil and #errors >= 4)
end)

print(string.format("%d Lua tests passed", passed))
