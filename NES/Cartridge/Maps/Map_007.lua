local cart = require("NES.Cartridge.Cartridge")
local loopy = require("NES.PPU.loopy")

local mapper = {}
mapper.version = 0x07
mapper.chrDirty = true

local band = bit.band

local PRGROMBank = 0
local PRG32KCount = 0

mapper.chrRAM = {}

for i = 0, 0x1FFF do
    mapper.chrRAM[i] = 0x00
end

function mapper.CPURead(addr)
    if addr >= 0x8000 and addr <= 0xFFFF then
        local bank = PRGROMBank % PRG32KCount
        return cart.ROM[bank * 0x8000 + band(addr, 0x7FFF) + 0x0010]
    end

    return 0x00
end

function mapper.CPUWrite(addr, data)
    if addr >= 0x8000 and addr <= 0xFFFF then
        PRGROMBank = band(data, 0x07) % PRG32KCount

        if band(data, 0x10) ~= 0 then
            cart.Mirror = 3 -- one-screen upper
        else
            cart.Mirror = 2 -- one-screen lower
        end

        mapper.chrDirty = true

        if loopy.scanLine < 240 then
            loopy:SearchPPUStatesInRangeAndReplace(
                loopy.scanLine - 1,
                loopy.scanLine + 1,
                require("NES.PPU.ppu").GetPPUState(loopy.scanLine)
            )
        end
    end
end

function mapper.PPURead(addr)
    if addr >= 0x0000 and addr <= 0x1FFF then
        return mapper.chrRAM[addr] or 0x00
    end

    return 0x00
end

function mapper.PPUWrite(addr, data)
    if addr >= 0x0000 and addr <= 0x1FFF then
        mapper.chrRAM[addr] = data
        return true
    end

    return false
end

function mapper.GetSaveState()
    return {
        PRGROMBank = PRGROMBank,
        PRG32KCount = PRG32KCount,
        chrRAM = mapper.chrRAM
    }
end

function mapper.LoadSaveState(state)
    if not state then return end
    PRGROMBank = state.PRGROMBank or PRGROMBank
    PRG32KCount = state.PRG32KCount or PRG32KCount
    mapper.chrRAM = state.chrRAM or mapper.chrRAM
    mapper.chrDirty = true
end

function mapper.INI()
    PRG32KCount = math.floor(cart.header[0x04] / 2)

    if PRG32KCount <= 0 then
        PRG32KCount = 1
    end

    -- Last 32 KB bank is safest for reset vector.
    PRGROMBank = PRG32KCount - 1

    for i = 0, 0x1FFF do
        mapper.chrRAM[i] = 0x00
    end
    mapper.chrDirty = true

    cart.Mirror = 2 -- one-screen lower default

    print("Mapper 7 initialized")
    print("PRG 32K banks:", PRG32KCount)
    print("Initial PRG bank:", PRGROMBank)
    print("Mirror:", cart.Mirror)
end

return mapper
