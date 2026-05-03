local cart = require("NES.Cartridge.Cartridge")
local loopy = require("NES.PPU.loopy")

local mapper = {}
mapper.version = 0x01
mapper.chrDirty = true
local CHRoffset

CHRoffset = cart.header[0x04]*0x4000 + 0x0010
mapper.nControlRegister     = 0x0C
mapper.nLoadRegister        = 0x00
mapper.nLoadRegisterCount   = 0x00
mapper.PRGMode             = 3

mapper.nCHRBankSelect4Lo   = 0x00
mapper.nCHRBankSelect4Hi   = 0x00
mapper.nCHRBankSelect8     = 0x00

-- For 512KB PRG ROM:
mapper.nPRGBankSelect32    = 0x00
mapper.nPRGBankSelect16Lo  = 0x00
-- Set to last bank (32 banks - 1)
mapper.nPRGBankSelect16Hi  = 0x1F
mapper.A18                 = 0x00

-- Initialize mirroring
cart.Mirror = 3-bit.band(mapper.nControlRegister, 0x03)


mapper.prgRAM = {}
mapper.chrRAM = {}
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local debugMAP = false
local SAVE_INTERVAL = 2
local SaveTimeout = love.timer.getTime()
local batteryDirty = false

-- Helper functions for 512KB PRG ROM (SUROM/SXROM) handling
local function Is512KPRG()
    return cart.header[0x04] == 0x20
end

local function OuterBank()
    if Is512KPRG() then
        return mapper.A18
    end
    return 0
end

local function LastInnerBank()
    if Is512KPRG() then
        return 0x0F
    end
    return cart.header[0x04] - 1
end

local function ClampPRGBank(bank)
    return bank % cart.header[0x04]
end

-- CHR-RAM: 8 KB for MMC1 games
for i = 0, 0x1FFF do
    mapper.chrRAM[i] = 0x00
end
for i = 0x6000, 0x7FFF do
    mapper.prgRAM[i] = 0x00
end

local function loadSaveState()
    print("LoadSave")
    -- Check if the save state file exists
    local file_path = SAVE_STATE_FILE
    local file = io.open(file_path, "rb")
    if file then
        local data = file:read("*all")
        file:close()
        for i = SAVE_STATE_START_ADDRESS, SAVE_STATE_END_ADDRESS do
            mapper.prgRAM[i] = data:byte(i - SAVE_STATE_START_ADDRESS + 1) or 0x00
        end
        batteryDirty = false
    else
        -- If the save state file doesn't exist, do nothing
        print("No save state file found")
    end
end

local function createSaveState(force)
    if not force and not batteryDirty then
        return
    end

    print("CreateSave")
    -- Write the save state data to a file
    local file_path = SAVE_STATE_FILE
    local file = io.open(file_path, "wb")
    if file then
        local data = ""
        for i = SAVE_STATE_START_ADDRESS, SAVE_STATE_END_ADDRESS do
            data = data .. string.char(mapper.prgRAM[i] or 0x00)
        end
        file:write(data)
        file:close()
        batteryDirty = false
        SaveTimeout = love.timer.getTime()
    else
        print("Failed to create save state file at " .. file_path)
    end
end

-- Save State prgROM (Battery Backup)
function mapper.load()
    -- check if the file "save_state.bin" exists
    local file_path = SAVE_STATE_FILE
    local file = io.open(file_path, "rb")
    if file then
        -- file exists, load it into memory
        local data = file:read("*all")
        file:close()
        loadSaveState() -- load the save state into memory
    else
        -- file does not exist, create a new save state
        createSaveState(true)
    end
end

function mapper.UpdateBatterySave()
    if batteryDirty and love.timer.getTime() - SaveTimeout > SAVE_INTERVAL then
        createSaveState()
    end
end

function mapper.FlushBatterySave()
    createSaveState()
end

function mapper.GetSaveState()
    return {
        nControlRegister = mapper.nControlRegister,
        nLoadRegister = mapper.nLoadRegister,
        nLoadRegisterCount = mapper.nLoadRegisterCount,
        PRGMode = mapper.PRGMode,
        nCHRBankSelect4Lo = mapper.nCHRBankSelect4Lo,
        nCHRBankSelect4Hi = mapper.nCHRBankSelect4Hi,
        nCHRBankSelect8 = mapper.nCHRBankSelect8,
        nPRGBankSelect32 = mapper.nPRGBankSelect32,
        nPRGBankSelect16Lo = mapper.nPRGBankSelect16Lo,
        nPRGBankSelect16Hi = mapper.nPRGBankSelect16Hi,
        A18 = mapper.A18,
        prgRAM = mapper.prgRAM,
        chrRAM = mapper.chrRAM,
        batteryDirty = batteryDirty
    }
