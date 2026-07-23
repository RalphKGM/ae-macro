local Camera = {}
Camera.__index = Camera

function Camera.new(options)
  return setmetatable({
    input = options.input,
    mapStore = options.mapStore,
    profile = options.profile,
    logger = options.logger,
    timer = nil,
    cancelled = false,
  }, Camera)
end

function Camera:_after(milliseconds, callback)
  if self.timer then self.timer:stop() end
  self.timer = hs.timer.doAfter(math.max(0, milliseconds) / 1000, function()
    self.timer = nil
    if not self.cancelled then callback() end
  end)
end

function Camera:_pitch(callback)
  local config = self.profile.camera
  local ok, err = self.input:pitchDown(
    config.pitch_origin or { x = 408, y = 319 },
    config.pitch_steps or 30,
    config.pitch_delta_y or 100,
    "camera pitch toward ground",
    function(success, helperError)
      if not success then callback(nil, helperError) return end
      self:_after(200, function() callback(true) end)
    end
  )
  if not ok then callback(nil, err) end
end

function Camera:setup(task, progress, callback)
  self.cancelled = false
  local config = self.profile.camera
  progress("camera", "zooming into first person")
  local zoomInMs = config.zoom_in_ms or ((config.zoom_in_presses or 18) * 80)
  local ok, err = self.input:zoom("i", 1, zoomInMs, "camera zoom into first person", function(zoomed, zoomError)
    if not zoomed then callback(nil, zoomError) return end
    self:_after(200, function()
    progress("camera", "looking at the ground")
    self:_pitch(function(pitched, pitchError)
      if pitched == nil and pitchError then callback(nil, pitchError) return end
      progress("camera", "zooming out to bird's-eye")
      local zoomOutMs = config.zoom_out_ms or (math.abs(config.zoom_out_delta or -20) * 80)
      local scrollOk, scrollError = self.input:zoom("o", -1, zoomOutMs, "camera bird's-eye zoom", function(success, helperError)
        if not success then callback(nil, helperError) return end
        self:_after(config.settle_ms or 1800, function()
          progress("camera", "bird's-eye view ready")
          callback({
            output_path = self.mapStore:path(task),
            reused_map = hs.fs.attributes(self.mapStore:path(task)) ~= nil,
          })
        end)
      end)
      if not scrollOk then callback(nil, scrollError) end
    end)
  end)
  end)
  if not ok then callback(nil, err) end
end

function Camera:stop()
  self.cancelled = true
  if self.timer then self.timer:stop() self.timer = nil end
end

return Camera
