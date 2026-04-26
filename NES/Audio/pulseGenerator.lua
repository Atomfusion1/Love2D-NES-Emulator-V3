print("Setting Up Pulse Sound Table This Might Take a Second")

--& NES Pulse Channel Notes to Create
local frequencyTable = {}
local A4 = 440.00
local noteStep = .4
local noteStart = 0.5
local noteEnd = 128

local index = 1

for n = noteStart, noteEnd, noteStep do
    local frequency = A4 * 2 ^ ((n - 69) / 12)

    frequencyTable[index] = frequency

    -- create your source here using frequency
    -- pulseSource[channel][index][dutyCycle] = love.audio.newSource(...)

    index = index + 1
end

-- Pulse Wave Settings
local sampleRate = 44100
local amplitude = .5
local duration = 0.5
local dutyCycles = {0.125, 0.25, 0.5, 0.75}  -- NES pulse duty modes: 12.5%, 25%, 50%, 75%
local pulseSource = {}

--# Generate Square Wave Table
local function generateSquareWave(sampleRate, frequency, amplitude, duration, dutyCycle)
    local samplePoints = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samplePoints, sampleRate, 16, 1)

    for i = 0, samplePoints - 1 do
        local time = i / sampleRate
        local phase = (time * frequency) % 1
        local value = phase < dutyCycle and amplitude or -amplitude
        soundData:setSample(i, value)
    end
    return soundData
end

--# Pulse Source for 2 Channels each having 4 Duty Cycles and 254 channels .5 midi 
for l = 1, 2 do
    pulseSource[l] = {}
    for i, note in ipairs(frequencyTable) do
        pulseSource[l][i] = {}
        for j = 0, #dutyCycles - 1 do
            local dutyCycle = dutyCycles[j + 1]
            local soundData = generateSquareWave(sampleRate, note, amplitude, duration, dutyCycle)
---@diagnostic disable-next-line: param-type-mismatch
            pulseSource[l][i][j] = love.audio.newSource(soundData, "static") -- True in love 11+
            pulseSource[l][i][j]:setLooping(true)
        end
    end
end

--# Find the closest frequency in the frequency table
function pulseSource.FindClosestFrequencyIndex(targetFrequency)
    local closestIndex = 1
    local closestDifference = math.abs(targetFrequency - frequencyTable[1])
    for i = 2, #frequencyTable do
        local difference = math.abs(targetFrequency - frequencyTable[i])
        if difference < closestDifference then
            closestIndex = i
            closestDifference = difference
        end
    end
    return closestIndex
end

pulseSource.NoteCount = #frequencyTable

return pulseSource