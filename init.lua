local function scriptPath()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*/)")
end

local HammerDrag = {}

local geom = require 'hs.geometry'

HammerDrag.author = "David Balatero <d@balatero.com>"
HammerDrag.homepage = "https://github.com/dbalatero/HammerDrag.spoon"
HammerDrag.license = "MIT"
HammerDrag.name = "HammerDrag"
HammerDrag.version = "1.0.2"
HammerDrag.spoonPath = scriptPath()

local dragTypes = {
    move = 1,
    resize = 2
}

local function tableToMap(table)
    local map = {}

    for _, value in pairs(table) do
        map[value] = true
    end

    return map
end

local function createResizeCanvas(alpha)
    local canvas = hs.canvas.new {}

    canvas:insertElement({
        id = 'opaque_layer',
        action = 'fill',
        type = 'rectangle',
        fillColor = {
            red = 0,
            green = 0,
            blue = 0,
            alpha = alpha
        },
        roundedRectRadii = {
            xRadius = 8.0,
            yRadius = 8.0
        }
    }, 1)

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

local function buttonNameToEventType(name, optionName)
    if name == 'left' then
        return hs.eventtap.event.types.leftMouseDown
    end
    if name == 'right' then
        return hs.eventtap.event.types.rightMouseDown
    end
    error(optionName .. ': only "left" and "right" mouse button supported, got ' .. name)
end

-- Usage:
--   resizer = HammerDrag:new({
--     opacity = 0.3,
--     moveModifiers = {'cmd', 'shift'},
--     moveMouseButton = 'left',
--     resizeModifiers = {'ctrl', 'shift'}
--     resizeMouseButton = 'left',
--   })
--
function HammerDrag:new(options)
    options = options or {}

    local resizer = {
        disabledApps = tableToMap(options.disabledApps or {}),
        dragging = false,
        dragType = nil,

        focusOnClick = options.focusOnClick or true,
        preview = options.preview or false,

        -- Allow passing an hs.grid
        grid = options.grid or require "hs.grid",

        windowCanvas = createResizeCanvas(options.opacity or 0.3),

        moveStartMouseEvent = buttonNameToEventType(options.moveMouseButton or 'left', 'moveMouseButton'),
        moveModifiers = options.moveModifiers or {'ctrl', 'cmd'},

        resizeStartMouseEvent = buttonNameToEventType(options.resizeMouseButton or 'right', 'resizeMouseButton'),
        resizeModifiers = options.resizeModifiers or {'ctrl', 'cmd'},

        moveGridStartMouseEvent = buttonNameToEventType(options.moveGridMouseButton or 'left', 'moveGridMouseButton'),
        moveGridModifiers = options.moveGridModifiers or {'ctrl', 'alt'},

        resizeGridStartMouseEvent = buttonNameToEventType(options.resizeGridMouseButton or 'right',
            'resizeGridMouseButton'),
        resizeGridModifiers = options.resizeGridModifiers or {'ctrl', 'alt'},

        targetWindow = nil
    }

    setmetatable(resizer, self)
    self.__index = self

    resizer.clickHandler = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown,
                                            hs.eventtap.event.types.rightMouseDown}, resizer:handleClick())

    resizer.cancelHandler = hs.eventtap.new({hs.eventtap.event.types.leftMouseUp, hs.eventtap.event.types.rightMouseUp},
        resizer:handleCancel())

    resizer.dragHandler = hs.eventtap.new({hs.eventtap.event.types.leftMouseDragged,
                                           hs.eventtap.event.types.rightMouseDragged}, resizer:handleDrag())

    resizer.clickHandler:start()

    return resizer
end

function HammerDrag:stop()
    self.dragging = false
    self.dragType = nil
    self.useGrid = false

    self.windowCanvas:hide()
    self.cancelHandler:stop()
    self.dragHandler:stop()
    self.clickHandler:start()
end

function HammerDrag:isResizing()
    return self.dragType == dragTypes.resize
end

function HammerDrag:isMoving()
    return self.dragType == dragTypes.move
end

function HammerDrag:getGridCellForCoordinates(x, y, screen)
    -- Ensure we have a screen
    local targetScreen = screen or hs.mouse.getCurrentScreen()
    if not targetScreen then
        return nil
    end

    -- Get the screen grid and frame
    local screenFrame = targetScreen:frame()
    local gridSize = hs.grid.getGrid(targetScreen) -- Returns {w, h} for grid size

    -- Calculate grid cell size
    local cellWidth = screenFrame.w / gridSize.w
    local cellHeight = screenFrame.h / gridSize.h

    -- Adjust for offsets and map coordinates to grid
    local gridX = math.floor((x - screenFrame.x) / cellWidth)
    local gridY = math.floor((y - screenFrame.y) / cellHeight)

    return {
        x = gridX,
        y = gridY
    }
