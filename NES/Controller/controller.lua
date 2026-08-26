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
function controller.CheckControllers()
    controller.Controller1State = 0x00
    controller.Controller2State = 0x00
    OverRideSpeed = false
    for key, value in pairs(keyIsDown) do
        if love.keyboard.isDown(key) then
            controller.Controller1State = value(controller.Controller1State)
        end
    end
    if joystick1 then
        for key, value in pairs(gamepadIsDown) do
            if joystick1:isGamepadDown(key) then
                controller.Controller1State = value(controller.Controller1State)
            end
        end
    end
    if joystick2 then
        for key, value in pairs(gamepadIsDown) do
            if joystick2:isGamepadDown(key) then
                controller.Controller2State = value(controller.Controller2State)
            end
        end
    end
    if joystick1 and joystick1:getGamepadAxis("triggerright") > .8 then
        OverRideSpeed = true
    end
end

return controller
