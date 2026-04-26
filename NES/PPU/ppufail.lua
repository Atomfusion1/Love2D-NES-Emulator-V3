--[[
[0x0005] = function (addr, data)
    if scrollPPULatch == 0 then
        trimaddr = 0x00
        --t: ....... ...ABCDE <- d: ABCDE...
        trimaddr = bit.rshift(bit.band(data,0xF8), 3)
        --x:              FGH <- d: .....FGH
        loopy.fine_x = bit.band(data, 0x07)
        scrollPPULatch = 1
        if true then print(string.format("Write PPU 2005.1 fineX %x courseX %x nameY %x trimaddr %x data %x pointer:%04x", 
            scrollPPULatch, loopy.fine_x, loopy.course_x, trimaddr, data, loopy.register_vram_addr),loopy.scanLine) end
        --    print(loopy.scanLine, data, trimaddr)
    else
        --t: FGH..AB CDE..... <- d: ABCDEFGH
        local part1 = bit.lshift(bit.band(data, 0x07), 12)
        local part2 = bit.lshift(bit.band(data, 0xF8), 2)
        trimaddr = bit.bor(trimaddr, bit.bor(part1, part2))
--print(loopy.scanLine, data, part1, part2, trimaddr)
        --Combine the data from the second write with trimaddr
        -- Apply horizontal bits immediately
        if loopy.scanLine >= 241 then
            loopy.course_x = bit.band(trimaddr, 0x1F)
            loopy.course_y = bit.rshift(bit.band(trimaddr, 0x3E0),5)
            loopy.nametable_x = bit.rshift(bit.band(trimaddr,0x400), 10)
            loopy.nametable_y = bit.rshift(bit.band(trimaddr,0x800), 11)
            loopy.fine_y = bit.rshift(bit.band(trimaddr, 0x7000), 12)
        else
            loopy.course_x = bit.band(trimaddr, 0x00F8)
            loopy.nametable_x = bit.rshift(bit.band(trimaddr, 0x08),3)
        end
        scrollPPULatch = 0
        -- Tigger Save State 
--print("2005 " .. loopy.scanLine, loopy.register_vram_addr)
        if loopy.scanLine > 0 and loopy.scanLine < 242  then loopy:SearchPPUStatesInRangeAndReplace( loopy.scanLine  -1, loopy.scanLine +1, require("NES.PPU.ppu").GetPPUState(loopy.scanLine)) end
        if true then print(string.format("Write PPU 2005.2 fineY %x courseY %x nameY %x trimaddr %x data %x pointer:%04x", 
            scrollPPULatch, loopy.fine_y, loopy.course_y, trimaddr, data, loopy.register_vram_addr),loopy.scanLine) end
    end
    return nil
end, -- Scroll
[0x0006] = function (addr, data)
    if scrollPPULatch == 0 then
        trimaddr = 0x00
        trimaddr = bit.lshift(bit.band(data,0x3F),8)
        scrollPPULatch = 1
        --if loopy.scanLine < 242  then loopy:SearchPPUStatesInRangeAndReplace( loopy.scanLine -1 , loopy.scanLine +1, require("NES.PPU.ppu").GetPPUState(loopy.scanLine)) end
        if true then print(string.format("Write PPU 2006 latch %x nameX %x nameY %x trimaddr %x data %x pointer:%04x", 
            scrollPPULatch, loopy.nametable_x, loopy.nametable_y, trimaddr, data, loopy.register_vram_addr),loopy.scanLine) end
    else
        loopy.register_vram_addr = bit.bor(bit.band(trimaddr,0xFF00), data)
        loopy.course_x = bit.band(loopy.register_vram_addr, 0x1F)
        loopy.course_y = bit.rshift(bit.band(loopy.register_vram_addr, 0x3E0),5)
        loopy.nametable_x = bit.rshift(bit.band(loopy.register_vram_addr,0x400), 10)
        loopy.nametable_y = bit.rshift(bit.band(loopy.register_vram_addr,0x800), 11)
        loopy.fine_y = bit.rshift(bit.band(loopy.register_vram_addr, 0x7000), 12)
        scrollPPULatch = 0
        if true then print(string.format("Write PPU 2006 latch %x nameX %x nameY %x trimaddr %x data %x pointer:%04x", 
            scrollPPULatch, loopy.nametable_x, loopy.nametable_y, trimaddr, data, loopy.register_vram_addr),loopy.scanLine) end
    end
    --print(string.format("PPU %x %x", addr, data))
    return nil
end, -- PPU Address
]]