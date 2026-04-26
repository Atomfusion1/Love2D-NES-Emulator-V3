local cart          = require("NES.Cartridge.Cartridge")
local cpuMemory     = require("NES.CPU.cpuInternal")
local PPUtoLove     = require("NES.PPU.PPUtoLove2d")
local ppuIO         = require("NES.PPU.ppuIO")
local OAM           = require("NES.PPU.ppuOAM")
local loopy         = require("NES.PPU.loopy")
local ppuBus        = require("NES.PPU.ppuBus")
local profile       = require("Includes.profile.profile")
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
local NMIArmed = false
local scanLinePixels
local scanLines
local CTRL
local STATUS
local Sprite0Scanline
local ppuCycles
local debug = false
local scanLineHit = false

ppu.DrawScreen = false
--# Main Update PPU Cycle
function ppu.Update(cpuCycles)
    ppuCycles = cpuCycles * 3
    Sprite0Scanline = OAM[0]
    STATUS = ppuIO.STATUS
    CTRL = ppuIO.CTRL
    scanLines = ppu.scanLines
    scanLinePixels = ppu.scanLinePixels
    NMIArmed = ppuIO.NMIArmed621828621828
    while ppuCycles > 0 and not ppu.vBlankEnd do
        if scanLines == 2 and scanLinePixels == 0 then
            ppu.clearPPUStates()
            ppu.DrawScreen = false
            if debug then print( ) print("Start Of Frame") end
            ppu.savePPUStates(0)
        end
        --% Increment scanline pixel count
        if debug and scanLinePixels == 0 and scanLines == 0 then
            print("---Start PPU courseX"..loopy.course_x)
        end
        scanLinePixels = scanLinePixels + 1
        loopy.scanLine = scanLines
        loopy.scanLinePixels = scanLinePixels
        --& Check if the first sprite of the scanline is visible
        if scanLines > 8 and scanLines < 241 and scanLines == Sprite0Scanline + ppu.sprite0Offset and not (band(STATUS, 0x40) > 0) then
            STATUS = bor(STATUS, 0x40)
            STATUS = bor(STATUS, 0x20)
            if debug then print("#Sprite0 Hit Scanline "..Sprite0Scanline) end
        end
        
        --& Check if we've reached the end of a scanline
        if scanLinePixels >= 341 then
            scanLinePixels = 0
            scanLines = scanLines + 1
            if scanLines >= 0 and scanLines <= 239 and loopy.drawScreen then ppuBus.ppuScanLineUpdate(scanLines) end -- 241 lines total 
        end
        --& Check if we're in vBlank
        if scanLines >= 241 then
            --& Set NMI After VBlank Start by 3 Pixels -- Fixed Solomons Keys Startup
            if ppuIO.NMIArmed and STATUS >= 0x80 and CTRL >= 0x80 then
                --* Set CPU NMI
                cpuMemory.TriggerNMI = true
                ppuIO.NMIArmed = false
                if debug then print("NMI Triggered") end
            end
            --& Start VBlank if we're on the first Pixel of the 241st scanline
            if scanLines == 241 and scanLinePixels == 1 and STATUS < 0x80 and vBlankFlag == false then
                vBlankFlag = true
                loopy.inVBlank = true
                if debug then print("#VBlank Start") end
                ppu.savePPUStates(241)
                STATUS = bor(STATUS,0x80)
            end
            --& Check if vBlank has ended
            if scanLines >= 261 and vBlankFlag == true then
                if debug then print("---VBlank End \n") end
                vBlankFlag = false
                loopy.inVBlank = false
                STATUS = 0x00
                ppuCycles = ppuCycles - 1
                ppu.scanLines = -1
                ppu.scanLinePixels = 0
                ppu.StartGameWindow()
                ppu.currentFrame = ppu.currentFrame + 1
                if debug then print("End Of Frame") end
                return false
            end
        end
        --* Decrement cycle count
        ppuCycles = ppuCycles - 1
    end
    ppu.scanLines = scanLines
    ppu.scanLinePixels = scanLinePixels
    ppuIO.STATUS = STATUS
    return true
end

--# clear States
function ppu.clearPPUStates()
    loopy.ppuStates = {}
    cachedTileSet = nil
end

local function getCachedTileSet()
    local currentMapper = mapper[cart.mapper].mapper
    if currentMapper.chrDirty or not cachedTileSet then
        cachedTileSet = ppuBus.ppuBuffer(0, 0x1FFF)
        currentMapper.chrDirty = false
    end
    return cachedTileSet
end

