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
    moveStartMouseEvent = buttonNameToEventType(options.moveMouseButton or 'left', 'moveMouseButton'),
    moveModifiers = options.moveModifiers or {'cmd', 'shift'},
    windowCanvas = createResizeCanvas(options.opacity or 0.3),
    resizeStartMouseEvent = buttonNameToEventType(options.resizeMouseButton or 'left', 'resizeMouseButton'),
    resizeModifiers = options.resizeModifiers or {'ctrl', 'shift'},
    targetWindow = nil,

    canDrag = false,
    dragging = false,
    dragType = nil,

    enableWithoutClick = options.enableWithoutClick or false,
    mouseActivationThreshold = options.mouseActivationThreshold or 15,
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

  resizer.flagsHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.flagsChanged,
    },
    resizer:handleFlags()
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

  resizer.mouseMoveHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.mouseMoved,
    },
    resizer:handleMouseMoved()
  )

  resizer.clickHandler:start()
  resizer.flagsHandler:start()

  return resizer
end

function SkyRocket:stop()
  self.canDrag = false
  self.dragging = false
  self.dragType = nil

  self.windowCanvas:hide()
  self.cancelHandler:stop()
  self.dragHandler:stop()
  self.mouseMoveHandler:stop()
  self.clickHandler:start()
end

function SkyRocket:isResizing()
  return self.dragType == dragTypes.resize
end

function SkyRocket:isMoving()
  return self.dragType == dragTypes.move
end

function SkyRocket:cancel()
  if not self.dragging then return end

  if self:isResizing() then
    self:resizeWindowToCanvas()
  else
    self:moveWindowToCanvas()
  end

  self:stop()
end

function SkyRocket:handleCancel()
  return function()
    self:cancel()
  end
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

function SkyRocket:handleMouseMoved()
  return function(event)
    if not self.enableWithoutClick then return nil end
    if not self.canDrag then return nil end

    local dx = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
    local dy = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)

    if self:isMoving() then
      local current = self.windowCanvas:topLeft()

      local newX = current.x + dx
      local newY = current.y + dy

      if not self.dragging then
        if self.mouseActivationThreshold == 0 then
          self.dragging = true
          self.windowCanvas:show()
        else
          local target = self.targetWindow:topLeft()
          local delta = math.max(math.abs(target.x - newX), math.abs(target.y - newY))
          if delta > self.mouseActivationThreshold then
            self.dragging = true
            self.windowCanvas:show()
          end
        end
      end

      self.windowCanvas:topLeft({
        x = newX,
        y = newY,
      })

      return true
    elseif self:isResizing() then
      local currentSize = self.windowCanvas:size()

      local newW = currentSize.w + dx
      local newH = currentSize.h + dy

      if not self.dragging then
        if self.mouseActivationThreshold == 0 then
          self.dragging = true
          self.windowCanvas:show()
        else
          local target = self.targetWindow:size()
          local delta = math.max(math.abs(target.w - newW), math.abs(target.h - newH))
          if delta > self.mouseActivationThreshold then
            self.dragging = true
            self.windowCanvas:show()
          end
        end
      end

      self.windowCanvas:size({
        w = newW,
        h = newH,
      })

      return true
    else
      return nil
    end
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
    if self.enableWithoutClick then return nil end
    if self.dragging then return true end
    if not (self:isMoving() or self:isResizing()) then return nil end

    local eventType = event:getType()

    local isMoving = eventType == self.moveStartMouseEvent
    local isResizing = eventType == self.resizeStartMouseEvent

    if isMoving or isResizing then
      local currentWindow = getWindowUnderMouse()

      if self.disabledApps[currentWindow:application():name()] then
        return nil
      end

      self.dragging = true
      self.targetWindow = currentWindow

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

function SkyRocket:handleFlags()
  return function(event)
    local flags = event:getFlags()

    local isMoving = flags:containExactly(self.moveModifiers)
    local isResizing = flags:containExactly(self.resizeModifiers)

    if isMoving or isResizing then
      if isMoving then
        self.dragType = dragTypes.move
      else
        self.dragType = dragTypes.resize
      end

      if self.enableWithoutClick then
        local currentWindow = getWindowUnderMouse()

        if self.disabledApps[currentWindow:application():name()] then
          return nil
        end

        self.canDrag = true
        self.targetWindow = currentWindow

        self:resizeCanvasToWindow()
        self.mouseMoveHandler:start()
      end
    else
      self.canDrag = false
      if self.enableWithoutClick then
        self:cancel()
      end
    end

    return nil
  end
end

return SkyRocket