end

function mapper.LoadSaveState(state)
    if not state then return end
    mapper.nControlRegister = state.nControlRegister or mapper.nControlRegister
    mapper.nLoadRegister = state.nLoadRegister or 0x00
    mapper.nLoadRegisterCount = state.nLoadRegisterCount or 0x00
    mapper.PRGMode = state.PRGMode or mapper.PRGMode
    mapper.nCHRBankSelect4Lo = state.nCHRBankSelect4Lo or 0x00
    mapper.nCHRBankSelect4Hi = state.nCHRBankSelect4Hi or 0x00
    mapper.nCHRBankSelect8 = state.nCHRBankSelect8 or 0x00
    mapper.nPRGBankSelect32 = state.nPRGBankSelect32 or 0x00
    mapper.nPRGBankSelect16Lo = state.nPRGBankSelect16Lo or 0x00
    mapper.nPRGBankSelect16Hi = state.nPRGBankSelect16Hi or LastInnerBank()
    mapper.A18 = state.A18 or 0x00
    mapper.prgRAM = state.prgRAM or mapper.prgRAM
    mapper.chrRAM = state.chrRAM or mapper.chrRAM
    batteryDirty = state.batteryDirty or false
    mapper.chrDirty = true
end

function mapper.CPURead(addr)
    -- Cartridge PRG-RAM ($6000-$7FFF) - always mapped
    if addr >= 0x6000 and addr <= 0x7FFF then
        return mapper.prgRAM[addr] or 0x00
    end

    if addr < 0x8000 then
        return 0x00
    end

    -- Special case: 2-bank PRG ROM (32KB total) - simple linear mapping
    if cart.header[0x04] == 2 and addr >= 0x8000 then
        return cart.ROM[bit.band(addr, 0x7FFF) + 0x0010]
    end

    local prgMode = band(rshift(mapper.nControlRegister, 2), 0x03)
    local outer = OuterBank()

    -- 32KB mode: PRG modes 0 and 1
    if prgMode == 0 or prgMode == 1 then
        local bank = outer + band(mapper.nPRGBankSelect16Lo, 0x0E)
        bank = ClampPRGBank(bank)

        return cart.ROM[bank * 0x4000 + band(addr, 0x7FFF) + 0x0010]
    end

    -- 16KB mode, $8000-$BFFF
    if addr < 0xC000 then
        local bank
        if prgMode == 2 then
            -- Mode 2: fixed first bank at $8000
            bank = outer + 0x00
        else
            -- Mode 3: switchable bank at $8000
            bank = outer + mapper.nPRGBankSelect16Lo
        end
        bank = ClampPRGBank(bank)
        return cart.ROM[bank * 0x4000 + band(addr, 0x3FFF) + 0x0010]
    end

    -- 16KB mode, $C000-$FFFF
    local bank
    if prgMode == 2 then
        -- Mode 2: switchable bank at $C000
        bank = outer + mapper.nPRGBankSelect16Hi
    else
        -- Mode 3: fixed last bank of selected 256KB half
        bank = outer + LastInnerBank()
    end
    bank = ClampPRGBank(bank)
    return cart.ROM[bank * 0x4000 + band(addr, 0x3FFF) + 0x0010]
end

