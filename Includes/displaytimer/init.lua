-- Local Variables
local displayTimer = {}

local cycleTime = 0
local sleepTime = 0
local timerForFPS = 0
local desiredFrameTime = 1 / 61.0
local lastFrameTime = 0
-- conf.lua already enables VSync. Sleeping here as well can miss a refresh
-- boundary, producing ~57 FPS, uneven motion, and slow audio even when the
-- emulator workload is comfortably below 16.7 ms.
displayTimer.isDelaySkipped = true
local currentAverage = 0.0
local alpha = 0.01  -- This is the smoothing factor, usually a small value
local emulatedFPS = 0.0
local lastEmulatedSampleTime = nil
local maxFUT = 0.0
local maxFUT1 = 0.0
local maxFUTTime = 0
local metricsFont = nil
local frameSamples = {}
local componentSamples = { cpu = {}, cpuCore = {}, cpuInstruction = {}, cpuRead = {}, apu = {}, ppuEmu = {}, ppu = {}, ppuSetup = {}, ppuBackground = {}, ppuSprites = {}, ppuUpload = {}, ppuChrSnapshot = {}, ppuDebug = {} }
local pendingComponents = {}
local eventComponents = { ppuChrSnapshot = true, ppuDebug = true }
local counterSamples = { ppuChrCopies = {}, cpuInstructions = {}, cpuReads = {}, ppuUpdateCalls = {} }
local pendingCounters = {}
local memoryDeltaSamples = {}
local memoryDropSamples = {}
local frameNumberSamples = {}
local previousMemoryKB = nil
local frameSampleIndex = 0
local frameSampleCount = 0
local totalFrameSamples = 0
local FRAME_SAMPLE_LIMIT = 600
local love2dDrawCurrent = 0.0
local love2dDrawAverage = 0.0
local love2dDrawSamples = 0

--# Start the timer
function displayTimer.StartTimer()
    timerForFPS = love.timer.getTime()
end

local function UpdateRunningAverage(newValue)
    currentAverage = alpha * newValue + (1 - alpha) * currentAverage
end

local function UpdateFUT(newValue)
    if newValue > maxFUT then
        maxFUT = newValue
        maxFUTTime = 0
    elseif newValue > maxFUT1 then
        maxFUT1 = newValue
    end
    if maxFUTTime > 30 then
        maxFUT = maxFUT1
        maxFUT1 = 0
        maxFUTTime = 0
    end
    maxFUTTime = maxFUTTime + 1
end

--# Display performance metrics on the screen
function displayTimer.RecordEmulatedFrame(elapsed)
    local now = love.timer.getTime()
    cycleTime = math.max(0, elapsed or 0)
    UpdateRunningAverage(cycleTime)
    UpdateFUT(cycleTime)
    if lastEmulatedSampleTime then
        local interval = now - lastEmulatedSampleTime
        if interval > 0 then
            emulatedFPS = 1 / interval
        end
    end
    lastEmulatedSampleTime = now

    frameSampleIndex = frameSampleIndex % FRAME_SAMPLE_LIMIT + 1
    totalFrameSamples = totalFrameSamples + 1
    frameNumberSamples[frameSampleIndex] = totalFrameSamples
    frameSamples[frameSampleIndex] = cycleTime
    for name, samples in pairs(componentSamples) do
        if eventComponents[name] then
            samples[frameSampleIndex] = math.max(0, pendingComponents[name] or 0)
        elseif pendingComponents[name] then
            samples[frameSampleIndex] = math.max(0, pendingComponents[name])
        else
            samples[frameSampleIndex] = 0
        end
    end
    for name, samples in pairs(counterSamples) do
        samples[frameSampleIndex] = pendingCounters[name] or 0
    end
    local memoryKB = collectgarbage("count")
    local memoryDeltaKB = previousMemoryKB and (memoryKB - previousMemoryKB) or 0
    memoryDeltaSamples[frameSampleIndex] = memoryDeltaKB
    memoryDropSamples[frameSampleIndex] = math.max(0, -memoryDeltaKB)
    previousMemoryKB = memoryKB
    frameSampleCount = math.min(frameSampleCount + 1, FRAME_SAMPLE_LIMIT)

    pendingComponents = {}
    pendingCounters = {}
