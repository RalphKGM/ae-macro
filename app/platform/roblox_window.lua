local Coordinates = require("app.core.coordinates")
local RobloxWindow = {}
RobloxWindow.__index = RobloxWindow

function RobloxWindow.new(config, logger)
  return setmetatable({ config = config, logger = logger, dock_content_frame = nil }, RobloxWindow)
end

function RobloxWindow:application()
  local app = hs.application.get(self.config.bundle_id)
  if app then return app end
  return hs.application.find(self.config.application_name or "Roblox")
end

function RobloxWindow:find()
  local app = self:application()
  if not app then return nil, "Roblox is not running" end
  local window = app:mainWindow() or app:focusedWindow()
  if not window then
    for _, candidate in ipairs(app:allWindows()) do
      if candidate:isVisible() then window = candidate break end
    end
  end
  if not window then return nil, "Roblox has no visible window" end
  return window
end

function RobloxWindow:contentFrame(window)
  window = window or assert(self:find())
  return Coordinates.contentFrame(window:frame(), self.config.content_insets)
end

function RobloxWindow:isFrontmost(window)
  local front = hs.application.frontmostApplication()
  local owner = window and window:application()
  return front and owner and front:pid() == owner:pid()
end

function RobloxWindow:focus()
  local window, err = self:find()
  if not window then return nil, err end
  if window:isMinimized() then window:unminimize() end
  window:focus()
  return window
end

function RobloxWindow:setDockContentFrame(frame)
  if not frame then
    self.dock_content_frame = nil
    return
  end
  self.dock_content_frame = {
    x = frame.x, y = frame.y, w = frame.w, h = frame.h,
  }
end

function RobloxWindow:alignToContentFrame(contentFrame)
  local window, err = self:find()
  if not window then return nil, err end
  if window:isFullScreen() then return nil, "leave macOS full-screen mode before alignment" end
  local insets = self.config.content_insets or {}
  local target = {
    x = contentFrame.x - (insets.left or 0),
    y = contentFrame.y - (insets.top or 0),
    w = contentFrame.w + (insets.left or 0) + (insets.right or 0),
    h = contentFrame.h + (insets.top or 0) + (insets.bottom or 0),
  }
  window:setFrame(target, 0)
  self.logger:info("roblox_docked", {
    content_x = contentFrame.x, content_y = contentFrame.y,
    content_w = contentFrame.w, content_h = contentFrame.h,
    window_x = target.x, window_y = target.y, window_w = target.w, window_h = target.h,
  })
  return window
end

function RobloxWindow:align(reference, fraction)
  if self.dock_content_frame then
    return self:alignToContentFrame(self.dock_content_frame)
  end
  local window, err = self:find()
  if not window then return nil, err end
  if window:isFullScreen() then return nil, "leave macOS full-screen mode before alignment" end
  local screen = window:screen() or hs.screen.mainScreen()
  local usable = screen:frame()
  local target = Coordinates.fitContentWindow(usable, reference, self.config.content_insets, fraction or 0.88)
  window:setFrame(target, 0)
  self.logger:info("roblox_aligned", { x = target.x, y = target.y, w = target.w, h = target.h })
  return window
end

return RobloxWindow
