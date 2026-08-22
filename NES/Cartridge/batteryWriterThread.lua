local requests = love.thread.getChannel("nes_battery_save_requests")
local acknowledgements = love.thread.getChannel("nes_battery_save_acknowledgements")
local timer = require("love.timer")

while true do
    local command = requests:demand()
    if command == "quit" then
        acknowledgements:push("-1\t1\t0\t")
        return
    end

    if command == "save" then
        local id = requests:demand()
        local path = requests:demand()
        local data = requests:demand()
        local started = timer.getTime()
        local ok = false
        local errorMessage = ""

        local file, openError = io.open(path, "wb")
        if file then
            local writeOk, writeError = file:write(data)
            local closeOk, closeError = file:close()
            ok = writeOk ~= nil and closeOk ~= nil
            errorMessage = writeError or closeError or ""
        else
            errorMessage = openError or "unable to open battery file"
        end

        local duration = timer.getTime() - started
        if not ok then
            print(string.format("Battery save #%d failed: %s", id, errorMessage))
        end

        acknowledgements:push(string.format(
            "%d\t%d\t%.9f\t%s",
            id,
            ok and 1 or 0,
            duration,
            errorMessage
        ))
    end
end