end

function HammerDrag:getCanvasGridCell(canvas)
    -- Get the frame of the canvas
    local canvasFrame = canvas:frame()
    local screen = hs.mouse.getCurrentScreen()
    local screenFrame = screen:frame()

    local gridStepX = (screenFrame.w - (self.grid.MARGINX * (self.grid.GRIDWIDTH + 1))) / self.grid.GRIDWIDTH
    local gridStepY = screenFrame.h / self.grid.GRIDHEIGHT

    -- Calculate grid cell position and size
    local gridCell = {
        x = math.floor((canvasFrame.x - screenFrame.x) / gridStepX),
        y = math.floor((canvasFrame.y - screenFrame.y) / gridStepY),
        w = math.floor(canvasFrame.w / gridStepX),
        h = math.floor(canvasFrame.h / gridStepY)
    }

    return hs.geometry(gridCell.x, gridCell.y, gridCell.w, gridCell.h)
end

function HammerDrag:handleDrag()
    return function(event)
        if not self.dragging then
            return nil
        end

        -- Current mouse position
        local mouse = event:location()

        -- Calculate deltas
        local dx = mouse.x - self.originalMousePos.x
        local dy = mouse.y - self.originalMousePos.y

        local mouseOrigin = self.originalMousePos

        -- Original positions
        local current = self.originalWindowPos
        local currentSize = self.originalWindowSize

        if self:isMoving() then
            if self.useGrid then
                -- Get the original grid cell
                local windowCell = hs.geometry.copy(self.grid.get(self.targetWindow))
                if not windowCell then
                    print("Error: Could not retrieve grid cell for target window")
                    return nil
                end
                local canvasCell = hs.geometry.copy(self:getCanvasGridCell(self.windowCanvas))

                local mouseOriginCell = HammerDrag:getGridCellForCoordinates(mouseOrigin.x, mouseOrigin.y)
                local mouseCell = HammerDrag:getGridCellForCoordinates(mouse.x, mouse.y)

                local newCell = hs.geometry.copy(windowCell)

                -- TODO: Don't resize

                if self.preview == true then
                    newCell.x = canvasCell.x + (mouseCell.x - mouseOriginCell.x)
                    newCell.y = canvasCell.y + (mouseCell.y - mouseOriginCell.y)
                    -- local snappedFrame = self.grid.getCell(newCell, self.targetWindow:screen())
                    --
                    -- -- Update the canvas to match the snapped frame
                    -- self.windowCanvas:topLeft({
                    --     x = snappedFrame.x,
                    --     y = snappedFrame.y
                    -- })
                    -- self.windowCanvas:size({
                    --     w = snappedFrame.w,
                    --     h = snappedFrame.h
                    -- })

                    -- With Preview
                    local snappedFrame = self.grid.getCell(newCell, self.targetWindow:screen())

                    -- Apply screen margin adjustments
                    local xAdjust = 0
                    local yAdjust = 0
                    local wAdjust = 0
                    local hAdjust = 0

                    local screenFrame = self.targetWindow:screen():frame()

                    if snappedFrame.x == screenFrame.x then
                        xAdjust = self.grid.MARGINX / 2
                    end

                    if snappedFrame.y == screenFrame.y then
                        yAdjust = self.grid.MARGINY / 2
                    end

                    if snappedFrame.x + snappedFrame.w >= screenFrame.w then
                        wAdjust = self.grid.MARGINX / 2
                    end

                    if snappedFrame.y + snappedFrame.h >= screenFrame.h then
                        hAdjust = self.grid.MARGINY / 2
                    end

                    self.windowCanvas:topLeft({
                        x = snappedFrame.x + self.grid.MARGINX / 2 + xAdjust,
                        y = snappedFrame.y + self.grid.MARGINY / 2 + yAdjust
                    })
                    self.windowCanvas:size({
                        w = snappedFrame.w - self.grid.MARGINX - xAdjust - wAdjust,
                        h = snappedFrame.h - self.grid.MARGINX - yAdjust - hAdjust
                    })
                else
                    newCell.x = newCell.x + (mouseCell.x - mouseOriginCell.x)
                    newCell.y = newCell.y + (mouseCell.y - mouseOriginCell.y)
                    self.grid.set(self.targetWindow, newCell)
                end
                self.originalMousePos = mouse

            else
                local newX = current.x + dx
                local newY = current.y + dy

                if self.preview then
                    self.windowCanvas:topLeft({
                        x = newX,
                        y = newY
                    })
                else
                    local eventDx = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
                    local eventDy = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)

                    self.targetWindow:topLeft({
                        x = newX,
                        y = newY
                    })
                    self.targetWindow:move(hs.geometry.new(eventDx, eventDy))

                end
            end

            return true
        elseif self:isResizing() then
            if self.useGrid then
                -- Get the original grid cell of the window
                local originalGridCell = self.grid.get(self.targetWindow)
                if not originalGridCell then
                    print("Error: Could not retrieve grid cell for target window")
                    return nil
                end

                -- Get the grid cell for the original and current mouse positions
                local originalMouseCell = HammerDrag:getGridCellForCoordinates(self.originalMousePos.x,
                    self.originalMousePos.y)
                local currentMouseCell = HammerDrag:getGridCellForCoordinates(mouse.x, mouse.y)

                -- Copy the original window's grid cell to modify dimensions
                local newCell = originalGridCell

                -- Adjust the grid cell based on the resizing quadrant
                if self.startQuadrant == "topLeft" then
                    newCell.x = newCell.x + (currentMouseCell.x - originalMouseCell.x)
                    newCell.y = newCell.y + (currentMouseCell.y - originalMouseCell.y)
                    newCell.w = newCell.w - (currentMouseCell.x - originalMouseCell.x)
                    newCell.h = newCell.h - (currentMouseCell.y - originalMouseCell.y)

                elseif self.startQuadrant == "bottomLeft" then
                    newCell.x = newCell.x + (currentMouseCell.x - originalMouseCell.x)
                    newCell.w = newCell.w - (currentMouseCell.x - originalMouseCell.x)
                    newCell.h = newCell.h + (currentMouseCell.y - originalMouseCell.y)

                elseif self.startQuadrant == "topRight" then
                    newCell.y = newCell.y + (currentMouseCell.y - originalMouseCell.y)
                    newCell.w = newCell.w + (currentMouseCell.x - originalMouseCell.x)
                    newCell.h = newCell.h - (currentMouseCell.y - originalMouseCell.y)

                elseif self.startQuadrant == "bottomRight" then
                    newCell.w = newCell.w + (currentMouseCell.x - originalMouseCell.x)
                    newCell.h = newCell.h + (currentMouseCell.y - originalMouseCell.y)
                end

                -- Update the canvas for visual feedback
                if self.preview then
                    -- With Preview
                    local snappedFrame = self.grid.getCell(newCell, self.targetWindow:screen())

                    -- Apply screen margin adjustments
                    local xAdjust = 0
                    local yAdjust = 0
                    local wAdjust = 0
                    local hAdjust = 0

                    local screenFrame = self.targetWindow:screen():frame()

                    if snappedFrame.x == screenFrame.x then
                        xAdjust = self.grid.MARGINX / 2
                    end

                    if snappedFrame.y == screenFrame.y then
                        yAdjust = self.grid.MARGINY / 2
                    end

                    if snappedFrame.x + snappedFrame.w >= screenFrame.w then
                        wAdjust = self.grid.MARGINX / 2
                    end

                    if snappedFrame.y + snappedFrame.h >= screenFrame.h then
                        hAdjust = self.grid.MARGINY / 2
                    end

                    self.windowCanvas:topLeft({
                        x = snappedFrame.x + self.grid.MARGINX / 2 + xAdjust,
                        y = snappedFrame.y + self.grid.MARGINY / 2 + yAdjust
                    })
                    self.windowCanvas:size({
                        w = snappedFrame.w - self.grid.MARGINX - xAdjust - wAdjust,
                        h = snappedFrame.h - self.grid.MARGINX - yAdjust - hAdjust
                    })
                else
                    -- Without Preview
                    -- Apply the updated grid cell
                    self.grid.set(self.targetWindow, newCell)
                    -- Reset the mouse position to prevent cumulative deltas
                    self.originalMousePos = mouse
                end
            else
                -- Resize, without grid
                local newX, newY, newWidth, newHeight

                if self.startQuadrant == "topLeft" then
                    newX = current.x + dx
                    newY = current.y + dy
                    newWidth = currentSize.w - dx
                    newHeight = currentSize.h - dy

                elseif self.startQuadrant == "bottomLeft" then
                    newX = current.x + dx
                    newY = current.y
                    newWidth = currentSize.w - dx
                    newHeight = currentSize.h + dy

                elseif self.startQuadrant == "topRight" then
                    newX = current.x
                    newY = current.y + dy
                    newWidth = currentSize.w + dx
                    newHeight = currentSize.h - dy

                elseif self.startQuadrant == "bottomRight" then
                    newX = current.x
                    newY = current.y
                    newWidth = currentSize.w + dx
                    newHeight = currentSize.h + dy
                end

                if self.preview then
                    -- With Preview
                    self.windowCanvas:size({
                        w = newWidth,
                        h = newHeight
                    })
                    self.windowCanvas:topLeft({
                        x = newX,
                        y = newY
                    })
                else
                    -- No Preview
                    local moveTo = {
                        x = newX,
                        y = newY,
                        w = newWidth,
                        h = newHeight
                    }

                    -- Throttle resizes so they don't lag behind
                    if self.resizeThrottle and (hs.timer.secondsSinceEpoch() - self.resizeThrottle) < .05 then
                        return
                    end
                    self.resizeThrottle = hs.timer.secondsSinceEpoch()

                    self.targetWindow:setFrame(moveTo, 0)
                end
            end
        else
            return nil
        end
    end
