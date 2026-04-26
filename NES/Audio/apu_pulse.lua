local lengthTable = require("NES.Audio.lengthcounter").LoadCounterTable()

local apu_Pulse = {}

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

--* Pulse Sound Sources
local pulseSource = require("NES.Audio.pulseGenerator")

--% Pulse Channel Objects (consolidated from parallel arrays)
local channels = {
    [1] = {
        playingNote = 127,
        playingDutyCycle = 0,
        isNotePlaying = false,
        timerValue = 0,
        dutyCycle = 0,
        LCHalt = 0,
        constVolume = 0,
        volume = 0,
        elapsedTime = 0,
        elapsedTimeLength = 0,
        sweepEnabled = false,
        sweepPeriod = 0,
        sweepNegate = false,
        sweepShift = 0,
        sweepCounter = 0,
        sweepElapsedTime = 0,
        LCTimer = 0,
        LCTimerLength = 0,
        apuDebug = false,
    },
    [2] = {
        playingNote = 127,
        playingDutyCycle = 0,
        isNotePlaying = false,
        timerValue = 0,
        dutyCycle = 0,
        LCHalt = 0,
        constVolume = 0,
        volume = 0,
        elapsedTime = 0,
        elapsedTimeLength = 0,
        sweepEnabled = false,
        sweepPeriod = 0,
        sweepNegate = false,
        sweepShift = 0,
        sweepCounter = 0,
        sweepElapsedTime = 0,
        LCTimer = 0,
        LCTimerLength = 0,
        apuDebug = false,
    }
}

apu_Pulse.MainVolume = .001
local maxNoteHeight = pulseSource.NoteCount -- Dynamically set to actual frequency table size

--# Stop Pulse Note
function apu_Pulse.StopPulseNote(channel)
    local ch = channels[channel]
    local note = ch.playingNote
    local duty = ch.playingDutyCycle

    if pulseSource[channel] and pulseSource[channel][note] and pulseSource[channel][note][duty] then
        pulseSource[channel][note][duty]:setVolume(0)
        pulseSource[channel][note][duty]:stop()
    end

    ch.isNotePlaying = false
end

--# Adjust Pulse Note Volume
function apu_Pulse.AdjustVolume(channel,volume)
    -- require('jit').off() -- Step 3: Commented out JIT toggle (crash prevention workaround)
    local setVolume = volume * apu_Pulse.MainVolume * VolumeMulti
    -- audio hack to stop love2d from crashing from sweep and Envelope Failed 
    if setVolume > 1 then setVolume = 1 end
    if setVolume < 0.001 then setVolume = 0 end
    
    local ch = channels[channel]
    local note = ch.playingNote
    local duty = ch.playingDutyCycle
    if pulseSource[channel] and pulseSource[channel][note] and pulseSource[channel][note][duty] then
        pulseSource[channel][note][duty]:setVolume(setVolume)
    end
    
    -- require('jit').on() -- Step 3: Commented out JIT toggle (crash prevention workaround)
end 

--# Play Pulse Note
function apu_Pulse.PlayPulseNote(channel, note, volume, dutyCycle)
    -- require('jit').off() -- Step 3: Commented out JIT toggle (crash prevention workaround)
    local ch = channels[channel]
    
    if ch.playingNote == note and ch.isNotePlaying then  return end
    --& Set volume to 0 and stop any playing notes
        apu_Pulse.StopPulseNote(channel)
    --& Set volume to level and play
    if note >= 1 and note <= maxNoteHeight then
        pulseSource[channel][note][dutyCycle]:setVolume(volume * apu_Pulse.MainVolume * VolumeMulti)
        pulseSource[channel][note][dutyCycle]:play()

        ch.isNotePlaying = true
        ch.playingNote = note
        ch.playingDutyCycle = dutyCycle
        ch.elapsedTime = 0
        ch.LCTimer = 0
        ch.sweepElapsedTime = 0
    end
    -- require('jit').on() -- Step 3: Commented out JIT toggle (crash prevention workaround)
end

--# Pulse Channel Length Timer Update
function LengthUpdate(channel, dt)
    -- require('jit').off() -- Step 3: Commented out JIT toggle (crash prevention workaround)
    local ch = channels[channel]
    if ch.LCHalt == 1 then --* Do Nothing Note will not stop        
    else
        ch.LCTimer = ch.LCTimer + (dt * 100)
        if ch.LCTimer > ch.LCTimerLength then
            apu_Pulse.StopPulseNote(channel)
        end
    end
    -- require('jit').on() -- Step 3: Commented out JIT toggle (crash prevention workaround)
end

--# Pulse Channel Volume Envelope Update
function EnvelopeUpdate(channel, dt)
    -- require('jit').off() -- Step 3: Commented out JIT toggle (crash prevention workaround)
    local ch = channels[channel]
    if ch.constVolume == 0 then
        ch.elapsedTime = ch.elapsedTime + dt*20
        if ch.elapsedTime >= (ch.elapsedTimeLength) then
            if ch.LCHalt == 1 then
                ch.elapsedTime = 0
            else --* one shot
                apu_Pulse.StopPulseNote(channel)
            end
        else
            --* Optional: Fade out the volume (linear fade out)
            local fadeOutFactor = (((ch.elapsedTimeLength) - ch.elapsedTime) / (ch.elapsedTimeLength))
            local newVolume = 0x09 * fadeOutFactor
            if newVolume > 0 then
                apu_Pulse.AdjustVolume(channel, newVolume)
            end
        end
    else
        --* Playing Sound at Constant Volume
    end
    -- require('jit').on() -- Step 3: Commented out JIT toggle (crash prevention workaround)
end

