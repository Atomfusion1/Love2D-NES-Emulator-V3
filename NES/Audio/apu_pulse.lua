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
        envelopeDivider = 0,
        envelopeDecay = 15,
        envelopeStart = false,
        pulseMuted = false,
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
        envelopeDivider = 0,
        envelopeDecay = 15,
        envelopeStart = false,
        pulseMuted = false,
        LCTimer = 0,
        LCTimerLength = 0,
        apuDebug = false,
    }
}

apu_Pulse.MainVolume = .001

local function calculateSweepTarget(channel, timer)
    local ch = channels[channel]
    local change = math.floor(timer / (2 ^ ch.sweepShift))
    if ch.sweepNegate then
        return timer - change - (channel == 1 and 1 or 0)
    end
    return timer + change
end

local function pulseOutputMuted(channel)
    local ch = channels[channel]
    -- The NES pulse output is silent for periods below 8. The sweep adder
    -- can also mute the channel when its target overflows, even when sweep
    -- updating is disabled.
    return ch.timerValue < 8 or calculateSweepTarget(channel, ch.timerValue) > 0x7FF
end

--# Stop Pulse Note
function apu_Pulse.StopPulseNote(channel)
    local ch = channels[channel]
    local duty = ch.playingDutyCycle
    local source = pulseSource[channel] and pulseSource[channel][duty]

    if source then
        source:setVolume(0)
        source:stop()
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
    local duty = ch.playingDutyCycle
    local source = pulseSource[channel] and pulseSource[channel][duty]
    if source then
        source:setVolume(setVolume)
    end
    
    -- require('jit').on() -- Step 3: Commented out JIT toggle (crash prevention workaround)
end 

local function currentOutputLevel(ch)
    if ch.constVolume == 1 then return ch.volume end
    return ch.envelopeDecay
end

function apu_Pulse.ApplyCurrentVolume(channel)
    local ch = channels[channel]
    ch.pulseMuted = pulseOutputMuted(channel)
    if ch.pulseMuted then
        local source = pulseSource[channel] and pulseSource[channel][ch.playingDutyCycle]
        if source then source:setVolume(0) end
        return
    end
    apu_Pulse.AdjustVolume(channel, currentOutputLevel(ch))
end

--# Clock the NES envelope once per quarter frame.
function apu_Pulse.ClockQuarterFrame(channel)
    local ch = channels[channel]
    if ch.envelopeStart then
        ch.envelopeStart = false
        ch.envelopeDecay = 15
        ch.envelopeDivider = ch.volume
    elseif ch.envelopeDivider == 0 then
        ch.envelopeDivider = ch.volume
        if ch.envelopeDecay > 0 then
            ch.envelopeDecay = ch.envelopeDecay - 1
        elseif ch.LCHalt == 1 then
            ch.envelopeDecay = 15
        end
    else
        ch.envelopeDivider = ch.envelopeDivider - 1
    end

    if ch.isNotePlaying then apu_Pulse.ApplyCurrentVolume(channel) end
end

--# Update the pulse sweep using the previous frame-time implementation.
function SweepUpdate(channel, dt)
    local ch = channels[channel]
    if not ch.sweepEnabled or ch.sweepShift == 0 then return end

    local sweepSpeedMultiplier = 70
    local sweepInterval = ch.sweepPeriod
    ch.sweepElapsedTime = ch.sweepElapsedTime + (dt * sweepSpeedMultiplier)

    if ch.sweepElapsedTime >= sweepInterval then
        ch.sweepElapsedTime = ch.sweepElapsedTime - sweepInterval

        local timer = ch.timerValue
        local newTimer = calculateSweepTarget(channel, timer)

        if newTimer > 0x7FF then
            -- Sweep overflow mutes the pulse but does not stop the channel's
            -- length/envelope state on the NES.
            apu_Pulse.ApplyCurrentVolume(channel)
        elseif newTimer < 8 then
            ch.timerValue = newTimer
            if ch.isNotePlaying then apu_Pulse.SetPulseFrequency(channel) end
        else
            ch.timerValue = newTimer
            if ch.isNotePlaying then apu_Pulse.SetPulseFrequency(channel) end
        end
    end
end

--# Update the exact timer frequency without restarting the source.
function apu_Pulse.SetPulseFrequency(channel)
    local ch = channels[channel]
    local source = pulseSource.SetVoice(channel, ch.timerValue, ch.dutyCycle)
    if ch.isNotePlaying then apu_Pulse.ApplyCurrentVolume(channel) end
    return source
end

--# Start a pulse. A high timer write ($4003/$4007) resets the sequencer.
function apu_Pulse.PlayPulseNote(channel, timerValue, volume, dutyCycle)
    -- require('jit').off() -- Step 3: Commented out JIT toggle (crash prevention workaround)
    local ch = channels[channel]

    --& Set volume to 0 and stop any playing notes
    apu_Pulse.StopPulseNote(channel)
    --& Set volume to level and play
    local source = pulseSource.SetVoice(channel, timerValue, dutyCycle)
    if not source then return end
    source:setVolume(volume * apu_Pulse.MainVolume * VolumeMulti)
    source:play()

    ch.isNotePlaying = true
    ch.playingNote = timerValue
    ch.playingDutyCycle = dutyCycle
    ch.elapsedTime = 0
    ch.LCTimer = 0
    ch.sweepElapsedTime = 0
    ch.envelopeStart = true
    ch.envelopeDecay = 15
    ch.envelopeDivider = ch.volume
    apu_Pulse.ApplyCurrentVolume(channel)
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

--# Update Pulse Channels
function apu_Pulse.UpdatePulse(channel, dt)
    local ch = channels[channel]
    if ch.isNotePlaying == false then return end
    LengthUpdate(channel, dt)
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
        apu_Pulse.ApplyCurrentVolume(channel)
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
            ch.sweepShift.." sweepCounter "..ch.sweepCounter)
        end
    elseif pulseOffset == 2 then
        --% Pulse Channel Timer Low
        ch.timerValue = bit.band(ch.timerValue, 0x700)
        ch.timerValue = bit.bor(ch.timerValue, data)
        --& A low timer write changes pitch but does not reset pulse phase.
        if ch.isNotePlaying then apu_Pulse.SetPulseFrequency(channel) end
        if ch.apuDebug then
            print("0x4002 "..channel.." data "..numToBinary(data).." TimerValue "..ch.timerValue)
        end
    elseif pulseOffset == 3 then
        --% Pulse Channel Timer High
        ch.timerValue = bit.band(ch.timerValue, 0xFF)
        ch.timerValue = bit.bor(ch.timerValue, bit.lshift(bit.band(data, 0x07), 8))
        ch.LCTimerLength = lengthTable[bit.rshift(data, 3)]
        --& A high timer write reloads the timer and resets the pulse phase.
        apu_Pulse.PlayPulseNote(channel, ch.timerValue, ch.volume, ch.dutyCycle)
        if ch.apuDebug then
            local frequency = 1789773 / (16 * (ch.timerValue + 1))
            print("0x4003 "..channel.." data "..numToBinary(data).. " TimerValue "..
            ch.timerValue.." frequency "..frequency.." timeoutLength "..ch.LCTimerLength)
        end
    end
end
return apu_Pulse
