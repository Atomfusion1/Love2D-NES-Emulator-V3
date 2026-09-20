package.path = package.path .. ";./?.lua;./?/init.lua"

local cart = require("NES.Cartridge.Cartridge")
local mapper = require("NES.Cartridge.Maps.Map_218")

local function check(condition, message)
    if not condition then error(message) end
end

function love.load()
    cart.header[0x04] = 1
    for i = 0, 0x3FFF do cart.ROM[i + 0x10] = bit.band(i, 0xFF) end

    local expectedMirror = {[0x00] = 0, [0x01] = 1, [0x08] = 3, [0x09] = 2}
    local addressPair = {[0x00] = {0x0000, 0x0800}, [0x01] = {0x0000, 0x0400},
        [0x08] = {0x0000, 0x2000}, [0x09] = {0x0000, 0x1000}}

    for flags, mirror in pairs(expectedMirror) do
        cart.header[0x06] = flags
        mapper.INI()
        check(cart.Mirror == mirror, string.format("flags %02X mirror", flags))
        local pair = addressPair[flags]
        mapper.PPUWrite(pair[1], 0x5A)
        check(mapper.PPURead(pair[1]) == 0x5A, string.format("flags %02X first CIRAM bank", flags))
        mapper.PPUWrite(pair[2], 0xA5)
        check(mapper.PPURead(pair[2]) == 0xA5, string.format("flags %02X second CIRAM bank", flags))
        check(mapper.PPURead(pair[1]) == 0x5A, string.format("flags %02X banks are distinct", flags))
    end

    cart.header[0x06] = 0x00
    mapper.INI()
    check(mapper.CPURead(0x8000) == mapper.CPURead(0xC000), "16 KiB PRG mirrors")
    print("Mapper 218 tests passed")
    love.event.quit(0)
end