function ppu.GetPPUState(scanLine, offset, is2006)
    local state = {
        scanLine            = scanLine,
        spriteTileSet       = getCachedTileSet(),
        fineOffset_x        = loopy.fine_x,
        offset_x            = loopy.course_x,
        namespace_x         = loopy.nametable_x,
        fineOffset_y        = loopy.fine_y,
        offset_y            = loopy.course_y,
        namespace_y         = loopy.nametable_y,
        ppuAddress          = loopy.register_vram_addr,
        spriteTable         = ppuIO.SpriteTable,
        backgroundTable     = ppuIO.BackgroundTable,
        mirror              = cart.Mirror,
        isDrawScreen        = loopy.drawScreen,
        isDrawSprites       = loopy.drawSprites,
        offsetY             = offset or 0,
        is2006              = is2006 or false
    }
    return state
end

--# Loopy Save State 
function ppu.savePPUStates(scanLine, offset, is2006)
    local state = {
        scanLine            = scanLine,
        spriteTileSet       = getCachedTileSet(),
        fineOffset_x        = loopy.fine_x,
        offset_x            = loopy.course_x,
        namespace_x         = loopy.nametable_x,
        fineOffset_y        = loopy.fine_y,
        offset_y            = loopy.course_y,
        namespace_y         = loopy.nametable_y,
        ppuAddress          = loopy.register_vram_addr,
        spriteTable         = ppuIO.SpriteTable,
        backgroundTable     = ppuIO.BackgroundTable,
        mirror              = cart.Mirror,
        isDrawScreen        = loopy.drawScreen,
        isDrawSprites       = loopy.drawSprites,
        offsetY             = offset or 0,
        is2006              = is2006 or false
    }
    table.insert(loopy.ppuStates, state)
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
    if collectgarbage("count") > 20000 then collectgarbage() end -- This is BAD I do not want this
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
--# Draw Background with 3F00 Color 
    local ptrScreenBuffer = require("ffi").cast("uint32_t*", ppu.screenBuffer:getFFIPointer())
    PPUtoLove.SetupScreenArray(ptrScreenBuffer)
--# Draw Sprites behind background
    PPUtoLove.DrawBehindSpritesOnly(ptrScreenBuffer)
--# Draw Background 
    if loopy.drawScreen then PPUtoLove.DrawMainScreen(ptrScreenBuffer) end
--# Draw Forground Sprites
    PPUtoLove.DrawInFrontSpritesOnly(ptrScreenBuffer)
--# Load Background to buffer
    PPUtoLove.FrameToScreen(ppu.screenBuffer)
--# ppuOAM.Clear()
    if Profile then
        profile.stop()
        print(profile.report(20))
        profile.reset()
    end
end

function ppu.StartScreenToNumbers()
    PPUtoLove.ScreenToNumbers(ppu.patternScreen0 , ppu.patternScreen1)
end

local CHR0 = {}
local CHR1 = {}

function ppu.DrawMirroredNametables(nametable1, nametable2, mirrorMode)
    -- Base positions (x, y) for 2x2 grid
    -- Display mirror mode
    local mirrorNames = {
        [0] = "HORIZONTAL (0): A A B B",
        [1] = "VERTICAL (1): A B A B",
        [2] = "SINGLE LOW (2): A A A A",
        [3] = "SINGLE HIGH (3): B B B B"
    }
    love.graphics.print(mirrorNames[cart.Mirror] or "Unknown Mirror Mode", 10, 470)

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
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(mirrorNames[cart.Mirror] or "Unknown Mirror Mode", x+20, y-20, 0, 1, 1)
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

function ppu.DrawCharacterTiles()
    ppu.StartCharacterTiles()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(ppu.patternScreen0, 10, 500, 0, 2)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(ppu.patternScreen1, 275, 500, 0, 2)
    -- Draw PPU state selector under nametable debug screens (right side)
    local stateX = 1010
    local stateY = 590
    local totalStates = #loopy.ppuStates
    local itemsPerRow = 4
    local itemWidth = 110
    local itemHeight = 22
    local spacing = 5
    
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.print("[C] prev  [V] next", stateX, stateY)
    
    for i = 1, totalStates do
        local state = loopy.ppuStates[i]
        local col = (i - 1) % itemsPerRow
        local row = math.floor((i - 1) / itemsPerRow)
        local xPos = stateX + col * (itemWidth + spacing)
        local yPos = stateY + 18 + row * (itemHeight + spacing)
        
        if i == selectedState then
            love.graphics.setColor(0, 1, 0.4, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        love.graphics.rectangle("fill", xPos, yPos, itemWidth, itemHeight, 3, 3)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.print(string.format("%d/%d  SL:%d", i, totalStates, state.scanLine), xPos + 4, yPos + 3)
    end
    love.graphics.setColor(1, 1, 1, 1)
    --ppu.StartCharacterTiles()
    local nametable1, nametable2 = PPUtoLove.ScreenToNumbers(ppu.patternScreen0, ppu.patternScreen1)
    ppu.DrawMirroredNametables(nametable1, nametable2, cart.Mirror)
end

return ppu