function mapper.CPUWrite(addr, data)
    -- Cartridge PRG-RAM ($6000-$7FFF) - always mapped
    if addr >= 0x6000 and addr <= 0x7FFF then
        mapper.prgRAM[addr] = data
        batteryDirty = true
        
        return
    end
    if addr >= 0x8000 then
        if debugMAP then print("CPU Write 8000+ ", string.format("%x %x", addr, data)) end
        if band(data,0x80) ~= 0 then
            if debugMAP then print("reset") end
            mapper.nLoadRegister = 0x00
            mapper.nLoadRegisterCount = 0x00
            mapper.nControlRegister = bor(mapper.nControlRegister, 0x0C)
        else
            -- load serial data into register
            mapper.nLoadRegister = rshift(mapper.nLoadRegister,1)
            mapper.nLoadRegister = bor(mapper.nLoadRegister, lshift(band(data,0x01), 4))
            mapper.nLoadRegisterCount = mapper.nLoadRegisterCount + 1
            if debugMAP then print(string.format("CPU Write %x %x",addr, data)) end
            if mapper.nLoadRegisterCount == 5 then
                
                -- get Mapper target Register by examining bits 13 and 14
                local nTargetRegister = band(rshift(addr, 13), 0x03)
                if debugMAP then print("Mapper Set Target Register "..nTargetRegister.." Data "..mapper.nControlRegister) end
                if nTargetRegister == 0 then
                    -- set control register
                    mapper.nControlRegister = band(mapper.nLoadRegister, 0x1F)
                    -- Mirror Mode
                    if debugMAP then print("Mirror Mode ", 3-band(mapper.nControlRegister, 0x03)) end
                    local mirroring = band(mapper.nControlRegister, 0x03)
                    if mirroring == 0 then
                        cart.Mirror = 2  -- One-screen lower
                    elseif mirroring == 1 then
                        cart.Mirror = 3  -- One-screen upper
                    elseif mirroring == 2 then
                        cart.Mirror = 1  -- Vertical
                    else
                        cart.Mirror = 0  -- Horizontal
                    end
                elseif nTargetRegister == 1 then
                    -- CHR Bank Select (low 4K) + PRG ROM A18 for 512KB games
                    if cart.header[0x04] == 0x20 and band(mapper.nLoadRegister, 0x10) ~= 0 then
                        mapper.A18 = 0x10
                    else
                        mapper.A18 = 0x00
                    end
                    
                    if band(mapper.nControlRegister, 0x10) ~= 0 then
                        mapper.nCHRBankSelect4Lo = band(mapper.nLoadRegister, 0x1F)
                    else
                        mapper.nCHRBankSelect8 = band(mapper.nLoadRegister, 0x1E)
                    end
                    
                    mapper.chrDirty = true
                    if loopy.scanLine < 240 then
                        loopy:SearchPPUStatesInRangeAndReplace(
                            loopy.scanLine - 1,
                            loopy.scanLine + 1,
                            require("NES.PPU.ppu").GetPPUState(loopy.scanLine)
                        )
                    end
                    
                    if Is512KPRG() then
                        --[[
                        print(string.format(
                            "MMC1 A18 update: load=%02X A18=%02X outer=%02X fixedHi=%02X",
                            mapper.nLoadRegister,
                            mapper.A18,
                            OuterBank(),
                            OuterBank() + LastInnerBank()
                        ))
                        ]]
                    end
                    
                    if debugMAP then
                        print(string.format(
                            "CHRReg1 BankLo:%x BankHi:%x Value:%x, A18:%x",
                            mapper.nCHRBankSelect4Lo,
                            mapper.nCHRBankSelect4Hi,
                            mapper.nLoadRegister,
                            mapper.A18
                        ))
                    end
                elseif nTargetRegister == 2 then
                    -- CHR Bank Select (high 4K) - do NOT set A18 here
                    if band(mapper.nControlRegister, 0x10) ~= 0 then
                        mapper.nCHRBankSelect4Hi = band(mapper.nLoadRegister, 0x1F)
                    end
                    mapper.chrDirty = true
                    if loopy.scanLine < 240 then
                        loopy:SearchPPUStatesInRangeAndReplace(
                            loopy.scanLine - 1,
                            loopy.scanLine + 1,
                            require("NES.PPU.ppu").GetPPUState(loopy.scanLine)
                        )
                    end
                    if debugMAP then
                        print(string.format(
                            "CHRReg2 BankLo:%x BankHi:%x Value:%x, A18:%x",
                            mapper.nCHRBankSelect4Lo,
                            mapper.nCHRBankSelect4Hi,
                            mapper.nLoadRegister,
                            mapper.A18
                        ))
                    end
                elseif nTargetRegister == 3 then
                    local nPRGMode = band(rshift(mapper.nControlRegister, 2), 0x03)
                    local prgBank = band(mapper.nLoadRegister, 0x0F)

                    if nPRGMode == 0 or nPRGMode == 1 then
                        -- 32KB mode
                        mapper.PRGMode = 1
                        mapper.nPRGBankSelect16Lo = band(prgBank, 0x0E)
                        mapper.nPRGBankSelect32 = rshift(mapper.nPRGBankSelect16Lo, 1)

                    elseif nPRGMode == 2 then
                        -- 16KB mode: fixed first bank at $8000
                        mapper.PRGMode = 2
                        mapper.nPRGBankSelect16Lo = 0
                        mapper.nPRGBankSelect16Hi = prgBank

                    elseif nPRGMode == 3 then
                        -- 16KB mode: fixed last bank at $C000
                        mapper.PRGMode = 3
                        mapper.nPRGBankSelect16Lo = prgBank
                        mapper.nPRGBankSelect16Hi = LastInnerBank()
                    end

                    if debugMAP then
                        print(string.format(
                            "PRGReg mode=%d BankLo:%x BankHi:%x A18:%x",
                            nPRGMode,
                            mapper.nPRGBankSelect16Lo,
                            mapper.nPRGBankSelect16Hi,
                            mapper.A18
                        ))
                    end
                end
                mapper.nLoadRegister = 0x00
                mapper.nLoadRegisterCount = 0
            end
        end
    end
