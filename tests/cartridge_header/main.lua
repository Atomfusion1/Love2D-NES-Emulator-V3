package.path = package.path .. ";./?.lua;./?/init.lua"

local cartridge = require("NES.Cartridge.Cartridge")

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local function makeHeader(mapperId, flags)
    local flags6 = bit.bor(bit.lshift(bit.band(mapperId, 0x0F), 4), flags or 0)
    local flags7 = bit.band(mapperId, 0xF0)
    return "NES\26" .. string.char(1, 1, flags6, flags7) .. string.rep("\0", 8)
end

function love.load()
    local mapper5 = assert(cartridge.ParseHeader(makeHeader(5, 0x03)))
    assertEqual(mapper5.mapper, 5, "unsupported mapper ID is parsed")
    assertEqual(mapper5.mirror, 1, "mirror flag")
    assertEqual(mapper5.battery, true, "battery flag")

    local mapper206 = assert(cartridge.ParseHeader(makeHeader(206)))
    assertEqual(mapper206.mapper, 206, "high and low mapper nibbles")

    local shortHeader, shortError = cartridge.ParseHeader("NES\26")
    assertEqual(shortHeader, nil, "truncated header rejected")
    assert(shortError and #shortError > 0, "truncated header returns an explanation")

    local invalidHeader, invalidError = cartridge.ParseHeader(string.rep("\0", 16))
    assertEqual(invalidHeader, nil, "invalid magic rejected")
    assert(invalidError and #invalidError > 0, "invalid magic returns an explanation")

    print("Cartridge header preflight tests passed")
    love.event.quit(0)
end
