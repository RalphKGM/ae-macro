local Coordinates = require("app.core.coordinates")
local Strategy = require("app.core.strategy")

local Controller = {}
Controller.__index = Controller

local function read(path)
  local file, err = io.open(path, "r")
  if not file then return nil, err end
  local contents = file:read("*a")
  file:close()
  return contents
end

local function timestamp()
  return os.date("!%Y%m%dT%H%M%SZ") .. "-" .. tostring(math.floor((hs.timer.secondsSinceEpoch() % 1) * 1000))
end

function Controller.new(options)
  return setmetatable({
    root = options.root,
    profile = options.profile,
    store = options.store,
    roblox = options.roblox,
    capture = options.capture,
    vision = options.vision,
    input = options.input,
    logger = options.logger,
    webview = nil,
    content = nil,
    recordTap = nil,
    menu = nil,
  }, Controller)
end

function Controller:_send(event, payload)
  if not self.webview then return end
  local message = self.profile and hs.json.encode({ event = event, payload = payload }) or "{}"
  self.webview:evaluateJavaScript("window.MacroApp && window.MacroApp.receive(" .. message .. ")")
end

function Controller:_error(message)
  self.logger:error("strategy_gui_error", { error = tostring(message) })
  self:_send("error", { message = tostring(message) })
end

function Controller:_toast(message)
  self:_send("toast", { message = tostring(message) })
end

function Controller:_bootstrap()
  local strategy = Strategy.new({
    id = "kings-tomb-act-1-mastery",
    name = "King's Tomb Act 1 Mastery",
    map = "King's Tomb",
    stage = "Act 1",
    difficulty = "Mastery",
    team = "current",
    reference_resolution = self.profile.reference_resolution,
  })
  local saved = self.store:load(strategy.id)
  if saved then strategy = saved end
  self:_send("bootstrap", {
    strategy = strategy,
    strategies = self.store:list(),
    reference_resolution = self.profile.reference_resolution,
    input_armed = self.input:isArmed(),
  })
end

function Controller:_makeWindow()
  local screen = hs.screen.mainScreen():frame()
  local width = math.min(1380, screen.w - 60)
  local height = math.min(900, screen.h - 60)
  local frame = {
    x = screen.x + (screen.w - width) / 2,
    y = screen.y + (screen.h - height) / 2,
    w = width,
    h = height,
  }
  self.content = hs.webview.usercontent.new("animeMacroBridge")
  self.content:setCallback(function(message)
    local body = message and message.body or message
    if type(body) ~= "table" then self:_error("invalid GUI message") return end
    self:_handle(body)
  end)
  local html, err = read(self.root .. "/app/ui/index.html")
  if not html then return nil, err end
  local css, cssError = read(self.root .. "/app/ui/styles.css")
  if not css then return nil, cssError end
  local javascript, scriptError = read(self.root .. "/app/ui/app.js")
  if not javascript then return nil, scriptError end
  html = html:gsub('<link rel="stylesheet" href="styles.css">', function()
    return "<style>" .. css .. "</style>"
  end)
  html = html:gsub('<script src="app.js"></script>', function()
    return "<script>" .. javascript .. "</script>"
  end)
  self.webview = hs.webview.new(frame, {
    javaScriptEnabled = true,
    javaScriptCanOpenWindowsAutomatically = false,
    developerExtrasEnabled = true,
    privateBrowsing = true,
  }, self.content)
    :allowTextEntry(true)
    :allowGestures(false)
    :allowNewWindows(false)
    :windowStyle({ "titled", "closable", "resizable", "miniaturizable" })
    :windowTitle("Anime Expeditions — Strategy Studio")
    :closeOnEscape(true)
    :deleteOnClose(false)
    :darkMode(true)
  self.webview:html(html)
  return true
end

function Controller:show()
  if not self.webview then
    local ok, err = self:_makeWindow()
    if not ok then hs.showError("Strategy Studio: " .. tostring(err)) return nil, err end
  end
  self.webview:show():bringToFront(true)
  return true
end

function Controller:hide()
  if self.webview then self.webview:hide() end
end

function Controller:toggle()
  if self.webview and self.webview:isVisible() then self:hide() else self:show() end
end

function Controller:_capture()
  local metadata, err = self.capture:window()
  if not metadata then self:_error(err) return end
  local profileInsets = self.profile.roblox.content_insets or {}
  local captureInsets = {
    left = math.floor((profileInsets.left or 0) * metadata.pixel_scale.x + 0.5),
    right = math.floor((profileInsets.right or 0) * metadata.pixel_scale.x + 0.5),
    top = math.floor((profileInsets.top or 0) * metadata.pixel_scale.y + 0.5),
    bottom = math.floor((profileInsets.bottom or 0) * metadata.pixel_scale.y + 0.5),
  }
  local output = self.root .. "/runtime/captures/editor-" .. timestamp() .. ".png"
  local id, requestError = self.vision:request("normalize", {
    input_path = metadata.path,
    output_path = output,
    width = self.profile.reference_resolution.w,
    height = self.profile.reference_resolution.h,
    insets = captureInsets,
  }, function(result, visionError)
    if not result then self:_error(visionError) return end
    local image = hs.image.imageFromPath(result.output_path)
    if not image then self:_error("could not load normalized editor capture") return end
    self:_send("capture", {
      image_url = image:encodeAsURLString(),
      width = result.width,
      height = result.height,
      blank_or_solid = result.blank_or_solid,
      path = result.output_path,
    })
    self.logger:info("strategy_gui_capture", result)
  end)
  if not id then self:_error(requestError) end
