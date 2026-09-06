-- Zapper trigger and photosensor are independent parallel input lines.
local lightGun = {}
local enabled, triggerDown = false, false
local aimX, aimY
local radius, threshold = 2, 0.75
local lightDots, brightness = 0, 0
local HOLD_DOTS = 20 * 341 -- finite sensor decay, including vblank
local calibrationPoints = {}
local sampleFrame, sampleLine, sampleX = 0, -1, -1
local frameNumber, traceFrames, shotNumber = 0, 0, 0
local reads, lightReads = 0, 0
local framePeak, frameSamples = 0, 0

function lightGun.Reset()
    aimX, aimY = nil, nil
    triggerDown, lightDots, brightness = false, 0, 0
    calibrationPoints = {}
    frameNumber, traceFrames, shotNumber = 0, 0, 0
    reads, lightReads, framePeak, frameSamples = 0, 0, 0, 0
    sampleFrame, sampleLine, sampleX = 0, -1, -1
end

function lightGun.SetEnabled(value)
    enabled = not not value
    lightGun.Reset()
end

function lightGun.IsEnabled() return enabled end

function lightGun.SetAim(x, y)
    if type(x) == "number" and type(y) == "number"
        and x >= 0 and x < 256 and y >= 0 and y < 240 then
        aimX, aimY = math.floor(x), math.floor(y)
    else
        aimX, aimY, lightDots, brightness = nil, nil, 0, 0
    end
end

function lightGun.GetAim() return aimX, aimY end

function lightGun.SetSensorConfig(size, level)
    if type(size) == "number" then radius = math.max(0, math.min(16, math.floor(size))) end
    if type(level) == "number" then threshold = math.max(0, math.min(1, level)) end
end

function lightGun.GetSensorConfig() return radius, threshold end

function lightGun.GetDebugInfo()
    return aimX, aimY, radius, brightness, threshold, lightDots > 0,
        nil, nil, 0, 0
end

function lightGun.GetSampleInfo()
    return sampleFrame, sampleLine, sampleX, lightDots, lightReads
end

function lightGun.RecordCalibrationPoint()
    if aimX == nil then return end
    if #calibrationPoints >= 4 then table.remove(calibrationPoints, 1) end
    calibrationPoints[#calibrationPoints + 1] = { x = aimX, y = aimY }
end

function lightGun.GetCalibrationPoints() return calibrationPoints end

function lightGun.BeginFrame()
    if traceFrames > 0 then
        print(string.format("Zapper #%d PPU frame %d: aim=(%s,%s) samples=%d peak=%.3f threshold=%.3f $4017 reads=%d lightReads=%d",
            shotNumber, frameNumber, tostring(aimX), tostring(aimY), frameSamples,
            framePeak, threshold, reads, lightReads))
        traceFrames = traceFrames - 1
    end
    frameNumber = frameNumber + 1
    reads, lightReads, framePeak, frameSamples = 0, 0, 0, 0
    -- No reset here: light decays in emulated dots, not frame boundaries.
end

-- BEFORE scroll transfers, evaluate current pixels crossed by the beam.
-- No completed-frame ImageData may drive this sensor.
function lightGun.AdvancePPU(scanline, oldDot, newDot, readPixel)
    if not enabled then return end
    lightDots = math.max(0, lightDots - (newDot - oldDot))
    if aimX == nil or scanline < 0 or scanline >= 240
        or math.abs(scanline - aimY) > radius then return end
    local first = math.max(0, aimX - radius, oldDot)
    local last = math.min(255, aimX + radius, newDot - 1)
    for x = first, last do
        local value = readPixel(x, scanline)
        brightness = value
        sampleFrame, sampleLine, sampleX = frameNumber, scanline, x
        frameSamples = frameSamples + 1
        framePeak = math.max(framePeak, value)
        if value >= threshold then
            lightDots = math.max(lightDots, HOLD_DOTS - (newDot - (x + 1)))
        end
    end
end

function lightGun.SetTrigger(down)
    down = enabled and not not down
    if down and not triggerDown then
        shotNumber = shotNumber + 1
        traceFrames = 8
    end
    triggerDown = down
end

function lightGun.MousePressed(button)
    if button == 1 then lightGun.SetTrigger(true) end
end

function lightGun.MouseReleased(button)
    if button == 1 then lightGun.SetTrigger(false) end
end

function lightGun.UpdateMouse(screenX, screenY, screenWidth, screenHeight)
    if not enabled then return end
    if not love.window.hasFocus() then lightGun.Reset(); return end
    local mouseX, mouseY = love.mouse.getPosition()
    if screenWidth > 0 and screenHeight > 0 then
        -- Each 4x4 displayed block maps to exactly one native pixel at 4x.
        lightGun.SetAim((mouseX - screenX) * 256 / screenWidth,
            (mouseY - screenY) * 240 / screenHeight)
    else
        lightGun.SetAim(nil, nil)
    end
    lightGun.SetTrigger(love.mouse.isDown(1))
end

function lightGun.ReadState()
    if not enabled then return 0 end
    reads = reads + 1
    if lightDots > 0 then lightReads = lightReads + 1 end
    -- D3 = 1 dark, 0 light. D4 = 1 trigger pressed.
    return (lightDots > 0 and 0 or 0x08) + (triggerDown and 0x10 or 0)
end

return lightGun