end

function mapper.PPURead(addr)
    if addr < 0x2000 then
        -- using Cartridge RAM
        if cart.header[0x05] == 0 then
            --print(string.format("PPU Read %x", addr))
            return mapper.chrRAM[addr]
        -- using Cartridge ROM
        else
            if band(mapper.nControlRegister, 0x10) ~= 0 then
                -- 4k CHR Banks
                if addr >= 0x0000 and addr <= 0x0FFF then
                    return cart.ROM[mapper.nCHRBankSelect4Lo * 0x1000 + band(addr, 0x0FFF) + CHRoffset]
                end
                if addr >= 0x1000 and addr <= 0x1FFF then
                    return cart.ROM[mapper.nCHRBankSelect4Hi * 0x1000 + band(addr, 0x0FFF) + CHRoffset]
                end
            else
                -- 8k CHR Bank Mode
                return cart.ROM[mapper.nCHRBankSelect8 * 0x1000 + band(addr, 0x1FFF) + CHRoffset]
            end
        end
    end
end

function mapper.PPUWrite(addr, value)
    -- reset Serial Data
    if addr < 0x2000 then
        if cart.header[0x05] == 0 then
            mapper.chrRAM[addr] = value
            return true
        end
        return true
    else
        return false
    end
end

--[[
    0x8000 - 0xA000 Control Zone 
    0xA000 - 0xC000 CHR low byte 
    0xC000 - 0xE000 CHR Hi byte
    0xE000 - 0xFFFF PRG Rom
]]

function mapper.INI()
    CHRoffset = cart.header[0x04] * 0x4000 + 0x0010
    for i = 0, 0x1FFF do
        mapper.chrRAM[i] = 0x00
    end
    for i = 0x6000, 0x7FFF do
        mapper.prgRAM[i] = 0x00
    end
    batteryDirty = false
    SaveTimeout = love.timer.getTime()
    
    mapper.nControlRegister = 0x0C
    mapper.nLoadRegister = 0x00
    mapper.nLoadRegisterCount = 0x00
    mapper.PRGMode = 3

    mapper.nCHRBankSelect4Lo = 0x00
    mapper.nCHRBankSelect4Hi = 0x00
    mapper.nCHRBankSelect8 = 0x00

    mapper.nPRGBankSelect32 = 0x00
    mapper.nPRGBankSelect16Lo = 0x00
    mapper.nPRGBankSelect16Hi = LastInnerBank()
    mapper.A18 = 0x00
    
    -- Debug: Print PRG ROM bytes around reset vector and interrupts
    if cart.header[0x04] == 2 then
        print("\n=== Mapper 1 (MMC1) - 32KB PRG ROM Debug ===")
        print(string.format("PRG Banks: %d", cart.header[0x04]))
        print("\nBytes at $FFC0-$FFFF (Reset, NMI, IRQ vectors):")
        for addr = 0xFFC0, 0xFFFF do
            io.write(string.format("%04X:%02X ", addr, mapper.CPURead(addr)))
            if (addr - 0xFFC0 + 1) % 8 == 0 then
                print()
            end
        end
        print("\nReset vector: $" .. string.format("%02X%02X", mapper.CPURead(0xFFFD), mapper.CPURead(0xFFFC)))
        print("NMI vector:   $" .. string.format("%02X%02X", mapper.CPURead(0xFFFB), mapper.CPURead(0xFFFA)))
        print("IRQ vector:   $" .. string.format("%02X%02X", mapper.CPURead(0xFFFF), mapper.CPURead(0xFFFE)))
        print("=========================================\n")
    end
    
    -- Define the memory location to store the save state data
    -- Remove the last three letters of the file path and replace them with "batt"
    local basename = string.gsub(GlobalFileName, "%.nes$", "") -- remove the file extension
    basename = string.gsub(basename, "^.*[/\\]", "") -- remove the directory path
    local new_file_path = LoveFileDir.."RomSaves/"..basename..".batt"
    SAVE_STATE_FILE = new_file_path
    SAVE_STATE_START_ADDRESS = 0x6000
    SAVE_STATE_END_ADDRESS = 0x7FFF
    mapper.load()
end

return mapper
