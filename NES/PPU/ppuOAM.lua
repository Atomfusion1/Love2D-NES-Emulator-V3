local memory     = require("NES.CPU.cpuram")

local bit = bit
local ppu = {
    OAM = {}
}

-- Sprite OAM Memory PPU Internal Tables - initialize to 0xF8 (off-screen sprites)
for i = 0x00, 0xFF do
    ppu.OAM[i] = 0xF8
end

function ppu.OAM.RefreshOAM(data, oamAddr)
    -- DMA transfer from CPU RAM to OAM
    -- data: CPU page ($0200 = 0x02)
    -- oamAddr: destination offset in OAM (OAMADDR)
    local sourceAddress = bit.lshift(data, 8)
    oamAddr = oamAddr or 0

    for i = 0, 255 do
        -- Source always from CPU RAM page (with 0x0800 mirror wrap)
        local sourceIndex = bit.band(sourceAddress + i, 0x07FF)
        -- Destination in OAM, wrapping at 256
        local destIndex = bit.band(oamAddr + i, 0xFF)

        ppu.OAM[destIndex] = memory.cpuRAM[sourceIndex] or 0x00
    end
end

function ppu.OAM.Clear(data)
    for i = 0, 255 do
        ppu.OAM[i] = 0xF8
    end
end

function ppu.OAM.WriteToOAM(OAM, data)
    ppu.OAM[OAM.OAMADDR] = data
    OAM.OAMADDR = bit.band(OAM.OAMADDR + 1, 0xFF)
end

return ppu.OAM