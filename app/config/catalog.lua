local Catalog = {}

Catalog.modes = {
  { id = "Story", maps = { "School Grounds", "Flower Forest", "Rose Kingdom", "Fairy King Forest", "King's Tomb" } },
  { id = "Raid", maps = { "Spirit City" } },
  { id = "Challenge", maps = { "Regular", "Hourly", "Daily", "Weekly" } },
  { id = "Expedition", maps = { "School Grounds", "Flower Forest", "Rose Kingdom" } },
}

Catalog.stages = { "Act 1", "Act 2", "Act 3", "Act 4", "Act 5", "Infinite" }
Catalog.difficulties = { "Normal", "Hard", "Mastery" }
Catalog.teams = { "current", "1", "2", "3", "4", "5", "6" }

Catalog.unit_bar = {
  [1] = { x = 270, y = 584 },
  [2] = { x = 324, y = 584 },
  [3] = { x = 378, y = 584 },
  [4] = { x = 433, y = 584 },
  [5] = { x = 489, y = 584 },
  [6] = { x = 544, y = 584 },
}

Catalog.unit_panel = {
  upgrade = { x = 194, y = 389 },
  auto_upgrade = { x = 269, y = 389 },
  ability = { x = 137, y = 355 },
  priority = { x = 58, y = 389 },
  sell = { x = 116, y = 389 },
  close = { x = 287, y = 240 },
}

Catalog.routes = {
  kings_tomb_act_1_mastery = {
    lobby = {
      { type = "click", point = { x = 80, y = 390 }, wait_ms = 1000, label = "open play" },
      { type = "click", point = { x = 437, y = 122 }, wait_ms = 900, label = "select story" },
      { type = "drag", from = { x = 235, y = 578 }, to = { x = 575, y = 578 }, duration_ms = 900, wait_ms = 900, label = "scroll story maps" },
      { type = "click", point = { x = 685, y = 310 }, wait_ms = 900, label = "select king's tomb" },
      { type = "click", point = { x = 151, y = 468 }, wait_ms = 500, label = "select mastery" },
      { type = "click", point = { x = 260, y = 468 }, wait_ms = 900, label = "select act 1" },
    },
    afk_return_to_lobby = { x = 482, y = 608 },
    start_private_party = { x = 451, y = 420 },
    repeat_stage = { x = 210, y = 472 },
    start_game = { x = 408, y = 193 },
  },
}

Catalog.v4_navigation = {
  open_play = { x = 80, y = 393 },
  modes = {
    Story = { x = 393, y = 73 },
    Raid = { x = 607, y = 72 },
    Challenge = { x = 430, y = 209 },
    Expedition = { x = 630, y = 209 },
  },
  story_maps = {
    ["School Grounds"] = { x = 146, y = 385, scroll = 20 },
    ["Flower Forest"] = { x = 397, y = 385, scroll = 20 },
    ["Rose Kingdom"] = { x = 649, y = 385, scroll = 20 },
    ["Fairy King Forest"] = { x = 446, y = 385, scroll = -20 },
    ["King's Tomb"] = { x = 698, y = 385, scroll = -20 },
  },
  story_stages = {
    ["Act 1"] = { x = 152, y = 204 },
    ["Act 2"] = { x = 152, y = 247 },
    ["Act 3"] = { x = 152, y = 290 },
    ["Act 4"] = { x = 152, y = 333 },
    ["Act 5"] = { x = 152, y = 376 },
    Infinite = { x = 152, y = 419 },
    Mastery = { x = 152, y = 462 },
  },
  story_difficulty = {
    Normal = { x = 202, y = 272 },
    Hard = { x = 243, y = 272 },
  },
  raid_map = { x = 146, y = 385 },
  raid_stages = {
    ["Act 1"] = { x = 174, y = 241 },
    ["Act 2"] = { x = 174, y = 333 },
    ["Act 3"] = { x = 174, y = 423 },
  },
  challenge_tab = { x = 204, y = 232 },
  challenge_slots = {
    Regular = { x = 659, y = 253 },
    Hourly = { x = 659, y = 253 },
    Daily = { x = 659, y = 343 },
    Weekly = { x = 659, y = 433 },
  },
  expedition_maps = {
    ["School Grounds"] = { x = 110, y = 237 },
    ["Flower Forest"] = { x = 110, y = 294 },
    ["Rose Kingdom"] = { x = 110, y = 352 },
  },
  expedition_min = { x = 646, y = 404 },
  expedition_plus = { x = 771, y = 404 },
  select_stage = { x = 273, y = 451 },
  select_challenge = { x = 430, y = 451 },
  select_expedition = { x = 727, y = 557 },
  party_start = { x = 450, y = 420 },
  start_game = { x = 408, y = 193 },
}

local function click(point, wait, label)
  return { type = "click", point = point, wait_ms = wait or 700, label = label }
end

