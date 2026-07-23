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
  local path = self:path(task)
  if not hs.fs.attributes(path) then return nil end
  return hs.image.imageFromPath(path), path
end

return MapStore
