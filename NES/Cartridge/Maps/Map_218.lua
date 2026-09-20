-- iNES Mapper 218: single-chip PRG-ROM board using the NES's 2 KiB CIRAM
-- as both nametable RAM and CHR-RAM.  CIRAM A10 is wired to one of PPU A10
-- through A13, selected by Flags 6 bits 0 and 3.

local cart = require("NES.Cartridge.Cartridge")
local nameTable = require("NES.PPU.ppunametable")

local mapper = {}
mapper.version = 0xDA
mapper.chrDirty = true

local band = bit.band
local ciramAddressBit = 10

local function ciramIndex(addr)
    local offset = band(addr, 0x03FF)
    if band(addr, 2 ^ ciramAddressBit) ~= 0 then
        offset = offset + 0x0400
    end
    return offset
end

function mapper.CPURead(addr)
    if addr < 0x8000 or addr > 0xFFFF then
        return 0x00
    end

    local prgSize = (cart.header[0x04] or 0) * 0x4000
    if prgSize <= 0 then
        return 0x00
    end

    local offset = addr - 0x8000
    if prgSize == 0x4000 then
        offset = band(offset, 0x3FFF)
    else
        offset = offset % prgSize
    end
    return cart.ROM[offset + 0x0010] or 0x00
end

-- Mapper 218 has no registers.  The header permanently selects its wiring.
function mapper.CPUWrite(addr, value)
end

function mapper.PPURead(addr)
    if addr < 0x0000 or addr > 0x3EFF then
        return 0x00
    end
    local physical = ciramIndex(addr)
    local tableIndex = physical >= 0x0400 and 1 or 0
    return nameTable.tblName[tableIndex][band(physical, 0x03FF)] or 0x00
end

function mapper.PPUWrite(addr, value)
    if addr < 0x0000 or addr > 0x3EFF then
        return false
    end
    local physical = ciramIndex(addr)
    local tableIndex = physical >= 0x0400 and 1 or 0
    nameTable.tblName[tableIndex][band(physical, 0x03FF)] = band(value or 0, 0xFF)
    mapper.chrDirty = true
    return true
end

function mapper.GetSaveState()
    -- CIRAM is already included in the PPU nametable snapshot.
    return {}
end

function mapper.LoadSaveState(state)
    mapper.chrDirty = true
end

function mapper.INI()
    local flags6 = cart.header[0x06] or 0
    local wiring = band(flags6, 0x09)

    -- $A1: A10, $A0: A11, $A8: A13, $A9: A12.
    if wiring == 0x01 then
        ciramAddressBit = 10
    elseif wiring == 0x00 then
        ciramAddressBit = 11
    elseif wiring == 0x08 then
        ciramAddressBit = 13
    else
        ciramAddressBit = 12
    end

    -- For A10/A11, the normal vertical and horizontal mirror modes are
    -- represented by the renderer.  A12/A13 use one-screen lower/upper for
    -- the visible $2000-$2FFF nametable range.
    if ciramAddressBit == 10 then
        cart.Mirror = 1
    elseif ciramAddressBit == 11 then
        cart.Mirror = 0
    elseif ciramAddressBit == 12 then
        cart.Mirror = 2
    else
        cart.Mirror = 3
    end

    mapper.chrDirty = true
end

return mapper
