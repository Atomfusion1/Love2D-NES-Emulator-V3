local cpuMemory   = require("NES.CPU.cpuInternal")
local cpu         = require("NES.CPU.cpuram")
local bus         = require("NES.BUS.bus")
local ppuBus      = require("NES.PPU.ppuBus")
local opcode      = require("NES.CPU.opcodes.opcodeTable")
local memory      = require("NES.CPU.cpuram")
local ppu         = require("NES.PPU.ppu")
local oam         = require("NES.PPU.ppuOAM")
local loopy       = require("NES.PPU.loopy")

local testing = {}
local holdingString = {}
-- Debug section toggles
local showCPUKeys = true
local showPPUKeys = true
local showSaveLoadKeys = true
local showOtherKeys = true

local screenYOffset = 15  -- Offset for debug UI shift
local Y = 15
G_ViewMemory = 0
-- text, x, r, g, b, a
local function PrintText(text, x, r, g, b, a)
    love.graphics.setColor(r, g, b, a)
    love.graphics.print(text, x, Y)
    Y = Y + 15
end

--# Display CPU Status 
local function CPUParamaters()
    local X = 550;
    Y = 30 + screenYOffset
    local flags = string.format("N:%i V:%i B:%i D:%i I:%i Z:%i C:%i", cpuMemory.GetFlag("negative"),
        cpuMemory.GetFlag("overflow"), cpuMemory.GetFlag("breakflow"), cpuMemory.GetFlag("decimal"),
        cpuMemory.GetFlag("interrupt"), cpuMemory.GetFlag("zero"), cpuMemory.GetFlag("carry"))
    PrintText("STATUS: " .. flags, X, 1, 1, 1, 1)
    PrintText(string.upper(string.format("A: $%04x  X: $%04x  Y: $%04x  PC: $%04x", cpuMemory.A, cpuMemory.X, cpuMemory.Y, cpuMemory.programCounter)), X, 1, 1, 1, 1)
    local stack = 0x0100 + cpuMemory.stackPointer
    PrintText(string.upper(string.format("SP: $%04x  Stack: [%02x] [%02x] [%02x] [%02x]", stack, cpu.cpuRAM[stack - 1],
        cpu.cpuRAM[stack + 0], cpu.cpuRAM[stack + 1], cpu.cpuRAM[stack + 2])), X, 1, 1, 1, 1)
    PrintText(string.upper(string.format("PPU ScanLine: %d   VBlank: %s", ppu.scanLines, tostring(ppu.vBlank))), X, 1, 1, 1, 1)
    
    -- Draw separator line
    Y = Y + 5
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.line(545, Y + screenYOffset, 895, Y + screenYOffset)
    love.graphics.setColor(1, 1, 1, 1)
    Y = Y + 10
end

local previousTrace = "Old Trace"

--# Display Command List To Be Run 
local function DebugTrace()
    local X = 550;
    Y = 100 + screenYOffset
    local cpuCounter = cpuMemory.programCounter
    
    -- Print Previous Value
    PrintText(previousTrace, X, 1, 1, 1, 1)

    love.graphics.rectangle("line", 545, 145 + screenYOffset, 200, 16)
    local i = 0
    local whileX = 0
    while whileX < 15 do
        local instruction = bus.CPURead(cpuCounter + i)
        if opcode[instruction] then
            local command1 = ""
            local command2 = ""
            local command3 = ""
            local programCounts = opcode[instruction].bytes
            if programCounts >= 2 then
                if bus.CPURead(cpuCounter + i + 1) then command1 = string.upper(string.format("%02x",
                            bus.CPURead(cpuCounter + i + 1))) end
            end
            if programCounts >= 3 then
                if bus.CPURead(cpuCounter + i + 2) then command2 = string.upper(string.format("%02x",
                            bus.CPURead(cpuCounter + i + 2))) end
            end
            if programCounts >= 4 then
                command3 = string.upper(string.format("%02x", bus.CPURead(cpuCounter + i + 3)))
            end

            if programCounts == 1 then
                PrintText(
                    string.upper(string.format("%04x %02x %03s %02s %02s %02s", cpuCounter + i, instruction,
                        opcode[instruction].mnemonic, command1, command2, command3)), X, 1, 1, 1, 1)
            elseif programCounts == 2 then
                PrintText(
                    string.upper(string.format("%04x %02x %03s [$%02s] %02s %02s", cpuCounter + i, instruction,
                        opcode[instruction].mnemonic, command1, command2, command3)), X, 1, 1, 1, 1)
            elseif programCounts == 3 then
                PrintText(
                    string.upper(string.format("%04x %02x %03s [$%02s%02s] %02s", cpuCounter + i, instruction,
                        opcode[instruction].mnemonic, command2, command1, command3)), X, 1, 1, 1, 1)
            elseif programCounts == 4 then
                PrintText(
                    string.upper(string.format("%04x %02x %03s [$%02] [s%02s%02s]", cpuCounter + i, instruction,
                        opcode[instruction].mnemonic, command2, command1, command3)), X, 1, 1, 1, 1)
                --if t == 0 then previousTrace = string.upper(string.format("%04x %02x %03s [$%02s%02s] %02s", programCount+i, instruction, opcode[instruction].opcode,command2,command1,command3)) end
            else
                PrintText(string.upper(string.format("%04x %02x %03s", cpuCounter + i, instruction, "UNK")), X, 1, 0, 0,
                    .8)
                i = i + 1
            end

            i = i + programCounts
        else

        end
        whileX = whileX + 1
    end
