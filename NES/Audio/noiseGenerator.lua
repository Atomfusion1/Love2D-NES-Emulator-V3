print("Setting Up Noise Table This Might Take a Second")

--# Generate LFSR-Based Noise (15-bit shift register, NES-style)
local function generateLFSRNoise(frequency, numSamples, sampleRate, amplitude, mode)
    local samples = {}
    local shiftReg = 0x4000  -- Initialize with a non-zero value (15-bit)
    local feedback
    
    -- Pre-calculate how many LFSR ticks per audio sample to match frequency
    -- The LFSR runs at a certain "clock" rate; we simplify by ticking once per sample
    local ticksPerSample = 1
    
    for i = 1, numSamples do
        -- Tick the LFSR for this sample
        for tick = 1, ticksPerSample do
            if mode == 0 then
                -- NES noise mode 0: XOR of bits 0 and 1
                feedback = bit.bxor(bit.band(shiftReg, 1), bit.band(bit.rshift(shiftReg, 1), 1))
            else
                -- NES noise mode 1: XOR of bits 0 and 6
                feedback = bit.bxor(bit.band(shiftReg, 1), bit.band(bit.rshift(shiftReg, 6), 1))
            end
            -- Shift right and insert feedback at bit 14
            shiftReg = bit.bor(bit.rshift(shiftReg, 1), bit.lshift(feedback, 14))
        end
        
        -- Output based on LSB
        samples[i] = (bit.band(shiftReg, 1) == 0) and amplitude or -amplitude
    end
    
    return samples
end

--# Convert Samples to SoundData
local function samplesToSoundData(samples, sampleRate)
    local data = love.sound.newSoundData(#samples, sampleRate, 16, 1)
    for i = 1, #samples do
        data:setSample(i - 1, samples[i])
    end
    return data
end

--# Create Noise Source
local function createNoiseSource(mode, numSamples, sampleRate, noiseAmplitude)
    local samples = generateLFSRNoise(0, numSamples, sampleRate, noiseAmplitude, mode)
    local soundData = samplesToSoundData(samples, sampleRate)
---@diagnostic disable-next-line: param-type-mismatch
    local noiseSource = love.audio.newSource(soundData, "static") -- True in Love 11.0 + 
    noiseSource:setLooping(true)
    return noiseSource
end

--* Noise settings. The NES period values are represented by the LFSR
--* clock rates; pitch selects one of these without creating another source.
local noiseRates = {
    447443, 223721, 111860, 55930, 27965, 18643, 13982,
    11186, 8860, 7046, 4709, 3523, 2348, 1761, 879, 440
}
local duration = .5 -- in seconds
local noiseAmplitude = 1
local baseSampleRate = 44100

--# Create one reusable source for each LFSR mode. Pitch controls the sixteen
--# NES noise periods, so no source is created when the period changes.
local noiseSources = {}
for l = 0, 1 do
    noiseSources[l] = createNoiseSource(
        l, baseSampleRate * duration, baseSampleRate, noiseAmplitude)
    noiseSources[l]:setLooping(true)
end

function noiseSources.SetVoice(mode, periodIndex)
    local rate = noiseRates[periodIndex]
    local source = noiseSources[mode]
    if not rate or not source then return nil end
    source:setPitch(rate / baseSampleRate)
    return source
end

return noiseSources
