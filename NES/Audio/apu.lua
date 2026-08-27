local pulseSound = require("NES.Audio.apu_pulse")
local triangleSound = require("NES.Audio.apu_triangle")
local noiseSound = require("NES.Audio.apu_noise")
local dmcSound = require("NES.Audio.apu_dmc")
local lengthTable = require("NES.Audio.lengthcounter").LoadCounterTable()

VolumeMulti = 1 --& Global Value for Volume Multiplier
APUChannelMute = { false, false, false, false, false }
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
    dmcSound.Clock(cycles)
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
    if dmcSound.CheckIRQ() then return true end
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
    return bit.bor(value, dmcSound.StatusBits())
end

-- Register state needed even when audio output is disabled.  This is kept
-- separate from the Love audio generators so CPU-visible APU behavior does
-- not depend on the user's sound setting.
function apu.RegisterWrite(addr, data)
    if addr >= 0x4010 and addr <= 0x4013 then
        dmcSound.RegisterWrite(addr, data)
        return
    end
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
    if not APUChannelMute[1] then pulseSound.UpdatePulse(1, dt) end
    if not APUChannelMute[2] then pulseSound.UpdatePulse(2, dt) end
    if not APUChannelMute[3] then triangleSound.UpdateTriangle(dt) end
    if not APUChannelMute[4] then noiseSound.UpdateNoise(dt) end
end

function apu.SetChannelMuted(channel, muted)
    if channel < 1 or channel > 5 then return end
    APUChannelMute[channel] = muted and true or false
    if APUChannelMute[channel] then
        if channel == 1 or channel == 2 then pulseSound.StopPulseNote(channel)
        elseif channel == 3 then triangleSound.StopTriangle()
        elseif channel == 4 then noiseSound.StopNoise()
        else dmcSound.SetAudioEnabled(false) end
    elseif channel == 5 then
        dmcSound.SetAudioEnabled(UseSound ~= false)
    end
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
    dmcSound.StatusHandle(data)

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

function apu.SetAudioEnabled(enabled)
    dmcSound.SetAudioEnabled(enabled)
end

function apu.SetVolume(multiplier)
    dmcSound.SetVolume(multiplier)
end

function apu.SetDMCVolumeScale(scale)
    dmcSound.SetMixScale(scale)
end

function apu.GetDMCVolumeScale()
    return dmcSound.GetMixScale()
end

--# Handle APU Addresses
function apu.APUSound(addr, data)
    --@ Pulse 1
    if addr >= 0x4000 and addr <= 0x4003 and not APUChannelMute[1] then
        pulseSound.HandlePulse(1, addr, data)
    end
    --@ Pulse 2
    if addr >= 0x4004 and addr <= 0x4007 and not APUChannelMute[2] then
        pulseSound.HandlePulse(2, addr, data)
    end
    --@ Triangle
    if addr >= 0x4008 and addr <= 0x400B and not APUChannelMute[3] then
        triangleSound.HandleTriangle(addr, data)
    end
    --@ Noise
    if addr >= 0x400C and addr <= 0x400F and not APUChannelMute[4] then
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
    APUChannelMute = { false, false, false, false, false }
    dmcSound.Initialize()
    return apu
end

function apu.SetDMCReadCallback(callback)
    dmcSound.SetReadCallback(callback)
end

function apu.GetDMCOutput()
    return dmcSound.GetOutputLevel()
end

function apu.GetDMCDebugStatus()
    return dmcSound.GetDebugStatus()
end

return apu
