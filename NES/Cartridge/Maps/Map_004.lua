local cart = require("NES.Cartridge.Cartridge")

local mapper = {}
mapper.version = 0x03
mapper.chrDirty = true

local CHRoffset
local PRGoffset
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local prgBankMode = 0
local chrBankMode = 0
local bankSelect = 0
local irqCounter = 0
local irqLatch = 0
local irqReload = false
local doIRQ = false
local irqEnable = false
local PRGRAMEnabled = true

local PRGBank6 = 0x00
local PRGBank7 = 0x00

local PRGBankLast = 0x00
local PRGBankSecondLast = 0x00
local prg8kCount = 0

--2f
local CHRBank0a = 0x20
local CHRBank0b = 0x21
local CHRBank1a = 0x2a
local CHRBank1b = 0x2b
local CHRBank2 = 0x2c
local CHRBank3 = 0x2d
local CHRBank4 = 0x2e
local CHRBank5 = 0x2f

mapper.prgRAM = {}

--! MMC3 COMMON
for i = 0x6000, 0x7FFF do
    mapper.prgRAM[i] = 0x00
end

local function updateBanks()
    -- Update PRG and CHR banks based on bankData and modes
end

function mapper.CPURead(addr)
    if addr >= 0x6000 and addr <= 0x7FFF then
        return mapper.prgRAM[addr] or 0x00
    end

    if addr >= 0x8000 and addr <= 0x9FFF then
        local bank

        if prgBankMode == 0 then
            bank = PRGBank6
        else
            bank = PRGBankSecondLast
        end

        bank = bank % prg8kCount
        return cart.ROM[bank * 0x2000 + bit.band(addr, 0x1FFF) + 0x0010]
    end

    if addr >= 0xA000 and addr <= 0xBFFF then
        local bank = PRGBank7 % prg8kCount
        return cart.ROM[bank * 0x2000 + bit.band(addr, 0x1FFF) + 0x0010]
    end

    if addr >= 0xC000 and addr <= 0xDFFF then
        local bank

        if prgBankMode == 0 then
            bank = PRGBankSecondLast
        else
            bank = PRGBank6
        end

        bank = bank % prg8kCount
        return cart.ROM[bank * 0x2000 + bit.band(addr, 0x1FFF) + 0x0010]
    end

    if addr >= 0xE000 and addr <= 0xFFFF then
        local bank = PRGBankLast % prg8kCount
        return cart.ROM[bank * 0x2000 + bit.band(addr, 0x1FFF) + 0x0010]
    end

    return 0x00
end
local loopy = require("NES.PPU.loopy")

-- MMC3 CHR writes are scanline-visible events.  A state is not necessarily
-- already present at the write location (most frames only have the frame
-- start and vblank states), so always insert/replace one rather than only
-- updating an existing state.
local function captureCHRState()
    if loopy.scanLine >= 0 and loopy.scanLine < 240 then
        local ppu = require("NES.PPU.ppu")
        -- Do not use the normal +/-1 scanline coalescing here. Bad Dudes
        -- changes horizontal scroll on one line and CHR banks on the next;
        -- merging those events loses their ordering.
        loopy:SearchPPUStatesInRangeAndReplace(
            loopy.scanLine,
            loopy.scanLine,
            ppu.GetPPUState(loopy.scanLine, nil, false, "mapper"))
    end
end