end

-- Love2D presentation runs on the display refresh, which can be a different
-- rate from the NES frame rate.  Keep it as a separate stream instead of
-- mixing it into the emulated-frame graph.
function displayTimer.RecordLove2DFrame(elapsed)
    love2dDrawCurrent = math.max(0, elapsed or 0)
    love2dDrawSamples = love2dDrawSamples + 1
    local alphaValue = 0.05
    love2dDrawAverage = love2dDrawAverage == 0
        and love2dDrawCurrent
        or alphaValue * love2dDrawCurrent + (1 - alphaValue) * love2dDrawAverage
end

function displayTimer.DisplayScreen()
    UpdateScreenValues()
    DrawPerformanceMetrics()
    DelayScreen()
    -- Presentation-only diagnostics belong to the display callback, not to
    -- the next emulated-frame sample.
    pendingComponents = {}
    pendingCounters = {}
    timerForFPS = love.timer.getTime()              -- This timer is the amount of time it takes to update and draw the next screen before delay for next frame
end

function displayTimer.ResetStats()
    cycleTime = 0
    currentAverage = 0
    maxFUT = 0
    maxFUT1 = 0
    maxFUTTime = 0
    emulatedFPS = 0.0
    lastEmulatedSampleTime = nil
    love2dDrawCurrent = 0.0
    love2dDrawAverage = 0.0
    love2dDrawSamples = 0
    frameSampleIndex = 0
    frameSampleCount = 0
    frameSamples = {}
    componentSamples = { cpu = {}, cpuCore = {}, cpuInstruction = {}, cpuRead = {}, apu = {}, ppuEmu = {}, ppu = {}, ppuSetup = {}, ppuBackground = {}, ppuSprites = {}, ppuUpload = {}, ppuChrSnapshot = {}, ppuDebug = {} }
    pendingComponents = {}
    counterSamples = { ppuChrCopies = {}, cpuInstructions = {}, cpuReads = {}, ppuUpdateCalls = {} }
    pendingCounters = {}
    memoryDeltaSamples = {}
    memoryDropSamples = {}
    frameNumberSamples = {}
    previousMemoryKB = nil
    totalFrameSamples = 0
end

function displayTimer.RecordComponent(name, elapsed)
    if not componentSamples[name] then componentSamples[name] = {} end
    pendingComponents[name] = (pendingComponents[name] or 0) + elapsed
end

function displayTimer.RecordCounter(name, amount)
    if not counterSamples[name] then counterSamples[name] = {} end
    pendingCounters[name] = (pendingCounters[name] or 0) + (amount or 1)
end

function displayTimer.RecordGauge(name, value)
    if not counterSamples[name] then counterSamples[name] = {} end
    pendingCounters[name] = math.max(pendingCounters[name] or 0, value or 0)
end

