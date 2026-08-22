local cart      = require("NES.Cartridge.Cartridge")
local mapper    = require("NES.Cartridge.Mappers")
local nameTable = require("NES.PPU.ppunametable")
local loopy     = require("NES.PPU.loopy")
local OAM       = require("NES.PPU.ppuOAM")
local ppuIO     = require("NES.PPU.ppuIO")
local ppuBus = {}

local debugPPU = false
local debugPPU2005 = false
local debugPPU2006 = false
local debugPPU2000 = false

local ppu_data_buffer = 0x00
local vRamAddress = 0x00

function ppuBus.Reset()
    ppu_data_buffer = 0x00
    vRamAddress = 0x00

    for tableIndex = 0, 1 do
        for i = 0, 0x03FF do
            nameTable.tblName[tableIndex][i] = 0x00
        end
    end
    for i = 0, 0x1F do
        nameTable.tblPalette[i] = 0x00
    end
    OAM.Clear()
end

local CPURegisters = {
    readHandlers = {
        [0x0000] = function () return 0x00 end, -- control
        [0x0001] = function () return 0x00 end, -- mask
        [0x0002] = function ()                  -- status       
            local data = bit.bor(bit.band(ppuIO.STATUS,0xE0),bit.band(ppu_data_buffer,0x1F))
            loopy:ResetWriteToggle()
            ppuIO.STATUS = bit.band(ppuIO.STATUS,0x7F)
            return data end,
        [0x0003] = function () return 0x00 end, -- OAM address
        [0x0004] = function () return 0x00 end, -- OAM Data
        [0x0005] = function () return 0x00 end, -- Scroll
        [0x0006] = function () return 0x00 end, -- PPU Address
        [0x0007] = function () -- Delay Output from PPU one Read so store it then give it the next read
            local data = ppu_data_buffer
            ppu_data_buffer = ppuBus.PPURead(loopy.v)
            -- but if its palette data send right away
            if loopy.v >= 0x3F00 then data = ppu_data_buffer end
            -- update Pointer location         
            if ppuIO.IsBitSet(ppuIO.CTRL, 2) then
                loopy:IncrementV(32)
            else
                loopy:IncrementV(1)
            end
            if false then print("Read PPU 2007 and data ", data, ppu_data_buffer, loopy.register_vram_addr, ppuIO.IsBitSet(ppuIO.CTRL, 2)) end
            
            return data
        end,
    },
    writeHandlers = {
        [0x0000] = function (addr, data)
            local oldCTRL = ppuIO.CTRL
            ppuIO.CTRL = data
            if debugPPU then print("cpuWrite in "..data.." current status " ..  ppuIO.STATUS.." current CTRL".. ppuIO.CTRL) end
            --ppuIO.CTRL = bit.bor(ppuIO.CTRL, 0x80) -- Reset NMI Flag
            if bit.band(data, 0x80) == 0x80 and bit.band(oldCTRL, 0x80) ~= 0x80 and ppuIO.STATUS >= 0x80 then
                ppuIO.NMIArmed = true
            end
            ppuIO.NameTableAddress = bit.band(data, 0x03)
            ppuIO.BackgroundTable = bit.band(data, 0x10) ~= 0 and 1 or 0
            ppuIO.SpriteTable = bit.band(data, 0x08) ~= 0 and 1 or 0
            loopy:WriteControl(data)
            if loopy.scanLine < 242  then loopy:SearchPPUStatesInRangeAndReplace( loopy.scanLine -1, loopy.scanLine +1, require("NES.PPU.ppu").GetPPUState(loopy.scanLine)) end
            if debugPPU2000 then print(string.format("%i, Write PPU 2000 nameX:%x nameY:%x BackGroundTable:%x SpriteTable:%x",
                loopy.scanLine, loopy.nametable_x, loopy.nametable_y, ppuIO.BackgroundTable, ppuIO.SpriteTable)) end
            return nil
        end, -- control
        [0x0001] = function (addr, data) 
            ppuIO.MASKS = data
            loopy.drawScreen = bit.band(data, 0x08) ~= 0 and true or false
            loopy.drawSprites = bit.band(data, 0x10) ~= 0 and true or false
            --print(loopy.drawScreen, loopy.drawSprites)
            if debugPPU then print(string.format("Write PPU 2001 %x %x", addr, data)) end
            return nil
        end, -- mask
        [0x0002] = function (addr, data)
            loopy:ResetWriteToggle()
            if debugPPU then print(string.format("Write PPU 2002 %x %x", addr, data)) end
            return nil
        end, -- status
        [0x0003] = function (addr, data) 
            ppuIO.OAMADDR = data
            if debugPPU then print(string.format("Write PPU 2003 %x %x", addr, data)) end
            return nil
        end, -- OAM address
        [0x0004] = function (addr, data)
            OAM.WriteToOAM(ppuIO, data)
            if debugPPU then print(string.format("Write PPU 2004 %x %x", addr, data)) end
            return nil
        end, -- OAM Data
        [0x0005] = function (addr, data)
            if loopy.w == 0 then
                loopy:WriteScroll(data)
                if debugPPU2005 then print(string.format("%i, Write PPU 2005.1 fineX:%x courseX:%x data %x ",
                    loopy.scanLine, loopy.fine_x, loopy.course_x, data)) end
            else
                loopy:WriteScroll(data)
                -- Tigger Save State 
    --print("2005 " .. loopy.scanLine, loopy.register_vram_addr)
                if loopy.scanLine > 0 and loopy.scanLine < 242  then loopy:SearchPPUStatesInRangeAndReplace( loopy.scanLine  -1, loopy.scanLine +1, require("NES.PPU.ppu").GetPPUState(loopy.scanLine)) end
                if debugPPU2005 and loopy.scanLine > 240 then
                    print(string.format("%i, Write PPU 2005.2 fineY:%x courseY:%x data %x",
                        loopy.scanLine, loopy.fine_y, loopy.course_y, data))
                elseif debugPPU2005 and loopy.scanLine <= 240 then
                    print(string.format("%i, Write PPU 2005.2 Not Changed fineY:%x courseY:%x data %x",
                        loopy.scanLine, loopy.fine_y, loopy.course_y, data)) end
            end
            return nil
        end, -- Scroll
        [0x0006] = function (addr, data)
            if loopy.w == 0 then
                loopy:WriteAddress(data)
                
                if debugPPU2006 then print(string.format("%i, Write PPU 2006.1 nameX:%x nameY:%x trimaddr %x data %x pointer:%04x",
                    loopy.scanLine, bit.rshift(bit.band(loopy.t, 0x0400), 10), bit.rshift(bit.band(loopy.t, 0x0800), 11), loopy.t, data, loopy.v)) end
            else
                loopy:WriteAddress(data)
    --print(" 2006 " .. loopy.scanLine, offsetY, loopy.register_vram_addr)
                local splitCoarseY = bit.rshift(bit.band(loopy.v, 0x03E0), 5)
                if loopy.scanLine < 242  then loopy:SearchPPUStatesInRangeAndReplace( loopy.scanLine -1 , loopy.scanLine +1, require("NES.PPU.ppu").GetPPUState(loopy.scanLine, splitCoarseY, true)) end
                if debugPPU2006 then print(string.format("%i, Write PPU 2006.2 nameX:%x nameY:%x trimaddr %x data %x pointer:%04x",
                    loopy.scanLine, loopy.nametable_x, loopy.nametable_y, loopy.t, data, loopy.v)) end
            end
            --print(string.format("PPU %x %x", addr, data))
            return nil
        end, -- PPU Address
        [0x0007] = function (addr, data)
            ppuBus.PPUWrite(loopy.v, data)
            if ppuIO.IsBitSet(ppuIO.CTRL, 2) then
                loopy:IncrementV(32)
            else
                loopy:IncrementV(1)
            end
            if false then print(string.format("Write PPU 2007 %x, %x, %x, %s", addr, data, loopy.register_vram_addr ,tostring(ppuIO.IsBitSet(ppuIO.CTRL, 2)))) end
            return nil
        end, -- PPU Data
        [0x4014] = function (addr, data) OAM.RefreshOAM(data, ppuIO.OAMADDR) end, -- DMA
    },
}

