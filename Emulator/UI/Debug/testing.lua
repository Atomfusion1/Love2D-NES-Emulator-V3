local cpuMemory   = require("NES.CPU.cpuInternal")
local cpu         = require("NES.CPU.cpuram")
local bus         = require("NES.BUS.bus")
local ppuBus      = require("NES.PPU.ppuBus")
local opcode      = require("NES.CPU.opcodes.opcodeTable")
local memory      = require("NES.CPU.cpuram")
local ppu         = require("NES.PPU.ppu")
local nameTable  = require("NES.PPU.ppunametable")
local paletteRGB = require("NES.PPU.VGA_Pallette").Pallette
local displayTimer = require("Includes.displaytimer")
local oam         = require("NES.PPU.ppuOAM")
local loopy       = require("NES.PPU.loopy")
local apu         = require("NES.Audio.apu")

local testing = {}
local holdingString = {}
local activeTab = "overview"
DebugActiveTab = activeTab
local ppuLayerRects = {}
local tabOrder = { "overview", "cpu", "ppu", "memory", "performance", "apu" }
local tabLabels = {
    overview = "Overview",
    cpu = "CPU",
    ppu = "PPU",
    memory = "Memory",
    performance = "Performance",
    apu = "APU"
}
local toolbarButtons = {
    { id = "run", label = "Run" },
    { id = "pause", label = "Pause" },
    { id = "step", label = "Step" },
    { id = "frame", label = "Frame" },
    { id = "reset", label = "Reset" },
    { id = "save", label = "Save" },
    { id = "load", label = "Load" },
    { id = "help", label = "Help (F1)" }
}
local toolbarRects = {}
local tabRects = {}
local memorySourceRects = {}
local memoryNavRects = {}
local performanceRects = {}
local audioRects = {}
local nametableRect = nil
local paletteCycleRect = nil
local performanceFocus = "overall"
local pcHistory = {}
local lastObservedPC = nil
-- Debug section toggles
local showCPUKeys = true
local showPPUKeys = true
local showSaveLoadKeys = true
local showOtherKeys = true

local screenYOffset = 45  -- Leave room for the debugger toolbar
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
    local traceLimit = (activeTab == "cpu") and 32 or 4
    
    -- Print Previous Value
    PrintText(previousTrace, X, 1, 1, 1, 1)

    love.graphics.rectangle("line", 545, 145 + screenYOffset, 200, 16)
    local i = 0
    local whileX = 0
    while whileX < traceLimit do
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
function testing.displayPointerCounterLocation(x, y, address)
    local col = bit.band(address, 0x0F)
    local row = bit.band(address, 0xF0) / 16
    love.graphics.setColor(1, 0, 0, 1);
    love.graphics.rectangle("line", x + col * 20 + 40, y + row * 15, 20, 15)
    love.graphics.setColor(1, 1, 1, 1);
end

local chunkSize = 256
local gridSize = 16
debug.debugOpcode = false
debug.viewMemory = 0x0100
--# Col and Row of 256 memory print out on screen
function testing.displayMemoryChunk(ReadWith, startAddress, screenX, screenY, highlightAddress)
    if highlightAddress and highlightAddress >= startAddress and highlightAddress < startAddress + chunkSize then
        testing.displayPointerCounterLocation(screenX, screenY, highlightAddress - startAddress)
    end
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

local drawButton

