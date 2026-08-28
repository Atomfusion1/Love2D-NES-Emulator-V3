local saveState = "NES.Emulator.UI.savestate"

--# Setup Joystick Controller
local joysticks = love.joystick.getJoysticks()
local joystick1 = joysticks[1]
local joystick2 = joysticks[2]
if joysticks[1] then print("Joystick1 Detected and Setup Successfully") end
if joysticks[2] then print("Joystick2 Detected and Setup Successfully") end

-- # Setup Controller
local controller             = {}
controller.turboLatch1 = 0
controller.turboLatch2 = 0
controller.Controller1State  = 0x00
controller.Controller2State  = 0x00
local Controller1FreezeState = 0x00
local Controller2FreezeState = 0x00
local controllerStrobe = false
local cheats = require("Emulator.cheats")
local rapidCounter = 0
local directionSequence = {
    [1] = { up = 0, down = 0, left = 0, right = 0, next = 0 },
    [2] = { up = 0, down = 0, left = 0, right = 0, next = 0 }
}
local previousDirections = {
    [1] = { up = false, down = false, left = false, right = false },
    [2] = { up = false, down = false, left = false, right = false }
}

local function latchControllers()
    Controller1FreezeState = controller.Controller1State
    Controller2FreezeState = controller.Controller2State
end

--# Read Out Controller Bit
function controller.ReadState(addr)
    if addr == 0x4016 then
        local state = controllerStrobe and controller.Controller1State or Controller1FreezeState
        local data = bit.band(state, 0x80) > 0 and 1 or 0
        if not controllerStrobe then
            -- After the eight buttons have shifted out, a standard NES
            -- controller keeps returning 1.
            Controller1FreezeState = bit.band(bit.bor(bit.lshift(Controller1FreezeState, 1), 1), 0xFF)
        end
        return data
    end
    if addr == 0x4017 then
        local state = controllerStrobe and controller.Controller2State or Controller2FreezeState
        local data = bit.band(state, 0x80) > 0 and 1 or 0
        if not controllerStrobe then
            Controller2FreezeState = bit.band(bit.bor(bit.lshift(Controller2FreezeState, 1), 1), 0xFF)
        end
        return data
    end
end

--# Set Controller State
function controller.GetState(addr, data)
    if addr == 0x4016 then
        local newStrobe = bit.band(data or 0, 0x01) ~= 0
        if newStrobe or controllerStrobe then
            -- While strobe is high the controller continuously reloads; the
            -- falling edge leaves the latest state in the shift registers.
            latchControllers()
        end
        controllerStrobe = newStrobe
    end
end

function controller.Reset()
    controller.turboLatch1 = 0
    controller.turboLatch2 = 0
    controller.Controller1State = 0x00
    controller.Controller2State = 0x00
    Controller1FreezeState = 0x00
    Controller2FreezeState = 0x00
    controllerStrobe = false
    rapidCounter = 0
    for index = 1, 2 do
        directionSequence[index] = { up = 0, down = 0, left = 0, right = 0, next = 0 }
        previousDirections[index] = { up = false, down = false, left = false, right = false }
    end
end

-- # Setup Key Pressed Values 
local keyIsDown = {
    ["up"] = function(controllers) return controllers + bit.lshift(1, 3) end,
    ["down"] = function(controllers) return controllers + bit.lshift(1, 2) end,
    ["left"] = function(controllers) return controllers + bit.lshift(1, 1) end,
    ["right"] = function(controllers) return controllers + bit.lshift(1, 0) end,
    ["z"] = function(controllers) return controllers + bit.lshift(1, 4) end,
    ["x"] = function(controllers) return controllers + bit.lshift(1, 5) end,
    ["s"] = function(controllers) return controllers + bit.lshift(1, 6) end,
    ["a"] = function(controllers) return controllers + bit.lshift(1, 7) end,
    ["v"] = function(controllers)
        OverRideSpeed = not OverRideSpeed
        return controllers
    end,
}

