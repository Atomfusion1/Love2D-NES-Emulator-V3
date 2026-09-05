print("Setting Up Pulse Sound Table This Might Take a Second")

-- Pulse Wave Settings
local sampleRate = 44100
local amplitude = .5
local duration = 0.5
local dutyCycles = {0.125, 0.25, 0.5, 0.75}  -- NES pulse duty modes: 12.5%, 25%, 50%, 75%
local baseFrequency = 440.0
local cpuClock = 1789773
local pulseSource = {}
local sharedWaveData = {}

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

--# Generate one shared waveform for each duty cycle at a base frequency.
-- Pulse 1 and Pulse 2 use separate Source objects below so they can play
-- independently; pitch changes select the NES frequency without creating a
-- new waveform or source during gameplay.
for j = 0, #dutyCycles - 1 do
    sharedWaveData[j] = generateSquareWave(
        sampleRate, baseFrequency, amplitude, duration, dutyCycles[j + 1])
end

--# Pulse sources: 2 independent channels × 4 duty cycles.
for l = 1, 2 do
    pulseSource[l] = {}
    for j = 0, #dutyCycles - 1 do
        local soundData = sharedWaveData[j]
---@diagnostic disable-next-line: param-type-mismatch
        pulseSource[l][j] = love.audio.newSource(soundData, "static") -- True in love 11+
        pulseSource[l][j]:setLooping(true)
        pulseSource[l][j]:setPitch(1)
    end
end

function pulseSource.SetVoice(channel, timerValue, dutyCycle)
    if type(timerValue) ~= "number" or timerValue < 0 or timerValue > 0x7FF then
        return nil
    end
    local frequency = cpuClock / (16 * (timerValue + 1))
    local source = pulseSource[channel] and pulseSource[channel][dutyCycle]
    if not frequency or not source then return nil end
    -- NES pulse periods below 8 are muted. Keep the source at a safe pitch
    -- while muted instead of asking Love2D to reproduce an ultrasonic tone.
    source:setPitch(timerValue < 8 and 1 or frequency / baseFrequency)
    return source
end

return pulseSource