function ppuBus.CPURead(addr)
    if CPURegisters.readHandlers[addr] then
        return CPURegisters.readHandlers[addr]()
    end
    print("PPU Read Error " .. addr)
    return 0x00
end

function ppuBus.CPUWrite(addr, data)
    if CPURegisters.writeHandlers[addr] then
        CPURegisters.writeHandlers[addr](addr, data)
    end
    return nil
end

-- PPU Own Bus .. NOT FOR 2000-2007 Those are Mapped on the CPU to stored in internal registers location in PPU 
-- This is written out as is faster 
-- Optimize PPURead first
local band = bit.band
local nameTableRead = nameTable.NameTableMirrorRead
local tblPalette = nameTable.tblPalette
function ppuBus.PPURead(addr)
    if addr > 0x3FFF then
        addr = band(addr, 0x3FFF)
    end
    
    -- Use lookup table for address ranges
    if addr <= 0x1FFF then
        return mapper[cart.mapper].mapper.PPURead(addr)
    elseif addr <= 0x3EFF then
        return nameTableRead(addr)
    else -- Palette range (0x3F00-0x3FFF)
        return tblPalette[ addr - 0x3F00 ]
    end
end


    -- Speed 
    function ppuBus.PPUWrite(addr, data)
    -- Mirrors 0x0 - 0x3FFF
        addr = bit.band(addr, 0x3FFF)
        local cartMapper = mapper[cart.mapper].mapper
    -- Pattern Tables CHR ROM
        if addr >= 0x0000 and addr <= 0x1FFF then
            cartMapper.PPUWrite(addr,data)
            return data
    -- Access internal NameTable Memory VRAM
        elseif addr >= 0x2000 and addr <= 0x3EFF then
                return nameTable.NameTableMirrorWrite(addr, data)
    -- Palette Memory Palette 
        elseif addr >= 0x3F00 and addr <= 0x3FFF then
            addr = bit.band(addr,0x001F)
            if addr == 0x0010 then addr = 0x0000 end
            if addr == 0x0014 then addr = 0x0004 end
            if addr == 0x0018 then addr = 0x0008 end
            if addr == 0x001C then addr = 0x000C end
            nameTable.tblPalette[addr] = data
            return
        else
            print(string.format("PPU Error Write Memory %x %x", addr, data))
        end
    end

-- Function Return Buffer 
    function ppuBus.ppuBuffer(startAddress, stopAddress)
        local Buffer = {}
        for i = startAddress,stopAddress do
            Buffer[i] = ppuBus.PPURead(i)
        end
        return Buffer
    end

    function ppuBus.ppuScanLineUpdate(scanLines)
        if cart.mapper == 4 then
            mapper[cart.mapper].mapper.ScanLineUpdate(scanLines)
        end
    end

    function ppuBus.GetSaveState()
        return {
            ppu_data_buffer = ppu_data_buffer,
            vRamAddress = vRamAddress
        }
    end

    function ppuBus.LoadSaveState(state)
        if not state then return end
        ppu_data_buffer = state.ppu_data_buffer or 0x00
        vRamAddress = state.vRamAddress or 0x00
    end
return ppuBus
