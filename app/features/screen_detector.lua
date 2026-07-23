local ScreenDetector = {}
ScreenDetector.__index = ScreenDetector

local function stamp()
  return os.date("!%Y%m%dT%H%M%SZ") .. "-" .. tostring(math.floor((hs.timer.secondsSinceEpoch() % 1) * 1000))
end

function ScreenDetector.new(options)
  return setmetatable({
    root = options.root,
    profile = options.profile,
    capture = options.capture,
    vision = options.vision,
    logger = options.logger,
  }, ScreenDetector)
end

function ScreenDetector:detect(callback, label, context)
  local path = self.root .. "/runtime/diagnostics/screen-" .. stamp() .. ".png"
  local id, err = self.capture:normalized(self.vision, self.profile, path, function(result, normalizeError)
    if not result then callback(nil, normalizeError) return end
    local requestId, requestError = self.vision:request("classify_screen", {
      image_path = result.output_path,
      templates_dir = "assets/nav",
      context = context,
    }, function(classification, classificationError)
      if classification then
        classification.image_path = result.output_path
        self.logger:info("screen_classified", {
          state = classification.state,
          confidence = classification.confidence,
          label = label,
          context = context,
        })
      end
      callback(classification, classificationError)
    end)
    if not requestId then callback(nil, requestError) end
  end)
  if not id then return nil, err end
  return id
end

return ScreenDetector
