local opcodeTable   = require("NES.CPU.opcodes.opcodeTable")
local cpuInternal   = require("NES.CPU.cpuInternal")
local cart          = require("NES.Cartridge.Cartridge")
local ppu           = require("NES.PPU.ppu")
local ppuIO         = require("NES.PPU.ppuIO")
local bus           = require("NES.BUS.bus")
local addressMode   = require("NES.CPU.opcodes.addressmodes")
local apu           = require("NES.Audio.apu")
local loopy         = require("NES.PPU.loopy")
local displayTimer  = require("Includes.displaytimer")

-- # 6502 CPU
local cpu         = {}
local rshift, band, bor = bit.rshift, bit.band, bit.bor
local CPURead = bus.CPURead
local debugCPU = false
cpu.drawFrame = false
cpu.totalCycles = 4

function cpu.Initialize(startPCAt)
    cpu.totalCycles = 7
    cpu.drawFrame = false
    cpuInternal.A              = 0x00
    cpuInternal.X              = 0x00
    cpuInternal.Y              = 0x00
    cpuInternal.stackPointer   = 0xFD
    cpuInternal.statusRegister = 0x24
    cpuInternal.info.cycle     = 7
    cpuInternal.info.execute   = 5
    --memory.Initialize(0x00)
    print("CPU Initialized")
    print(CPURead(0xfffb))
    print(CPURead(0xFFFA))
    cpuInternal.NMIInterrupt   =  CPURead(0xFFFA) + CPURead(0xFFFB) * 256
    -- Change Startup for Debug nesTest
    if startPCAt then
        cpuInternal.programCounter = startPCAt
    else
        cpuInternal.resetInterrupt = CPURead(0xFFFC) + CPURead(0xFFFD) * 256
        cpuInternal.programCounter = cpuInternal.resetInterrupt
        print(string.format("CPU ini %x",cpuInternal.programCounter))
    end
    cpuInternal.BRKInterrupt =  CPURead(0xFFFE) + CPURead(0xFFFF) * 256

    cpuInternal.CHRLocation  = cart.header[0x04] * 0x4000 + 0x010 -- offset Header
    
    -- Initialize interrupt trigger flags
    cpuInternal.TriggerNMI = false
    cpuInternal.TriggerIRQ = false
    cpuInternal.StartNMI = false
    cpuInternal.StartBreak = false
    cpuInternal.StartReset = false

    print(string.format("NMI:%x, PC:%x, BRK:%x, CHRLocation:%x CartMapper:%x", cpuInternal.NMIInterrupt, cpuInternal.programCounter,
        cpuInternal.BRKInterrupt, cpuInternal.CHRLocation, cart.mapper))
    print("CPU Initialized")

end

-- # Interrupt BRK
local function DoBRK()
    --print("*BRK Trigger")
    -- Store Highbyte current Stack + 2 (return address after BRK)
    addressMode.WriteToStack(rshift(cpuInternal.programCounter + 2, 8))
    -- Store Lowbyte current Stack + 2
    addressMode.WriteToStack(band(cpuInternal.programCounter + 2, 0xFF))
    -- Processor Status To Stack (with B and unused bit set to 1)
    addressMode.WriteToStack(bor(cpuInternal.statusRegister, 0x30))
    
    -- Set interrupt disable flag
    cpuInternal.statusRegister = bor(cpuInternal.statusRegister, 0x04)
    
    -- Jump to BRK vector
    cpuInternal.programCounter = cpuInternal.BRKInterrupt
    
    -- Return cycle cost (7 cycles for BRK)
    return 7
end

-- # Interrupt NMI
function cpu.DoNMI()
    --print("*NMI Trigger")
    cpuInternal.TriggerNMI = false
    
    -- Store program counter to stack
    addressMode.WriteToStack(rshift(cpuInternal.programCounter, 8))
    addressMode.WriteToStack(band(cpuInternal.programCounter, 0xFF))
    
    -- Hardware interrupt: B=0 (clear bit 4), unused bit=1 (set bit 5)
    addressMode.WriteToStack(bor(band(cpuInternal.statusRegister, 0xEF), 0x20))
    
    -- Set interrupt disable flag (I flag)
    cpuInternal.statusRegister = bor(cpuInternal.statusRegister, 0x04)
    
    -- Jump to NMI vector
    cpuInternal.programCounter = CPURead(0xFFFA) + CPURead(0xFFFB) * 256
    
    -- Return cycle cost (7 cycles for NMI)
    return 7
