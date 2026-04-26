

local apu_Noise = {}

--* Debug number to binary
local function numToBinary(num, bitLength)
    bitLength = bitLength or 8
    local binary = ""
    while num > 0 do
        local remainder = num % 2
        binary = tostring(remainder) .. binary
        num = math.floor(num / 2)
    end
    while #binary < bitLength do
        binary = "0" .. binary
    end
    return binary
end

--* Noise Sound Sources
local noiseSources = require("NES.Audio.noiseGenerator")

--% Noise Channel Object (Step 5 refactor: consolidated from separate fields)
local channel = {
    playingNote = 0x05,
    timerValue = 5,
    infPlay = 0,
    constVolume = 0,
    volume = 1,
    noiseMode = 0,
    elapsedTime = 0,
    timeoutLength = 0,
    playingNoiseMode = 0,
    apuDebug = false,
}

apu_Noise.MainVolume = .025

--# Stop the noise channel
function apu_Noise.StopNoise()
    local mode = channel.playingNoiseMode
    local note = channel.playingNote
    if noiseSources and noiseSources[mode] and noiseSources[mode][note] then
        noiseSources[mode][note]:setVolume(0)
        noiseSources[mode][note]:stop()
    end
end

--# Adjust the volume of the noise channel
function apu_Noise.AdjustVolume(volume)
    local mode = channel.playingNoiseMode
    local note = channel.playingNote
    if noiseSources and noiseSources[mode] and noiseSources[mode][note] then
        noiseSources[mode][note]:setVolume(volume * VolumeMulti * apu_Noise.MainVolume)
    end
end

--# Play the noise channel
function apu_Noise.PlayNoise(note, volume)
    if channel.apuDebug then print("PLAYING NOTE:"..note.." volume "..volume * apu_Noise.MainVolume) end
    channel.elapsedTime = 0
    noiseSources[channel.playingNoiseMode][channel.playingNote]:setVolume(0)
    noiseSources[channel.playingNoiseMode][channel.playingNote]:stop()
    --* Calculate the playback rate based on the timer value and CPU clock
    noiseSources[channel.noiseMode][note]:setVolume(volume * VolumeMulti * apu_Noise.MainVolume)
    noiseSources[channel.noiseMode][note]:play()
    channel.playingNote = note
    channel.playingNoiseMode = channel.noiseMode
end

--# Update the noise channel
function apu_Noise.UpdateNoise(dt)
    if channel.infPlay == 0 then
        channel.elapsedTime = channel.elapsedTime + dt*200
        if channel.elapsedTime >= channel.timeoutLength then
            --* Stop the noise
            apu_Noise.StopNoise()
        elseif channel.constVolume == 0 then
            --* Optional: Fade out the volume (linear fade out)
            local fadeOutFactor = 1 - (channel.elapsedTime / channel.timeoutLength)
            local newVolume = channel.volume * fadeOutFactor
            apu_Noise.AdjustVolume(newVolume)
        end
    end
end

--# Handle the noise channel
--TODO Initial Noise Setup Will Need more work to get it to work properly
function apu_Noise.HandleNoise(addr, data)
    local baseAddr = 0x400C
    local noiseOffset = addr - baseAddr
    if noiseOffset == 0 then --400C
        --% Noise Channel Length Control and Volume Control
        channel.infPlay = bit.rshift(bit.band(data, 0x20), 5)
        channel.constVolume = bit.rshift(bit.band(data, 0x10), 4)
        channel.volume = bit.band(data, 0x0F) / 0x0F0
        if channel.volume > 0 and channel.volume < .5 then channel.volume = channel.volume * 20 end
        channel.volume = channel.volume * VolumeMulti * apu_Noise.MainVolume
        apu_Noise.AdjustVolume(channel.volume)
        if channel.apuDebug then
            print("0x400C data "..numToBinary(data).." infPlay "..channel.infPlay.." constVolume "..channel.constVolume.." volume "..channel.volume)
        end
    elseif noiseOffset == 1 then -- 400D
        --% Noise channel Unused
    elseif noiseOffset == 2 then -- 400E
        --% Noise timer Period and Mode
        channel.timerValue = bit.band(data, 0x0F)+1
        channel.noiseMode = bit.rshift(bit.band(data, 0x80), 7)
        if channel.apuDebug then
            print("0x400E data "..numToBinary(data).." TimerValue "..channel.timerValue.." noiseMode "..channel.noiseMode)
        end
    elseif noiseOffset == 3 then -- 400F
        ---% Length Counter Load and Envelope Restart
        channel.timeoutLength = bit.rshift(bit.band(data, 0xF8), 3)
        if channel.volume == 0 then channel.volume = .3 * VolumeMulti * apu_Noise.MainVolume end
        apu_Noise.PlayNoise(channel.timerValue, channel.volume)
        if channel.apuDebug then
            print("0x400F data "..numToBinary(data).." timeoutLength "..channel.timeoutLength.." Noise "..channel.timerValue)
        end
    end
end

return apu_Noise
