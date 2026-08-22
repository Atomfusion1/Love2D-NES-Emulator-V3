local serpent   = require("Emulator.tabletofile")
local cpuMemory = require("NES.CPU.cpuInternal")
local cart      = require("NES.Cartridge.Cartridge")
local mapper    = require("NES.Cartridge.Mappers")
local cpuRAM    = require("NES.CPU.cpuram")
local ppu       = require("NES.PPU.ppu")
local nameTable = require("NES.PPU.ppunametable")
local ppuOAM    = require("NES.PPU.ppuOAM")
local ppuIO     = require("NES.PPU.ppuIO")
local loopy     = require("NES.PPU.loopy")
local ppuBus    = require("NES.PPU.ppuBus")
-- Creates a Save State of all the Memory and creates a file 
    -- Define the memory location to store the save state data
    -- Remove the last three letters of the file path and replace them with "batt"

local saveState = {}

local  function createSaveState(table, FILE)
    print("CreateSave "..FILE)
    -- Write the save state data to a file
    local file_path = FILE
    local file = io.open(file_path, "wb")
    if file then
        local serialized_table = serpent.dump(table)
        file:write(serialized_table)
        file:close()
    else
        print("Failed to create save state file at " .. file_path)
    end
end

local table = {
CPU   = {},
PPU   = {},
CART  = {},
OAM   = {},
PPUIO = {}
}
local function updateSaveTable()
        local activeMapper = mapper[cart.mapper].mapper
        table.CPU.A               =     cpuMemory.A
        table.CPU.X               =     cpuMemory.X
        table.CPU.Y               =     cpuMemory.Y
        table.CPU.stackPointer    =     cpuMemory.stackPointer
        table.CPU.statusRegister  =     cpuMemory.statusRegister
        table.CPU.info_cycle      =     cpuMemory.info.cycle
        table.CPU.info_execute    =     cpuMemory.info.execute
        table.CPU.programCounter  =     cpuMemory.programCounter
        table.CPU.resetInterrupt  =     cpuMemory.resetInterrupt
        table.CPU.NMIInterrupt    =     cpuMemory.NMIInterrupt
        table.CPU.BRKInterrupt    =     cpuMemory.BRKInterrupt
        table.CPU.CHRLocation     =     cpuMemory.CHRLocation
        table.CPU.RAM             =     cpuRAM.cpuRAM

        -- Legacy MMC1 fields are kept so old .save files still load.
        table.PPU.nCHRBankSelect4Lo     = activeMapper.nCHRBankSelect4Lo
        table.PPU.nCHRBankSelect4Hi     = activeMapper.nCHRBankSelect4Hi
        table.PPU.nCHRBankSelect8       = activeMapper.nCHRBankSelect8
        table.PPU.nPRGBankSelect32      = activeMapper.nPRGBankSelect32
        table.PPU.nPRGBankSelect16Lo    = activeMapper.nPRGBankSelect16Lo
        table.PPU.nPRGBankSelect16Hi    = activeMapper.nPRGBankSelect16Hi

        table.PPU.nControlRegister      = activeMapper.nControlRegister
        table.PPU.nLoadRegister         = activeMapper.nLoadRegister
        table.PPU.nLoadRegisterCount    = activeMapper.nLoadRegisterCount
        table.PPU.prgRAM                = activeMapper.prgRAM
        table.PPU.chrRAM                = activeMapper.chrRAM
        table.PPU.memory                = ppu.memory
        table.PPU.tblName               = nameTable.tblName
        table.PPU.tblPallette           = nameTable.tblPalette
        table.PPU.scanLines             = ppu.scanLines
        table.PPU.scanLinePixels        = ppu.scanLinePixels
        table.PPU.currentFrame          = ppu.currentFrame
        table.PPU.vBlankEnd             = ppu.vBlankEnd
        table.PPU.DrawScreen            = ppu.DrawScreen

        table.CART.Mirror               = cart.Mirror
        table.CART.mapper               = cart.mapper
        table.OAM.OAM                   = ppuOAM.OAM
        table.PPUIO.NameTableAddress    = ppuIO.NameTableAddress
        table.PPUIO.BackgroundTable     = ppuIO.BackgroundTable
        table.PPUIO.SpriteTable         = ppuIO.SpriteTable
        table.PPUIO.CTRL                = ppuIO.CTRL
        table.PPUIO.MASKS               = ppuIO.MASKS
        table.PPUIO.STATUS              = ppuIO.STATUS
        table.PPUIO.OAMADDR             = ppuIO.OAMADDR
        table.PPUIO.OAMDATA             = ppuIO.OAMDATA
        table.PPUIO.SCROLL              = ppuIO.SCROLL
        table.PPUIO.ADDR                = ppuIO.ADDR
        table.PPUIO.DATA                = ppuIO.DATA
        table.PPUIO.OAMDMA              = ppuIO.OAMDMA
        table.PPUIO.NMIArmed            = ppuIO.NMIArmed
        table.PPUIO.delayPPU            = ppuIO.delayPPU
        table.PPUIO.Bus                 = ppuBus.GetSaveState and ppuBus.GetSaveState() or nil

        table.LOOPY                     = table.LOOPY or {}
        table.LOOPY.ppuStates           = loopy.ppuStates
        table.LOOPY.v                   = loopy.v
        table.LOOPY.t                   = loopy.t
        table.LOOPY.x                   = loopy.x
        table.LOOPY.w                   = loopy.w
        table.LOOPY.fine_x              = loopy.fine_x
        table.LOOPY.course_x            = loopy.course_x
        table.LOOPY.fine_y              = loopy.fine_y
        table.LOOPY.course_y            = loopy.course_y
        table.LOOPY.nametable_x         = loopy.nametable_x
        table.LOOPY.nametable_y         = loopy.nametable_y
        table.LOOPY.drawScreen          = loopy.drawScreen
        table.LOOPY.drawSprites         = loopy.drawSprites
        table.LOOPY.register_vram_addr  = loopy.register_vram_addr
        table.LOOPY.register_tram_addr  = loopy.register_tram_addr
        table.LOOPY.scanLine            = loopy.scanLine
        table.LOOPY.scanLinePixels      = loopy.scanLinePixels
        table.LOOPY.inVBlank            = loopy.inVBlank

        table.MAPPER                    = table.MAPPER or {}
        table.MAPPER.id                 = cart.mapper
        table.MAPPER.state              = activeMapper.GetSaveState and activeMapper.GetSaveState() or nil
