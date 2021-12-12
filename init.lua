local function scriptPath()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

local SkyRocket = {}

SkyRocket.author = "David Balatero <d@balatero.com>"
SkyRocket.homepage = "https://github.com/dbalatero/SkyRocket.spoon"
SkyRocket.license = "MIT"
SkyRocket.name = "SkyRocket"
SkyRocket.version = "1.0.3"
SkyRocket.spoonPath = scriptPath()

local dragTypes = {
  move = 1,
  resize = 2,
  fancy = 3,
}

local function tableToMap(table)
  local map = {}

  for _, value in pairs(table) do
    map[value] = true
  end

  return map
end

local function createResizeCanvas()
  local canvas = hs.canvas.new{}

  canvas:insertElement(
    {
      id = 'opaque_layer',
      action = 'fill',
      type = 'rectangle',
      fillColor = { red = 0, green = 0, blue = 0, alpha = 0.3 },
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
--     moveModifiers = {'cmd', 'shift'},
--     resizeModifiers = {'ctrl', 'shift'}
--     fancyZoneModifier = {'shift'},
--     zones = {
--        {w=0.50,h=0.50,x=0.0 ,y=0},
--        {w=0.50,h=0.50,x=0.0 ,y=50},
--     }
--   })
--
function SkyRocket:new(options)
  options = options or {}

  local resizer = {
    disabledApps = tableToMap(options.disabledApps or {}),
    dragging = false,
    dragType = nil,
    moveModifiers = options.moveModifiers or {'cmd', 'shift'},
    windowCanvas = createResizeCanvas(),
    resizeModifiers = options.resizeModifiers or {'ctrl', 'shift'},
    targetWindow = nil,

    fancyZoneModifier = options.fancyZoneModifier or {'shift'},
    zones = options.zones or {
      {w=0.50,h=0.50,x=0.0 ,y=0},
      {w=0.50,h=0.50,x=0.0,y=50},
      {w=0.50,h=0.50,x=0.50, y=0},
      {w=0.50,h=0.50,x=0.50,y=50},
    },
    fancyPosition=hs.geometry.point(0,0),
    showcanvas = false,
    screen = nil,
    menuheight = 22,
  }

  setmetatable(resizer, self)
  self.__index = self

  resizer.clickHandler = hs.eventtap.new(
    { hs.eventtap.event.types.leftMouseDown },
    resizer:handleClick()
  )

  resizer.cancelHandler = hs.eventtap.new(
    { hs.eventtap.event.types.leftMouseUp },
    resizer:handleCancel()
  )

  resizer.dragHandler = hs.eventtap.new(
    { hs.eventtap.event.types.leftMouseDragged },
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

function SkyRocket:isFancy()
  return self.dragType == dragTypes.fancy
end

function SkyRocket:handleDrag()
  return function(event)
    if not self.dragging then return nil end

    if not self.showcanvas then
      self:resizeCanvasToWindow()
      self.windowCanvas:show()
      self.showcanvas = true
    end

    local dx = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
    local dy = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)

    if self:isMoving() then
      local current = self.windowCanvas:topLeft()

      self.windowCanvas:topLeft({
        x = current.x + dx,
        y = current.y + dy,
      })

      return true
    end

    if self:isResizing() then
      local currentSize = self.windowCanvas:size()

      self.windowCanvas:size({
        w = currentSize.w + dx,
        h = currentSize.h + dy
      })

      return true
    end

    if self:isFancy() then
      self.fancyPosition.x = self.fancyPosition.x + dx
      self.fancyPosition.y = self.fancyPosition.y + dy

      -- Avoid the current position to be off-screen
      if self.fancyPosition.x < 0 then 
        self.fancyPosition.x = 0 
      elseif self.fancyPosition.x > self.screen.w then 
          self.fancyPosition.x = self.screen.w 
      end
      if self.fancyPosition.y < 0 then 
        self.fancyPosition.y = 0
      elseif self.fancyPosition.y > self.screen.h then 
          self.fancyPosition.y = self.screen.h 
      end

      -- Transform position from absolute to ratio
      local position = hs.geometry.point(0,0)
      position.x = self.fancyPosition.x / self.screen.w
      position.y = self.fancyPosition.y / self.screen.h

      -- For each zone if the current position is in the zone we render the canvas and exit the loop
      for k,v in pairs(self.zones) do            
          if 
              (position.x > v.x) and 
              (position.x < v.x + v.w) and 
              (position.y > v.y) and 
              (position.y < v.y + v.h) 
          then
              self.windowCanvas:topLeft({
                  x = v.x * self.screen.w,
                  y = v.y * self.screen.h + self.menuheight
              })
              self.windowCanvas:size({
                  w = v.w * self.screen.w,
                  h = v.h * self.screen.h
              })

              return true
          end
      end

      return true
    end

    return nil
  end
end

function SkyRocket:handleCancel()
  return function()
    if not self.dragging then return end

    if self:isResizing() then
      self:resizeWindowToCanvas()
    elseif self:isMoving() then
      self:moveWindowToCanvas()
    elseif self:isFancy() then
      self:moveWindowToCanvas()
      self:resizeWindowToCanvas()
    end

    self.showcanvas = false
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

    local isMoving = flags:containExactly(self.moveModifiers)
    local isResizing = flags:containExactly(self.resizeModifiers)
    local isFancy = flags:containExactly(self.fancyZoneModifier)

    if isMoving or isResizing or isFancy then
      local currentWindow = getWindowUnderMouse()

      if currentWindow==nil or self.disabledApps[currentWindow:application():name()] then
        return nil
      end

      self.dragging = true
      self.targetWindow = currentWindow

      if isMoving then 
        self.dragType = dragTypes.move
      elseif isResizing then 
        self.dragType = dragTypes.resize
      elseif isFancy then 
          self.dragType = dragTypes.fancy
          self.fancyPosition = hs.mouse.absolutePosition()
          self.screen = getWindowUnderMouse():screen():currentMode()
          self.screen.h = self.screen.h - self.menuheight
      end

      self.cancelHandler:start()
      self.dragHandler:start()
      self.clickHandler:stop()

      return true
    else
      return nil
    end
  end
end

return SkyRocket