function Catalog.routeFor(task)
  local nav = Catalog.v4_navigation
  local actions = {
    click(nav.open_play, 900, "open play"),
    click(nav.modes[task.mode], 900, "select " .. tostring(task.mode):lower()),
  }
  if not nav.modes[task.mode] then return nil end

  if task.mode == "Story" then
    local map = nav.story_maps[task.map]
    if not map then return nil end
    table.insert(actions, {
      type = "scroll", point = { x = 400, y = 385 }, delta = map.scroll,
      wait_ms = 500, label = "scroll story maps",
    })
    table.insert(actions, click(map, 850, "select " .. task.map))
    local stageName = task.difficulty == "Mastery" and "Mastery" or task.stage
    local stage = nav.story_stages[stageName]
    if not stage then return nil end
    table.insert(actions, click(stage, 500, "select " .. stageName))
    if stageName == "Mastery" and task.stage and task.stage ~= "Mastery" then
      table.insert(actions, click({ x = 260, y = 468 }, 850, "select " .. task.stage))
    elseif nav.story_difficulty[task.difficulty] then
      table.insert(actions, click(nav.story_difficulty[task.difficulty], 400, "select " .. task.difficulty))
      table.insert(actions, click(nav.select_stage, 850, "select stage"))
    else
      table.insert(actions, click(nav.select_stage, 850, "select stage"))
    end
  elseif task.mode == "Raid" then
    table.insert(actions, click(nav.raid_map, 700, "select Spirit City"))
    local stage = nav.raid_stages[task.stage] or nav.raid_stages["Act 1"]
    table.insert(actions, click(stage, 500, "select " .. tostring(task.stage)))
    table.insert(actions, click(nav.select_stage, 850, "select stage"))
  elseif task.mode == "Challenge" then
    table.insert(actions, click(nav.challenge_tab, 400, "open challenges"))
    table.insert(actions, click(nav.challenge_slots[task.map] or nav.challenge_slots.Regular, 700, "select challenge"))
    table.insert(actions, click(nav.select_challenge, 850, "select stage"))
  elseif task.mode == "Expedition" then
    local map = nav.expedition_maps[task.map]
    if not map then return nil end
    table.insert(actions, click(map, 450, "select " .. task.map))
    local difficulty = tonumber(tostring(task.stage):match("%d+")) or 1
    difficulty = math.max(1, math.min(3, difficulty))
    for _ = 1, 2 do table.insert(actions, click(nav.expedition_min, 140, "reset expedition difficulty")) end
    for _ = 2, difficulty do table.insert(actions, click(nav.expedition_plus, 140, "raise expedition difficulty")) end
    table.insert(actions, click(nav.select_expedition, 850, "select expedition"))
  end

  return {
    lobby = actions,
    team = task.team_actions or {},
    afk_return_to_lobby = { x = 482, y = 608 },
    start_private_party = nav.party_start,
    start_game = nav.start_game,
    repeat_stage = Catalog.results and Catalog.results.repeat_stage or { x = 210, y = 472 },
  }
end

Catalog.results = {
  repeat_stage = { x = 210, y = 472 },
  return_to_lobby = { x = 488, y = 472 },
  confirm_return_to_lobby = { x = 348, y = 342 },
}

Catalog.overlays = {
  lobby_modal_close = { x = 683, y = 164 },
}

Catalog.crafting = {
  rainbow_sprite = {
    id = "rainbow_sprite",
    name = "Sprite (Rainbow)",
    ingredient = "Sprite (Grey)",
    ingredient_cost = 30,
    quick_craft = false,
    workflow = {
      { type = "click", point = { x = 30, y = 393 }, wait_ms = 800, label = "open areas" },
      { type = "click", point = { x = 323, y = 280 }, wait_ms = 2500, label = "travel to crafting" },
      { type = "key", key = "e", repeats = 1, wait_ms = 900, label = "open crafting station" },
      { type = "click", point = { x = 290, y = 246 }, wait_ms = 400, label = "select rainbow sprite" },
      { type = "click", point = { x = 640, y = 420 }, wait_ms = 400, label = "set minimum craft amount" },
      { type = "click", point = { x = 448, y = 456 }, wait_ms = 700, label = "craft rainbow sprite" },
      { type = "click", point = { x = 660, y = 169 }, wait_ms = 500, label = "close crafting result" },
    },
  },
}

Catalog.challenge_kinds = {
  { id = "regular_side", name = "regular side challenge", default_cap = 10 },
  { id = "hourly", name = "hourly challenge", default_cap = 1 },
  { id = "daily", name = "daily challenge", default_cap = 1 },
  { id = "weekly", name = "weekly challenge", default_cap = 1 },
}

Catalog.challenge_panel = {
  open_play = { x = 80, y = 390 },
  open_challenges = { x = 430, y = 230 },
  categories = {
    regular_side = { x = 180, y = 215 },
    hourly = { x = 180, y = 215 },
    daily = { x = 180, y = 290 },
    weekly = { x = 180, y = 370 },
  },
  counter_roi = { x = 250, y = 260, w = 180, h = 80 },
  close = { x = 698, y = 164 },
  back_to_lobby = { x = 55, y = 612 },
}

function Catalog.snapshot()
  return {
    modes = Catalog.modes,
    stages = Catalog.stages,
    difficulties = Catalog.difficulties,
    teams = Catalog.teams,
    challenge_kinds = Catalog.challenge_kinds,
  }
end

return Catalog