end

function HammerDrag:handleCancel()
    return function()
        if not self.dragging then
            return
        end

        if self.preview then
            self:moveWindowToCanvas()
        end

        self:stop()
    end
end

function HammerDrag:resizeCanvasToWindow()
    local position = self.targetWindow:topLeft()
    local size = self.targetWindow:size()

    self.windowCanvas:topLeft({
        x = position.x,
        y = position.y
    })
    self.windowCanvas:size({
        w = size.w,
        h = size.h
    })
end

function HammerDrag:resizeWindowToCanvas()
    if not self.targetWindow then
        return
    end
    if not self.windowCanvas then
        return
    end

    local size = self.windowCanvas:size()
    self.targetWindow:setSize(size.w, size.h)

    local point = self.windowCanvas:topLeft()
end

function HammerDrag:moveWindowToCanvas()
    if not self.targetWindow then
        return
    end
    if not self.windowCanvas then
        return
    end

    local frame = self.windowCanvas:frame()
    local point = self.windowCanvas:topLeft()

    local moveTo = {
        x = point.x,
        y = point.y,
        w = frame.w,
        h = frame.h
    }

    self.targetWindow:move(hs.geometry.new(moveTo), nil, false, 0)
end

function HammerDrag:determineQuadrant(windowFrame, mousePos)
    local centerX = windowFrame.x + windowFrame.w / 2
    local centerY = windowFrame.y + windowFrame.h / 2

    if mousePos.x < centerX and mousePos.y < centerY then
        return "topLeft"
    elseif mousePos.x >= centerX and mousePos.y < centerY then
        return "topRight"
    elseif mousePos.x < centerX and mousePos.y >= centerY then
        return "bottomLeft"
    else
        return "bottomRight"
    end
