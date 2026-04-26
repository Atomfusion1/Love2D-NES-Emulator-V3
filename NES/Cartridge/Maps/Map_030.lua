local cart = require("NES.Cartridge.Cartridge")
local loopy = require("NES.PPU.loopy")

local mapper = {}
mapper.version = 0x1E  -- Mapper 30 (UNROM 512)
mapper.chrDirty = true

local band, rshift = bit.band, bit.rshift

-- UNROM 512 / Mapper 30
-- CPU $8000-$BFFF: 16KB switchable PRG window
-- CPU $C000-$FFFF: 16KB fixed (last bank)
-- PPU $0000-$1FFF: 8KB switchable CHR-RAM window

local PRGBank16K = 0          -- Selected 16KB bank for $8000-$BFFF (bits [4:0])
local PRG16KCount = 0         -- Total number of 16KB banks
local PRG16KLastBank = 0      -- Index of last 16KB bank

local CHRBank = 0             -- Selected 8KB CHR-RAM bank (bits [6:5], only 2 bits = 4 banks)
local chrRAM = {}             -- CHR RAM (32KB total for UNROM 512)

local nametableMode = 0       -- Bit 7: Nametable arrangement
local submapper = 0
local hasBattery = false
local useBusConflicts = false
local registerStart = 0x8000
local headerMirrorMode = 0
local switchOneScreen = false

-- Initialize CHR RAM (32KB for UNROM 512)
for i = 0, 0x7FFF do
    chrRAM[i] = 0x00
end

function mapper.CPURead(addr)
    if addr >= 0x8000 and addr <= 0xBFFF then
        -- $8000-$BFFF: Switchable 16KB PRG ROM bank
        if PRG16KCount > 0 then
            local offset = band(addr, 0x3FFF)  -- 16KB mask
            local bank = PRGBank16K % PRG16KCount
            local romIdx = bank * 0x4000 + offset + 0x0010
            return cart.ROM[romIdx] or 0x00
        end
    
    elseif addr >= 0xC000 and addr <= 0xFFFF then
        -- $C000-$FFFF: Fixed to last 16KB bank
        if PRG16KCount > 0 then
            local offset = band(addr, 0x3FFF)  -- 16KB mask
            local romIdx = PRG16KLastBank * 0x4000 + offset + 0x0010
            return cart.ROM[romIdx] or 0x00
        end
    end

    return 0x00
end

local function updateMirroring()
    if submapper == 3 then
        -- Submapper 3 uses bit 7 as H/V mirroring select.
        cart.Mirror = nametableMode == 1 and 1 or 0
    elseif switchOneScreen then
        cart.Mirror = nametableMode == 1 and 3 or 2
    else
        cart.Mirror = headerMirrorMode
    end
end

local function applyBankRegister(value)
    -- Register write: D~[NCCP PPPP]
    -- Bits [4:0]: PRG bank select
    -- Bits [6:5]: CHR-RAM bank select
    -- Bit [7]: Optional nametable control, depending on board/header.
    PRGBank16K = band(value, 0x1F)
    CHRBank = band(rshift(value, 5), 0x03)
    nametableMode = band(rshift(value, 7), 0x01)
    updateMirroring()

    mapper.chrDirty = true

    if loopy and loopy.scanLine < 240 and loopy:SearchPPUStatesInRange(loopy.scanLine - 1, loopy.scanLine + 1) then
        loopy:SearchPPUStatesInRangeAndReplace(
            loopy.scanLine - 1,
            loopy.scanLine + 1,
            require("NES.PPU.ppu").GetPPUState(loopy.scanLine)
        )
    end
end

function mapper.CPUWrite(addr, value)
    if addr >= registerStart and addr <= 0xFFFF then
        if useBusConflicts then
            value = band(value, mapper.CPURead(addr))
        end

        applyBankRegister(value)
    end
end

function mapper.PPURead(addr)
    -- PPU $0000-$1FFF: 8KB switchable window into 32KB CHR-RAM
    -- CHRBank is 2 bits (values 0-3), each selects 8KB
    if addr >= 0x0000 and addr <= 0x1FFF then
        -- UNROM 512 uses CHR-RAM, not CHR-ROM
        local chrAddr = CHRBank * 0x2000 + band(addr, 0x1FFF)
        return chrRAM[chrAddr] or 0x00
    end
    
    return 0x00
end

function mapper.PPUWrite(addr, value)
    -- PPU $0000-$1FFF: 8KB switchable CHR-RAM window
    if addr >= 0x0000 and addr <= 0x1FFF then
        local chrAddr = CHRBank * 0x2000 + band(addr, 0x1FFF)
        chrRAM[chrAddr] = value
        mapper.chrDirty = true
        return true
    end
    
    return false
end

function mapper.INI()
    -- UNROM 512 header format:
    -- Byte 4: PRG ROM size in 16KB units
    -- Byte 5: CHR capacity (should be 0 for CHR-RAM only)
    
    local prgSize = cart.header[0x04] or 0
    local flags6 = cart.header[0x06] or 0
    local flags7 = cart.header[0x07] or 0
    local flags8 = cart.header[0x08] or 0
    local isNES2 = band(flags7, 0x0C) == 0x08
    submapper = isNES2 and rshift(flags8, 4) or 0
    hasBattery = band(flags6, 0x02) ~= 0
    
    -- Calculate total 16KB banks
    -- Each unit in header is 16KB (PRG), so:
    -- If prgSize = 2, we have 2 * 16KB = 32KB = 2 banks of 16KB
    if prgSize > 0 then
        PRG16KCount = prgSize
    else
        -- Default fallback: assume at least 32KB (2 banks)
        PRG16KCount = 2
        print("WARNING: PRG size in header is 0, defaulting to 2 (32KB)")
    end
    
    PRG16KLastBank = PRG16KCount - 1
    
    -- UNROM 512 always uses CHR-RAM (32KB)
    -- CHR-RAM is divided into 4 x 8KB banks (controlled by bits 6-5 of register)
    
    -- Initialize to first PRG bank and first CHR bank
    PRGBank16K = 0
    CHRBank = 0
    nametableMode = 0

    -- Header mirroring follows the emulator convention: 0=horizontal, 1=vertical.
    headerMirrorMode = band(flags6, 0x01)
    switchOneScreen = submapper ~= 3 and band(flags6, 0x08) ~= 0 and headerMirrorMode == 0

    if submapper == 0 then
        useBusConflicts = not hasBattery
    else
        useBusConflicts = submapper == 2
    end

    -- No-bus-conflict/self-flashable UNROM-512 decodes the bank register at $C000-$FFFF.
    registerStart = (useBusConflicts or (submapper == 0 and not hasBattery)) and 0x8000 or 0xC000
    updateMirroring()
    
    print("Mapper 30 (UNROM 512) initialized")
    print("PRG 16K banks:", PRG16KCount)
    print("CHR: 32KB RAM (4 x 8KB banks)")
    print("Submapper:", submapper)
    print("Bus conflicts:", useBusConflicts and "Yes" or "No")
    print(string.format("Register decode: $%04X-$FFFF", registerStart))
    print("Mirror mode:", cart.Mirror == 0 and "Horizontal" or cart.Mirror == 1 and "Vertical" or cart.Mirror == 2 and "One-screen lower" or "One-screen upper")
    print(string.format("Register: PRG bank=%d, CHR bank=%d, Nametable=%d", PRGBank16K, CHRBank, nametableMode))
end

return mapper
