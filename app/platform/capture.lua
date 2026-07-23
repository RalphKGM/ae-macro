local Capture = {}
Capture.__index = Capture

local function stamp()
  return os.date("!%Y%m%dT%H%M%SZ") .. "-" .. tostring(math.floor((hs.timer.secondsSinceEpoch() % 1) * 1000))
end

function Capture.new(root, robloxWindow, logger)
  return setmetatable({ root = root, roblox = robloxWindow, logger = logger }, Capture)
end

function Capture:window(path)
  local window, err = self.roblox:find()
  if not window then return nil, err end
  local started = hs.timer.secondsSinceEpoch()
  local image = window:snapshot(false)
  if not image then return nil, "hs.window:snapshot returned nil (check Screen Recording permission)" end
  path = path or (self.root .. "/runtime/captures/raw-" .. stamp() .. ".png")
  if not image:saveToFile(path, true, "PNG") then return nil, "failed to save capture" end
  local size = image:size()
  local elapsed = (hs.timer.secondsSinceEpoch() - started) * 1000
  local frame = window:frame()
  local metadata = {
    path = path, capture_ms = elapsed,
    image_points = { w = size.w, h = size.h },
    pixel_scale = { x = size.w / frame.w, y = size.h / frame.h },
    window_frame = { x = frame.x, y = frame.y, w = frame.w, h = frame.h },
    window_id = window:id(), title = window:title(),
  }
  local metadataPath = path:gsub("%.png$", ".json")
  local file = io.open(metadataPath, "w")
  if file then file:write(hs.json.encode(metadata, true)) file:close() end
  self.logger:info("capture_saved", metadata)
  return metadata
end

function Capture:normalized(vision, profile, output, callback)
  local metadata, err = self:window()
  if not metadata then return nil, err end
  local insets = profile.roblox.content_insets or {}
  local scaledInsets = {
    left = math.floor((insets.left or 0) * metadata.pixel_scale.x + 0.5),
    right = math.floor((insets.right or 0) * metadata.pixel_scale.x + 0.5),
    top = math.floor((insets.top or 0) * metadata.pixel_scale.y + 0.5),
    bottom = math.floor((insets.bottom or 0) * metadata.pixel_scale.y + 0.5),
  }
  return vision:request("normalize", {
    input_path = metadata.path,
    output_path = output,
    width = profile.reference_resolution.w,
    height = profile.reference_resolution.h,
    insets = scaledInsets,
  }, callback)
end

return Capture
