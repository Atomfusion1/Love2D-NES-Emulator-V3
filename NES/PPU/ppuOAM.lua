local bit = bit
local ppu = {
    OAM = {}
}

-- Sprite OAM Memory PPU Internal Tables - initialize to 0xF8 (off-screen sprites)
for i = 0x00, 0xFF do
    ppu.OAM[i] = 0xF8
end

function ppu.OAM.DMAWrite(data, address)
    ppu.OAM[bit.band(address, 0xFF)] = bit.band(data or 0, 0xFF)
end

function ppu.OAM.RefreshOAM(data, oamAddr, readByte)
    -- DMA transfer from the CPU bus. The callback keeps this module
    -- independent of the CPU bus and allows mapper-backed source pages.
    -- data: CPU page ($0200 = 0x02)
    -- oamAddr: destination offset in OAM (OAMADDR)
    local sourceAddress = bit.lshift(data, 8)
    oamAddr = oamAddr or 0

    for i = 0, 255 do
        local value = readByte(sourceAddress + i)
        ppu.OAM.DMAWrite(value, oamAddr + i)
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