--# Pulse Channel Sweep Update 
--# Pulse Channel Sweep Update (Updated)
function SweepUpdate(channel, dt)
    -- require('jit').off() -- Step 3: Commented out JIT toggle (crash prevention workaround)
    local ch = channels[channel]
    if not ch.sweepEnabled or ch.sweepShift == 0 then
        -- require('jit').on() -- Step 3: Commented out JIT toggle (crash prevention workaround)
        return
    end
    -- Use a higher multiplier to speed up the sweep tick rate.
    local sweepSpeedMultiplier = 70  -- Increase this value for even faster updates.
    local sweepInterval = ch.sweepPeriod
    ch.sweepElapsedTime = ch.sweepElapsedTime + (dt * sweepSpeedMultiplier)

    if ch.sweepElapsedTime >= sweepInterval then
        ch.sweepElapsedTime = ch.sweepElapsedTime - sweepInterval

        local timer = ch.timerValue
        -- Compute the sweep change using a right-shift equivalent.
        local change = math.floor(timer / (2 ^ ch.sweepShift))
        local newTimer

        if ch.sweepNegate then
            -- For pulse channel 1, subtract an extra 1.
            newTimer = timer - change - (channel == 1 and 1 or 0)
        else
            newTimer = timer + change
        end

        -- If the new timer value is out of bounds, silence the channel.
        if newTimer < 8 or newTimer > 0x7FF then
            apu_Pulse.StopPulseNote(channel)
        else
            ch.timerValue = newTimer * .98
            local frequency = 1789773 / (16 * (newTimer + 1))
            local noteToPlay = pulseSource.FindClosestFrequencyIndex(frequency)
            apu_Pulse.PlayPulseNote(channel, noteToPlay, ch.volume, ch.dutyCycle)
        end
    end
    -- require('jit').on() -- Step 3: Commented out JIT toggle (crash prevention workaround)
end




--# Update Pulse Channels
function apu_Pulse.UpdatePulse(channel, dt)
    local ch = channels[channel]
    if ch.isNotePlaying == false then return end
    LengthUpdate(channel, dt)
    EnvelopeUpdate(channel,dt)
    SweepUpdate(channel, dt)
end

--# Handle Pulse Channels
function apu_Pulse.HandlePulse(channel, addr, data)
    local baseAddr = channel == 1 and 0x4000 or 0x4004
    local pulseOffset = addr - baseAddr
    local ch = channels[channel]
    
    if pulseOffset == 0 then
        --% Pulse Channel Duty Cycle, Length Counter and Volume Envelope
        ch.dutyCycle = bit.rshift(bit.band(data, 0xC0), 6)
        ch.LCHalt = bit.rshift(bit.band(data, 0x20), 5)
        ch.constVolume = bit.rshift(bit.band(data, 0x10), 4)
        ch.volume = bit.band(data, 0x0F)
        ch.elapsedTimeLength = ch.volume + 1
        apu_Pulse.AdjustVolume(channel, ch.volume) 
        if ch.apuDebug then 
            print("0x4000 "..channel.." data "..numToBinary(data).." dutyCycle "..ch.dutyCycle.." LCHalt "..
            ch.LCHalt.." constVolume1 "..ch.constVolume.." pulseVolume1 "..ch.volume)
        end
    elseif pulseOffset == 1 then
        --% Pulse Channel Sweep Enabled Period Negative and Counter
        ch.sweepEnabled = bit.band(data, 0x80) ~= 0
        ch.sweepPeriod = bit.rshift(bit.band(data, 0x70), 4)
        ch.sweepNegate = bit.band(data, 0x08) ~= 0
        ch.sweepShift = bit.band(data, 0x07)
        ch.sweepCounter = ch.sweepPeriod
        if ch.apuDebug then
            print("0x4001 "..channel.." data "..numToBinary(data).." sweepenabled ",
            ch.sweepEnabled," sweepperiod "..ch.sweepPeriod.." sweepNegative ",ch.sweepNegate," sweepshift "..
            ch.sweepShift.." swiftCounter "..ch.sweepCounter) 
        end
    elseif pulseOffset == 2 then
        --% Pulse Channel Timer Low
        ch.timerValue = bit.band(ch.timerValue, 0x700)
        ch.timerValue = bit.bor(ch.timerValue, data)
        --& Calculate frequency and Play Note
        local frequency = 1789773 / (16 * (ch.timerValue + 1))
        local noteToPlay = pulseSource.FindClosestFrequencyIndex(frequency)
        apu_Pulse.PlayPulseNote(channel, noteToPlay, ch.volume, ch.dutyCycle)
        if ch.apuDebug then
            print("0x4002 "..channel.." data "..numToBinary(data).." TimerValue "..ch.timerValue)
        end
    elseif pulseOffset == 3 then
        --% Pulse Channel Timer High
        ch.timerValue = bit.band(ch.timerValue, 0xFF)
        ch.timerValue = bit.bor(ch.timerValue, bit.lshift(bit.band(data, 0x07), 8))
        ch.LCTimerLength = lengthTable[bit.rshift(data, 3)]
        --& Calculate frequency and Play Note
        local frequency = 1789773 / (16 * (ch.timerValue + 1))
        local noteToPlay = pulseSource.FindClosestFrequencyIndex(frequency)
        apu_Pulse.PlayPulseNote(channel, noteToPlay, ch.volume, ch.dutyCycle)
        if ch.apuDebug then
            print("0x4003 "..channel.." data "..numToBinary(data).. " TimerValue "..
            ch.timerValue.." frequency "..frequency.." midi "..noteToPlay.." timeoutLength "..ch.LCTimerLength)
        end
    end
end
return apu_Pulse