end

function saveState.Save(key)
    updateSaveTable()
    local basename = string.gsub(GlobalFileName, "%.nes$", "") -- remove the file extension
    basename = string.gsub(basename, "^.*[/\\]", "") -- remove the directory path
    local new_file_path = LoveFileDir.."RomSaves/"..basename..key..".save"
    createSaveState(table, new_file_path)
    print("File Saved PC ",new_file_path, table.CPU.stackPointer, string.format("%x",table.CPU.programCounter))
    --print(table.CPU.RAM[0x10])
end

function saveState.LoadFile(file_path)
    print("Loading "..file_path)
    local file = io.open(file_path, "r")
    if file then
        local data = file:read("*all")
        local tableFunction = load(data)
        file:close()
        return true, tableFunction()
    else
        print("Failed to load save state file at " .. file_path)
        return false
    end
end

local function Merge(data)
    local activeMapper = mapper[cart.mapper].mapper
    --CPU
    cpuMemory.A               = data.CPU.A
    cpuMemory.X               = data.CPU.X
    cpuMemory.Y               = data.CPU.Y
    cpuMemory.stackPointer    = data.CPU.stackPointer
    cpuMemory.statusRegister  = data.CPU.statusRegister
    cpuMemory.info.cycle      = data.CPU.info_cycle
    cpuMemory.info.execute    = data.CPU.info_execute
    cpuMemory.programCounter  = data.CPU.programCounter
    cpuMemory.resetInterrupt  = data.CPU.resetInterrupt
    cpuMemory.NMIInterrupt    = data.CPU.NMIInterrupt
    cpuMemory.BRKInterrupt    = data.CPU.BRKInterrupt
    cpuMemory.CHRLocation     = data.CPU.CHRLocation
    cpuRAM.cpuRAM             = data.CPU.RAM
    --PPU
    if data.MAPPER and data.MAPPER.state and activeMapper.LoadSaveState then
        activeMapper.LoadSaveState(data.MAPPER.state)
    else
        activeMapper.nCHRBankSelect4Lo    = data.PPU.nCHRBankSelect4Lo
        activeMapper.nCHRBankSelect4Hi    = data.PPU.nCHRBankSelect4Hi
        activeMapper.nCHRBankSelect8      = data.PPU.nCHRBankSelect8
        activeMapper.nPRGBankSelect32     = data.PPU.nPRGBankSelect32
        activeMapper.nPRGBankSelect16Lo   = data.PPU.nPRGBankSelect16Lo
        activeMapper.nPRGBankSelect16Hi   = data.PPU.nPRGBankSelect16Hi
        activeMapper.prgRAM               = data.PPU.prgRAM
        activeMapper.chrRAM               = data.PPU.chrRAM
        activeMapper.nControlRegister     = data.PPU.nControlRegister
        activeMapper.nLoadRegister        = data.PPU.nLoadRegister
        activeMapper.nLoadRegisterCount   = data.PPU.nLoadRegisterCount
    end
    ppu.memory                                      = data.PPU.memory
    nameTable.tblName                               = data.PPU.tblName
    nameTable.tblPalette                            = data.PPU.tblPallette
    ppu.scanLines                                  = data.PPU.scanLines or ppu.scanLines
    ppu.scanLinePixels                             = data.PPU.scanLinePixels or ppu.scanLinePixels
    ppu.currentFrame                               = data.PPU.currentFrame or ppu.currentFrame
    ppu.vBlankEnd                                  = data.PPU.vBlankEnd or false
    ppu.DrawScreen                                 = data.PPU.DrawScreen or false
    cart.Mirror                                     = data.CART.Mirror
    ppuOAM.OAM                                      = data.OAM.OAM
    if data.PPUIO then
        ppuIO.NameTableAddress                        = data.PPUIO.NameTableAddress
        ppuIO.BackgroundTable                         = data.PPUIO.BackgroundTable
        ppuIO.SpriteTable                             = data.PPUIO.SpriteTable
        ppuIO.CTRL                                    = data.PPUIO.CTRL  or ppuIO.CTRL
        ppuIO.MASKS                                   = data.PPUIO.MASKS or ppuIO.MASKS
        ppuIO.STATUS                                  = data.PPUIO.STATUS or ppuIO.STATUS
        ppuIO.OAMADDR                                 = data.PPUIO.OAMADDR or ppuIO.OAMADDR
        ppuIO.OAMDATA                                 = data.PPUIO.OAMDATA or ppuIO.OAMDATA
        ppuIO.SCROLL                                  = data.PPUIO.SCROLL or ppuIO.SCROLL
        ppuIO.ADDR                                    = data.PPUIO.ADDR or ppuIO.ADDR
        ppuIO.DATA                                    = data.PPUIO.DATA or ppuIO.DATA
        ppuIO.OAMDMA                                  = data.PPUIO.OAMDMA or ppuIO.OAMDMA
        ppuIO.NMIArmed                                = data.PPUIO.NMIArmed or false
        ppuIO.delayPPU                                = data.PPUIO.delayPPU or 0
        if ppuBus.LoadSaveState then ppuBus.LoadSaveState(data.PPUIO.Bus) end
    end
    if data.LOOPY then
        loopy.ppuStates          = data.LOOPY.ppuStates or loopy.ppuStates
        loopy:RestoreScroll(data.LOOPY)
        loopy.drawScreen         = data.LOOPY.drawScreen
        loopy.drawSprites        = data.LOOPY.drawSprites
        loopy.scanLine           = data.LOOPY.scanLine or loopy.scanLine
        loopy.scanLinePixels     = data.LOOPY.scanLinePixels or loopy.scanLinePixels
        loopy.inVBlank           = data.LOOPY.inVBlank or false
    end
    -- Force CHR cache refresh after restoring mapper bank registers
    activeMapper.chrDirty = true

    ppu.clearPPUStates()
    ppu.savePPUStates(0)
    ppu.StartGameWindow()
    G_SkipFrameAfterStateLoad = true
end


function saveState.Load(key)
    local basename = string.gsub(GlobalFileName, "%.nes$", "") -- remove the file extension
    basename = string.gsub(basename, "^.*[/\\]", "") -- remove the directory path
    local new_file_path = LoveFileDir.."RomSaves/"..basename..(key-6)..".save"
    local condition, data = saveState.LoadFile(new_file_path)
    if condition then
        Initialize(GlobalFileName)
        love.timer.sleep(.1)
        Merge(data)
        love.timer.sleep(.2)
        print("File Loaded PC ", cpuMemory.stackPointer  , string.format("%x",cpuMemory.programCounter))
        love.timer.sleep(.1)
    else
        print("No Save File Found ")
    end
end

return saveState
