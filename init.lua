local function scriptPath()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

local SkyRocket = {}

SkyRocket.author = "David Balatero <d@balatero.com>"
SkyRocket.homepage = "https://github.com/dbalatero/SkyRocket.spoon"
SkyRocket.license = "MIT"
SkyRocket.name = "SkyRocket"
SkyRocket.version = "1.0.2"
SkyRocket.spoonPath = scriptPath()

local dragTypes = {
  move = 1,
  resize = 2,
}

local function tableToMap(table)
  local map = {}

  for _, value in pairs(table) do
    map[value] = true
  end

  return map
end

local function createResizeCanvas(alpha)
  local canvas = hs.canvas.new{}

  canvas:insertElement(
    {
      id = 'opaque_layer',
      action = 'fill',
      type = 'rectangle',
      fillColor = { red = 0, green = 0, blue = 0, alpha = alpha },
      roundedRectRadii = { xRadius = 5.0, yRadius = 5.0 },
    },
    1
  )

  return canvas
end

local function getWindowUnderMouse()
  -- Invoke `hs.application` because `hs.window.orderedWindows()` doesn't do it
  -- and breaks itself
  local _ = hs.application

  local my_pos = hs.geometry.new(hs.mouse.absolutePosition())
  local my_screen = hs.mouse.getCurrentScreen()

  return hs.fnutils.find(hs.window.orderedWindows(), function(w)
    return my_screen == w:screen() and my_pos:inside(w:frame())
  end)
end

-- Usage:
--   resizer = SkyRocket:new({
--     opacity = 0.3,
--     moveModifiers = {'cmd', 'shift'},
--     moveMouseButton = 'left',
--     resizeModifiers = {'ctrl', 'shift'}
--     resizeMouseButton = 'left',
--   })
--
local function buttonNameToEventType(name, optionName)
  if name == 'left' then
    return hs.eventtap.event.types.leftMouseDown
  end
  if name == 'right' then
    return hs.eventtap.event.types.rightMouseDown
  end
  error(optionName .. ': only "left" and "right" mouse button supported, got ' .. name)
end

function SkyRocket:new(options)
  options = options or {}

  local resizer = {
    disabledApps = tableToMap(options.disabledApps or {}),
    dragging = false,
    dragType = nil,
    moveStartMouseEvent = buttonNameToEventType(options.moveMouseButton or 'left', 'moveMouseButton'),
    moveModifiers = options.moveModifiers or {'cmd', 'shift'},
    windowCanvas = createResizeCanvas(options.opacity or 0.3),
    resizeStartMouseEvent = buttonNameToEventType(options.resizeMouseButton or 'left', 'resizeMouseButton'),
    resizeModifiers = options.resizeModifiers or {'ctrl', 'shift'},
    targetWindow = nil,
  }

  setmetatable(resizer, self)
  self.__index = self

  resizer.clickHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.leftMouseDown,
      hs.eventtap.event.types.rightMouseDown,
    },
    resizer:handleClick()
  )

  resizer.cancelHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.leftMouseUp,
      hs.eventtap.event.types.rightMouseUp,
    },
    resizer:handleCancel()
  )

  resizer.dragHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.leftMouseDragged,
      hs.eventtap.event.types.rightMouseDragged,
    },
    resizer:handleDrag()
  )

  resizer.clickHandler:start()

  return resizer
end

function SkyRocket:stop()
  self.dragging = false
  self.dragType = nil

  self.windowCanvas:hide()
  self.cancelHandler:stop()
  self.dragHandler:stop()
  self.clickHandler:start()
end

function SkyRocket:isResizing()
  return self.dragType == dragTypes.resize
end

function SkyRocket:isMoving()
  return self.dragType == dragTypes.move
end

function SkyRocket:handleDrag()
  return function(event)
    if not self.dragging then return nil end

    local dx = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
    local dy = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)

    if self:isMoving() then
      local current = self.windowCanvas:topLeft()

      self.windowCanvas:topLeft({
        x = current.x + dx,
        y = current.y + dy,
      })

      return true
    elseif self:isResizing() then
      local currentSize = self.windowCanvas:size()

      self.windowCanvas:size({
        w = currentSize.w + dx,
        h = currentSize.h + dy
      })

      return true
    else
      return nil
    end
  end
end

function SkyRocket:handleCancel()
  return function()
    if not self.dragging then return end

    if self:isResizing() then
      self:resizeWindowToCanvas()
    else
      self:moveWindowToCanvas()
    end

    self:stop()
  end
end

function SkyRocket:resizeCanvasToWindow()
  local position = self.targetWindow:topLeft()
  local size = self.targetWindow:size()

  self.windowCanvas:topLeft({ x = position.x, y = position.y })
  self.windowCanvas:size({ w = size.w, h = size.h })
end

function SkyRocket:resizeWindowToCanvas()
  if not self.targetWindow then return end
  if not self.windowCanvas then return end

  local size = self.windowCanvas:size()
  self.targetWindow:setSize(size.w, size.h)
end

function SkyRocket:moveWindowToCanvas()
  if not self.targetWindow then return end
  if not self.windowCanvas then return end

  local frame = self.windowCanvas:frame()
  local point = self.windowCanvas:topLeft()

  local moveTo = {
    x = point.x,
    y = point.y,
    w = frame.w,
    h = frame.h,
  }

  self.targetWindow:move(hs.geometry.new(moveTo), nil, false, 0)
end

function SkyRocket:handleClick()
  return function(event)
    if self.dragging then return true end

    local flags = event:getFlags()
    local eventType = event:getType()

    local isMoving = eventType == self.moveStartMouseEvent and flags:containExactly(self.moveModifiers)
    local isResizing = eventType == self.resizeStartMouseEvent and flags:containExactly(self.resizeModifiers)

    if isMoving or isResizing then
      local currentWindow = getWindowUnderMouse()

      if self.disabledApps[currentWindow:application():name()] then
        return nil
      end

      self.dragging = true
      self.targetWindow = currentWindow

      if isMoving then
        self.dragType = dragTypes.move
      else
        self.dragType = dragTypes.resize
      end

      self:resizeCanvasToWindow()
      self.windowCanvas:show()

      self.cancelHandler:start()
      self.dragHandler:start()
      self.clickHandler:stop()

      -- Prevent selection
      return true
    else
      return nil
    end
  end
end

return SkyRocket