end

-- # Interrupt IRQ
function cpu.DoIRQ()
    cpuInternal.TriggerIRQ = false
    --print("*IRQ Trigger", ppu.scanLines)
    
    -- Check if the I (Interrupt disable) flag is set
    if band(cpuInternal.statusRegister, 0x04) ~= 0 then
        return 0  -- Interrupts disabled, skip IRQ
    end
    
    ppu.savePPUStates(ppu.scanLines)
    
    -- Store program counter to stack
    addressMode.WriteToStack(rshift(cpuInternal.programCounter, 8))
    addressMode.WriteToStack(band(cpuInternal.programCounter, 0xFF))
    
    -- Hardware interrupt: B=0 (clear bit 4), unused bit=1 (set bit 5)
    addressMode.WriteToStack(bor(band(cpuInternal.statusRegister, 0xEF), 0x20))
    
    -- Set interrupt disable flag (I flag)
    cpuInternal.statusRegister = bor(cpuInternal.statusRegister, 0x04)
    
    -- Jump to IRQ vector
    cpuInternal.programCounter = CPURead(0xFFFE) + CPURead(0xFFFF) * 256
    
    -- Return cycle cost (7 cycles for IRQ)
    return 7
end

-- ! This needs to be As Fast As Possible .. with just Flags it takes 9000 microSeconds to complete .. You have 16600 micros per frame
-- ? The PPU should probably be done on a second thread
function cpu.ExecuteCycles(totalCycles)
    local cycleCount = 0
    local opcode, opTable, pcStep, cycleCost, results
    local ppuCycleDebt = 0  -- Batch PPU updates with threshold of 16
    
    -- Localize hot-path functions to avoid table lookups
    local PPUUpdate = ppu.Update
    local ExecuteOpcode = opcodeTable.Execute

    while totalCycles > cycleCount do
        -- Reset PPU with CPU
        if ppu.scanLines == -1 then
            ppu.scanLines = 0
            ppu.scanLinePixels = 0
            ppuIO.NMIArmed = true
            ppuIO.STATUS = 0x00
        end

        -- Handle interrupts (NMI, IRQ) and capture their cycle costs
        local interruptCycles = 0
        if cpuInternal.TriggerNMI then
            interruptCycles = cpu.DoNMI()
        elseif (cpuInternal.TriggerIRQ or bus.CheckIRQ()) and band(cpuInternal.statusRegister, 0x04) == 0 then
            cpuInternal.TriggerIRQ = false
            interruptCycles = cpu.DoIRQ()
        end
        
        -- If an interrupt was handled, add its cycles and skip normal opcode fetch
        if interruptCycles > 0 then
            cycleCount = cycleCount + interruptCycles
            cpu.totalCycles = cpu.totalCycles + interruptCycles
            ppuCycleDebt = ppuCycleDebt + interruptCycles
            
            if ppuCycleDebt >= 1024 then
                if not PPUUpdate(ppuCycleDebt) then
                    cpu.drawFrame = true
                    totalCycles = 0
                end
                ppuCycleDebt = 0
            end
        else
            -- No interrupt, fetch and execute normal opcode
            -- Check for breakpoints
            if UseBreakPoint and cpuInternal.programCounter == BreakPointValue then
                cycleCount = cpu.BreakPoint(BreakPointValue, totalCycles)
            end

            -- Fetch opcode
            opcode = CPURead(cpuInternal.programCounter)
            if opcode == 0x00 then  -- Handle BRK directly if opcode is 0x00
                cycleCost = DoBRK()
                pcStep = 0  -- PC already set to interrupt vector by DoBRK()
            else
                -- Execute normal opcode (using localized function)
                results, pcStep, cycleCost = ExecuteOpcode(opcode)
                cpuInternal.programCounter = band(cpuInternal.programCounter + pcStep, 0xFFFF)
            end

            -- Update cycle count and debug information
            cycleCount = cycleCount + cycleCost
            cpu.totalCycles = cpu.totalCycles + cycleCost
            ppuCycleDebt = ppuCycleDebt + cycleCost
            
            if addressMode.debugPrint then
                TraceLogger()
            end

            -- Batch PPU updates with threshold of 16 cycles
            if ppuCycleDebt >= 1 then
                local ppuEmuStart = PerformanceDetailEnabled and love.timer.getTime() or 0
                if not PPUUpdate(ppuCycleDebt) then
                    cpu.drawFrame = true
                    totalCycles = 0
                end
                if PerformanceDetailEnabled then
                    displayTimer.RecordComponent("ppuEmu", love.timer.getTime() - ppuEmuStart)
                end
                ppuCycleDebt = 0
            end
        end
    end
    