local function CPUExecutionInsight()
    local pc = cpuMemory.programCounter
    local instruction = bus.CPURead(pc) or 0
    local entry = opcode[instruction]
    local mnemonic = entry and entry.mnemonic or "???"
    local message = string.format("Current: $%04X  %02X %s", pc, instruction, mnemonic)
    local target = nil

    -- Relative conditional branches.
    if instruction == 0x10 or instruction == 0x30 or instruction == 0x50 or
       instruction == 0x70 or instruction == 0x90 or instruction == 0xB0 or
       instruction == 0xD0 or instruction == 0xF0 then
        local offset = bus.CPURead(pc + 1) or 0
        if offset >= 0x80 then offset = offset - 0x100 end
        target = bit.band(pc + 2 + offset, 0xffff)
        message = message .. string.format("  target $%04X", target)
        if target <= pc then
            message = message .. "  [backward branch: likely loop]"
        end
    elseif instruction == 0x4C then
        target = (bus.CPURead(pc + 1) or 0) + 256 * (bus.CPURead(pc + 2) or 0)
        message = message .. string.format("  target $%04X", target)
        if target <= pc then message = message .. "  [backward jump: likely loop]" end
    elseif instruction == 0x6C then
        local pointer = (bus.CPURead(pc + 1) or 0) + 256 * (bus.CPURead(pc + 2) or 0)
        target = (bus.CPURead(pointer) or 0) + 256 * (bus.CPURead(bit.band(pointer + 1, 0xffff)) or 0)
        message = message .. string.format("  target $%04X", target)
        if target <= pc then message = message .. "  [backward jump: likely loop]" end
    end

    love.graphics.setColor(0.72, 0.84, 0.94, 1)
    love.graphics.print("Execution insight", 550, 665)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(message, 550, 685)
    love.graphics.print(UseBreakPoint and string.format("Breakpoint: $%04X", BreakPointValue) or "Breakpoint: none", 550, 705)
    drawButton("Set breakpoint (B)", 550, 720, 150, 26, false)
end

drawButton = function(label, x, y, width, height, selected)
    love.graphics.setColor(selected and 0.12 or 0.08, selected and 0.42 or 0.12, selected and 0.62 or 0.18, 1)
    love.graphics.rectangle("fill", x, y, width, height, 3, 3)
    love.graphics.setColor(0.45, 0.75, 0.9, 1)
    love.graphics.rectangle("line", x, y, width, height, 3, 3)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(label, x, y + 5, width, "center")
end

local function runToolbarAction(id)
    if id == "run" then
        G_CPUStep = 2
    elseif id == "pause" then
        G_CPUStep = 0
    elseif id == "step" then
        G_CPUStep = 1
    elseif id == "frame" then
        G_FrameStepRequested = true
        G_CPUStep = 0
    elseif id == "reset" then
        Initialize(love.filesystem.read("Emulator/nesEmuState.txt"))
    elseif id == "save" then
        require("Emulator.savestate").Save("1")
    elseif id == "load" then
        require("Emulator.savestate").Load("1")
    elseif id == "help" then
        testing.helpVisible = not testing.helpVisible
    end
end

