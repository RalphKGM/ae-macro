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
