local Coordinates = require("app.core.coordinates")
local Calibration = {}
Calibration.__index = Calibration

function Calibration.new(options)
  return setmetatable({
    root = options.root,
    profile = options.profile,
    roblox = options.roblox,
    capture = options.capture,
    input = options.input,
    vision = options.vision,
    logger = options.logger,
    target = nil,
  }, Calibration)
end

function Calibration:captureAndNormalize()
  local metadata, err = self.capture:window()
  if not metadata then
    hs.alert.show("Capture failed: " .. tostring(err), 3)
    self.logger:error("calibration_capture_failed", { error = err })
    return
  end
  local normalized = metadata.path:gsub("/captures/raw%-", "/captures/normalized-")
  local diagnostic = metadata.path:gsub("/captures/raw%-", "/diagnostics/capture-"):gsub("%.png$", ".json")
  local profileInsets = self.profile.roblox.content_insets or {}
  local captureInsets = {
    left = math.floor((profileInsets.left or 0) * metadata.pixel_scale.x + 0.5),
    right = math.floor((profileInsets.right or 0) * metadata.pixel_scale.x + 0.5),
    top = math.floor((profileInsets.top or 0) * metadata.pixel_scale.y + 0.5),
    bottom = math.floor((profileInsets.bottom or 0) * metadata.pixel_scale.y + 0.5),
  }
  local id, requestErr = self.vision:request("normalize", {
    input_path = metadata.path,
    output_path = normalized,
    diagnostic_path = diagnostic,
    width = self.profile.reference_resolution.w,
    height = self.profile.reference_resolution.h,
    insets = captureInsets,
  }, function(result, visionErr)
    if not result then
      hs.alert.show("Normalize failed: " .. tostring(visionErr), 3)
      self.logger:error("calibration_normalize_failed", { error = visionErr, raw_path = metadata.path })
      return
    end
    self.logger:info("calibration_capture_ready", result)
    local warning = result.blank_or_solid and " — WARNING: blank/solid" or ""
    hs.alert.show("Capture ready" .. warning .. "\n" .. result.output_path, 4)
  end)
  if not id then
    hs.alert.show("Vision unavailable: " .. tostring(requestErr), 3)
  end
end

function Calibration:markPointer()
  local window, err = self.roblox:find()
  if not window then hs.alert.show(err, 2) return end
  local frame = self.roblox:contentFrame(window)
  local screenPoint = hs.mouse.absolutePosition()
  if not Coordinates.contains(frame, screenPoint, 1) then
    hs.alert.show("Move the pointer inside Roblox first", 2)
    return
  end
  local point = Coordinates.screenToReference(screenPoint, frame, self.profile.reference_resolution)
  self.target = { x = point.x, y = point.y }
  self.input:showMarker(self.target, "calibration target", 2)
  self.logger:info("calibration_target_set", self.target)
  hs.alert.show(string.format("Target %.1f, %.1f saved (dry run)", point.x, point.y), 2)
end

function Calibration:clickTarget()
  if not self.target then hs.alert.show("Set a target with the marker hotkey first", 2) return end
  local ok, err = self.input:click(self.target, "assisted calibration target")
  if not ok then hs.alert.show("Click blocked: " .. tostring(err), 2) return end
  self.input:disarm("single calibration click sent")
  hs.alert.show("One calibration click sent; input disarmed", 2)
end

return Calibration
