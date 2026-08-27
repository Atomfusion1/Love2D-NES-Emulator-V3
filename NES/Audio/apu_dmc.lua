-- Starter NES DMC channel.
-- This models the sample reader and output unit. DMA bus stealing and
-- OAM/DMC arbitration are intentionally deferred to the cycle scheduler.
local dmc = {}

-- Lightweight PCM output for the DMC. The CPU/DMC timing remains separate;
-- this queue simply turns the output unit's 7-bit level into audible samples.
local SAMPLE_RATE = 44100
local CPU_RATE = 1789773
local audioSource, audioQueue = nil, {}
local sampleAccumulator = 0
local audioEnabled = true
DMCVolumeScale = DMCVolumeScale or 0.025
local smoothedAudioSample = 0

local function ensureAudio()
    if audioSource or not love.audio or not love.audio.newQueueableSource then return end
    audioSource = love.audio.newQueueableSource(SAMPLE_RATE, 16, 1, 8)
    audioSource:setVolume((VolumeMulti or 1) * DMCVolumeScale)
    audioSource:play()
end

local function queueAudioSample(value)
    ensureAudio()
    if not audioSource then return end
    local target = (value / 127) * 2 - 1
    -- Ease DMC's 7-bit steps slightly before queuing PCM. This removes the
    -- harsh discontinuities that otherwise become audible clicks.
    smoothedAudioSample = smoothedAudioSample + (target - smoothedAudioSample) * 0.18
    audioQueue[#audioQueue + 1] = smoothedAudioSample
    if #audioQueue < 512 then return end
    local data = love.sound.newSoundData(#audioQueue, SAMPLE_RATE, 16, 1)
    for i, sample in ipairs(audioQueue) do data:setSample(i - 1, sample) end
    if audioSource:getFreeBufferCount() > 0 then audioSource:queue(data) end
    if not audioSource:isPlaying() then audioSource:play() end
    audioQueue = {}
end

local RATE_TABLE = { 428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 85, 72, 54 }
local readByte
local irqEnable, loop, rateIndex = false, false, 0
local timer, outputLevel = RATE_TABLE[1], 0
local sampleAddress, sampleLength = 0xC000, 1
local currentAddress, bytesRemaining = sampleAddress, 0
local sampleBuffer, sampleBufferEmpty = 0, true
local shiftRegister, bitsRemaining, silence = 0, 0, true
local irqFlag = false

local function fetchSampleByte()
    if not readByte or not sampleBufferEmpty or bytesRemaining == 0 then return end
    sampleBuffer = bit.band(readByte(currentAddress) or 0, 0xFF)
    sampleBufferEmpty = false
    currentAddress = currentAddress == 0xFFFF and 0x8000 or currentAddress + 1
    bytesRemaining = bytesRemaining - 1
end

local function restartSample()
    currentAddress = sampleAddress
    bytesRemaining = sampleLength
    fetchSampleByte()
end

local function clockOutputUnit()
    if bitsRemaining == 0 then
        if sampleBufferEmpty then fetchSampleByte() end
        if sampleBufferEmpty then
            silence = true
        else
            shiftRegister = sampleBuffer
            sampleBufferEmpty = true
            bitsRemaining = 8
            silence = false
        end
    end
    if not silence then
        if bit.band(shiftRegister, 1) ~= 0 then
            if outputLevel <= 125 then outputLevel = outputLevel + 2 end
        elseif outputLevel >= 2 then
            outputLevel = outputLevel - 2
        end
        shiftRegister = bit.rshift(shiftRegister, 1)
    end
    if bitsRemaining > 0 then bitsRemaining = bitsRemaining - 1 end
    if bitsRemaining == 0 then
        fetchSampleByte()
        if bytesRemaining == 0 and sampleBufferEmpty then
            if loop then restartSample()
            elseif irqEnable then irqFlag = true end
        end
    end
end

function dmc.SetReadCallback(callback) readByte = callback end

function dmc.Clock(cycles)
    if audioEnabled then
        sampleAccumulator = sampleAccumulator + (cycles or 0) * SAMPLE_RATE / CPU_RATE
        while sampleAccumulator >= 1 do
            queueAudioSample(outputLevel)
            sampleAccumulator = sampleAccumulator - 1
        end
    end
    for _ = 1, (cycles or 0) do
        timer = timer - 1
        if timer <= 0 then
            timer = RATE_TABLE[rateIndex + 1]
            clockOutputUnit()
        end
    end
end

function dmc.SetAudioEnabled(enabled)
    audioEnabled = enabled and true or false
    if not audioEnabled and audioSource then
        audioSource:stop()
        audioQueue = {}
    elseif audioEnabled then
        ensureAudio()
    end
end

function dmc.SetVolume(multiplier)
    if audioSource then audioSource:setVolume((multiplier or 1) * DMCVolumeScale) end
end

function dmc.SetMixScale(scale)
    DMCVolumeScale = math.max(0, math.min(1, scale or DMCVolumeScale))
    dmc.SetVolume(VolumeMulti or 1)
end

function dmc.GetMixScale() return DMCVolumeScale end

function dmc.RegisterWrite(addr, data)
    data = bit.band(data or 0, 0xFF)
    if addr == 0x4010 then
        loop = bit.band(data, 0x40) ~= 0
        irqEnable = bit.band(data, 0x80) ~= 0
        rateIndex = bit.band(data, 0x0F)
        timer = RATE_TABLE[rateIndex + 1]
        if not irqEnable then irqFlag = false end
    elseif addr == 0x4011 then
        outputLevel = bit.band(data, 0x7F)
    elseif addr == 0x4012 then
        sampleAddress = 0xC000 + bit.lshift(data, 6)
    elseif addr == 0x4013 then
        sampleLength = bit.lshift(data, 4) + 1
    end
end

function dmc.StatusHandle(data)
    if bit.band(data or 0, 0x10) == 0 then
        bytesRemaining = 0
        sampleBufferEmpty = true
    elseif bytesRemaining == 0 then
        restartSample()
    end
end

function dmc.StatusBits()
    local value = 0
    if bytesRemaining > 0 or not sampleBufferEmpty then value = bit.bor(value, 0x10) end
    if irqFlag then value = bit.bor(value, 0x80) end
    return value
end

function dmc.CheckIRQ() return irqFlag end
function dmc.GetOutputLevel() return outputLevel end

function dmc.GetDebugStatus()
    return {
        enabled = bytesRemaining > 0 or not sampleBufferEmpty,
        bytesRemaining = bytesRemaining,
        currentAddress = currentAddress,
        sampleAddress = sampleAddress,
        sampleLength = sampleLength,
        outputLevel = outputLevel,
        irq = irqFlag,
        queuedSamples = #audioQueue
    }
end

function dmc.Initialize()
    -- A cartridge reset must not leave queued PCM from the previous ROM.
    if audioSource then
        audioSource:stop()
        if audioSource.clearQueue then audioSource:clearQueue() end
    end
    irqEnable, loop, rateIndex = false, false, 0
    timer, outputLevel = RATE_TABLE[1], 0
    sampleAddress, sampleLength = 0xC000, 1
    currentAddress, bytesRemaining = sampleAddress, 0
    sampleBuffer, sampleBufferEmpty = 0, true
    shiftRegister, bitsRemaining, silence = 0, 0, true
    irqFlag = false
    sampleAccumulator = 0
    audioQueue = {}
    smoothedAudioSample = 0
    audioEnabled = true
end

return dmc
