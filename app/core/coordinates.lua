local Coordinates = {}

local function positive(value, label)
  assert(type(value) == "number" and value > 0, label .. " must be positive")
end

function Coordinates.referenceToScreen(point, contentFrame, reference)
  positive(contentFrame.w, "contentFrame.w")
  positive(contentFrame.h, "contentFrame.h")
  positive(reference.w, "reference.w")
  positive(reference.h, "reference.h")
  assert(point.x >= 0 and point.x <= reference.w, "reference x is out of bounds")
  assert(point.y >= 0 and point.y <= reference.h, "reference y is out of bounds")
  return {
    x = contentFrame.x + (point.x / reference.w) * contentFrame.w,
    y = contentFrame.y + (point.y / reference.h) * contentFrame.h,
  }
end

function Coordinates.screenToReference(point, contentFrame, reference)
  positive(contentFrame.w, "contentFrame.w")
  positive(contentFrame.h, "contentFrame.h")
  return {
    x = ((point.x - contentFrame.x) / contentFrame.w) * reference.w,
    y = ((point.y - contentFrame.y) / contentFrame.h) * reference.h,
  }
end

function Coordinates.contains(frame, point, margin)
  margin = margin or 0
  return point.x >= frame.x + margin
    and point.x <= frame.x + frame.w - margin
    and point.y >= frame.y + margin
    and point.y <= frame.y + frame.h - margin
end

function Coordinates.contentFrame(windowFrame, insets)
  insets = insets or {}
  local left = insets.left or 0
  local right = insets.right or 0
  local top = insets.top or 0
  local bottom = insets.bottom or 0
  local frame = {
    x = windowFrame.x + left,
    y = windowFrame.y + top,
    w = windowFrame.w - left - right,
    h = windowFrame.h - top - bottom,
  }
  positive(frame.w, "content frame width")
  positive(frame.h, "content frame height")
  return frame
end

function Coordinates.fitContentWindow(usableFrame, reference, insets, fraction)
  insets = insets or {}
  fraction = fraction or 0.88
  assert(fraction > 0 and fraction <= 1, "fraction must be in (0, 1]")
  local horizontal = (insets.left or 0) + (insets.right or 0)
  local vertical = (insets.top or 0) + (insets.bottom or 0)
  local maximumContentWidth = usableFrame.w * fraction - horizontal
  local maximumContentHeight = usableFrame.h * fraction - vertical
  positive(maximumContentWidth, "maximum content width")
  positive(maximumContentHeight, "maximum content height")
  local aspect = reference.w / reference.h
  local contentWidth = math.min(maximumContentWidth, maximumContentHeight * aspect)
  local contentHeight = contentWidth / aspect
  local width = contentWidth + horizontal
  local height = contentHeight + vertical
  return {
    x = usableFrame.x + (usableFrame.w - width) / 2,
    y = usableFrame.y + (usableFrame.h - height) / 2,
    w = width,
    h = height,
  }
end

return Coordinates