end

function Controller:_startRecord(payload)
  self:_stopRecord("restart")
  local window, err = self.roblox:focus()
  if not window then self:_error(err) return end
  self:hide()
  local types = hs.eventtap.event.types
  self.recordTap = hs.eventtap.new({ types.leftMouseDown, types.keyDown }, function(event)
    if event:getType() == types.keyDown and event:getKeyCode() == 53 then
      self:_stopRecord("cancelled")
      self:show()
      self:_toast("Recording cancelled")
      return true
    end
    if event:getType() ~= types.leftMouseDown then return false end
    local current, findError = self.roblox:find()
    if not current then
      self:_stopRecord("Roblox lost")
      self:show()
      self:_error(findError)
      return false
    end
    local screenPoint = event:location()
    local frame = self.roblox:contentFrame(current)
    if not Coordinates.contains(frame, screenPoint, 1) then return false end
    local point = Coordinates.screenToReference(screenPoint, frame, self.profile.reference_resolution)
    point.x = math.floor(point.x * 10 + 0.5) / 10
    point.y = math.floor(point.y * 10 + 0.5) / 10
    self:_stopRecord("point captured")
    self:show()
    self:_send("recorded_point", { x = point.x, y = point.y, unit_slot = payload.unit_slot })
    self.logger:info("strategy_point_recorded", { x = point.x, y = point.y, unit_slot = payload.unit_slot })
    return true
  end):start()
  hs.alert.show("Recording Unit " .. tostring(payload.unit_slot) .. " — click Roblox; Esc cancels", 2)
  self.logger:info("strategy_record_started", { unit_slot = payload.unit_slot })
end

function Controller:_stopRecord(reason)
  if self.recordTap then self.recordTap:stop() self.recordTap = nil end
  if reason then self.logger:info("strategy_record_stopped", { reason = reason }) end
end

function Controller:_preview(strategy)
  local valid, errors = Strategy.validate(strategy)
  if not valid then self:_error(table.concat(errors, "; ")) return end
  local window, err = self.roblox:focus()
  if not window then self:_error(err) return end
  self:hide()
  local count = 0
  for _, action in ipairs(strategy.actions) do
    if action.type == "place" then
      count = count + 1
      self.input:showMarker({ x = action.x, y = action.y }, "U" .. action.unit_slot .. " · " .. count, 4)
    end
  end
  if self.previewTimer then self.previewTimer:stop() end
  self.previewTimer = hs.timer.doAfter(4.1, function()
    self.previewTimer = nil
    self:show()
  end)
  self.logger:info("strategy_preview", { placements = count, strategy = strategy.id })
  if count == 0 then self:show() self:_toast("Add at least one placement first") end
end

function Controller:_handle(message)
  local operation = message.op
  local payload = message.payload or {}
  if operation == "ready" then
    self:_bootstrap()
  elseif operation == "capture" then
    self:_capture()
  elseif operation == "new" then
    self:_send("strategy", Strategy.new({ reference_resolution = self.profile.reference_resolution }))
  elseif operation == "load" then
    local strategy, err = self.store:load(payload.id)
    if not strategy then self:_error(err) else self:_send("strategy", strategy) end
  elseif operation == "save" then
    local strategy, pathOrError = self.store:save(payload.strategy)
    if not strategy then
      self:_error(pathOrError)
    else
      self:_send("saved", { strategy = strategy, strategies = self.store:list(), path = pathOrError })
      self:_toast("Strategy saved")
      self.logger:info("strategy_saved", { id = strategy.id, path = pathOrError, actions = #strategy.actions })
    end
  elseif operation == "delete" then
    local ok, err = self.store:delete(payload.id)
    if not ok then self:_error(err) else self:_send("deleted", { id = payload.id, strategies = self.store:list() }) end
  elseif operation == "copy_json" then
    local valid, errors = Strategy.validate(payload.strategy)
    if not valid then self:_error(table.concat(errors, "; ")) return end
    hs.pasteboard.setContents(hs.json.encode(payload.strategy, true))
    self:_toast("Strategy JSON copied")
  elseif operation == "import" then
    local paths = hs.dialog.chooseFileOrFolder("Import a strategy JSON", self.store.directory, true, false, false, { "json" }, true)
    if paths and paths[1] then
      local strategy, err = self.store:import(paths[1])
      if not strategy then self:_error(err) else self:_send("saved", { strategy = strategy, strategies = self.store:list() }) end
    end
  elseif operation == "record" then
    self:_startRecord(payload)
  elseif operation == "preview" then
    self:_preview(payload.strategy)
  elseif operation == "hide" then
    self:hide()
  else
    self:_error("unsupported GUI operation: " .. tostring(operation))
  end
end

function Controller:startMenu()
  self.menu = hs.menubar.new()
  if self.menu then
    self.menu:setTitle("AE")
    self.menu:setTooltip("Anime Expeditions Strategy Studio")
    self.menu:setMenu({
      { title = "Open Strategy Studio", fn = function() self:show() end },
      { title = "Capture Roblox", fn = function() self:_capture() end },
      { title = "Emergency Stop", fn = function() self.input:disarm("menu emergency stop") end },
    })
  end
end

function Controller:stop()
  self:_stopRecord("shutdown")
  if self.previewTimer then self.previewTimer:stop() self.previewTimer = nil end
  if self.webview then self.webview:delete(true) self.webview = nil end
  self.content = nil
  if self.menu then self.menu:delete() self.menu = nil end
end

return Controller