function mapper.CPUWrite(addr, data)
    -- Implement CPUWrite functionality
    --print(string.format("addr: %x data: %x",addr,data))
    if addr >=0x6000 and addr < 0x8000 then
        mapper.prgRAM[addr] = data
    elseif addr >= 0x8000 and addr < 0xA000 then
        local value = bit.band(addr,0x0001)
        if value == 0 then
            local newPrgBankMode = bit.rshift(bit.band(data,0x40),6)
            local newChrBankMode = bit.rshift(bit.band(data,0x80),7)
            local chrModeChanged = newChrBankMode ~= chrBankMode
            if chrModeChanged then
                mapper.chrDirty = true
            end
            prgBankMode = newPrgBankMode
            chrBankMode = newChrBankMode
            bankSelect = bit.band(data,0x07)
            
            -- A bank-select write alone does not change the active CHR
            -- mapping.  Capture only when the CHR mode actually changes.
            if chrModeChanged then
                captureCHRState()
            end
        else
            local chrChanged = false
            if bankSelect == 0 then
                local newBank = bit.band(data,0xFFFE)
                chrChanged = newBank ~= CHRBank0a
                if chrChanged then mapper.chrDirty = true end
                CHRBank0a = newBank
                CHRBank0b = newBank + 1
            elseif bankSelect == 1 then
                local newBank = bit.band(data,0xFFFE)
                chrChanged = newBank ~= CHRBank1a
                if chrChanged then mapper.chrDirty = true end
                CHRBank1a = newBank
                CHRBank1b = newBank + 1
            elseif bankSelect == 2 then
                chrChanged = data ~= CHRBank2
                if chrChanged then mapper.chrDirty = true end
                CHRBank2 = data
            elseif bankSelect == 3 then
                chrChanged = data ~= CHRBank3
                if chrChanged then mapper.chrDirty = true end
                CHRBank3 = data
            elseif bankSelect == 4 then
                chrChanged = data ~= CHRBank4
                if chrChanged then mapper.chrDirty = true end
                CHRBank4 = data
            elseif bankSelect == 5 then
                chrChanged = data ~= CHRBank5
                if chrChanged then mapper.chrDirty = true end
                CHRBank5 = data
            elseif bankSelect == 6 then
                PRGBank6 = data
                --print("prgbank6 "..PRGBank6 )
            elseif bankSelect == 7 then
                PRGBank7 = data
                --print("prgbank7 "..PRGBank7 )
            end
            --print("BankSelect "..bankSelect.." data "..data)
            if chrChanged then
                -- Capture the CHR mapping even when this scanline has no
                -- prior saved state.
                captureCHRState()
            end
        end
    elseif addr >= 0xA000 and addr < 0xC000 then
        local value = bit.band(addr,0x0001)
        if value == 0 then
            cart.Mirror = bit.band(data,0x01)==1 and 0 or 1

            --print("Mirror "..cart.Mirror)
        else
            PRGRAMEnabled = bit.band(data, 0x80) == 0x80 and true or false
            --print("PRGRAMEnabled ",PRGRAMEnabled)
        end
    elseif addr >= 0xC000 and addr < 0xE000 then
        local value = bit.band(addr, 0x0001)
        if value == 0 then
            -- $C000 even: IRQ latch
            irqLatch = data
        else
            -- $C001 odd: request reload on next A12 clock
            irqReload = true
        end
    elseif addr >= 0xE000 and addr <= 0xFFFF then
        local value = bit.band(addr, 0x0001)
        if value == 0 then
            -- $E000 even: disable IRQ and clear pending
            irqEnable = false
            doIRQ = false
        else
            -- $E001 odd: enable IRQ
            irqEnable = true
        end
    end
    --print(string.format("addr: %x data: %x",addr,data))
end

