local ffi = require("ffi")
local SIZE = 0x2000
local START = 0x6000
local ram = {}

for offset = 0, SIZE - 1 do
    ram[START + offset] = offset % 256
end

local function oldSnapshot()
    local data = ""
    for offset = 0, SIZE - 1 do
        data = data .. string.char(ram[START + offset])
    end
    return data
end

local buffer = ffi.new("uint8_t[?]", SIZE)
local function newSnapshot()
    for offset = 0, SIZE - 1 do
        buffer[offset] = ram[START + offset]
    end
    return ffi.string(buffer, SIZE)
end

local function waitForWorkerMessage(worker, channel)
    local deadline = love.timer.getTime() + 5
    while love.timer.getTime() < deadline do
        local message = channel:pop()
        if message then return message end
        local threadError = worker:getError()
        if threadError then error(threadError) end
        love.timer.sleep(0.001)
    end
    error("timed out waiting for battery worker")
end

function love.load()
    collectgarbage("collect")
    local started = love.timer.getTime()
    local oldData = oldSnapshot()
    local oldTime = love.timer.getTime() - started

    collectgarbage("collect")
    started = love.timer.getTime()
    local newData = newSnapshot()
    local newTime = love.timer.getTime() - started

    assert(#newData == SIZE, "battery snapshot must remain exactly 8 KB")
    assert(newData == oldData, "optimized battery snapshot changed its bytes")
    print(string.format(
        "Battery snapshot: old %.3f ms, buffered %.3f ms",
        oldTime * 1000,
        newTime * 1000
    ))

    local requests = love.thread.getChannel("nes_battery_save_requests")
    local acknowledgements = love.thread.getChannel("nes_battery_save_acknowledgements")
    requests:clear()
    acknowledgements:clear()
    local workerSourceFile = assert(io.open("NES/Cartridge/batteryWriterThread.lua", "rb"))
    local workerSource = workerSourceFile:read("*all")
    workerSourceFile:close()
    local workerFileData = love.filesystem.newFileData(workerSource, "batteryWriterThread.lua")
    local worker = love.thread.newThread(workerFileData)
    local testPath = os.tmpname()
    worker:start()
    requests:push("save")
    requests:push(1)
    requests:push(testPath)
    requests:push(newData)

    local acknowledgement = waitForWorkerMessage(worker, acknowledgements)
    assert(acknowledgement:match("^1\t1\t"), "background battery write failed")
    local file = assert(io.open(testPath, "rb"))
    local writtenData = file:read("*all")
    file:close()
    assert(writtenData == newData, "background writer changed battery bytes")

    requests:push("quit")
    assert(waitForWorkerMessage(worker, acknowledgements):match("^-1\t1\t"), "battery worker did not stop")
    worker:wait()
    os.remove(testPath)
    print("Background battery writer tests passed")
    love.event.quit(0)
end
