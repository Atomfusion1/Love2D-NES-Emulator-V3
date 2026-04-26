local cart = require("NES.Cartridge.Cartridge")
local loopy = require("NES.PPU.loopy")

local mapper = {}
mapper.version = 0x1E  -- Mapper 30 (UNROM 512)
mapper.chrDirty = true

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

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

function mapper.CPUWrite(addr, value)
    -- Register write: D~[NCCP PPPP]
    -- Bits [4:0]: PRG bank select (5 bits)
    -- Bits [6:5]: CHR bank select (2 bits, for 8KB windows in 32KB CHR)
    -- Bit [7]: Nametable arrangement
    
    if addr >= 0x8000 and addr <= 0xFFFF then
        PRGBank16K = band(value, 0x1F)              -- Lower 5 bits: PRG bank select
        CHRBank = band(rshift(value, 5), 0x03)      -- Bits 5-6: CHR bank select (2 bits only)
        nametableMode = band(rshift(value, 7), 0x01) -- Bit 7: Nametable arrangement
        
        -- Update mirroring based on nametable mode and header configuration
        -- For now, use nametable mode bit directly
        if nametableMode == 1 then
            cart.Mirror = 1  -- Vertical
        else
            cart.Mirror = 0  -- Horizontal
        end
        
        mapper.chrDirty = true
        
        -- Update PPU state if scanline < 240
        if loopy and loopy.scanLine < 240 and loopy:SearchPPUStatesInRange(loopy.scanLine - 1, loopy.scanLine + 1) then
            loopy:SearchPPUStatesInRangeAndReplace(
                loopy.scanLine - 1,
                loopy.scanLine + 1,
                require("NES.PPU.ppu").GetPPUState(loopy.scanLine)
            )
        end
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
        return true
    end
    
    return false
end

function mapper.INI()
    -- UNROM 512 header format:
    -- Byte 4: PRG ROM size in 16KB units
    -- Byte 5: CHR capacity (should be 0 for CHR-RAM only)
    
    local prgSize = cart.header[0x04] or 0
    
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
    
    -- Mirror mode from header (0=Horizontal, 1=Vertical)
    local headerMirror = band(cart.header[0x06] or 0, 0x01)
    cart.Mirror = headerMirror
    
    print("Mapper 30 (UNROM 512) initialized")
    print("PRG 16K banks:", PRG16KCount)
    print("CHR: 32KB RAM (4 x 8KB banks)")
    print("Mirror mode:", headerMirror == 0 and "Horizontal" or "Vertical")
    print(string.format("Register: PRG bank=%d, CHR bank=%d, Nametable=%d", PRGBank16K, CHRBank, nametableMode))
end

return mapper
