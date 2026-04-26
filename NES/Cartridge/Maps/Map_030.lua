local cart = require("NES.Cartridge.Cartridge")
local loopy = require("NES.PPU.loopy")

local mapper = {}
mapper.version = 0x1E  -- Mapper 30
mapper.chrDirty = true

local band = bit.band

-- UNROM 512 / Mapper 30
-- 16KB PRG ROM bank switching at $8000-$9FFF (switchable)
-- Fixed bank at $C000-$FFFF (last bank)
-- Simple CHR bank select

local PRGBank16K = 0          -- Selected 16KB bank for $8000-$BFFF
local PRG16KCount = 0         -- Total number of 16KB banks
local PRG16KLastBank = 0      -- Index of last 16KB bank

local CHRBank = 0             -- Selected CHR bank
local CHRBankCount = 0        -- Total CHR banks
local chrRAM = {}             -- CHR RAM for games without CHR ROM

local mirrorMode = 0          -- Mirroring mode from control register

-- Initialize CHR RAM (32KB for games without CHR ROM)
for i = 0, 0x7FFF do
    chrRAM[i] = 0x00
end

function mapper.CPURead(addr)
    if addr >= 0x8000 and addr <= 0xBFFF then
        -- $8000-$BFFF: Switchable 16KB PRG ROM bank
        local offset = band(addr, 0x3FFF)  -- 16KB mask
        local bank = PRGBank16K % PRG16KCount
        return cart.ROM[bank * 0x4000 + offset + 0x0010]
    
    elseif addr >= 0xC000 and addr <= 0xFFFF then
        -- $C000-$FFFF: Fixed to last 16KB bank
        local offset = band(addr, 0x3FFF)  -- 16KB mask
        return cart.ROM[PRG16KLastBank * 0x4000 + offset + 0x0010]
    end

    return 0x00
end

function mapper.CPUWrite(addr, value)
    if addr >= 0x8000 and addr <= 0xFFFF then
        -- Bank select and mirroring
        PRGBank16K = band(value, 0x0F)          -- Lower 4 bits: PRG bank select
        mirrorMode = band(rshift(value, 4), 0x01)  -- Bit 4: Mirroring (0=Horizontal, 1=Vertical)
        CHRBank = band(rshift(value, 5), 0x07)  -- Bits 5-7: CHR bank select
        
        -- Update mirroring
        cart.Mirror = mirrorMode
        
        mapper.chrDirty = true
        
        -- Update PPU state if scanline < 240
        if loopy.scanLine < 240 and loopy:SearchPPUStatesInRange(loopy.scanLine - 1, loopy.scanLine + 1) then
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
        if CHRBankCount > 0 then
            -- CHR ROM present
            local chrOffset = cart.header[0x04] * 0x4000  -- Skip PRG ROM
            local chrAddr = CHRBank * 0x2000 + band(addr, 0x1FFF)
            return cart.ROM[chrOffset + chrAddr + 0x0010]
        else
            -- CHR RAM
            return chrRAM[addr] or 0x00
        end
    end
    
    return 0x00
end

function mapper.PPUWrite(addr, value)
    if addr >= 0x0000 and addr <= 0x1FFF then
        if CHRBankCount == 0 then
            -- CHR RAM write only if CHR RAM is used
            chrRAM[addr] = value
            return true
        end
    end
    
    return false
end

function mapper.INI()
    -- Calculate PRG ROM info
    PRG16KCount = cart.header[0x04] * 2  -- Convert 16KB units to 16KB banks
    PRG16KLastBank = PRG16KCount - 1
    
    -- Calculate CHR info
    local chrSize = cart.header[0x05]
    CHRBankCount = chrSize
    
    if CHRBankCount == 0 then
        -- No CHR ROM, using CHR RAM
        CHRBankCount = 0
    else
        -- CHR ROM present
        CHRBankCount = chrSize
    end
    
    -- Initialize with first PRG bank selected and last bank fixed
    PRGBank16K = 0
    CHRBank = 0
    
    -- Mirror mode from header (0=Horizontal, 1=Vertical)
    mirrorMode = band(cart.header[0x06], 0x01)
    cart.Mirror = mirrorMode
    
    print("Mapper 30 (UNROM 512) initialized")
    print("PRG 16K banks:", PRG16KCount)
    print("CHR banks:", CHRBankCount > 0 and CHRBankCount or "RAM (8KB)")
    print("Mirror mode:", mirrorMode == 0 and "Horizontal" or "Vertical")
end

return mapper
