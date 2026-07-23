local Catalog = require("app.config.catalog")
local Profiles = require("app.config.profiles")
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
    profileStore = options.profileStore,
    store = options.store,
    roblox = options.roblox,
    capture = options.capture,
    vision = options.vision,
    input = options.input,
    mapStore = options.mapStore,
    webhooks = options.webhooks,
    logger = options.logger,
    statusProvider = options.statusProvider,
    onProfileChanged = options.onProfileChanged,
    automation = options.automation,
    webview = nil,
    content = nil,
    menu = nil,
    previewTimer = nil,
  }, Controller)
end

function Controller:setAutomation(automation)
  self.automation = automation
end

function Controller:_send(event, payload)
  if not self.webview then return end
  local message = hs.json.encode({ event = event, payload = payload or {} })
  self.webview:evaluateJavaScript("window.MacroApp && window.MacroApp.receive(" .. message .. ")")
end

function Controller:_error(message)
  self.logger:error("gui_error", { error = tostring(message) })
  self:_send("error", { message = tostring(message) })
end

function Controller:_toast(message)
  self:_send("toast", { message = tostring(message) })
end

function Controller:_taskAt(index)
  index = math.max(1, math.floor(index or 1))
  return self.profile.tasks[index] or self.profile.tasks[1]
end

function Controller:_strategyForTask(task)
  local id = task and task.strategy or "kings-tomb-act-1-mastery"
  local strategy = self.store:load(id)
  if strategy then return strategy end
  return Strategy.new({
    id = id,
    name = task and task.name or "new strategy",
    map = task and task.map or "King's Tomb",
    stage = task and task.stage or "Act 1",
    difficulty = task and task.difficulty or "Mastery",
    team = task and task.team or "current",
    reference_resolution = self.profile.reference_resolution,
  })
end

function Controller:_mapPayload(task)
  if not task then return nil end
  local image, path = self.mapStore:image(task)
  if not image then return { path = self.mapStore:path(task) } end
  return { image_url = image:encodeAsURLString(), path = path, key = self.mapStore:key(task) }
end

function Controller:_bootstrap()
  local runtime = self.automation and self.automation:status() or {
    active = false, paused = false, state = "IDLE", task_index = 1, stats = {},
  }
  local task = self:_taskAt(runtime.task_index)
  local strategy = self:_strategyForTask(task)
  local status = self.statusProvider and self.statusProvider() or {}
  self:_send("bootstrap", {
    profile = self.profile,
    strategy = strategy,
    strategies = self.store:list(),
    catalog = Catalog.snapshot(),
    runtime = runtime,
    status = status,
    map = self:_mapPayload(task),
  })
  self.webhooks:configured(function(configured)
    self:_send("webhook_status", { configured = configured })
  end)
end

function Controller:_makeWindow()
  local screen = hs.screen.mainScreen():frame()
  local frame = {
    x = screen.x + 20,
    y = screen.y + 20,
    w = math.max(980, screen.w - 40),
    h = math.max(700, screen.h - 40),
  }
  self.content = hs.webview.usercontent.new("animeMacroBridge")
  self.content:setCallback(function(message)
    local body = message and message.body or message
    if type(body) ~= "table" then self:_error("invalid gui message") return end
    self:_handle(body)
  end)
  local html, htmlError = read(self.root .. "/app/ui/index.html")
  if not html then return nil, htmlError end
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
    :windowTitle("anime expeditions mac")
    :closeOnEscape(true)
    :deleteOnClose(false)
    :darkMode(true)
  self.webview:html(html)
  return true
end

function Controller:show()
  if not self.webview then
    local ok, err = self:_makeWindow()
    if not ok then hs.showError("ae gui: " .. tostring(err)) return nil, err end
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

function Controller:_capturePreview()
  local output = self.root .. "/runtime/captures/dashboard-" .. timestamp() .. ".png"
  local id, err = self.capture:normalized(self.vision, self.profile, output, function(result, captureError)
    if not result then self:_error(captureError) return end
    local image = hs.image.imageFromPath(result.output_path)
    if not image then self:_error("could not load dashboard capture") return end
    self:_send("preview", {
      image_url = image:encodeAsURLString(),
      path = result.output_path,
      label = "roblox · " .. os.date("%H:%M:%S"),
    })
  end)
  if not id then self:_error(err) end
end

function Controller:_captureMap(task)
  local id, err = self.mapStore:capture(task, function(result, captureError)
    if not result then self:_error(captureError) return end
    self:_send("map", self:_mapPayload(task))
    self:_toast("map image saved")
  end)
  if not id then self:_error(err) end
end

function Controller:_previewStrategy(strategy)
  local valid, errors = Strategy.validate(strategy)
  if not valid then self:_error(table.concat(errors, "; ")) return end
  local window, err = self.roblox:focus()
  if not window then self:_error(err) return end
  self:hide()
  local count = 0
  for _, action in ipairs(strategy.actions) do
    if action.type == "place" then
      count = count + 1
      self.input:showMarker({ x = action.x, y = action.y }, "slot " .. tostring(action.unit_slot), 4)
    end
  end
  if self.previewTimer then self.previewTimer:stop() end
  self.previewTimer = hs.timer.doAfter(4.1, function()
    self.previewTimer = nil
    self:show()
  end)
  if count == 0 then self:show() self:_toast("add a placement first") end
end