end

function HammerDrag:handleClick()
    return function(event)
        if self.dragging then
            return true
        end

        local flags = event:getFlags()
        local eventType = event:getType()

        local isMoving = (eventType == self.moveStartMouseEvent and flags:containExactly(self.moveModifiers)) or
                             (eventType == self.moveGridStartMouseEvent and flags:containExactly(self.moveGridModifiers))

        local isResizing = (eventType == self.resizeStartMouseEvent and flags:containExactly(self.resizeModifiers)) or
                               (eventType == self.resizeGridStartMouseEvent and
                                   flags:containExactly(self.resizeGridModifiers))

        if isMoving or isResizing then
            local currentWindow = getWindowUnderMouse()

            if self.focusOnClick then
                currentWindow:focus()
            end

            if self.disabledApps[currentWindow:application():name()] then
                return nil
            end

            self.dragging = true
            self.targetWindow = currentWindow
            self.dragType = isMoving and dragTypes.move or dragTypes.resize
            self.useGrid = flags:containExactly(self.moveGridModifiers) or
                               flags:containExactly(self.resizeGridModifiers)

            -- Record original positions and size
            self.originalMousePos = hs.geometry.new(hs.mouse.absolutePosition())
            self.originalWindowPos = currentWindow:topLeft()
            self.originalWindowSize = currentWindow:size()

            if isMoving then
                self.dragType = dragTypes.move
            else
                self.dragType = dragTypes.resize
                -- Determine initial quadrant
                local windowFrame = currentWindow:frame()
                local mousePos = hs.mouse.absolutePosition()
                self.startQuadrant = self:determineQuadrant(windowFrame, mousePos)
            end

            if self.preview then
                self:resizeCanvasToWindow()
                self.windowCanvas:show()
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

return HammerDrag