end
    

-- # Debugging
local file

-- Function to convert the status register to the desired format
local function FormatStatusRegister(status)
    local flags = ""
    flags = flags .. (bit.band(status, 0x80) ~= 0 and "N" or "n")
    flags = flags .. (bit.band(status, 0x40) ~= 0 and "V" or "v")
    flags = flags .. (bit.band(status, 0x20) ~= 0 and "U" or "u")
    flags = flags .. (bit.band(status, 0x10) ~= 0 and "B" or "b")
    flags = flags .. (bit.band(status, 0x08) ~= 0 and "D" or "d")
    flags = flags .. (bit.band(status, 0x04) ~= 0 and "I" or "i")
    flags = flags .. (bit.band(status, 0x02) ~= 0 and "Z" or "z")
    flags = flags .. (bit.band(status, 0x01) ~= 0 and "C" or "c")
    return flags
end

local function TraceString()
    -- Define the format string to match the desired output
    local currentOpcode = CPURead(cpuInternal.programCounter)
    local opcodeEntry = opcodeTable[currentOpcode]
    local mnemonic = (opcodeEntry and opcodeEntry.mnemonic) or "???"
    
    local string = string.format(
        "%04X   %s $%02X%02X = $%02X          A:%02X X:%02X Y:%02X S:%02X P:%s Fr:%d Cycle:%d \n",
        cpuInternal.programCounter, 
        mnemonic,
        CPURead(cpuInternal.programCounter+2), 
        CPURead(cpuInternal.programCounter+1), 
        CPURead(cpuInternal.programCounter+3),
        cpuInternal.A, 
        cpuInternal.X, 
        cpuInternal.Y, 
        cpuInternal.stackPointer, 
        FormatStatusRegister(cpuInternal.statusRegister),
        ppu.currentFrame, 
        cpu.totalCycles - 7
    )
    return string
end


--! This was a Quick Implimentation of the TraceLogger .. it needs to be reworked to be more efficient and less of a hack job
local recent_program_counters = {}
local max_pattern_size = 6
local skipped_lines = 0

--% TraceLogger Detect Patterns and Stop Printing them
local function detect_pattern(recentPC, maxSize)
    for pattern_length = 1, maxSize do
        local pattern_found = true
        for idx = 1, pattern_length do
            local base = recentPC[#recentPC - pattern_length + idx]
            local compare = recentPC[#recentPC - 2 * pattern_length + idx]
            if base ~= compare then
                pattern_found = false
                break
            end
        end
        if pattern_found then
            return true
        end
    end
    return false
end

--% Process and save Trace String
local function process_trace_string(trace_string, program_counter)
    table.insert(recent_program_counters, program_counter)
    if #recent_program_counters > 2 * max_pattern_size then
        table.remove(recent_program_counters, 1)
    end
    local pattern_found = false --detect_pattern(recent_program_counters, max_pattern_size)
    if pattern_found then
        skipped_lines = skipped_lines + 1
        return nil
    else
        local output_string = trace_string
        if skipped_lines > 0 then
            output_string = "(" .. skipped_lines .. " lines skipped)\n" .. trace_string
            skipped_lines = 0
        end
        return output_string
    end
end

--% TraceLogger Main Function
function TraceLogger()
    local trace_string = TraceString()
    local processed_string = process_trace_string(trace_string, cpuInternal.programCounter)
    if file then
        if processed_string then
            file:write(processed_string)
        else
            skipped_lines = skipped_lines + 1
        end
    else
        file = io.open(LoveFileDir.."Trace.log", "a")
        print("File Location : "..LoveFileDir.."Trace.log")
        if file then
            file:write("FCEUX 2.6.4 - Trace Log File")
        else
            print("Error: Unable to open the file.")
        end
    end
end

UseBreakPoint = false
BreakPointValue = 0x00
function cpu.BreakPoint(value, totalCycles)
    print("Breakpoint Hit Stopped At:"..value)
    return totalCycles
end

return cpu
