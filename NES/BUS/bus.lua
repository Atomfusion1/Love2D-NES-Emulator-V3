local cart       = require("NES.Cartridge.Cartridge")
local mapper     = require("NES.Cartridge.Mappers")
local memory     = require("NES.CPU.cpuram")
local controller = require("NES.Controller.controller")
local ppuBus     = require("NES.PPU.ppuBus")
local apu        = require("NES.Audio.apu")

local rshift, band, bor = bit.rshift, bit.band, bit.bor

local bus        = {}
-- CPU data-bus latch used by unmapped/open-bus reads.  Operand fetches and
-- ordinary mapped reads naturally update it; an open-bus read leaves it
-- unchanged, matching the 2A03 bus behavior.
local cpuOpenBus = 0x00

local function driveBus(value)
    value = band(value or 0, 0xFF)
    cpuOpenBus = value
    return value
end

--# Initialize Mapper Cache
function bus.RefreshMapperCache()

end

--# CPU BUS READ 
function bus.CPURead(addr)
    local CPURAM = memory.cpuRAM
    local cartMapper = mapper[cart.mapper].mapper
    local CPURead = cartMapper.CPURead
--% Read Cartridge Prog Memory ROM
    if addr >= 0x4020 then
        -- $4020-$FFFF belongs to the cartridge.  In particular, many
        -- mappers expose PRG RAM at $6000-$7FFF, so this range must not be
        -- treated globally as open bus.  The mapper decides which portions
        -- are backed or unmapped.
        return driveBus(CPURead(addr))
--% Read Internal CPU RAM
    elseif addr < 0x2000 then
        local cpuRAMIndex    = band(addr, 0x07ff)
        return driveBus(CPURAM[cpuRAMIndex])
--% Read PPU Registers Directly 
    elseif addr >= 0x2000 and addr <= 0x3FFF then
        addr = band(addr, 0x0007)
        return driveBus(ppuBus.CPURead(addr))
--% Other CPU Reads (Controller Sound etc)
    elseif addr >= 0x4000 and addr <= 0x401f then
        if addr == 0x4016 or addr == 0x4017 then
            local previousByte = 0x40;
            local controllerData =  controller.ReadState(addr) -- This function reads the raw controller data.
            controllerData = bit.bor(bit.band(controllerData, 0x1F), previousByte) -- Keep the top 3 bits of the previous byte (0x40) and combine with the bottom 5 bits of the current byte.
            --print(string.format("%x", addr), controllerData)
            return driveBus(controllerData)
        end
        if addr == 0x4015 then
            --print("Read Status Length ")
            -- Channel bits are synthesized here; the upper status bits are
            -- open-bus bits unless an APU source drives them.
            return driveBus(bor(band(cpuOpenBus, 0xA0), apu.StatusRead()))
        end
        return cpuOpenBus
    else
        print(string.format("CPU Error Read not Mapped %x", addr))
        return cpuOpenBus
    end
end

-- Debugger-only CPU read that never invokes register read side effects.
function bus.CPUPeek(addr)
    local CPURAM = memory.cpuRAM
    local cartMapper = mapper[cart.mapper].mapper
    if addr >= 0x4020 then
        return cartMapper.CPURead(addr)
    elseif addr < 0x2000 then
        return CPURAM[band(addr, 0x07ff)]
    elseif addr >= 0x2000 and addr <= 0x3FFF then
        return ppuBus.CPUPeek(band(addr, 0x0007))
    elseif addr >= 0x4000 and addr <= 0x401F then
        if addr == 0x4015 then return 0x0F end
        return 0
    end
    return 0
end

--# CPU BUS WRITE
function bus.CPUWrite(addr, data)
    local CPUWrite = ppuBus.CPUWrite
    local CPURAM = memory.cpuRAM
    local cartMapper = mapper[cart.mapper].mapper
    local UseSound = UseSound
    data = band(data or 0, 0xFF)
    -- A CPU write drives the data bus even when the target is not mapped.
    cpuOpenBus = data
--% Write to Internal RAM
    if addr <= 0x1FFF then
        CPURAM[band(addr, 0x07ff)] = data
        return
--% Write to PPU Registers Directly 
    elseif addr >= 0x2000 and addr <= 0x3FFF then
        addr = band(addr, 0x0007)
        CPUWrite(addr, data)
--% Write to Controllers or Other (Sound)
    elseif addr >= 0x4000 and addr <= 0x401f then
        -- Controllers (only $4016 is controller strobe; $4017 is APU frame counter)
        if addr == 0x4016 then
            controller.GetState(addr, data)
            return
        end
        if addr == 0x4014 then
            ppuBus.CPUWrite(addr, data)
        end
        if addr >= 0x4000 and addr <= 0x400F then
            apu.RegisterWrite(addr, data)
            if UseSound then apu.APUSound(addr, data) end
        end
        if addr == 0x4015 then
            apu.StatusHandle(addr,data)
        end
        if addr == 0x4017 then
            apu.FrameCounterWrite(data)
        end
    elseif addr >= 0x4020 and addr <= 0xFFFF then
        cartMapper.CPUWrite(addr, data)
    else
        print(string.format("CPU Error Write Memory %x %x", addr, data))
    end
end

--# Check IRQ 
function bus.CheckIRQ()
    if apu.CheckIRQ() then return true end
    if cart.mapper == 4 then
        return mapper[cart.mapper].mapper.CheckIRQ()
    end
end

return bus

