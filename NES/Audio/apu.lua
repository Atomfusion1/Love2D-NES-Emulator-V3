local pulseSound = require("NES.Audio.apu_pulse")
local triangleSound = require("NES.Audio.apu_triangle")
local noiseSound = require("NES.Audio.apu_noise")
local lengthTable = require("NES.Audio.lengthcounter").LoadCounterTable()

VolumeMulti = 1 --& Global Value for Volume Multiplier
local apu = {}
local frameCycles = 0
local frameIRQ = false
local frameIRQInhibit = true
local frameFiveStep = false
local FRAME_PERIOD = 29830
local HALF_FRAME_PERIOD = 14915
local lengthCycles = 0
local channelEnable = 0
local channelLength = { 0, 0, 0, 0 }
local channelHalt = { false, false, false, false }

local function clockLengthCounters()
    for channel = 1, 4 do
        if not channelHalt[channel] and channelLength[channel] > 0 then
            channelLength[channel] = channelLength[channel] - 1
        end
    end
end

function apu.Clock(cycles)
    cycles = cycles or 0
    lengthCycles = lengthCycles + cycles
    while lengthCycles >= HALF_FRAME_PERIOD do
        lengthCycles = lengthCycles - HALF_FRAME_PERIOD
        clockLengthCounters()
    end

    if frameCycles > 0 then
        frameCycles = frameCycles - cycles
        if frameCycles <= 0 then
            if not frameFiveStep and not frameIRQInhibit then frameIRQ = true end
            frameCycles = FRAME_PERIOD
        end
    end
end

function apu.FrameCounterWrite(data)
    data = bit.band(data or 0, 0xFF)
    frameIRQInhibit = bit.band(data, 0x40) ~= 0
    frameFiveStep = bit.band(data, 0x80) ~= 0
    if frameIRQInhibit then frameIRQ = false end
    frameCycles = FRAME_PERIOD
    lengthCycles = 0
    if frameFiveStep then clockLengthCounters() end
end

function apu.CheckIRQ()
    return frameIRQ
end

function apu.StatusRead()
    local value = frameIRQ and 0x40 or 0
    for channel = 1, 4 do
        if channelLength[channel] > 0 then
            value = bit.bor(value, bit.lshift(1, channel - 1))
        end
    end
    frameIRQ = false
    return value
end

-- Register state needed even when audio output is disabled.  This is kept
-- separate from the Love audio generators so CPU-visible APU behavior does
-- not depend on the user's sound setting.
function apu.RegisterWrite(addr, data)
    local channel
    if addr >= 0x4000 and addr <= 0x4003 then channel = 1
    elseif addr >= 0x4004 and addr <= 0x4007 then channel = 2
    elseif addr >= 0x4008 and addr <= 0x400B then channel = 3
    elseif addr >= 0x400C and addr <= 0x400F then channel = 4
    end
    if not channel then return end

    local register = bit.band(addr, 0x03)
    if register == 0 then
        if channel == 3 then
            channelHalt[channel] = bit.band(data, 0x80) ~= 0
        else
            channelHalt[channel] = bit.band(data, 0x20) ~= 0
        end
    elseif register == 3 and bit.band(channelEnable, bit.lshift(1, channel - 1)) ~= 0 then
        channelLength[channel] = lengthTable[bit.rshift(data, 3)] or 0
    end
end

--# Handle APU Updates Per Frame
function apu.TimerCheck(dt)
    pulseSound.UpdatePulse(1, dt)
    pulseSound.UpdatePulse(2, dt)
    triangleSound.UpdateTriangle(dt)
    noiseSound.UpdateNoise(dt)
end

--# Sound Off
function SoundOff()
    pulseSound.StopPulseNote(1)
    pulseSound.StopPulseNote(2)
    triangleSound.StopTriangle()
    noiseSound.StopNoise()
end

--# Handle APU Status Handles
function apu.StatusHandle(addr, data)
    if addr ~= 0x4015 then return end

    channelEnable = bit.band(data, 0x0F)
    for channel = 1, 4 do
        if bit.band(channelEnable, bit.lshift(1, channel - 1)) == 0 then
            channelLength[channel] = 0
        end
    end

    if bit.band(data, 0x01) == 0 then
        pulseSound.StopPulseNote(1)
    end

    if bit.band(data, 0x02) == 0 then
        pulseSound.StopPulseNote(2)
    end

    if bit.band(data, 0x04) == 0 then
        triangleSound.StopTriangle()
    end

    if bit.band(data, 0x08) == 0 then
        noiseSound.StopNoise()
    end
end

--# Handle APU Addresses
function apu.APUSound(addr, data)
    --@ Pulse 1
    if addr >= 0x4000 and addr <= 0x4003 then
        pulseSound.HandlePulse(1, addr, data)
    end
    --@ Pulse 2
    if addr >= 0x4004 and addr <= 0x4007 then
        pulseSound.HandlePulse(2, addr, data)
    end
    --@ Triangle
    if addr >= 0x4008 and addr <= 0x400B then
        triangleSound.HandleTriangle(addr, data)
    end
    --@ Noise
    if addr >= 0x400C and addr <= 0x400F then
        noiseSound.HandleNoise(addr, data)
    end
end

--# Initialize Sound Sources
function apu.Initialize()
    SoundOff()
    frameCycles = 0
    frameIRQ = false
    frameIRQInhibit = true
    frameFiveStep = false
    lengthCycles = 0
    channelEnable = 0
    channelLength = { 0, 0, 0, 0 }
    channelHalt = { false, false, false, false }
    return apu
end

return apu
