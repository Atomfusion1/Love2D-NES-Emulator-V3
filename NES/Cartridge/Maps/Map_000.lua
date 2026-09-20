local cart = require("NES.Cartridge.Cartridge")

local mapper = {}
mapper.version = 0x00
mapper.chrDirty = true
mapper.chrRAM = {}
local CHRoffset = nil
local functionRead = nil
local ROM = nil

for i = 0, 0x1FFF do
    mapper.chrRAM[i] = 0x00
end

function mapper.CPURead(addr)
    return functionRead and (functionRead(addr) or 0) or 0
end

function mapper.CPUWrite(addr, value)

end


    -- Character Memory 
function mapper.PPURead(addr)
    if cart.header[0x05] == 0 then
        return mapper.chrRAM[addr] or 0x00
    end
    return ROM[addr + CHRoffset]
end

function mapper.PPUWrite(addr, value)
    if cart.header[0x05] == 0 and addr >= 0x0000 and addr <= 0x1FFF then
        mapper.chrRAM[addr] = bit.band(value or 0, 0xFF)
        mapper.chrDirty = true
    end
end

function mapper.GetSaveState()
    return { chrRAM = mapper.chrRAM }
end

function mapper.LoadSaveState(state)
    if state and state.chrRAM then mapper.chrRAM = state.chrRAM end
    mapper.chrDirty = true
end

function mapper.INI()
    cart.Mirror = bit.band(cart.header[0x06], 0x01) == 1 and 1 or 0
    -- 0 - Horizontal Mirror
    -- 1 - Vertical Mirror
    print("mirror "..cart.Mirror)
    print("mapper initialized Mirror State "..cart.Mirror)
    CHRoffset = cart.header[0x04]*0x4000 + 0x0010 -- offset for header added back on 
    ROM = cart.ROM
    for i = 0, 0x1FFF do
        mapper.chrRAM[i] = 0x00
    end
    mapper.chrDirty = true
    local prgBanks = cart.header[0x04] or 1
    functionRead = function(addr)
        -- $4020-$5FFF is cartridge expansion space and $6000-$7FFF is
        -- optional PRG-RAM. Mapper 0 cartridges without PRG-RAM read as zero.
        if addr < 0x8000 or addr > 0xFFFF then return 0 end
        local offset = addr - 0x8000
        if prgBanks == 1 then
            offset = bit.band(offset, 0x3FFF) -- mirror the 16 KiB PRG bank
        end
        return ROM[offset + 0x0010] or 0
    end
end

return mapper
