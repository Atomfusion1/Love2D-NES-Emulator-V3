local cart       = require("NES.Cartridge.Cartridge")
local mapper     = require("NES.Cartridge.Mappers")
local memory     = require("NES.CPU.cpuram")
local controller = require("NES.Controller.controller")
local ppuBus     = require("NES.PPU.ppuBus")
local ppuIO      = require("NES.PPU.ppuIO")
local apu        = require("NES.Audio.apu")
local cheats     = require("Emulator.cheats")

local rshift, band, bor = bit.rshift, bit.band, bit.bor

local bus        = {}
local pendingOAMDMA
local CPURAM = memory.cpuRAM
local cachedMapper
local cachedMapperCPURead
local cachedMapperCPUWrite
local cachedMapperCheckIRQ
-- CPU data-bus latch used by unmapped/open-bus reads.  Operand fetches and
-- ordinary mapped reads naturally update it; an open-bus read leaves it
-- unchanged, matching the 2A03 bus behavior.
local cpuOpenBus = 0x00

local function driveBus(value)
    value = band(value or 0, 0xFF)
    cpuOpenBus = value
    return value
end

-- OAM DMA is queued by the $4014 write and consumed by the CPU after the
-- instruction completes. Capture OAMADDR at request time.
function bus.TakeOAMDMARequest()
    local request = pendingOAMDMA
    pendingOAMDMA = nil
    return request
end

--# Initialize Mapper Cache
function bus.RefreshMapperCache()
    cachedMapper = mapper[cart.mapper] and mapper[cart.mapper].mapper or nil
    cachedMapperCPURead = cachedMapper and cachedMapper.CPURead or nil
    cachedMapperCPUWrite = cachedMapper and cachedMapper.CPUWrite or nil
    cachedMapperCheckIRQ = cachedMapper and cachedMapper.CheckIRQ or nil
end

--# CPU BUS READ 
function bus.CPURead(addr)
    local mapperRead = cachedMapperCPURead
    if not mapperRead then
        bus.RefreshMapperCache()
        mapperRead = cachedMapperCPURead
    end
--% Read Cartridge Prog Memory ROM
    if addr >= 0x4020 then
        -- $4020-$FFFF belongs to the cartridge.  In particular, many
        -- mappers expose PRG RAM at $6000-$7FFF, so this range must not be
        -- treated globally as open bus.  The mapper decides which portions
        -- are backed or unmapped.
        local value = mapperRead(addr)
        if cheats.romOverridesActive then value = cheats.OverrideROMRead(addr, value) end
        return driveBus(value)
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
    local mapperRead = cachedMapperCPURead
    if not mapperRead then
        bus.RefreshMapperCache()
        mapperRead = cachedMapperCPURead
    end
    if addr >= 0x4020 then
        local value = mapperRead(addr)
        if cheats.romOverridesActive then value = cheats.OverrideROMRead(addr, value) end
        return value
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
    local mapperWrite = cachedMapperCPUWrite
    if not mapperWrite then
        bus.RefreshMapperCache()
        mapperWrite = cachedMapperCPUWrite
    end
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
            pendingOAMDMA = {
                page = data,
                oamAddress = ppuIO.OAMADDR or 0
            }
        end
        -- APU pulse/triangle/noise and DMC registers.  The DMC control
        -- registers live at $4010-$4013 and must reach RegisterWrite even
        -- though they are outside the waveform register range.
        if addr >= 0x4000 and addr <= 0x4013 then
            apu.RegisterWrite(addr, data)
            if UseSound and addr <= 0x400F then apu.APUSound(addr, data) end
        end
        if addr == 0x4015 then
            apu.StatusHandle(addr,data)
        end
        if addr == 0x4017 then
            apu.FrameCounterWrite(data)
        end
    elseif addr >= 0x4020 and addr <= 0xFFFF then
        mapperWrite(addr, data)
    else
        print(string.format("CPU Error Write Memory %x %x", addr, data))
    end
end

--# Check IRQ 
function bus.CheckIRQ()
    if apu.CheckIRQ() then return true end
    if cachedMapperCheckIRQ then return cachedMapperCheckIRQ() end
    return false
end

-- Starter DMC reads use the normal CPU address map. Cycle stealing is added
-- later with the shared DMA scheduler.
apu.SetDMCReadCallback(bus.CPURead)

return bus

