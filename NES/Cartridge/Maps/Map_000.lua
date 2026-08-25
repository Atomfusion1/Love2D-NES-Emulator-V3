local cart = require("NES.Cartridge.Cartridge")

local mapper = {}
mapper.version = 0x00
mapper.chrDirty = true
local CHRoffset = nil
local functionRead = nil
local ROM = nil

function mapper.CPURead(addr)
    return functionRead and (functionRead(addr) or 0) or 0
end

function mapper.CPUWrite(addr, value)

end


    -- Character Memory 
function mapper.PPURead(addr)
    return ROM[addr + CHRoffset]
end

function mapper.PPUWrite(addr, value)

end

function mapper.INI()
    cart.Mirror = bit.band(cart.header[0x06], 0x01) == 1 and 1 or 0
    -- 0 - Horizontal Mirror
    -- 1 - Vertical Mirror
    print("mirror "..cart.Mirror)
    print("mapper initialized Mirror State "..cart.Mirror)
    CHRoffset = cart.header[0x04]*0x4000 + 0x0010 -- offset for header added back on 
    ROM = cart.ROM
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
