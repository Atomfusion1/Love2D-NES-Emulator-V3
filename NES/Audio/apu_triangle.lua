local lengthTable = require("NES.Audio.lengthcounter").LoadCounterTable()

local apu_Triangle = {}

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

--* Triangle Sound Sources
local triangleSource = require("NES.Audio.triangleGenerator")

--% Triangle Channel Object (Step 5 refactor: consolidated from separate fields)
local channel = {
    playingNote = 69,
    playingDutyCycle = 0,
    timerValue = 0,
    dutyCycle = 0,
    infPlay = 0,
    constVolume = 0,
    volume = .5,
    elapsedTime = 0,
    timeoutLength = 0,
    linearCounter = 0,
    linearCounterTimer = 0,
    isNotePlaying = false,
    apuDebug = false,
}

apu_Triangle.MainVolume = .12

--# Stop the triangle channel
function apu_Triangle.StopTriangle()
    local note = channel.playingNote
    if triangleSource and triangleSource[note] then
        triangleSource[note]:stop()
    end
    channel.isNotePlaying = false
end

--# Adjust the volume of the triangle channel
function apu_Triangle.AdjustVolume(volume)
    local setVolume = volume * apu_Triangle.MainVolume * VolumeMulti
    local note = channel.playingNote
    if triangleSource and triangleSource[note] then
        triangleSource[note]:setVolume(setVolume)
    end
end

--# Play the triangle channel
function apu_Triangle.PlayTriangle(note, volume)
    if note < 4 and channel.isNotePlaying then apu_Triangle.StopTriangle() return end
    channel.elapsedTime = 0
    if channel.playingNote ~= note or channel.isNotePlaying == false then
        apu_Triangle.StopTriangle()
        if note > 300 then return end
        channel.playingNote = note
        channel.isNotePlaying = true
        apu_Triangle.AdjustVolume(apu_Triangle.MainVolume)
        triangleSource[note]:play()
    end
end

--# Update the triangle channel
function apu_Triangle.UpdateTriangle(dt)
    if channel.infPlay == 0 then
        channel.elapsedTime = channel.elapsedTime + dt*80
        if channel.elapsedTime >= channel.timeoutLength then
            apu_Triangle.StopTriangle()
        end
    end

    -- Time-scaled linear counter (decoupled from frame rate)
    channel.linearCounterTimer = channel.linearCounterTimer + dt * 60

    while channel.linearCounterTimer >= 1 do
        channel.linearCounterTimer = channel.linearCounterTimer - 1

        if channel.linearCounter > 0 then
            channel.linearCounter = channel.linearCounter - 1
        else
            apu_Triangle.StopTriangle()
            break
        end
    end
end

--# Handle the triangle channel
function apu_Triangle.HandleTriangle(addr, data)
    local baseAddr = 0x4008
    local triangleOffset = addr - baseAddr
    if triangleOffset == 0 then
        --% Set Linear Counter and Infinite Play
        channel.linearCounter = bit.band(data, 0x7F) --* Update the linear counter
        channel.infPlay = bit.rshift(bit.band(data, 0x80), 7)
        if channel.apuDebug then
            print("0x4008 data "..numToBinary(data).." linearCounter "..channel.linearCounter.." infPlay "..channel.infPlay.." constVolume "..channel.constVolume.." volume "..channel.volume)
        end
    elseif triangleOffset == 1 then
        --% Triangle channel unused
    elseif triangleOffset == 2 then
        --% Change Note Value Low
        channel.timerValue = bit.band(channel.timerValue, 0x700)
        channel.timerValue = bit.bor(channel.timerValue, data)
        --& Calculate frequency and Play Note
        local frequency = 1789773 / (32 * (channel.timerValue + 1))
        local noteToPlay = triangleSource.FindClosestFrequencyIndex(frequency)
        apu_Triangle.PlayTriangle(noteToPlay, channel.volume)
        if channel.apuDebug then
            print("0x400A data "..numToBinary(data).." TimerValue "..channel.timerValue)
        end
    elseif triangleOffset == 3 then
        --% Change Note Value High
        channel.timerValue = bit.band(channel.timerValue, 0xFF)
        channel.timerValue = bit.bor(channel.timerValue, bit.lshift(bit.band(data, 0x07), 8))
        channel.timeoutLength = lengthTable[bit.rshift(data, 3)]
        --& Calculate frequency and Play Note
        local frequency = 1789773 / (32 * (channel.timerValue + 1))
        local noteToPlay = triangleSource.FindClosestFrequencyIndex(frequency)
        apu_Triangle.PlayTriangle(noteToPlay, channel.volume)
        if channel.apuDebug then
            print("0x400B data "..numToBinary(data).." TimerValue "..channel.timerValue.." frequency "..frequency.." midi "..noteToPlay.." timeoutLength "..channel.timeoutLength)
        end
    end
end

return apu_Triangle