function mapper.PPURead(addr)
    -- Implement PPURead functionality
    if chrBankMode == 0 then
        if addr >= 0x0000 and addr < 0x0400 then
            return cart.ROM[CHRBank0a * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x0400 and addr < 0x0800 then
            return cart.ROM[CHRBank0b * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x0800 and addr < 0x0C00 then
            return cart.ROM[CHRBank1a * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x0C00 and addr < 0x1000 then
            return cart.ROM[CHRBank1b * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x1000 and addr < 0x1400 then
            return cart.ROM[CHRBank2 * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x1400 and addr < 0x1800 then
            return cart.ROM[CHRBank3 * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x1800 and addr < 0x1C00 then
            return cart.ROM[CHRBank4 * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x1C00 and addr < 0x2000 then
            return cart.ROM[CHRBank5 * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        end
    else
        if addr >= 0x0000 and addr < 0x0400 then
            return cart.ROM[CHRBank2 * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x0400 and addr < 0x0800 then
            return cart.ROM[CHRBank3 * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x0800 and addr < 0x0C00 then
            return cart.ROM[CHRBank4 * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x0C00 and addr < 0x1000 then
            return cart.ROM[CHRBank5 * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x1000 and addr < 0x1400 then
            return cart.ROM[CHRBank0a * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x1400 and addr < 0x1800 then
            return cart.ROM[CHRBank0b * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x1800 and addr < 0x1C00 then
            return cart.ROM[CHRBank1a * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        elseif addr >= 0x1C00 and addr < 0x2000 then
            return cart.ROM[CHRBank1b * 0x0400 + band(addr, 0x03FF) + CHRoffset]
        end
    end
end

function mapper.PPUWrite(addr, value)
    -- Implement PPUWrite functionality
end

function mapper.ScanLineUpdate(scanLines)
    -- Reload on A12 clock edge (or if counter = 0)
    if irqReload or irqCounter == 0 then
        irqCounter = irqLatch
        irqReload = false
    else
        irqCounter = irqCounter - 1
    end

    -- Trigger IRQ if counter reaches 0
    if irqCounter == 0 and irqEnable then
        doIRQ = true
    end
end

function mapper.CheckIRQ()
    if irqEnable == true and doIRQ then
        doIRQ = false
        return true
    end
    return false
end

function mapper.GetSaveState()
    return {
        prgBankMode = prgBankMode,
        chrBankMode = chrBankMode,
        bankSelect = bankSelect,
        irqCounter = irqCounter,
        irqLatch = irqLatch,
        irqReload = irqReload,
        doIRQ = doIRQ,
        irqEnable = irqEnable,
        PRGRAMEnabled = PRGRAMEnabled,
        PRGBank6 = PRGBank6,
        PRGBank7 = PRGBank7,
        PRGBankLast = PRGBankLast,
        PRGBankSecondLast = PRGBankSecondLast,
        prg8kCount = prg8kCount,
        CHRBank0a = CHRBank0a,
        CHRBank0b = CHRBank0b,
        CHRBank1a = CHRBank1a,
        CHRBank1b = CHRBank1b,
        CHRBank2 = CHRBank2,
        CHRBank3 = CHRBank3,
        CHRBank4 = CHRBank4,
        CHRBank5 = CHRBank5,
        prgRAM = mapper.prgRAM
    }
end

function mapper.LoadSaveState(state)
    if not state then return end
    prgBankMode = state.prgBankMode or 0
    chrBankMode = state.chrBankMode or 0
    bankSelect = state.bankSelect or 0
    irqCounter = state.irqCounter or 0
    irqLatch = state.irqLatch or 0
    irqReload = state.irqReload or false
    doIRQ = state.doIRQ or false
    irqEnable = state.irqEnable or false
    PRGRAMEnabled = state.PRGRAMEnabled ~= false
    PRGBank6 = state.PRGBank6 or 0x00
    PRGBank7 = state.PRGBank7 or 0x00
    PRGBankLast = state.PRGBankLast or PRGBankLast
    PRGBankSecondLast = state.PRGBankSecondLast or PRGBankSecondLast
    prg8kCount = state.prg8kCount or prg8kCount
    CHRBank0a = state.CHRBank0a or CHRBank0a
    CHRBank0b = state.CHRBank0b or CHRBank0b
    CHRBank1a = state.CHRBank1a or CHRBank1a
    CHRBank1b = state.CHRBank1b or CHRBank1b
    CHRBank2 = state.CHRBank2 or CHRBank2
    CHRBank3 = state.CHRBank3 or CHRBank3
    CHRBank4 = state.CHRBank4 or CHRBank4
    CHRBank5 = state.CHRBank5 or CHRBank5
    mapper.prgRAM = state.prgRAM or mapper.prgRAM
    mapper.chrDirty = true
end

function mapper.INI()
    CHRoffset = cart.header[0x04] * 0x4000 + 0x0010
    prg8kCount = cart.header[0x04] * 2
    PRGBankSecondLast = prg8kCount - 2
    PRGBankLast = prg8kCount - 1

    prgBankMode = 0
    chrBankMode = 0
    bankSelect = 0
    irqCounter = 0
    irqLatch = 0
    irqReload = false
    doIRQ = false
    irqEnable = false
    PRGRAMEnabled = true
    PRGBank6 = 0x00
    PRGBank7 = 0x00
    CHRBank0a = 0x00
    CHRBank0b = 0x01
    CHRBank1a = 0x00
    CHRBank1b = 0x01
    CHRBank2 = 0x00
    CHRBank3 = 0x00
    CHRBank4 = 0x00
    CHRBank5 = 0x00
    mapper.chrDirty = true

    for i = 0x6000, 0x7FFF do
        mapper.prgRAM[i] = 0x00
    end
end

return mapper

