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
local ppu_io_latch = 0x00
local vRamAddress = 0x00

local function readOAMData()
    local address = bit.band(ppuIO.OAMADDR or 0, 0xFF)
    local data = OAM[address] or 0x00

    -- Byte 2 of each sprite is the attribute byte.  The internal OAM data
    -- bus does not expose the unused attribute bits, so they read as zero.
    if bit.band(address, 0x03) == 0x02 then
        data = bit.band(data, 0xE3)
    end

    -- Reading OAMDATA does not increment OAMADDR.  Reads performed while
    -- the PPU is actively clearing/evaluating secondary OAM need the
    -- dot-level evaluation bus and are intentionally left for that model.
    return data
end

function ppuBus.Reset()
    ppu_data_buffer = 0x00
    ppu_io_latch = 0x00
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
        [0x0000] = function () return ppu_io_latch end, -- control (write-only/open bus)
        [0x0001] = function () return ppu_io_latch end, -- mask (write-only/open bus)
        [0x0002] = function ()                  -- status       
            local data = bit.bor(bit.band(ppuIO.STATUS,0xE0),bit.band(ppu_io_latch,0x1F))
            loopy:ResetWriteToggle()
            ppuIO.STATUS = bit.band(ppuIO.STATUS,0x7F)
            return data end,
        [0x0003] = function () return ppu_io_latch end, -- OAM address (write-only/open bus)
        [0x0004] = readOAMData, -- OAM Data
        [0x0005] = function () return ppu_io_latch end, -- Scroll (write-only/open bus)
        [0x0006] = function () return ppu_io_latch end, -- PPU Address (write-only/open bus)
        [0x0007] = function () -- PPUDATA read buffer
            local address = bit.band(loopy.v, 0x3FFF)
            local data

            if address >= 0x3F00 then
                -- Palette RAM bypasses the delayed return.  Its upper two
                -- result bits are open bus, while the hidden read performed
                -- at the same time refills the buffer from the mirrored
                -- nametable underneath the palette range.
                local paletteData = ppuBus.PPURead(address)
                data = bit.bor(bit.band(ppu_io_latch, 0xC0), bit.band(paletteData, 0x3F))
                ppu_data_buffer = ppuBus.PPURead(address - 0x1000)
            else
                data = ppu_data_buffer
                ppu_data_buffer = ppuBus.PPURead(address)
            end

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
            if loopy.scanLine < 242  then loopy:SearchPPUStatesInRangeAndReplace( loopy.scanLine -1, loopy.scanLine +1, require("NES.PPU.ppu").GetPPUState(loopy.scanLine, nil, nil, "$2000")) end
            if debugPPU2000 then print(string.format("%i, Write PPU 2000 nameX:%x nameY:%x BackGroundTable:%x SpriteTable:%x",
                loopy.scanLine, loopy.nametable_x, loopy.nametable_y, ppuIO.BackgroundTable, ppuIO.SpriteTable)) end
            return nil
        end, -- control
        [0x0001] = function (addr, data) 
            local oldMask = ppuIO.MASKS
            ppuIO.MASKS = data
            loopy.drawScreen = bit.band(data, 0x08) ~= 0 and true or false
            loopy.drawSprites = bit.band(data, 0x10) ~= 0 and true or false
            -- Save a scanline state only when background rendering changes.
            -- Sprite-only $2001 changes are handled by sprite evaluation and
            -- must not replace the background scroll state for the scanline.
            if loopy.scanLine < 242
                and bit.band(oldMask, 0x08) ~= bit.band(data, 0x08) then
                loopy:SearchPPUStatesInRangeAndReplace(
                    loopy.scanLine - 1,
                    loopy.scanLine + 1,
                    require("NES.PPU.ppu").GetPPUState(loopy.scanLine, nil, nil, "$2001")
                )
            end
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
                if loopy.scanLine > 0 and loopy.scanLine < 242  then loopy:SearchPPUStatesInRangeAndReplace( loopy.scanLine  -1, loopy.scanLine +1, require("NES.PPU.ppu").GetPPUState(loopy.scanLine, nil, nil, "$2005")) end
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
                if loopy.scanLine < 242  then loopy:SearchPPUStatesInRangeAndReplace( loopy.scanLine -1 , loopy.scanLine +1, require("NES.PPU.ppu").GetPPUState(loopy.scanLine, splitCoarseY, true, "$2006")) end
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
        -- $4014 is queued by NES.BUS.bus so the CPU can apply the DMA stall
        -- after the writing instruction completes.
    },
}

function ppuBus.CPURead(addr)
    if CPURegisters.readHandlers[addr] then
        local data = bit.band(CPURegisters.readHandlers[addr]() or 0, 0xFF)
        ppu_io_latch = data
        return data
    end
    print("PPU Read Error " .. addr)
    return 0x00
end

-- Side-effect-free debugger read for the CPU-visible PPU registers.
-- Normal CPURead must retain hardware behavior (for example $2002 clears
-- status and $2007 advances VRAM), so the memory viewer must not use it.
function ppuBus.CPUPeek(addr)
    if addr == 0x0000 then return ppu_io_latch
    elseif addr == 0x0001 then return ppu_io_latch
    elseif addr == 0x0002 then return ppuIO.STATUS
    elseif addr == 0x0003 then return ppu_io_latch
    elseif addr == 0x0004 then return readOAMData()
    elseif addr == 0x0005 then return ppu_io_latch
    elseif addr == 0x0006 then return ppu_io_latch
    elseif addr == 0x0007 then return ppuIO.DATA
    end
    return 0
end

function ppuBus.CPUWrite(addr, data)
    ppu_io_latch = bit.band(data or 0, 0xFF)
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
        local paletteAddress = band(addr - 0x3F00, 0x1F)
        -- The four sprite-palette color-zero entries mirror the universal
        -- background entries in palette RAM.
        if paletteAddress == 0x10 then paletteAddress = 0x00 end
        if paletteAddress == 0x14 then paletteAddress = 0x04 end
        if paletteAddress == 0x18 then paletteAddress = 0x08 end
        if paletteAddress == 0x1C then paletteAddress = 0x0C end
        local value = bit.band(tblPalette[paletteAddress] or 0, 0x3F)
        -- Greyscale affects the value presented by palette RAM, not the
        -- value stored there.  Only the luminance column remains visible.
        if bit.band(ppuIO.MASKS, 0x01) ~= 0 then
            value = bit.band(value, 0x30)
        end
        return value
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
            -- Palette RAM contains six data bits.  Greyscale mode masks
            -- reads/output only and must not modify writes.
            nameTable.tblPalette[addr] = bit.band(data, 0x3F)
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