local function drawToolbar()
    local width = love.graphics.getWidth()
    love.graphics.setColor(0.035, 0.045, 0.06, 1)
    love.graphics.rectangle("fill", 0, 0, width, 38)
    love.graphics.setColor(0.25, 0.35, 0.45, 1)
    love.graphics.line(0, 38, width, 38)
    love.graphics.setColor(0.8, 0.9, 1, 1)
    love.graphics.print("NES DEBUGGER", 12, 10)

    toolbarRects = {}
    local x = 135
    for _, button in ipairs(toolbarButtons) do
        local buttonWidth = button.id == "help" and 85 or 58
        toolbarRects[#toolbarRects + 1] = { id = button.id, x = x, y = 6, width = buttonWidth, height = 26 }
        drawButton(button.label, x, 6, buttonWidth, 26, false)
        x = x + buttonWidth + 6
    end

    love.graphics.setColor(0.65, 0.75, 0.85, 1)
    love.graphics.print(G_CPUStep == 0 and "Paused" or "Running", x + 12, 12)
end

local function drawTabs()
    local x = 600
    local y = 45
    tabRects = {}
    for _, id in ipairs(tabOrder) do
        local width = id == "performance" and 105 or 75
        tabRects[#tabRects + 1] = { id = id, x = x, y = y, width = width, height = 28 }
        drawButton(tabLabels[id], x, y, width, 28, activeTab == id)
        x = x + width + 5
    end
    -- PPU-only control positioned above the nametable images, just to the
    -- right of the Performance tab.
    -- Leave a deliberate gap after Performance so this reads as a PPU tool,
    -- not as another navigation tab.
    nametableRect = { x = x + 65, y = 45, width = 210, height = 28 }
    if activeTab == "ppu" then
        drawButton("Nametables: " .. ppu.GetDebugNametableModeLabel(),
            nametableRect.x, nametableRect.y, nametableRect.width, nametableRect.height, false)
    end
end

local function drawStatusBar()
    local height = love.graphics.getHeight()
    love.graphics.setColor(0.035, 0.045, 0.06, 1)
    love.graphics.rectangle("fill", 0, height - 24, love.graphics.getWidth(), 24)
    love.graphics.setColor(0.55, 0.65, 0.75, 1)
    love.graphics.print(string.format("%s  |  Audio: %s  |  Save slot: 1  |  F1: Help", G_CPUStep == 0 and "Paused" or "Running", UseSound and "On" or "Off"), 12, height - 19)
end

local function drawMemorySourceControls()
    love.graphics.setColor(0.75, 0.85, 0.95, 1)
    love.graphics.print("Memory", 545, 112)
    memorySourceRects = {}
    local sources = { { label = "CPU", source = 1 }, { label = "PPU", source = 2 }, { label = "OAM", source = 3 } }
    local sourceX = 545
    for _, source in ipairs(sources) do
        memorySourceRects[#memorySourceRects + 1] = { x = sourceX, y = 135, width = 65, height = 26, source = source.source }
        drawButton(source.label, sourceX, 135, 65, 26, G_ViewMemory == source.source)
        sourceX = sourceX + 72
    end

    memoryNavRects = {}
    local navigation = {
        { label = "-0x1000", delta = -0x1000 },
        { label = "-0x100", delta = -0x100 },
        { label = "+0x100", delta = 0x100 },
        { label = "+0x1000", delta = 0x1000 }
    }
    local navX = 545
    for _, item in ipairs(navigation) do
        memoryNavRects[#memoryNavRects + 1] = { x = navX, y = 167, width = 82, height = 26, delta = item.delta }
        drawButton(item.label, navX, 167, 82, 26, false)
        navX = navX + 88
    end
end

local function updatePCMemoryHistory()
    local pc = cpuMemory.programCounter
    if pc == lastObservedPC then return end
    lastObservedPC = pc
    table.insert(pcHistory, 1, pc)
    if #pcHistory > 12 then
        table.remove(pcHistory)
    end
end

local function drawPCMemoryHistory()
    updatePCMemoryHistory()
    love.graphics.setColor(0.08, 0.12, 0.16, 1)
    love.graphics.rectangle("fill", 920, 195, 220, 285)
    love.graphics.setColor(0.35, 0.65, 0.8, 1)
    love.graphics.rectangle("line", 920, 195, 220, 285)
    love.graphics.setColor(0.75, 0.85, 0.95, 1)
    love.graphics.print("CPU address", 935, 210)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("Current: $%04X", cpuMemory.programCounter), 935, 235)
    love.graphics.setColor(0.75, 0.85, 0.95, 1)
    love.graphics.print("Recent PC locations", 935, 270)
    love.graphics.setColor(1, 1, 1, 1)
    for i, address in ipairs(pcHistory) do
        love.graphics.print(string.format("%2d  $%04X", i, address), 935, 270 + i * 17)
    end
end

local function drawHelpOverlay()
    if not testing.helpVisible then return end
    local width, height = love.graphics.getWidth(), love.graphics.getHeight()
    local panelX, panelY = 180, 55
    local panelW, panelH = width - 360, height - 95
    love.graphics.setColor(0, 0, 0, 0.82)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH)
    love.graphics.setColor(0.45, 0.75, 0.9, 1)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Debugger Help and Keyboard Shortcuts", panelX + 25, panelY + 22)
    local function drawHelpSection(title, entries, x, y)
        love.graphics.setColor(0.35, 0.8, 1, 1)
        love.graphics.print(title, x, y)
        love.graphics.setColor(1, 1, 1, 1)
        for i, line in ipairs(entries) do
            love.graphics.print(line, x, y + 22 + (i - 1) * 20)
        end
        return y + 42 + #entries * 20
    end

    local leftX = panelX + 25
    local rightX = panelX + panelW / 2
    local startY = panelY + 60

    local leftY = startY
    leftY = drawHelpSection("GAME CONTROLS", {
        "Run button / .       Run emulation",
        "Pause button / ,     Pause emulation",
        "Step button / /      Execute one CPU cycle",
        "Frame button         Execute one complete frame",
        "Reset button / Space Reset the current ROM",
        "`                   Open the ROM picker",
        "Escape twice        Quit the window"
    }, leftX, leftY)
    leftY = drawHelpSection("SAVE / LOAD", {
        "1 / 2 / 3           Save state slot",
        "7 / 8 / 9           Load state slot"
    }, leftX, leftY)
    drawHelpSection("CPU CONTROLS", {
        "B                   Set an address breakpoint",
        "CPU tab             Expanded trace and insight",
        "Step button / /      Single-cycle execution",
        "Frame button         Single-frame execution"
    }, leftX, leftY)

    local rightY = startY
    rightY = drawHelpSection("MEMORY CONTROLS", {
        "T                   Cycle CPU / PPU / OAM",
        "[ / ]               Move address by 0x100",
        "O / P               Move address by 0x1000",
        "Memory buttons       Select source and page size"
    }, rightX, rightY)
    rightY = drawHelpSection("PPU CONTROLS", {
        "V / C               Next / previous PPU state",
        "Y                   Cycle palette",
        "Nametable button     Native / All A / All B"
    }, rightX, rightY)
    rightY = drawHelpSection("DEBUGGER / DIAGNOSTICS", {
        "F1 / Help            Show this help",
        "\\                   Toggle trace logging",
        "K                   Toggle profiler",
        "Mouse               Click buttons, tabs, and controls"
    }, rightX, rightY)
    drawHelpSection("AUDIO", {
        "N                   Mute / unmute",
        "- / =               Lower / raise volume"
    }, rightX, rightY)
    love.graphics.setColor(0.65, 0.75, 0.85, 1)
    love.graphics.print("Toolbar buttons are the recommended way to discover and use common actions.", panelX + 25, panelY + panelH - 35)
end

function testing.GetActiveTab()
    return activeTab
end

function testing.CycleCharacterPalette(delta)
    delta = delta or 1
    G_ColorOffset = (G_ColorOffset + delta) % 8
    if G_ColorOffset < 0 then G_ColorOffset = G_ColorOffset + 8 end
    return G_ColorOffset
end

function testing.SetActiveTab(tab)
    for _, id in ipairs(tabOrder) do
        if id == tab then
            activeTab = tab
            DebugActiveTab = tab
            return true
        end
    end
    return false
end

function testing.ToggleHelp()
    testing.helpVisible = not testing.helpVisible
end

function testing.DrawHelpOverlay()
    if EnableDebug then
        drawHelpOverlay()
    end
end

function testing.MousePressed(x, y, button)
    if not EnableDebug or (button ~= 1 and button ~= 2) then return end
    if testing.helpVisible then
        testing.helpVisible = false
        return
    end
    for _, rect in ipairs(toolbarRects) do
        if button ~= 1 then break end
        if x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height then
            runToolbarAction(rect.id)
            return
        end
    end
    if button == 1 and activeTab == "memory" then
        for _, rect in ipairs(memorySourceRects) do
            if x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height then
                G_ViewMemory = rect.source
                return
            end
        end
        for _, rect in ipairs(memoryNavRects) do
            if x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height then
                debug.viewMemory = bit.band(debug.viewMemory + rect.delta, 0xffff)
                return
            end
        end
    end
    if button == 1 and activeTab == "ppu" and nametableRect
        and x >= nametableRect.x and x <= nametableRect.x + nametableRect.width
        and y >= nametableRect.y and y <= nametableRect.y + nametableRect.height then
        ppu.CycleDebugNametableMode()
        return
    end
    if activeTab == "ppu" then
        for _, rect in ipairs(ppuLayerRects) do
            if x >= rect.x and x <= rect.x + rect.width
                and y >= rect.y and y <= rect.y + rect.height then
                if rect.layer == "background" then
                    ppu.ToggleDebugBackground()
                else
                    ppu.ToggleDebugSprites()
                end
                return
            end
        end
    end
    if activeTab == "ppu" and paletteCycleRect
        and x >= paletteCycleRect.x and x <= paletteCycleRect.x + paletteCycleRect.width
        and y >= paletteCycleRect.y and y <= paletteCycleRect.y + paletteCycleRect.height then
        testing.CycleCharacterPalette(button == 1 and 1 or -1)
        return
    end
    if button == 1 and activeTab == "performance" then
        for _, rect in ipairs(performanceRects) do
            if x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height then
                if rect.action == "reset" then
                    displayTimer.ResetStats()
                else
                    performanceFocus = rect.action
                    PerformanceDetailEnabled = performanceFocus ~= "overall"
                end
                return
            end
        end
    end
    if button == 1 and activeTab == "apu" then
        for _, rect in ipairs(audioRects) do
            if x >= rect.x and x <= rect.x + rect.width
                and y >= rect.y and y <= rect.y + rect.height then
                if rect.action == "toggle" then
                    UseSound = not UseSound
                    if not UseSound and SoundOff then SoundOff() end
                    apu.SetAudioEnabled(UseSound)
                elseif rect.action == "down" then
                    VolumeMulti = math.max(0, (VolumeMulti or 1) - 0.5)
                    apu.SetVolume(VolumeMulti)
                elseif rect.action == "up" then
                    VolumeMulti = math.min(10, (VolumeMulti or 1) + 0.5)
                    apu.SetVolume(VolumeMulti)
                elseif rect.action == "dmcDown" then
                    apu.SetDMCVolumeScale(math.max(0, apu.GetDMCVolumeScale() - 0.005))
                elseif rect.action == "dmcUp" then
                    apu.SetDMCVolumeScale(math.min(1, apu.GetDMCVolumeScale() + 0.005))
                elseif rect.channel then
                    apu.SetChannelMuted(rect.channel, not APUChannelMute[rect.channel])
                end
                return
            end
        end
    end
    if button == 1 and activeTab == "ppu" and y >= 635 and y <= 670 then
        if x >= 1010 and x <= 1090 then
            ppu.SelectDebugState(-1)
            return
        elseif x >= 1098 and x <= 1178 then
            ppu.SelectDebugState(1)
            return
        end
    end
    if button == 1 and activeTab == "cpu" and x >= 550 and x <= 700 and y >= 720 and y <= 746 then
        require("Includes.keyboard").OpenBreakpoint()
        return
    end
    if button ~= 1 then return end
    for _, rect in ipairs(tabRects) do
        if x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height then
            testing.SetActiveTab(rect.id)
            return
        end
    end
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
        drawToolbar()
        drawTabs()
        drawStatusBar()
        -- Main NES Screen
        love.graphics.setColor(.4, .4, .4, 1)
        love.graphics.rectangle("fill", 10, 65, 256 * 2, 240 * 2)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("line", 10, 65, 256 * 2, 240 * 2)
        if activeTab == "overview" or activeTab == "cpu" then
            -- CPU trace/status panel belongs only to CPU-oriented tabs.
            love.graphics.setColor(.2, .2, .2, 1)
            love.graphics.rectangle("line", 545, 100 + screenYOffset, 350, activeTab == "cpu" and 600 or 250)
            love.graphics.setColor(.0, .4, .6, 1)
            love.graphics.rectangle("fill", 545, 100 + screenYOffset, 350, activeTab == "cpu" and 600 or 250)
        elseif activeTab == "ppu" then
            -- CHR panels belong only to the PPU tab.
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("line", 600, 185, 128 * 2, 128 * 2)
            love.graphics.setColor(.1, .4, .4, 1)
            love.graphics.rectangle("fill", 600, 185, 128 * 2, 128 * 2)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("line", 600, 445, 128 * 2, 128 * 2)
            love.graphics.setColor(.1, .4, .4, 1)
            love.graphics.rectangle("fill", 600, 445, 128 * 2, 128 * 2)
        end

        if activeTab == "memory" then
            drawMemorySourceControls()
        end
        love.graphics.setColor(1,1,1,1)
        
        if activeTab == "overview" or activeTab == "cpu" then
            -- Display CPU parameters, trace, and diagnostic keys
            CPUParamaters()
            DebugTrace()
            if activeTab == "overview" then
                love.graphics.setColor(0.7, 0.8, 0.9, 1)
                love.graphics.print("Use the toolbar or F1 for commands", 550, 350)
            else
                love.graphics.setColor(0.7, 0.8, 0.9, 1)
                love.graphics.print("CPU trace: 32 instructions around the program counter", 550, 650)
                CPUExecutionInsight()
            end
            DrawDebugString()
        elseif activeTab == "memory" and G_ViewMemory == 0 then
            G_ViewMemory = 1
        elseif activeTab == "memory" and G_ViewMemory == 1 then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("CPU Memory", 545, 205)
            testing.displayMemoryChunk(function(value) return bus.CPUPeek(value) end, debug.viewMemory, 540, 225, cpuMemory.programCounter)
            drawPCMemoryHistory()
        elseif activeTab == "memory" and G_ViewMemory == 2 then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("PPU Memory", 545, 205)
            testing.displayMemoryChunk(function(value) return ppuBus.PPURead(value) end, debug.viewMemory+0x1F00, 540, 225)
        elseif activeTab == "memory" and G_ViewMemory == 3 then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("OAM Memory", 545, 205)
            testing.displayMemoryChunk(function(value) return oam[value] end, 0x00, 540, 225)
        elseif activeTab == "ppu" then
            love.graphics.setColor(0.75, 0.85, 0.95, 1)
            love.graphics.print("PPU visualizations are refreshed while this tab is active.", 600, 110)
            love.graphics.print("Use C/V for PPU state and Y or the button for CHR palette.", 600, 130)
            -- Layer controls live beside the nametable/scroll visualization.
            -- They affect only the debugger preview while this tab is active.
            ppuLayerRects = {
                { x = 1295, y = 50, width = 105, height = 24, layer = "background" },
                { x = 1407, y = 50, width = 105, height = 24, layer = "sprites" }
            }
            drawButton("BG: " .. (ppu.debugShowBackground and "ON" or "OFF"),
                1295, 50, 105, 24, ppu.debugShowBackground)
            drawButton("Sprites: " .. (ppu.debugShowSprites and "ON" or "OFF"),
                1407, 50, 105, 24, ppu.debugShowSprites)
            paletteCycleRect = { x = 600, y = 150, width = 145, height = 26 }
            drawButton("Cycle palette (Y)", 600, 150, 145, 26, false)
            local paletteBase = (G_ColorOffset % 8) * 4
            love.graphics.setColor(0.75, 0.85, 0.95, 1)
            love.graphics.print(string.format("CHR palette %d", G_ColorOffset), 760, 155)
            for i = 0, 3 do
                local paletteAddress = (i == 0) and 0 or ((paletteBase + i) % 0x20)
                local value = nameTable.tblPalette[paletteAddress] or 0
                value = bit.band(value, 0x3F)
                local rgb = paletteRGB[value] or paletteRGB[0]
                local swatchX = 880 + i * 30
                love.graphics.setColor(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, 1)
                love.graphics.rectangle("fill", swatchX, 150, 24, 24)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.rectangle("line", swatchX, 150, 24, 24)
            end
        elseif activeTab == "apu" then
            love.graphics.setColor(0.75, 0.85, 0.95, 1)
            love.graphics.print("APU / Audio", 600, 110)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("Controls affect audio output only; CPU/APU register behavior continues.", 600, 140)
            audioRects = {
                { x = 600, y = 175, width = 150, height = 28, action = "toggle" },
                { x = 600, y = 220, width = 80, height = 28, action = "down" },
                { x = 690, y = 220, width = 80, height = 28, action = "up" },
                { x = 600, y = 315, width = 80, height = 28, action = "dmcDown" },
                { x = 690, y = 315, width = 80, height = 28, action = "dmcUp" },
                { x = 600, y = 275, width = 125, height = 28, channel = 1 },
                { x = 735, y = 275, width = 125, height = 28, channel = 2 },
                { x = 870, y = 275, width = 125, height = 28, channel = 3 },
                { x = 1005, y = 275, width = 125, height = 28, channel = 4 },
                { x = 1140, y = 275, width = 125, height = 28, channel = 5 }
            }
            drawButton("Sound: " .. (UseSound and "ON" or "OFF"), 600, 175, 150, 28, UseSound)
            drawButton("Volume -", 600, 220, 80, 28, false)
            drawButton("Volume +", 690, 220, 80, 28, false)
            love.graphics.setColor(0.8, 0.9, 1, 1)
            love.graphics.print(string.format("Volume multiplier: %.1fx", VolumeMulti or 1), 790, 226)
            drawButton("DMC -", 600, 315, 80, 28, false)
            drawButton("DMC +", 690, 315, 80, 28, false)
            love.graphics.setColor(0.8, 0.9, 1, 1)
            love.graphics.print(string.format("DMC mix: %.1f%% of master", apu.GetDMCVolumeScale() * 100), 790, 321)
            local channelNames = { "Pulse 1", "Pulse 2", "Triangle", "Noise", "DMC" }
            for channel = 1, 5 do
                local rect = audioRects[channel + 5]
                local muted = APUChannelMute[channel]
                drawButton(channelNames[channel] .. (muted and ": OFF" or ": ON"),
                    rect.x, rect.y, rect.width, rect.height, not muted)
            end
            local dmcStatus = apu.GetDMCDebugStatus()
            love.graphics.setColor(0.7, 0.82, 0.92, 1)
            love.graphics.print(string.format("DMC: %s  bytes: %d  addr: $%04X  output: %d",
                dmcStatus.enabled and "ACTIVE" or "IDLE", dmcStatus.bytesRemaining,
                dmcStatus.currentAddress, dmcStatus.outputLevel), 600, 355)
        elseif activeTab == "performance" then
            local stats = displayTimer.GetStats()
            love.graphics.setColor(0.75, 0.85, 0.95, 1)
            love.graphics.print("Performance", 600, 110)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(string.format("Current: %.2f ms", stats.current * 1000), 600, 145)
            love.graphics.print(string.format("Average: %.2f ms", stats.average * 1000), 600, 165)
            love.graphics.print(string.format("Peak: %.2f ms", stats.peak * 1000), 600, 185)
            love.graphics.print(string.format("1%% low: %.1f FPS", stats.onePercentLow > 0 and 1 / stats.onePercentLow or 0), 600, 205)
            love.graphics.print(string.format("FPS: %.2f", stats.fps), 800, 145)
            love.graphics.print(string.format("Lua memory: %.2f MB", stats.memoryMB), 800, 165)
            performanceRects = {
                { x = 600, y = 225, width = 130, height = 26, action = "reset" },
                { x = 745, y = 225, width = 105, height = 26, action = "overall" },
                { x = 855, y = 225, width = 105, height = 26, action = "cpu" },
                { x = 965, y = 225, width = 105, height = 26, action = "ppu" }
            }
            drawButton("Reset Stats", 600, 225, 130, 26, false)
            drawButton("Overall", 745, 225, 105, 26, performanceFocus == "overall")
            drawButton("CPU/Emu", 855, 225, 105, 26, performanceFocus == "cpu")
            drawButton("PPU", 965, 225, 105, 26, performanceFocus == "ppu")
            local focusName = performanceFocus == "cpu" and "CPU/Emu" or performanceFocus == "ppu" and "PPU" or "Overall"
            local focusValue = performanceFocus == "cpu" and stats.components.cpu[#stats.components.cpu] or performanceFocus == "ppu" and stats.components.ppu[#stats.components.ppu] or stats.current
            love.graphics.setColor(0.7, 0.82, 0.92, 1)
            love.graphics.print(string.format("Selected: %s  %.2f ms", focusName, (focusValue or 0) * 1000), 600, 260)

            local graphX, graphY, graphW, graphH = 600, 285, 560, 220
            local graphValues = stats.samples
            if performanceFocus == "cpu" then graphValues = stats.components.cpuCore end
            if performanceFocus == "ppu" then graphValues = stats.components.ppuSetup end
            local focusedPeak = 0
            for _, value in ipairs(graphValues) do focusedPeak = math.max(focusedPeak, value) end
            local graphMaxMs = math.max(focusedPeak * 1000, 16.67)
            love.graphics.setColor(0.04, 0.07, 0.1, 1)
            love.graphics.rectangle("fill", graphX, graphY, graphW, graphH)
            love.graphics.setColor(0.3, 0.5, 0.65, 1)
            love.graphics.rectangle("line", graphX, graphY, graphW, graphH)
            love.graphics.setColor(0.65, 0.8, 0.9, 1)
            local graphTitle = performanceFocus == "cpu" and "CPU/Emu Time History" or performanceFocus == "ppu" and "PPU Time History" or "Frame Time History"
            love.graphics.print(graphTitle, graphX + 8, graphY + 5)
            love.graphics.line(graphX, graphY, graphX, graphY + graphH)
            love.graphics.line(graphX, graphY + graphH, graphX + graphW, graphY + graphH)
            love.graphics.print(string.format("%.1f ms", graphMaxMs), graphX - 58, graphY - 6)
            love.graphics.print(string.format("%.1f ms", graphMaxMs / 2), graphX - 58, graphY + graphH / 2 - 7)
            love.graphics.print("0 ms", graphX - 38, graphY + graphH - 7)
            love.graphics.print("older / compressed", graphX, graphY + graphH + 28)
            love.graphics.print("newest", graphX + graphW - 48, graphY + graphH + 28)
            local count = #graphValues
            if count > 1 then
                local maxValue = graphMaxMs / 1000
                local compressionScale = 4
                local logSpan = math.log(1 + (count - 1) * compressionScale)
                local allSeries = {
                    { label = "Overall", values = stats.samples, color = { 0.5, 0.85, 1, 1 } },
                    { label = "CPU/Emu", values = stats.components.cpu, color = { 1, 0.65, 0.3, 1 } },
                    { label = "PPU", values = stats.components.ppu, color = { 0.4, 1, 0.5, 1 } }
                }
                local series = allSeries
                if performanceFocus == "cpu" then
                    series = {
                        { label = "CPU core", values = stats.components.cpuCore, color = { 1, 0.65, 0.3, 1 } },
                        { label = "APU", values = stats.components.apu, color = { 1, 0.35, 0.6, 1 } },
                        { label = "PPU emu", values = stats.components.ppuEmu, color = { 0.75, 0.5, 1, 1 } }
                    }
                elseif performanceFocus == "ppu" then
                    series = {
                        { label = "Setup", values = stats.components.ppuSetup, color = { 0.4, 0.8, 1, 1 } },
                        { label = "Background", values = stats.components.ppuBackground, color = { 0.4, 1, 0.5, 1 } },
                        { label = "Sprites", values = stats.components.ppuSprites, color = { 1, 0.65, 0.3, 1 } },
                        { label = "Upload", values = stats.components.ppuUpload, color = { 1, 0.4, 0.6, 1 } }
                    }
                end
                for _, item in ipairs(series) do
                    love.graphics.setColor(unpack(item.color))
                    local previousX, previousY
                    for i, value in ipairs(item.values) do
                        local age = count - i
                        local agePosition = logSpan > 0 and math.log(1 + age * compressionScale) / logSpan or 0
                        local px = graphX + (1 - agePosition) * graphW
                        local normalized = math.max(0, math.min(value / maxValue, 1))
                        local py = graphY + graphH - normalized * graphH
                        if previousX then love.graphics.line(previousX, previousY, px, py) end
                        previousX, previousY = px, py
                    end
                end
            end
            local legendX = graphX + 180
            local legend = {
                { label = "Overall", color = { 0.5, 0.85, 1, 1 } },
                { label = "CPU/Emu", color = { 1, 0.65, 0.3, 1 } },
                { label = "PPU", color = { 0.4, 1, 0.5, 1 } }
            }
            if performanceFocus == "cpu" then
                legend = {
                    { label = "CPU core", color = { 1, 0.65, 0.3, 1 } },
                    { label = "APU", color = { 1, 0.35, 0.6, 1 } },
                    { label = "PPU emu", color = { 0.75, 0.5, 1, 1 } }
                }
            elseif performanceFocus == "ppu" then
                legend = {
                    { label = "Setup", color = { 0.4, 0.8, 1, 1 } },
                    { label = "Background", color = { 0.4, 1, 0.5, 1 } },
                    { label = "Sprites", color = { 1, 0.65, 0.3, 1 } },
                    { label = "Upload", color = { 1, 0.4, 0.6, 1 } }
                }
            end
            for _, item in ipairs(legend) do
                love.graphics.setColor(unpack(item.color))
                love.graphics.print("● " .. item.label, legendX, graphY + 5)
                legendX = legendX + 95
            end
            love.graphics.setColor(0.65, 0.75, 0.85, 1)
            love.graphics.print("Time axis: recent expanded -> older compressed (600 frames)", graphX + 10, graphY + graphH + 8)
            love.graphics.print("Use K to toggle the sampling profiler.", 600, 555)
        end
    end
end

return testing
