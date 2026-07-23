local Strategy = require("app.core.strategy")

local MapStore = {}
MapStore.__index = MapStore

function MapStore.new(options)
  return setmetatable({
    root = options.root,
    profile = options.profile,
    capture = options.capture,
    vision = options.vision,
    logger = options.logger,
  }, MapStore)
end

function MapStore:key(task)
  return Strategy.slug(table.concat({
    task.mode or "custom", task.map or "map", task.stage or "stage", task.difficulty or "difficulty",
  }, "-"))
end

function MapStore:path(task)
  return self.root .. "/assets/maps/" .. self:key(task) .. ".png"
end

local function compact(value)
  return tostring(value or ""):gsub("[^%w]", "")
end

function MapStore:v4Path(task)
  local mode = tostring(task.mode or "")
  local map = compact(task.map)
  local stage = tostring(task.stage or "")
  local difficulty = tostring(task.difficulty or "")
  local filename

  if mode == "Story" then
    local variant = "Acts"
    if difficulty == "Mastery" then
      variant = "Mastery"
    elseif stage == "Infinite" then
      variant = "Infinite"
    end
    filename = "Story_" .. map .. "_" .. variant .. ".png"
  elseif mode == "Raid" then
    filename = "Raid_" .. map .. "_" .. compact(stage) .. ".png"
  elseif mode == "Expedition" then
    filename = "Expedition_" .. map .. "_Exp.png"
  end

  if not filename then return nil end
  return self.root .. "/assets/maps/v4/" .. filename
end

function MapStore:resolvedPath(task)
  local exact = self:path(task)
  if hs.fs.attributes(exact) then return exact end
  local imported = self:v4Path(task)
  if imported and hs.fs.attributes(imported) then return imported end
  return exact
end

function MapStore:capture(task, callback)
  local path = self:path(task)
  local id, err = self.capture:normalized(self.vision, self.profile, path, function(result, captureError)
    if result then
      self.logger:info("map_capture_saved", { task = task.name, path = result.output_path })
    end
    callback(result, captureError)
  end)
  if not id then return nil, err end
  return id
end

function MapStore:image(task)
  local path = self:resolvedPath(task)
  if not hs.fs.attributes(path) then return nil end
  return hs.image.imageFromPath(path), path
end

return MapStore