end

-- get opcode string
function debug.GetOpcodeString(value)
    local opcodeString = "UNK"
    if opcode[value] then
        opcodeString = opcode[memory[cpuMemory.programCounter]].mnemonic
    end
    return opcodeString
end

-- Red box printed for programCounter location
function testing.displayPointerCounterLocation(x, y)
    local col = bit.band(cpuMemory.programCounter, 0x0F)
    local row = bit.band(cpuMemory.programCounter, 0xF0) / 16
    love.graphics.setColor(1, 0, 0, 1);
    love.graphics.rectangle("line", x + col * 20 + 40, y + row * 15, 20, 15)
    love.graphics.setColor(1, 1, 1, 1);
end

local chunkSize = 256
local gridSize = 16
debug.debugOpcode = false
debug.viewMemory = 0x0100
--# Col and Row of 256 memory print out on screen
function testing.displayMemoryChunk(ReadWith, startAddress, screenX, screenY)
    testing.displayPointerCounterLocation(screenX, screenY)
    for y = 0, (chunkSize / gridSize) - 1 do
        for x = 0, gridSize - 1 do
            local address = startAddress + (y * gridSize) + x
            local value = ReadWith(address) or 0
            if value > 0 then
                love.graphics.setColor(0, 1, 1, 1)
            else
                love.graphics.setColor(1, 1, 1, 1)
            end
            if debug.debugOpcode then
                local opcode = debug.GetOpcodeString(ReadWith(address))
                love.graphics.print(string.upper(opcode), screenX + (x * 20) + 40, screenY + (y * 15), nil, .8)
            else
                love.graphics.print(string.upper(string.format("%02X", value)), screenX + (x * 20) + 40,
                    screenY + (y * 15))
            end
        end
        love.graphics.print(string.upper(string.format("%04X", startAddress + (y * gridSize))), screenX,
            screenY + (y * 15))
    end
end

function AddDebugString(name, text, x, y, r, g, b, a)
    for i = 1, #holdingString do
        if holdingString[i].name == name then
            holdingString[i].text = text
            holdingString[i].x = x
            holdingString[i].y = y
            holdingString[i].r = r
            holdingString[i].g = g
            holdingString[i].b = b
            holdingString[i].a = a
            return
        end
    end
    table.insert(holdingString, {name = name, text = text, x = x, y = y, r = r, g = g, b = b, a = a})
end

function DrawDebugString()
    for i = 1, #holdingString do
        love.graphics.setColor(holdingString[i].r, holdingString[i].g, holdingString[i].b, holdingString[i].a)
        love.graphics.print(holdingString[i].text, holdingString[i].x, holdingString[i].y)
    end
end

local function drawPanel(x, y, width, height, r, g, b, a)
    -- Just draw outline, no fill background
    love.graphics.setColor(r, g, b, 1)
    love.graphics.rectangle("line", x, y, width, height)
end

