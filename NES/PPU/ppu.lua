local cart          = require("NES.Cartridge.Cartridge")
local cpuMemory     = require("NES.CPU.cpuInternal")
local PPUtoLove     = require("NES.PPU.PPUtoLove2d")
local ppuIO         = require("NES.PPU.ppuIO")
local OAM           = require("NES.PPU.ppuOAM")
local loopy         = require("NES.PPU.loopy")
local ppuBus        = require("NES.PPU.ppuBus")
local profile       = require("Includes.profile.profile")
local displayTimer  = require("Includes.displaytimer")
local mapper        = require("NES.Cartridge.Mappers")

--! Entire PPU is a Hack Job and Needs to be reworked from the ground up but I am lazy and it works so i am not going to touch it
local ppu             = {}
local cachedTileSet   = nil
ppu.memory            = {}
ppu.Name              = {}
ppu.Palette           = {}
ppu.Pattern           = {}
ppu.scanLinePixels    = 0
ppu.scanLines         = 30
ppu.vBlankEnd         = false
ppu.currentFrame      = 1
ppu.sprite0Offset     = 0
ppu.scanLineOffset    = 0
ppu.backgroundEnableOffset = 0


ppu.scroll = {
    fineX   = 0,
    courseX = 0,
    fineY   = 0,
    courseY = 0
}
function ppu.Initialize(value, chrLocation)
    -- Main PPU (addresses $0200-$FFFF)
    for i = 0x0000, 0xFFFF do
        ppu.memory[i] = bit.band(value, 0xFF)
    end
    print("CHR Location:" .. chrLocation)
end

local band, bor = bit.band, bit.bor
local vBlankFlag = false
local scanLinePixels
local scanLines
local CTRL
local STATUS
local Sprite0Scanline
local ppuCycles
local debug = false
ppu.DrawScreen = false
-- Debugger-only layer visibility. These flags never alter emulation state.
ppu.debugShowBackground = true
ppu.debugShowSprites = true
ppu.debugInspectionScanline = 0
ppu.debugInspectionEnabled = false
ppu.debugInspectionState = nil

function ppu.ToggleDebugBackground()
    ppu.debugShowBackground = not ppu.debugShowBackground
end

function ppu.ToggleDebugSprites()
    ppu.debugShowSprites = not ppu.debugShowSprites
end

function ppu.AdjustDebugInspectionScanline(delta)
    local scanline = (ppu.debugInspectionScanline or 0) + (delta or 0)
    ppu.debugInspectionScanline = math.max(0, math.min(239, scanline))
    for i = #loopy.ppuStates, 1, -1 do
        if loopy.ppuStates[i].trigger == "inspect" then
            table.remove(loopy.ppuStates, i)
        end
    end
    ppu.debugInspectionState = nil
    return ppu.debugInspectionScanline
end

function ppu.GetDebugInspectionScanline()
    return ppu.debugInspectionScanline or 0
end

function ppu.SetDebugInspectionEnabled(enabled)
    ppu.debugInspectionEnabled = enabled and true or false
    if not ppu.debugInspectionEnabled then
        for i = #loopy.ppuStates, 1, -1 do
            if loopy.ppuStates[i].trigger == "inspect" then
                table.remove(loopy.ppuStates, i)
            end
        end
        ppu.debugInspectionState = nil
    end
end

function ppu.GetDebugInspectionState()
    return ppu.debugInspectionState
end

