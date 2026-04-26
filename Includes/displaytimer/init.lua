-- Local Variables
local displayTimer = {}

local cycleTime = 0
local sleepTime = 0
local timerForFPS = 0
local desiredFrameTime = 1 / 61.0
local lastFrameTime = 0
displayTimer.isDelaySkipped = false
local currentAverage = 0.0
local alpha = 0.01  -- This is the smoothing factor, usually a small value
local maxFUT = 0.0
local maxFUT1 = 0.0
local maxFUTTime = 0

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
function displayTimer.DisplayScreen()
    cycleTime = love.timer.getTime() - timerForFPS  -- This timer is the amount of time it takes to update and draw the next screen
    UpdateRunningAverage(cycleTime)
    UpdateFUT(cycleTime)
    UpdateScreenValues()
    DrawPerformanceMetrics()
    DelayScreen()
    timerForFPS = love.timer.getTime()              -- This timer is the amount of time it takes to update and draw the next screen before delay for next frame
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
    local baseY = 5                 -- setup height on screen
    love.graphics.setFont(love.graphics.newFont(12))
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