function displayTimer.GetStats()
    local samples = {}
    local total = 0
    for i = 1, frameSampleCount do
        local index = (frameSampleIndex - frameSampleCount + i - 1) % FRAME_SAMPLE_LIMIT + 1
        local value = frameSamples[index] or 0
        samples[i] = value
        total = total + value
    end
    local sorted = {}
    for i, value in ipairs(samples) do sorted[i] = value end
    table.sort(sorted, function(a, b) return a > b end)
    local lowIndex = math.max(1, math.ceil(#sorted * 0.01))
    local onePercentLow = sorted[lowIndex] or 0
    local components = {}
    for name, source in pairs(componentSamples) do
        components[name] = {}
        for i = 1, frameSampleCount do
            local index = (frameSampleIndex - frameSampleCount + i - 1) % FRAME_SAMPLE_LIMIT + 1
            components[name][i] = source[index] or 0
        end
    end
    local counters = {}
    for name, source in pairs(counterSamples) do
        counters[name] = {}
        for i = 1, frameSampleCount do
            local index = (frameSampleIndex - frameSampleCount + i - 1) % FRAME_SAMPLE_LIMIT + 1
            counters[name][i] = source[index] or 0
        end
    end
    local latestMemoryDeltaKB = 0
    local latestMemoryDropKB = 0
    local memoryDeltas = {}
    local memoryDrops = {}
    local frameNumbers = {}
    for i = 1, frameSampleCount do
        local index = (frameSampleIndex - frameSampleCount + i - 1) % FRAME_SAMPLE_LIMIT + 1
        memoryDeltas[i] = memoryDeltaSamples[index] or 0
        memoryDrops[i] = memoryDropSamples[index] or 0
        frameNumbers[i] = frameNumberSamples[index] or 0
    end
    if frameSampleCount > 0 then
        latestMemoryDeltaKB = memoryDeltaSamples[frameSampleIndex] or 0
        latestMemoryDropKB = memoryDropSamples[frameSampleIndex] or 0
    end
    return {
        current = math.max(0, cycleTime),
        average = frameSampleCount > 0 and total / frameSampleCount or 0,
        peak = maxFUT,
        onePercentLow = onePercentLow,
        fps = emulatedFPS,
        memoryMB = collectgarbage("count") / 1024,
        memoryDeltaKB = latestMemoryDeltaKB,
        memoryDropKB = latestMemoryDropKB,
        memoryDeltas = memoryDeltas,
        memoryDrops = memoryDrops,
        frameNumbers = frameNumbers,
        totalFrameSamples = totalFrameSamples,
        samples = samples,
        components = components,
        counters = counters,
        love2dDraw = {
            current = love2dDrawCurrent,
            average = love2dDrawAverage,
            samples = love2dDrawSamples
        }
    }
end

--# Update the screen values
function UpdateScreenValues()
    local elapsed = love.timer.getTime() - lastFrameTime
    sleepTime = desiredFrameTime - elapsed          -- Amount of time we need to sleep this frame, in seconds.
end

--# Delay the screen if needed
function DelayScreen()
    if sleepTime > 0 and not displayTimer.isDelaySkipped and not OverRideSpeed then
        love.timer.sleep(sleepTime)
    end
    lastFrameTime = love.timer.getTime()
end

--# Draw a metric on screen
local function DrawMetric(label, value, color, baseX, baseY)
    love.graphics.setColor(.4, 1, .4, 1)            -- White color for the label
    love.graphics.print(label, baseX, baseY)
    local textWidth = love.graphics.getFont():getWidth(label)
    love.graphics.setColor(unpack(color))           -- Color for the value
    love.graphics.print(value, baseX + textWidth, baseY)
end

    
--# Draw the performance metrics
function DrawPerformanceMetrics()
    local baseX = 20                -- setup x location on screen
    -- Keep the metrics visible in debug mode, but place them above the
    -- debugger status bar instead of over the toolbar.
    local baseY = EnableDebug and (love.graphics.getHeight() - 44) or 5
    if not metricsFont then
        metricsFont = love.graphics.newFont(12)
    end
    love.graphics.setFont(metricsFont)
    local colorValue = {1, 0.3, 0.3, 1} -- Color for metric values
    
    -- Frame Time metric
    DrawMetric("Frame Usage Time (us): ", string.format("%d", math.floor(cycleTime * 1000 * 1000)), colorValue, baseX, baseY)
    
    -- FPS metric
    baseX = baseX + 200
    DrawMetric("avg (us): ", string.format("%d", math.floor(currentAverage * 1000 * 1000)), colorValue, baseX, baseY)
    
    baseX = baseX + 100
    DrawMetric("Max (us): ", string.format("%d", math.floor(maxFUT * 1000 * 1000)), colorValue, baseX, baseY)
    
    -- Add frame time percentage
    baseX = baseX + 120
    local frameTimePercent = (maxFUT * 1000000.0 / 16666.0) * 100
    DrawMetric("Frame %: ", string.format("%.1f", frameTimePercent), colorValue, baseX, baseY)
    
    baseX = baseX + 100
    -- Memory usage metric
    DrawMetric("Memory (MB): ", string.format("%.2f", collectgarbage("count") / 1024), colorValue, baseX, baseY)
    
    baseX = baseX + 160
    DrawMetric("FPS: ", string.format("%.2f", love.timer.getFPS()), colorValue, baseX, baseY)
    
    -- Info text
    baseX = baseX + 200
    love.graphics.setColor(.3, .5, 1, 1)
    love.graphics.print("Press ` or esc x2", baseX, baseY)
    love.graphics.setColor(1, 1, 1, 1)
end


return displayTimer