function ppu.GetDebugScreenChanges()
    local changes = {}
    for _, state in ipairs(loopy.ppuStates) do
        if state.trigger ~= "mapper" then
            local reason = state.trigger or "unknown"
            if state.mapperEvent and reason ~= "unknown" then
                reason = reason .. "+mapper"
            end
            changes[#changes + 1] = string.format("SL%d %s", state.scanLine or 0, reason)
        end
    end
    return #changes > 0 and table.concat(changes, " | ") or "none"
end

function ppu.GetDebugFrameData()
    local lines = {"PPU FRAME DATA (mapper-only events omitted)"}
    for _, state in ipairs(loopy.ppuStates) do
        if state.trigger ~= "mapper" then
            lines[#lines + 1] = string.format(
                "SL=%d trigger=%s v=$%04X t=$%04X x=%d coarse=%d,%d fine=%d,%d NT=%d,%d mask=$%02X BG=%s Spr=%s mirror=%d is2006=%s mapper=%s",
                state.scanLine or 0, state.trigger or "unknown",
                state.v or state.ppuAddress or 0, state.t or 0, state.x or 0,
                state.offset_x or 0, state.offset_y or 0,
                state.fineOffset_x or 0, state.fineOffset_y or 0,
                state.namespace_x or 0, state.namespace_y or 0,
                state.mask or 0,
                state.isDrawScreen == false and "OFF" or "ON",
                state.isDrawSprites == false and "OFF" or "ON",
                state.mirror or 0, state.is2006 and "yes" or "no",
                state.mapperEvent and "yes" or "no")
        end
    end
    return table.concat(lines, "\n")
end

local debugFrameCopyRect = { x = 1186, y = 640, width = 120, height = 24 }
function ppu.GetDebugFrameCopyRect()
    return debugFrameCopyRect
end

function ppu.CopyDebugFrameData()
    love.system.setClipboardText(ppu.GetDebugFrameData())
    ppu.debugFrameCopyStatus = "Frame data copied"
end

local function replaceDebugInspectionState(state)
    for i = #loopy.ppuStates, 1, -1 do
        if loopy.ppuStates[i].trigger == "inspect" then
            table.remove(loopy.ppuStates, i)
        end
    end
    ppu.debugInspectionState = state
    table.insert(loopy.ppuStates, state)
    selectedState = #loopy.ppuStates
end

-- Loading another cartridge is a complete console power cycle. Reset both the
-- public PPU state and the local timing state while retaining table identities
-- that other modules cache.
function ppu.Reset()
    ppu.scanLinePixels = 0
    ppu.scanLines = -1
    ppu.vBlankEnd = false
    ppu.currentFrame = 1
    ppu.debugInspectionState = nil
    ppu.DrawScreen = false
    ppu.debugShowBackground = true
    ppu.debugShowSprites = true
    ppu.sprite0Offset = 0
    ppu.scanLineOffset = 0
    ppu.backgroundEnableOffset = 0
    cachedTileSet = nil

    vBlankFlag = false
    scanLinePixels = 0
    scanLines = -1
    CTRL = 0x00
    STATUS = 0x00
    Sprite0Scanline = 0
    ppuCycles = 0

    ppuIO.CTRL = 0x00
    ppuIO.MASKS = 0x00
    ppuIO.STATUS = 0x00
    ppuIO.OAMADDR = 0x00
    ppuIO.OAMDATA = 0x00
    ppuIO.SCROLL = 0x00
    ppuIO.ADDR = 0x00
    ppuIO.DATA = 0x00
    ppuIO.OAMDMA = 0x00
    ppuIO.NMIArmed = false
    ppuIO.delayPPU = 0
    ppuIO.NameTableAddress = 0x00
    ppuIO.BackgroundTable = 0x00
    ppuIO.SpriteTable = 0x00

    loopy:ResetScroll()
    loopy.ppuStates = {}
    loopy.scanLine = -1
    loopy.scanLinePixels = 0
    loopy.drawScreen = false
    loopy.drawSprites = false
    loopy.inVBlank = false
    loopy.offsetY = 0

    ppuBus.Reset()
end

--# Main Update PPU Cycle
function ppu.Update(cpuCycles)
    ppuCycles = cpuCycles * 3
    Sprite0Scanline = OAM[0]
    STATUS = ppuIO.STATUS
    CTRL = ppuIO.CTRL
    scanLines = ppu.scanLines
    scanLinePixels = ppu.scanLinePixels
    local nmiArmed = ppuIO.NMIArmed
    -- CPU register writes only occur between ppu.Update calls, so this value is
    -- constant for this small batch of PPU dots.
    local renderingEnabled = band(ppuIO.MASKS, 0x18) ~= 0

    if scanLines == 0 and scanLinePixels == 0 then
        ppu.clearPPUStates()
        ppu.DrawScreen = false
        if debug then
            print()
            print("Start Of Frame")
            print("---Start PPU courseX" .. loopy.course_x)
        end
        ppu.savePPUStates(0)
        if ppu.debugInspectionEnabled and EnableDebug and DebugActiveTab == "ppu"
            and ppu.debugInspectionScanline == 0 then
            replaceDebugInspectionState(ppu.GetPPUState(0, 0, false, "inspect"))
        end
    end

    -- Enabling NMI during an already-active vblank takes effect at the next
    -- PPU update boundary. The normal vblank-start edge is handled at dot 2.
    if nmiArmed and scanLines >= 241 and scanLines < 261
        and STATUS >= 0x80 and CTRL >= 0x80 then
        cpuMemory.TriggerNMI = true
        nmiArmed = false
    end

    local spriteHitScanline = Sprite0Scanline + ppu.sprite0Offset
    while ppuCycles > 0 do
        -- No CPU or PPU register access occurs inside this batch. Jump directly
        -- to the end of the batch/scanline and process only event dots crossed
        -- along the way instead of iterating over every PPU dot.
        local oldPixel = scanLinePixels
        local dots = math.min(ppuCycles, 341 - oldPixel)
        local newPixel = oldPixel + dots

        -- Dot 1 events.
        if oldPixel < 1 and newPixel >= 1 then
            if scanLines == 261 then
                vBlankFlag = false
                loopy.inVBlank = false
                STATUS = band(STATUS, 0x1F)
                if debug then print("---VBlank End / Pre-render") end
            elseif scanLines == 241 and STATUS < 0x80 and not vBlankFlag then
                vBlankFlag = true
                loopy.inVBlank = true
                if debug then print("#VBlank Start") end
                ppu.savePPUStates(241)
                STATUS = bor(STATUS, 0x80)
            elseif scanLines > 8 and scanLines < 241
                and scanLines == spriteHitScanline
                and band(STATUS, 0x40) == 0 then
                STATUS = bor(STATUS, 0x60)
                if debug then print("#Sprite0 Hit Scanline " .. Sprite0Scanline) end
            end
        end

        -- The normal vblank NMI edge follows vblank start.
        if scanLines == 241 and oldPixel < 2 and newPixel >= 2
            and nmiArmed and STATUS >= 0x80 and CTRL >= 0x80 then
            cpuMemory.TriggerNMI = true
            nmiArmed = false
            if debug then print("NMI Triggered") end
        end

        -- Rendering reloads horizontal scroll for the next scanline at dot 257.
        if renderingEnabled and oldPixel < 257 and newPixel >= 257
            and (scanLines == 261 or (scanLines >= 0 and scanLines <= 239)) then
            local oldHorizontal = band(loopy.v, 0x041F)
            loopy:CopyHorizontalTToV()

            -- The screen is rendered after the frame from saved PPU states.
            -- A $2005/$2000 write changes t first, so the state saved at the
            -- write still contains the old coarse-X/nametable-X from v.  Once
            -- dot 257 performs the real t -> v reload, replace that scanline's
            -- state so the following rendered line sees the new horizontal
            -- origin.  Avoid recording the normal no-change reload each line.
            if scanLines >= 0 and scanLines <= 239
                and oldHorizontal ~= band(loopy.v, 0x041F) then
                loopy:SearchPPUStatesInRangeAndReplace(
                    scanLines,
                    scanLines,
                    ppu.GetPPUState(scanLines)
                )
            end
        end

        -- During dots 280-304 the pre-render line applies vertical scroll. t is
        -- constant inside this batch, so one copy for the intersecting span is
        -- equivalent to repeating the same copy on every included dot.
        if renderingEnabled and scanLines == 261
            and oldPixel < 304 and newPixel >= 280 then
            loopy:CopyVerticalTToV()
        end

        scanLinePixels = newPixel
        ppuCycles = ppuCycles - dots

        -- Check if we've reached the end of a scanline.
        if scanLinePixels >= 341 then
            scanLinePixels = 0
            scanLines = scanLines + 1
            if scanLines >= 0 and scanLines <= 239 and loopy.drawScreen then ppuBus.ppuScanLineUpdate(scanLines) end -- 241 lines total

            if ppu.debugInspectionEnabled and EnableDebug and DebugActiveTab == "ppu"
                and scanLines == ppu.debugInspectionScanline and scanLines > 0 then
                replaceDebugInspectionState(ppu.GetPPUState(scanLines, 0, false, "inspect"))
            end

            -- Scanline 261 must finish so its scroll transfers can run.
            if scanLines > 261 then
                ppu.scanLines = -1
                ppu.scanLinePixels = 0
                ppuIO.STATUS = STATUS
                ppuIO.NMIArmed = nmiArmed
                loopy.scanLine = 261
                loopy.scanLinePixels = 341
                ppu.StartGameWindow()
                ppu.currentFrame = ppu.currentFrame + 1
                if debug then print("End Of Frame") end
                return false
            end
        end
    end
    ppu.scanLines = scanLines
    ppu.scanLinePixels = scanLinePixels
    loopy.scanLine = scanLines
    loopy.scanLinePixels = scanLinePixels
    ppuIO.STATUS = STATUS
    ppuIO.NMIArmed = nmiArmed
    return true
end

--# clear States
function ppu.clearPPUStates()
    loopy.ppuStates = {}
    ppu.debugInspectionState = nil
end

local function getCachedTileSet()
    local currentMapper = mapper[cart.mapper].mapper
    if currentMapper.chrDirty or not cachedTileSet then
        local snapshotStart = love.timer.getTime()
        cachedTileSet = ppuBus.ppuBuffer(0, 0x1FFF)
        currentMapper.chrDirty = false
        displayTimer.RecordComponent("ppuChrSnapshot", love.timer.getTime() - snapshotStart)
        displayTimer.RecordCounter("ppuChrCopies", 1)
    end
    return cachedTileSet
end

function ppu.GetPPUState(scanLine, offset, is2006, trigger)
    local state = {
        scanLine            = scanLine,
        spriteTileSet       = getCachedTileSet(),
        fineOffset_x        = loopy.x,
        offset_x            = band(loopy.v, 0x001F),
        namespace_x         = bit.rshift(band(loopy.v, 0x0400), 10),
        fineOffset_y        = bit.rshift(band(loopy.v, 0x7000), 12),
        offset_y            = bit.rshift(band(loopy.v, 0x03E0), 5),
        namespace_y         = bit.rshift(band(loopy.v, 0x0800), 11),
        ppuAddress          = loopy.v,
        v                   = loopy.v,
        t                   = loopy.t,
        x                   = loopy.x,
        spriteTable         = ppuIO.SpriteTable,
        backgroundTable     = ppuIO.BackgroundTable,
        mirror              = cart.Mirror,
        isDrawScreen        = loopy.drawScreen,
        isDrawSprites       = loopy.drawSprites,
        mask                = ppuIO.MASKS,
        offsetY             = offset or 0,
        is2006              = is2006 or false,
        trigger             = trigger or "unknown",
        mapperEvent         = trigger == "mapper"
    }
    return state
end

--# Loopy Save State 
function ppu.savePPUStates(scanLine, offset, is2006, trigger)
    local state = {
        scanLine            = scanLine,
        spriteTileSet       = getCachedTileSet(),
        fineOffset_x        = loopy.x,
        offset_x            = band(loopy.v, 0x001F),
        namespace_x         = bit.rshift(band(loopy.v, 0x0400), 10),
        fineOffset_y        = bit.rshift(band(loopy.v, 0x7000), 12),
        offset_y            = bit.rshift(band(loopy.v, 0x03E0), 5),
        namespace_y         = bit.rshift(band(loopy.v, 0x0800), 11),
        ppuAddress          = loopy.v,
        v                   = loopy.v,
        t                   = loopy.t,
        x                   = loopy.x,
        spriteTable         = ppuIO.SpriteTable,
        backgroundTable     = ppuIO.BackgroundTable,
        mirror              = cart.Mirror,
        isDrawScreen        = loopy.drawScreen,
        isDrawSprites       = loopy.drawSprites,
        mask                = ppuIO.MASKS,
        offsetY             = offset or 0,
        is2006              = is2006 or false,
        trigger             = trigger or "scanline",
        mapperEvent         = trigger == "mapper"
    }
    table.insert(loopy.ppuStates, state)
    loopy.ppuStatesVersion = (loopy.ppuStatesVersion or 0) + 1
end

--! MAIN DRAW
-- DRAW SCREEN
local imageX = 256
local imageY = 240
-- Screen Buffer -- buffer to store the image data This STARTS Alpha 0
ppu.screenBuffer = love.image.newImageData(imageX, imageY, "rgba8")
-- CHR Buffer 0
ppu.patternbuffer0 = love.image.newImageData(128, 128, "rgba8")
ppu.patternScreen0 = love.graphics.newImage(ppu.patternbuffer0)
-- CHR Buffer 1
ppu.patternbuffer1 = love.image.newImageData(128, 128, "rgba8")
ppu.patternScreen1 = love.graphics.newImage(ppu.patternbuffer1)

function ppu.FFIBuffer(ArrayToRender, screenImage, buffer)
    local pointer = require("ffi").cast("uint8_t*", buffer:getFFIPointer())
    local pixelCount = (4 * screenImage:getWidth() * screenImage:getHeight()) - 1
    for i = 0, pixelCount, 4 do
        pointer[i] = ArrayToRender[i] or 0
        pointer[i + 1] = ArrayToRender[i + 1] or 0
        pointer[i + 2] = ArrayToRender[i + 2] or 0
        pointer[i + 3] = ArrayToRender[i + 3] or 0
    end
    screenImage:replacePixels(buffer)
end

function ppu.StartGameWindow()
    local ppuRenderStart = love.timer.getTime()
    displayTimer.RecordGauge("ppuStateCount", #loopy.ppuStates)
--# Draw Background with 3F00 Color 
    local ptrScreenBuffer = require("ffi").cast("uint32_t*", ppu.screenBuffer:getFFIPointer())
    local setupStart = love.timer.getTime()
    PPUtoLove.SetupScreenArray(ptrScreenBuffer)
    displayTimer.RecordComponent("ppuSetup", love.timer.getTime() - setupStart)
--# Draw Sprites behind background
    local spriteStart = love.timer.getTime()
    local debugLayers = EnableDebug and DebugActiveTab == "ppu"
    local showBackground = not debugLayers or ppu.debugShowBackground
    local showSprites = not debugLayers or ppu.debugShowSprites
    if showSprites then
        PPUtoLove.DrawBehindSpritesOnly(ptrScreenBuffer)
    end
    displayTimer.RecordComponent("ppuSprites", love.timer.getTime() - spriteStart)
--# Draw Background 
    local backgroundStart = love.timer.getTime()
    -- Rendering can be enabled and disabled mid-frame.  Do not use the
    -- final mask value as a frame-wide gate: DrawMainScreen applies each
    -- saved scanline state's isDrawScreen flag and leaves disabled lines at
    -- the backdrop color.
    if showBackground then
        PPUtoLove.DrawMainScreen(ptrScreenBuffer)
    end
    displayTimer.RecordComponent("ppuBackground", love.timer.getTime() - backgroundStart)
--# Draw Forground Sprites
    local foregroundStart = love.timer.getTime()
    if showSprites then
        PPUtoLove.DrawInFrontSpritesOnly(ptrScreenBuffer)
    end
    displayTimer.RecordComponent("ppuSprites", love.timer.getTime() - foregroundStart)
--# Load Background to buffer
    local uploadStart = love.timer.getTime()
    PPUtoLove.FrameToScreen(ppu.screenBuffer)
    displayTimer.RecordComponent("ppuUpload", love.timer.getTime() - uploadStart)
--# ppuOAM.Clear()
    if Profile then
        profile.stop()
        print(profile.report(20))
        profile.reset()
    end
    displayTimer.RecordComponent("ppu", love.timer.getTime() - ppuRenderStart)
end

function ppu.StartScreenToNumbers()
    PPUtoLove.ScreenToNumbers(ppu.patternScreen0 , ppu.patternScreen1)
end

local CHR0 = {}
local CHR1 = {}
local debugNametable1 = nil
local debugNametable2 = nil
local chrDebugX0 = 10
local chrDebugX1 = 280
local chrDebugY0 = 560
local chrDebugY1 = 560
local chrDebugScale = 2
local debugNametableMode = 0 -- 0=native, 1=all nametable A, 2=all nametable B

function ppu.CycleDebugNametableMode()
    debugNametableMode = (debugNametableMode + 1) % 3
end

function ppu.GetDebugNametableModeLabel()
    if debugNametableMode == 1 then return "All A" end
    if debugNametableMode == 2 then return "All B" end
    return "Native"
end

function ppu.DrawMirroredNametables(nametable1, nametable2, mirrorMode)
    -- Base positions (x, y) for 2x2 grid
    -- Display mirror mode
    local mirrorNames = {
        [0] = "HORIZONTAL (0): A A B B",
        [1] = "VERTICAL (1): A B A B",
        [2] = "SINGLE LOW (2): A A A A",
        [3] = "SINGLE HIGH (3): B B B B"
    }
    local mirrorLabel = mirrorNames[cart.Mirror] or "Unknown Mirror Mode"
    if debugNametableMode == 1 then mirrorLabel = mirrorLabel .. "  |  DEBUG: ALL A" end
    if debugNametableMode == 2 then mirrorLabel = mirrorLabel .. "  |  DEBUG: ALL B" end
    love.graphics.print(mirrorLabel, 1000, 80)

    local x = 1000
    local y = 100
    local positions = {
        {x = x+10,   y = y+0},    -- Position 0 (Top Left)
        {x = x+266,  y = y+0},    -- Position 1 (Top Right)
        {x = x+10,   y = y+240},    -- Position 2 (Bottom Left)
        {x = x+266,  y = y+240}     -- Position 3 (Bottom Right)
    }
    
    -- Mirror mapping tables (which nametable goes where)
    local mirrorMap = {
        [0] = {nametable1, nametable1, nametable2, nametable2}, -- A A B B Horizontal
        [1] = {nametable1, nametable2, nametable1, nametable2},   -- A B A B Vertical
        [2] = {nametable1, nametable1, nametable1, nametable2},     -- A A A B Single Low
        [3] = {nametable2, nametable2, nametable2, nametable1}        -- B B B A Single High
    }
    
    -- Get correct mapping based on mirror mode
    local layout = mirrorMap[mirrorMode]
    if debugNametableMode == 1 then
        layout = {nametable1, nametable1, nametable1, nametable1}
    elseif debugNametableMode == 2 then
        layout = {nametable2, nametable2, nametable2, nametable2}
    end
    love.graphics.setColor(1, 1, 1, 1)
    -- Draw all four positions
    for i = 1, 4 do
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(layout[i], positions[i].x, positions[i].y)
        -- Add position label for debugging
        love.graphics.print(i-1, positions[i].x, positions[i].y-15)
    end
end

-- CAN select Sprite0 Scanline to see Tiles loaded 
function ppu.StartCharacterTiles()
    PPUtoLove.DrawCHR(CHR0, 0,selectedState)
    PPUtoLove.DrawCHR(CHR1, 1,selectedState)

    ppu.FFIBuffer(CHR0, ppu.patternScreen0, ppu.patternbuffer0)
    ppu.FFIBuffer(CHR1, ppu.patternScreen1, ppu.patternbuffer1)
end

-- Rebuild the expensive debug images. Call this at a limited rate while the
-- debugger is running; DrawCharacterTiles below can still run every frame.
function ppu.UpdateCharacterTiles()
    ppu.StartCharacterTiles()
    debugNametable1, debugNametable2 = PPUtoLove.ScreenToNumbers(ppu.patternScreen0, ppu.patternScreen1)
end

function ppu.SelectDebugState(delta)
    local totalStates = #loopy.ppuStates
    if totalStates == 0 then return end
    selectedState = (selectedState - 1 + delta) % totalStates + 1
end

function ppu.DrawCharacterTiles()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(ppu.patternScreen0, chrDebugX0, chrDebugY0, 0, chrDebugScale)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(ppu.patternScreen1, chrDebugX1, chrDebugY1, 0, chrDebugScale)
    -- Draw PPU state selector under nametable debug screens (right side)
    local stateX = 1010
    local stateY = 640
    local totalStates = #loopy.ppuStates
    local itemsPerRow = 4
    local itemWidth = 110
    local itemHeight = 22
    local spacing = 5
    
    local function stateButton(label, x, width)
        width = width or 80
        love.graphics.setColor(0.08, 0.16, 0.22, 1)
        love.graphics.rectangle("fill", x, stateY, width, 24, 3, 3)
        love.graphics.setColor(0.45, 0.75, 0.9, 1)
        love.graphics.rectangle("line", x, stateY, width, 24, 3, 3)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(label, x, stateY + 4, width, "center")
    end
    stateButton("C  Prev", stateX)
    stateButton("V  Next", stateX + 88)
    stateButton("COPY FRAME", debugFrameCopyRect.x, debugFrameCopyRect.width)
    if ppu.debugFrameCopyStatus then
        love.graphics.setColor(0.35, 1, 0.55, 1)
        love.graphics.print(ppu.debugFrameCopyStatus, debugFrameCopyRect.x, debugFrameCopyRect.y + 28)
    end

    love.graphics.setColor(0.65, 0.85, 0.95, 1)
    love.graphics.printf("SCREEN CHANGES: " .. ppu.GetDebugScreenChanges(),
        stateX - 410, stateY + 4, 400, "left")

    -- Show the important saved PPU state values for the selected scanline.
    local selected = loopy.ppuStates[selectedState]
    if selected then
        local detailX = stateX
        local detailY = stateY - 42
        love.graphics.setColor(0.7, 0.82, 0.92, 1)
        love.graphics.print(string.format(
            "Selected SL:%d  trigger:%s  NT:%d,%d  coarse:%d,%d  fine:%d,%d",
            selected.scanLine or 0, selected.trigger or "unknown",
            selected.namespace_x or 0, selected.namespace_y or 0,
            selected.offset_x or 0,
            selected.offset_y or 0, selected.fineOffset_x or 0,
            selected.fineOffset_y or 0), detailX, detailY)
        love.graphics.print(string.format(
            "MASK:$%02X  BG table:%d  Sprite table:%d  Mirror:%d  BG:%s  Sprites:%s",
            selected.mask or 0,
            selected.backgroundTable or 0, selected.spriteTable or 0,
            selected.mirror or 0, selected.isDrawScreen == false and "OFF" or "ON",
            selected.isDrawSprites == false and "OFF" or "ON"), detailX, detailY + 20)
    end
    
    for i = 1, totalStates do
        local state = loopy.ppuStates[i]
        local col = (i - 1) % itemsPerRow
        local row = math.floor((i - 1) / itemsPerRow)
        local xPos = stateX + col * (itemWidth + spacing)
        local yPos = stateY + 30 + row * (itemHeight + spacing)
        
        if i == selectedState then
            love.graphics.setColor(0, 1, 0.4, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        love.graphics.rectangle("fill", xPos, yPos, itemWidth, itemHeight, 3, 3)
        love.graphics.setColor(0, 0, 0, 1)
        local reason = state.trigger or "unknown"
        if state.mapperEvent and reason ~= "mapper" then reason = reason .. "+mapper" end
        love.graphics.print(string.format("%d/%d  SL:%d %s", i, totalStates, state.scanLine, reason), xPos + 4, yPos + 3)
    end
    love.graphics.setColor(1, 1, 1, 1)
    --ppu.StartCharacterTiles()
    if debugNametable1 and debugNametable2 then
        ppu.DrawMirroredNametables(debugNametable1, debugNametable2, cart.Mirror)
    end
end

return ppu