function Controller:_saveProfile(profile)
  profile = Profiles.defaults(profile)
  local saved, err = self.profileStore:save(profile)
  if not saved then self:_error(err) return end
  self.profile = saved
  self.mapStore.profile = saved
  if self.onProfileChanged then self.onProfileChanged(saved) end
  self:_send("profile_saved", { profile = saved })
end

function Controller:_start(payload)
  if not self.automation then self:_error("run engine is not ready") return end
  self:hide()
  local ok, err = self.automation:start(payload)
  if not ok then
    self:show()
    self:_error(err)
  end
end

function Controller:runtimeEvent(event, payload)
  self:_send(event, payload)
  self:_send("runtime", {
    active = self.automation and self.automation.active or false,
    paused = self.automation and self.automation.paused or false,
    state = payload.state,
    task = self.automation and self.automation.queue:current() and self.automation.queue:current().name,
    stats = payload.stats,
    challenges = payload.challenges,
    crafting = payload.crafting,
  })
  if event == "complete" or event == "stopped" or event == "error" then
    hs.timer.doAfter(0.2, function() self:show() end)
  end
end

function Controller:_handle(message)
  local operation = message.op
  local payload = message.payload or {}
  if operation == "ready" then
    self:_bootstrap()
  elseif operation == "hide" then
    self:hide()
  elseif operation == "align" then
    local _, err = self.roblox:align(self.profile.reference_resolution)
    if err then self:_error(err) else self:_toast("roblox aligned") end
  elseif operation == "capture_preview" then
    self:_capturePreview()
  elseif operation == "capture_map" then
    self:_captureMap(payload.task)
  elseif operation == "load_map" then
    self:_send("map", self:_mapPayload(payload.task))
  elseif operation == "new_strategy" then
    self:_send("strategy", Strategy.new({ reference_resolution = self.profile.reference_resolution }))
  elseif operation == "load_strategy" then
    local strategy, err = self.store:load(payload.id)
    if not strategy then self:_error(err) else self:_send("strategy", strategy) end
  elseif operation == "save_strategy" then
    local strategy, err = self.store:save(payload.strategy)
    if not strategy then
      self:_error(err)
    else
      self:_send("strategy_saved", { strategy = strategy, strategies = self.store:list() })
    end
  elseif operation == "copy_strategy" then
    local valid, errors = Strategy.validate(payload.strategy)
    if not valid then self:_error(table.concat(errors, "; ")) return end
    hs.pasteboard.setContents(hs.json.encode(payload.strategy, true))
    self:_toast("strategy json copied")
  elseif operation == "import_strategy" then
    local paths = hs.dialog.chooseFileOrFolder("import strategy json", self.store.directory, true, false, false, { "json" }, true)
    if paths and paths[1] then
      local strategy, err = self.store:import(paths[1])
      if not strategy then self:_error(err) else self:_send("strategy_saved", { strategy = strategy, strategies = self.store:list() }) end
    end
  elseif operation == "preview_strategy" then
    self:_previewStrategy(payload.strategy)
  elseif operation == "save_profile" then
    self:_saveProfile(payload.profile)
  elseif operation == "start" then
    self:_start(payload)
  elseif operation == "pause" then
    if not self.automation:pause() then self:_error("the macro is not running") end
  elseif operation == "resume" then
    if not self.automation:resume() then self:_error("the macro is not paused") end
  elseif operation == "stop" then
    self.automation:stop(payload.reason or "gui stop")
  elseif operation == "set_webhook" then
    self.webhooks:setURL(payload.url, function(ok, err)
      if not ok then self:_error(err) return end
      self:_send("webhook_status", { configured = true })
      self:_toast("webhook saved in macos keychain")
    end)
  elseif operation == "test_webhook" then
    local enabled = self.webhooks.config.enabled
    self.webhooks.config.enabled = true
    self.webhooks:send("started", { message = "test from ae mac" }, nil, function(ok, err)
      self.webhooks.config.enabled = enabled
      if not ok then self:_error(err) else self:_toast("test webhook sent") end
    end)
  else
    self:_error("unsupported gui operation: " .. tostring(operation))
  end
end

function Controller:startMenu()
  self.menu = hs.menubar.new()
  if not self.menu then return end
  self.menu:setTitle("ae")
  self.menu:setTooltip("anime expeditions mac")
  self.menu:setMenu(function()
    local running = self.automation and self.automation.active
    return {
      { title = "open ae", fn = function() self:show() end },
      { title = "-" },
      { title = "start", disabled = running, fn = function() self:_start({}) end },
      { title = self.automation and self.automation.paused and "resume" or "pause", disabled = not running, fn = function()
        if self.automation.paused then self.automation:resume() else self.automation:pause() end
      end },
      { title = "stop", disabled = not running, fn = function() self.automation:stop("menu stop") end },
      { title = "-" },
      { title = "align roblox", fn = function() self.roblox:align(self.profile.reference_resolution) end },
      { title = "refresh preview", fn = function() self:_capturePreview() end },
      { title = "emergency stop", fn = function() self.automation:stop("menu emergency stop") end },
    }
  end)
end

function Controller:stop()
  if self.previewTimer then self.previewTimer:stop() self.previewTimer = nil end
  if self.webview then self.webview:delete(true) self.webview = nil end
  self.content = nil
  if self.menu then self.menu:delete() self.menu = nil end
end

return Controller
