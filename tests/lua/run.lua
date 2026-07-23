local root = arg[1] or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Coordinates = require("app.core.coordinates")
local TaskQueue = require("app.core.task_queue")
local StateMachine = require("app.core.state_machine")
local Schema = require("app.config.schema")
local Strategy = require("app.core.strategy")
local Stats = require("app.core.stats")
local Crafting = require("app.features.crafting")
local Challenges = require("app.features.challenges")
local Webhooks = require("app.features.webhooks")
local Navigation = require("app.features.navigation")
local MapStore = require("app.features.map_store")
local StrategyRunner = require("app.features.strategy_runner")
local Automation = require("app.features.automation")
local RobloxWindow = require("app.platform.roblox_window")
local Catalog = require("app.config.catalog")

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

test("completed queue can restart without a task limit", function()
  local queue = TaskQueue.new({
    { name = "A", repetitions = 1 },
    { name = "B", repetitions = 1 },
  })
  queue:recordSuccess()
  queue:recordSuccess()
  assert(queue:current() == nil)
  assert(queue:restart().name == "A")
  assert(queue.index == 1 and queue.repetition == 0)
end)

test("same-stage repeat returns to lobby when the next task changes team", function()
  local previous = {
    mode = "Story", map = "School Grounds", stage = "Act 1", difficulty = "Normal", team = "1",
  }
  local nextTask = {
    mode = "Story", map = "School Grounds", stage = "Act 1", difficulty = "Normal", team = "2",
  }
  assert(Automation._nextStartMode({}, previous, previous) == "repeat")
  assert(Automation._nextStartMode({}, previous, nextTask) == "lobby")
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
    tasks[index] = {
      name = "T" .. index,
      mode = "Story",
      map = "King's Tomb",
      stage = "Act 1",
      difficulty = "Mastery",
      repetitions = 1,
    }
  end
  local ok, errors = Schema.validate({ schema_version = 1, reference_resolution = { w = 816, h = 638 }, tasks = tasks })
  assert(ok == true and #errors == 0)
end)

test("profile schema accepts custom routes and crafting workflows", function()
  local profile = {
    schema_version = 1,
    reference_resolution = { w = 816, h = 638 },
    tasks = {
      {
        name = "custom raid",
        mode = "Raid",
        map = "custom",
        stage = "Act 1",
        difficulty = "Normal",
        repetitions = 2,
        navigation_actions = {
          { type = "click", point = { x = 80, y = 390 }, wait_ms = 200 },
          { type = "drag", from = { x = 100, y = 500 }, to = { x = 700, y = 500 } },
          { type = "scroll", point = { x = 400, y = 385 }, delta = -20 },
          { type = "key", key = "e" },
          { type = "wait", wait_ms = 100 },
        },
        team_actions = {
          { type = "key", key = "h", wait_ms = 200 },
          { type = "click", point = { x = 603, y = 273 } },
        },
      },
    },
    crafting = {
      workflow = {
        { type = "click", point = { x = 640, y = 420 } },
      },
    },
  }
  local ok, errors = Schema.validate(profile)
  assert(ok == true and #errors == 0)
end)

test("built-in navigation keeps task-level team actions", function()
  local navigation = Navigation.new({})
  local route = navigation:_route({
    mode = "Story",
    map = "King's Tomb",
    stage = "Act 1",
    difficulty = "Mastery",
    team_actions = {
      { type = "key", key = "h" },
    },
  })
  assert(route ~= nil and #route.lobby > 0)
  assert(#route.team == 1 and route.team[1].key == "h")
  assert(route.lobby[2].point.x == Catalog.v4_navigation.modes.Story.x)
  assert(route.lobby[3].type == "scroll" and route.lobby[3].delta == -20)
end)

test("profile schema validates retry and webhook customization", function()
  local profile = {
    schema_version = 1,
    reference_resolution = { w = 816, h = 638 },
    tasks = {
      {
        name = "repeatable",
        mode = "Story",
        map = "School Grounds",
        stage = "Act 1",
        difficulty = "Normal",
        repetitions = 1,
        retry = { maximum_consecutive_failures = 3, on_exhausted = "skip" },
      },
    },
    webhooks = { events = { "started", "victory", "defeat" } },
  }
  local ok, errors = Schema.validate(profile)
  assert(ok == true and #errors == 0)
  profile.tasks[1].retry.on_exhausted = "buy"
  ok = Schema.validate(profile)
  assert(ok == nil)
end)

test("v0.4 map image names cover story raid and expedition", function()
  local maps = MapStore.new({ root = "/project" })
  assert(maps:v4Path({
    mode = "Story", map = "King's Tomb", stage = "Act 1", difficulty = "Mastery",
  }) == "/project/assets/maps/v4/Story_KingsTomb_Mastery.png")
  assert(maps:v4Path({
    mode = "Story", map = "School Grounds", stage = "Infinite", difficulty = "Normal",
  }) == "/project/assets/maps/v4/Story_SchoolGrounds_Infinite.png")
  assert(maps:v4Path({
    mode = "Raid", map = "Spirit City", stage = "Act 3", difficulty = "Hard",
  }) == "/project/assets/maps/v4/Raid_SpiritCity_Act3.png")
  assert(maps:v4Path({
    mode = "Expedition", map = "Flower Forest", stage = "Act 1", difficulty = "Normal",
  }) == "/project/assets/maps/v4/Expedition_FlowerForest_Exp.png")
end)

test("v4 navigation builds routes for every supported mode", function()
  local tasks = {
    { mode = "Story", map = "Flower Forest", stage = "Act 2", difficulty = "Hard" },
    { mode = "Raid", map = "Spirit City", stage = "Act 3", difficulty = "Hard" },
    { mode = "Challenge", map = "Daily", stage = "Act 1", difficulty = "Normal" },
    { mode = "Expedition", map = "Rose Kingdom", stage = "3", difficulty = "Normal" },
  }
  for _, task in ipairs(tasks) do
    local route = Catalog.routeFor(task)
    assert(route and #route.lobby >= 5)
    assert(route.start_private_party.x == 450 and route.start_game.x == 408)
  end
end)

test("roblox docks its content inside the gui hole", function()
  local target
  local fakeWindow = {
    isFullScreen = function() return false end,
    setFrame = function(_, frame) target = frame end,
  }
  local roblox = RobloxWindow.new({
    content_insets = { left = 0, right = 0, top = 18, bottom = 0 },
  }, { info = function() end })
  roblox.find = function()
    return fakeWindow
  end
  roblox:setDockContentFrame({ x = 400, y = 180, w = 816, h = 638 })
  local window = roblox:align({ w = 816, h = 638 })
  assert(window == fakeWindow)
  assert(target.x == 400 and target.y == 162)
  assert(target.w == 816 and target.h == 656)
  roblox:setDockContentFrame(nil)
  assert(roblox.dock_content_frame == nil)
end)

test("roblox focus activates and raises its real window", function()
  local calls = {}
  local fakeApp = {
    activate = function(_, allWindows) table.insert(calls, "activate:" .. tostring(allWindows)) end,
  }
  local fakeWindow = {
    isMinimized = function() return false end,
    application = function() return fakeApp end,
    raise = function() table.insert(calls, "raise") end,
    focus = function() table.insert(calls, "focus") end,
  }
  local roblox = RobloxWindow.new({}, {})
  roblox.find = function() return fakeWindow end
  assert(roblox:focus() == fakeWindow)
  assert(table.concat(calls, "|") == "activate:true|raise|focus")
end)

test("profile schema rejects automation points outside the canvas", function()
  local profile = {
    schema_version = 1,
    reference_resolution = { w = 816, h = 638 },
    tasks = {
      {
        name = "unsafe",
        mode = "Story",
        map = "map",
        stage = "Act 1",
        difficulty = "Normal",
        repetitions = 1,
        navigation_actions = {
          { type = "click", point = { x = 817, y = 200 } },
        },
      },
    },
  }
  local ok, errors = Schema.validate(profile)
  assert(ok == nil and #errors == 1)
end)

test("run stats track victories and defeats", function()
  local stats = Stats.new()
  stats:startRun(100)
  assert(stats:record("victory", 130) == 30)
  stats:startRun(200)
  assert(stats:record("defeat", 212) == 12)
  local snapshot = stats:snapshot()
  assert(snapshot.runs == 2)
  assert(snapshot.victories == 1)
  assert(snapshot.defeats == 1)
  assert(snapshot.win_rate == 50)
  assert(snapshot.total_runtime == 42)
end)

test("strategy validates placement automation", function()
  local strategy = Strategy.new({ id = "kings-tomb", name = "King's Tomb" })
  strategy.actions = {
    { id = "p1", type = "place", unit_slot = 1, x = 408, y = 319, delay_ms = 500, upgrade_target = "max", ability_mode = "auto", target_mode = "first" },
    { id = "u1", type = "upgrade", placement_id = "p1", levels = "max", delay_ms = 0 },
    { id = "au1", type = "auto_upgrade", placement_id = "p1", at_ms = 5000 },
    { id = "a1", type = "ability", placement_id = "p1", mode = "auto", delay_ms = 0 },
    { id = "t1", type = "target", placement_id = "p1", mode = "strongest", delay_ms = 0 },
    { id = "w1", type = "wait", duration_ms = 1000, delay_ms = 0 },
    { id = "s1", type = "sell", placement_id = "p1", delay_ms = 0 },
  }
  local ok, errors = Strategy.validate(strategy)
  assert(ok == true and #errors == 0)
  local summary = Strategy.summary(strategy)
  assert(summary.actions == 7 and summary.placements == 1)
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

test("strategy runner confirms and closes unit menus like v0.4", function()
  local scheduled = {}
  local now = 0
  _G.hs = {
    timer = {
      secondsSinceEpoch = function() return now end,
      doAfter = function(_, callback)
        table.insert(scheduled, callback)
        return { stop = function() end }
      end,
    },
  }
  local seen = {}
  local runner = StrategyRunner.new({
    input = {
      key = function(_, key, repeats)
        table.insert(seen, "key:" .. key .. ":" .. tostring(repeats))
        return true
      end,
      click = function(_, point, reason, callback)
        table.insert(seen, "click:" .. reason .. ":" .. point.x .. "," .. point.y)
        callback(true)
        return true
      end,
    },
    detector = {
      detect = function(_, callback, _, context)
        table.insert(seen, "detect:" .. tostring(context))
        callback({ state = "unit_menu" })
        return "request"
      end,
    },
    logger = { info = function() end, error = function() end },
  })
  local completed
  local started = runner:start({
    schema_version = 1,
    id = "confirmed",
    name = "confirmed",
    map = "King's Tomb",
    stage = "Act 1",
    difficulty = "Mastery",
    team = "current",
    reference_resolution = { w = 816, h = 638 },
    actions = {
      { id = "p1", type = "place", unit_slot = 1, x = 315, y = 455, at_ms = 0 },
      { id = "a1", type = "auto_upgrade", placement_id = "p1", at_ms = 1 },
    },
  }, 0, function() end, function(ok) completed = ok end)
  assert(started == true)
  while #scheduled > 0 do
    now = now + 1
    table.remove(scheduled, 1)()
  end
  assert(completed == true)
  local joined = table.concat(seen, "|")
  assert(joined:match("key:1:1"))
  assert(joined:match("click:place p1:315,455"))
  assert(joined:match("detect:unit_menu"))
  assert(joined:match("click:auto_upgrade p1:270,377"))
  assert(joined:match("click:close unit menu:287,228"))
  _G.hs = nil
end)

test("repeat flow opens results and uses the detected retry button", function()
  local scheduled = {}
  local now = 0
  _G.hs = {
    timer = {
      secondsSinceEpoch = function() return now end,
      doAfter = function(_, callback)
        table.insert(scheduled, callback)
        return { stop = function() end }
      end,
    },
  }
  local detections = {
    { state = "finished_stage" },
    {
      state = "defeat",
      templates = { retry = { center_x = 205, center_y = 471 } },
    },
    { state = "stage_ready" },
    { state = "battle" },
  }
  local seen = {}
  local navigation = Navigation.new({
    input = {
      click = function(_, point, reason, callback)
        table.insert(seen, reason .. ":" .. point.x .. "," .. point.y)
        callback(true)
        return true
      end,
    },
    roblox = { focus = function() return {} end },
    detector = {
      detect = function(_, callback)
        callback(table.remove(detections, 1))
        return "request"
      end,
    },
    profile = { navigation = { load_timeout_ms = 10000, stage_start_timeout_ms = 10000 } },
    logger = { warn = function() end, info = function() end },
  })
  local completed
  navigation:start({
    name = "king's tomb",
    mode = "Story",
    map = "King's Tomb",
    stage = "Act 1",
    difficulty = "Mastery",
  }, "repeat", function() end, function(ok) completed = ok end)
  while #scheduled > 0 do
    now = now + 1
    table.remove(scheduled, 1)()
  end
  assert(completed == true)
  assert(table.concat(seen, "|") == table.concat({
    "open game results:408,520",
    "repeat stage:205,471",
    "start game:408,193",
  }, "|"))
  _G.hs = nil
end)

test("auto craft is gated and quick craft is blocked", function()
  local crafting = Crafting.new({
    config = {
      enabled = true,
      live_confirmation = false,
      trigger = { type = "mastery_victories", every = 2 },
      recipes = {
        { enabled = true, name = "Sprite (Rainbow)", allow_quick_craft = false },
      },
    },
    logger = { info = function() end, error = function() end },
  })
  crafting:recordVictory({ difficulty = "Mastery" })
  assert(crafting:due() == false)
  crafting:recordVictory({ difficulty = "Mastery" })
  assert(crafting:due() == true)
  local plan, err = crafting:plan()
  assert(plan == nil and err:match("live%-confirmation"))
  crafting.config.live_confirmation = true
  crafting.config.recipes[1].allow_quick_craft = true
  plan, err = crafting:plan()
  assert(plan == nil and err:match("premium currency"))
  crafting.config.recipes[1].allow_quick_craft = false
  plan, err = crafting:plan()
  assert(type(plan) == "table" and err == nil)
end)

test("guarded auto craft runs the configured workflow in order", function()
  local scheduled = {}
  _G.hs = {
    timer = {
      doAfter = function(_, callback)
        table.insert(scheduled, callback)
        return { stop = function() end }
      end,
    },
  }
  local actions = {
    { type = "click", point = { x = 1, y = 2 }, label = "open", wait_ms = 1 },
    { type = "key", key = "e", label = "station", wait_ms = 1 },
    { type = "wait", label = "settle", wait_ms = 1 },
    { type = "click", point = { x = 3, y = 4 }, label = "normal craft", wait_ms = 1 },
  }
  local seen = {}
  local crafting = Crafting.new({
    config = {
      enabled = true,
      live_confirmation = true,
      workflow = actions,
      recipes = {
        { enabled = true, name = "Sprite (Rainbow)", allow_quick_craft = false },
      },
    },
    input = {
      click = function(_, _, reason, callback)
        table.insert(seen, reason)
        callback(true)
        return true
      end,
      key = function(_, key)
        table.insert(seen, "key:" .. key)
        return true
      end,
    },
    logger = { info = function() end, error = function() end },
  })
  local completed, completedRecipe
  crafting:run(function(_, message) table.insert(seen, "progress:" .. message) end, function(ok, _, recipe)
    completed, completedRecipe = ok, recipe
  end)
  while #scheduled > 0 do
    local callback = table.remove(scheduled, 1)
    callback()
  end
  assert(completed == true and completedRecipe.name == "Sprite (Rainbow)")
  assert(crafting:snapshot().completed_crafts == 1)
  assert(table.concat(seen, "|"):match("progress:normal craft|crafting: normal craft"))
  _G.hs = nil
end)

test("challenge caps skip only matching challenge tasks", function()
  local challenges = Challenges.new({
    config = {
      enabled = true,
      regular_cap = 10,
      caps = { regular_side = 10, daily = 1, hourly = 1, weekly = 1 },
    },
    path = os.tmpname(),
    json = { decode = function() return {} end, encode = function() return "{}" end },
  })
  local challenge = { mode = "Challenge", challenge_kind = "regular_side" }
  local story = { mode = "Story", map = "King's Tomb" }
  challenges.counters.regular_side = {
    current = 10,
    maximum = 10,
    period = os.date("%Y-%m-%d"),
    source = "visible_counter",
  }
  local allowed, status = challenges:allowsTask(challenge)
  assert(allowed == false and status.state == "capped")
  assert(challenges:allowsTask(story) == true)
  os.remove(challenges.path)
end)

test("webhook storage only accepts Discord webhook hosts", function()
  local webhooks = Webhooks.new({ config = {}, logger = {} })
  webhooks._keychain = function(_, _, callback) callback("", nil) return true end
  local accepted, errorMessage
  webhooks:setURL("https://example.com/api/webhooks/123/token", function(ok, err)
    accepted, errorMessage = ok, err
  end)
  assert(accepted == nil and errorMessage:match("Discord"))
  webhooks:setURL("https://discord.com/api/webhooks/123/token_abc-DEF", function(ok, err)
    accepted, errorMessage = ok, err
  end)
  assert(accepted == true and errorMessage == nil)
end)

print(string.format("%d Lua tests passed", passed))