local function drawKeySection(title, keys, startX, startY, bgR, bgG, bgB, titleR, titleG, titleB)
    local sectionHeight = #keys * 15 + 25
    drawPanel(startX, startY, 350, sectionHeight, bgR, bgG, bgB, 0.2)
    love.graphics.setColor(titleR, titleG, titleB, 1)
    love.graphics.print(title, startX + 10, startY + 5)
    love.graphics.setColor(1, 1, 1, 0.9)
    for i, keyText in ipairs(keys) do
        love.graphics.print(keyText, startX + 10, startY + 20 + (i - 1) * 15)
    end
    return startY + sectionHeight + 10
end

function testing.DisplayDiagnosticKeys()
    local startX = 550
    local currentY = 365
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Diagnostics Keys (toggle: 1/2/3/4)", startX, currentY)
    currentY = currentY + 20
    
    if showCPUKeys then
        local cpuKeys = {
            "b = breakpoint",
            ". = Run Program Counter",
            "/ = single step Program Counter",
            "t = toggle memory view"
        }
        currentY = drawKeySection("CPU KEYS", cpuKeys, startX, currentY, 0, 0.3, 0.5, 0.4, 0.7, 1) 
    end
    
    if showPPUKeys then
        local ppuKeys = {
            "v c = cycle PPU state view",
            "y = change palette color",
            "o p [ ] = change memory offset"
        }
        currentY = drawKeySection("PPU KEYS", ppuKeys, startX, currentY, 0, 0.4, 0.4, 0.3, 1, 1)
    end
    
    if showSaveLoadKeys then
        local saveLoadKeys = {
            "1 2 3 = Save State",
            "7 8 9 = Load State"
        }
        currentY = drawKeySection("SAVE/LOAD", saveLoadKeys, startX, currentY, 0.3, 0.3, 0, 1, 1, 0.5)
    end
    
    if showOtherKeys then
        local otherKeys = {
            "k = Profiling",
            "\\ = Start/stop Trace Log file",
            "n = Mute Sound",
            "- = = adjust volume",
            "space = reset rom",
            "` = change rom",
            "esc x 2 = exit Love2D Window"
        }
        drawKeySection("OTHER KEYS", otherKeys, startX, currentY, 0.2, 0.2, 0.2, 0.7, 0.7, 0.7)
    end
end
function testing.DisplayUI()
    if EnableDebug then
        -- Main NES Screen
        love.graphics.setColor(.4, .4, .4, 1)
        love.graphics.rectangle("fill", 15, 10 + screenYOffset, 256 * 2, 240 * 2)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("line", 15, 10 + screenYOffset, 256 * 2, 240 * 2)
        -- Debug Text Area
        love.graphics.setColor(.2, .2, .2, 1)
        love.graphics.rectangle("line", 545, 100 + screenYOffset, 350, 250)
        love.graphics.setColor(.0, .4, .6, 1)
        love.graphics.rectangle("fill", 545, 100 + screenYOffset, 350, 250)
        -- Char Rom Page 0
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("line", 10, 500, 128 * 2, 128 * 2)
        love.graphics.setColor(.1, .4, .4, 1)
        love.graphics.rectangle("fill", 10, 500, 128 * 2, 128 * 2)
        -- Char Rom Page 1
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("line", 276, 500, 128 * 2, 128 * 2)
        love.graphics.setColor(.1, .4, .4, 1)
        love.graphics.rectangle("fill", 276, 500, 128 * 2, 128 * 2)
        love.graphics.setColor(1,1,1,1)
        
        if G_ViewMemory == 0 then
            -- Display CPU parameters, trace, and diagnostic keys
            CPUParamaters()
            DebugTrace()
            testing.DisplayDiagnosticKeys()
            DrawDebugString()
        elseif G_ViewMemory == 1 then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("CPU Memory", 650 , 495)
            testing.displayMemoryChunk(function(value) return bus.CPURead(value) end, debug.viewMemory, 540, 510)
        elseif G_ViewMemory == 2 then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("PPU Memory", 650, 495)
            testing.displayMemoryChunk(function(value) return ppuBus.PPURead(value) end, debug.viewMemory+0x1F00, 540, 510)
        elseif G_ViewMemory == 3 then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("OAM Memory", 650, 495)
            testing.displayMemoryChunk(function(value) return oam[value] end, 0x00, 540, 510)
        end
    end
end

return testing