--# Setup Gamepad Pressed Values
local gamepadIsDown = {
    ["dpup"] = function(controllers) return controllers + bit.lshift(1, 3) end,
    ["dpdown"] = function(controllers) return controllers + bit.lshift(1, 2) end,
    ["dpleft"] = function(controllers) return controllers + bit.lshift(1, 1) end,
    ["dpright"] = function(controllers) return controllers + bit.lshift(1, 0) end,
    ["back"] = function(controllers)  return controllers + bit.lshift(1, 4) end,
    ["start"] = function(controllers) return controllers + bit.lshift(1, 5)end,
    ["x"] = function(controllers) return controllers + bit.lshift(1, 6)end,
    ["a"] = function(controllers) return controllers + bit.lshift(1, 7)end,
    ["y"] = function(controllers)
        controller.turboLatch1 = controller.turboLatch1 + 1
        if controller.turboLatch1 == 4 then controller.turboLatch1 = 0 end
        if controller.turboLatch1 == 0 then
            return controllers + bit.lshift(1, 6)
        end
        return controllers
    end,
    ["b"] = function(controllers)
        controller.turboLatch1 = controller.turboLatch1 + 1
        if controller.turboLatch1 == 4 then controller.turboLatch1 = 0 end
        if controller.turboLatch1 == 0 then
            return controllers + bit.lshift(1, 7)
        end
        return controllers
    end,
    ["rightshoulder"] = function(controllers)
        require("Emulator.savestate").Load("9")
        return controllers
    end,
    ["leftshoulder"] = function(controllers)
        require("Emulator.savestate").Save("3")
        return controllers
    end,
}

--# Check for Key Presses and Joystick Presses
local directionBits = {
    up = bit.lshift(1, 3),
    down = bit.lshift(1, 2),
    left = bit.lshift(1, 1),
    right = bit.lshift(1, 0)
}

local function resolveDirections(controllerIndex, keyboardSource, joystickSource)
    local current = {
        up = keyboardSource and love.keyboard.isDown("up") or false,
        down = keyboardSource and love.keyboard.isDown("down") or false,
        left = keyboardSource and love.keyboard.isDown("left") or false,
        right = keyboardSource and love.keyboard.isDown("right") or false
    }
    if joystickSource then
        current.up = current.up or joystickSource:isGamepadDown("dpup")
        current.down = current.down or joystickSource:isGamepadDown("dpdown")
        current.left = current.left or joystickSource:isGamepadDown("dpleft")
        current.right = current.right or joystickSource:isGamepadDown("dpright")
    end

    local sequence = directionSequence[controllerIndex]
    local previous = previousDirections[controllerIndex]
    for _, direction in ipairs({ "up", "down", "left", "right" }) do
        if current[direction] and not previous[direction] then
            sequence.next = sequence.next + 1
            sequence[direction] = sequence.next
        end
        previous[direction] = current[direction]
    end

    local result = 0
    if current.up and current.down then
        if sequence.up > sequence.down then current.down = false else current.up = false end
    end
    if current.left and current.right then
        if sequence.left > sequence.right then current.right = false else current.left = false end
    end
    for _, direction in ipairs({ "up", "down", "left", "right" }) do
        if current[direction] then result = bit.bor(result, directionBits[direction]) end
    end
    return result
end

function controller.CheckControllers()
    controller.Controller1State = 0x00
    controller.Controller2State = 0x00
    OverRideSpeed = false
    local rapidRate = cheats.GetRapidRate()
    rapidCounter = (rapidCounter + 1) % (rapidRate * 2)
    for key, value in pairs(keyIsDown) do
        if key ~= "up" and key ~= "down" and key ~= "left" and key ~= "right" and love.keyboard.isDown(key) then
            controller.Controller1State = value(controller.Controller1State)
        end
    end
    if joystick1 then
        for key, value in pairs(gamepadIsDown) do
            if key ~= "dpup" and key ~= "dpdown" and key ~= "dpleft" and key ~= "dpright" and joystick1:isGamepadDown(key) then
                controller.Controller1State = value(controller.Controller1State)
            end
        end
    end
    controller.Controller1State = bit.bor(controller.Controller1State, resolveDirections(1, true, joystick1))
    if joystick2 then
        for key, value in pairs(gamepadIsDown) do
            if key ~= "dpup" and key ~= "dpdown" and key ~= "dpleft" and key ~= "dpright" and joystick2:isGamepadDown(key) then
                controller.Controller2State = value(controller.Controller2State)
            end
        end
        controller.Controller2State = bit.bor(controller.Controller2State, resolveDirections(2, false, joystick2))
    else
        resolveDirections(2, false, nil)
    end
    -- A held A/B button is presented on alternating controller polls when
    -- rapid fire is enabled, producing one frame on and one frame off.
    if rapidCounter >= rapidRate then
        if cheats.IsRapidButtonEnabled("a") then
            controller.Controller1State = bit.band(controller.Controller1State, bit.bnot(bit.lshift(1, 7)))
        end
        if cheats.IsRapidButtonEnabled("b") then
            controller.Controller1State = bit.band(controller.Controller1State, bit.bnot(bit.lshift(1, 6)))
        end
    end
    if joystick1 and joystick1:getGamepadAxis("triggerright") > .8 then
        OverRideSpeed = true
    end
end

return controller
