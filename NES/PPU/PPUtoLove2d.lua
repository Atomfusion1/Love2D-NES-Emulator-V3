local bus           = require("NES.PPU.ppuBus")
local colors        = require("NES.PPU.VGA_Pallette").Pallette
local colors32      = require("NES.PPU.VGA_Pallette").Pallette_32bit2
local nameTable     = require("NES.PPU.ppunametable")
local OAM           = require("NES.PPU.ppuOAM")
local ppuIO         = require("NES.PPU.ppuIO")
local loopy         = require("NES.PPU.loopy")
local cart          = require("NES.Cartridge.Cartridge")


local PPUtoLove2d = {}
PPUtoLove2d.PointerArray = {}

local band, lshift, rshift,bor = bit.band,bit.lshift,bit.rshift, bit.bor
local PPURead = bus.PPURead
local ramBuffer = {}
local ramBuffer32 = {}

--# Create Ram Buffer of the Colors in use OLD 
local function fillRamBufferWithColors()
    for i = 0x3F00, 0x3F1F do
        local value = PPURead(i) or 0x00
        if value > 0x3F then value = band(value,0x3F) end
        ramBuffer[i] = colors[value]
    end
end



-- Optimized fill function
local function fillRamBufferWithColors32()
    local start = 0x3F00
    local stop = 0x3F1F  -- Reduced range since palette is only 32 bytes
    local tablePalette = nameTable.tblPalette
    for i = start, stop do
        ramBuffer32[i] = colors32[tablePalette[i-0x3F00]]
    end

end

--# Draw CHR Tiles in Debug
function PPUtoLove2d.DrawCHR(array, CHRTileSet, offset)
    fillRamBufferWithColors()
    if not loopy.ppuStates[offset] or not loopy.ppuStates[offset].spriteTileSet[0] then return end
    local NumberSprites = 64
    local spriteHeight = (NumberSprites == 64) and 8 or 16
    local colorOffset = G_ColorOffset
    local image = loopy.ppuStates[offset].spriteTileSet

    for nTileY = 0, 15 do
        for nTileX = 0, 15 do
            local nOffset = nTileY * 256 + nTileX * 16

            for littleY = 0, spriteHeight - 1 do
                local i = CHRTileSet
                local tileAddr
                if spriteHeight == 16 then
                    local isBottomHalf = littleY >= 8
                    tileAddr = i * 0x1000 + nOffset + (isBottomHalf and 16 or 0) + (littleY % 8)
                else
                    tileAddr = i * 0x1000 + nOffset + littleY
                end
                
                local tile_lsb = image[tileAddr]
                local tile_msb = image[tileAddr + 8]

                local x_offset = nTileX * 8
                -- Corrected line: use spriteHeight instead of hardcoded 16
                local y_offset = nTileY * spriteHeight * 128 + littleY * 128
                if tile_lsb == nil then return end

                for x = 7, 0, -1 do
                    local pixel = bor(band(tile_lsb, 0x01), lshift(band(tile_msb, 0x01), 1))
                    tile_msb = rshift(tile_msb, 1)
                    tile_lsb = rshift(tile_lsb, 1)
                    local pixelIndex = 4 * (x_offset + x + y_offset)
                    -- Pixel value 0 is transparent/universal background on
                    -- the NES; it always uses $3F00, not $3F04/$3F08/$3F0C.
                    local paletteAddress = (pixel == 0)
                        and 0x3F00
                        or (0x3F00 + colorOffset * 4 + pixel)
                    Setup1DArray(paletteAddress, array, pixelIndex)
                end
            end
        end
    end
    return array
end

local pixelCount = 256 * 240 * 4
local ffi = require("ffi")
local screenArray = ffi.new("uint8_t[?]", pixelCount)

--# Clear Background to Background Pallette Color
function PPUtoLove2d.SetupScreenArray(ptrScreenBuffer)
    fillRamBufferWithColors32()  -- update palette values
    local color = ramBuffer32[0x3F00]  -- a 32-bit color value
    local pixelCount = 256 * 240       -- total number of pixels
    -- Cast the pointer (assumed to be a uint8_t buffer of pixelCount*4 bytes)
    local pixels = ffi.cast("uint32_t*", ptrScreenBuffer)
    for i = 0, pixelCount - 1 do
        pixels[i] = color or 0x00000000  -- Set each pixel to the background color
    end
end

--# Draw Main Screen Helper
local function SelectAttributeValue(attributeTable, c_X, c_Y)
    local Attr_X    = c_X % 4 -- get the last 2 bits of c_X
    local Attr_Y    = c_Y % 4 -- get the last 2 bits of c_Y
    local offset    = math.floor(Attr_Y / 2) * 4
    local shift     = math.floor(Attr_X / 2) * 2
    return band(rshift(attributeTable, offset + shift), 0x03)
end

--# Draw Main Screen Helper
local function calculateTileAndAttributeAddresses(ScrollX, ScrollY, localNamespace)
    local tileAddress         = localNamespace + ScrollY * 32 + ScrollX
    local tileID              = nameTable.NameTableMirrorRead(tileAddress)
    local attributeAddress    = 0x03C0 + (rshift(ScrollY, 2)) * 8 + rshift(ScrollX, 2) + localNamespace
    local attributeByte       = nameTable.NameTableMirrorRead(attributeAddress)
    local attributeValue      = SelectAttributeValue(attributeByte, ScrollX, ScrollY)
    return tileID, attributeValue
end

local function drawTileRow(screenTileX, screenTileY, fineY, tile_lsb, tile_msb, attributeValue, ptrScreenBuffer)
    for fineX = 0, 7 do
        local screenX = screenTileX + fineX
        local screenY = screenTileY + fineY
        if screenX >= 0 and screenX < 256 and screenY >= 0 and screenY < 240 then
            local pixelPosition = screenX + screenY * 256
            -- The leftmost pixel is stored in bit7, so compute bit index as 7 - fineX
            local bitIndex = 7 - fineX
            local pixelLSB = bit.band(tile_lsb, bit.lshift(1, bitIndex)) ~= 0 and 1 or 0
            local pixelMSB = bit.band(tile_msb, bit.lshift(1, bitIndex)) ~= 0 and 1 or 0
            local pixel = pixelLSB + (pixelMSB * 2)
            if pixel ~= 0 then
                local colorAddress = 0x3F00 + attributeValue * 4 + pixel
                ptrScreenBuffer[pixelPosition] = ramBuffer32[colorAddress]
            end
        end
    end
end

printScanline = 100

--! MAIN DRAW LOOP 
--! ****************************
function PPUtoLove2d.DrawMainScreen(ptrScreenBuffer)
    local ppuIRQCount = 1
    local states = loopy.ppuStates
    local state = states[1]
    if not state then return end
    local nametableX, nametableY = state.namespace_x, state.namespace_y
    local coarseScrollX, coarseScrollY = state.offset_x, state.offset_y
    local fineXOffset, fineYOffset = state.fineOffset_x, state.fineOffset_y
    local tileSet, backgroundTable = state.spriteTileSet, state.backgroundTable
    local scanLineOffset = require("NES.PPU.ppu").scanLineOffset
    local scanLine = -1
    local baseScreenX, baseScreenY = -fineXOffset, -fineYOffset
    local screenY = 0
    for tileY = 0, 30 do
        for fineY = 0, 7 do
            if scanLine < 241 and states[ppuIRQCount + 1]
                and scanLine == states[ppuIRQCount + 1].scanLine + scanLineOffset then
                ppuIRQCount = ppuIRQCount + 1
                state = states[ppuIRQCount]
                -- A PPUMASK ($2001) state is a rendering-layer change, not a
                -- scroll/nametable change. Keep the prior background source
                -- so enabling sprites or masking the screen cannot blank or
                -- reposition the map.
                if state.trigger ~= "$2001" then
                    nametableX, nametableY = state.namespace_x, state.namespace_y
                    coarseScrollX, coarseScrollY = state.offset_x, state.offset_y
                    fineXOffset, fineYOffset = state.fineOffset_x, state.fineOffset_y
                    tileSet, backgroundTable = state.spriteTileSet, state.backgroundTable
                    cart.Mirror = state.mirror
                    baseScreenX, baseScreenY = -fineXOffset, -fineYOffset
                    if state.is2006 then
                        local holder = tileY - state.offsetY
                        coarseScrollY = -holder
                    end
                end
            end
            local tileYIndex, effectiveNametableY = loopy.AdvanceVertical(
                coarseScrollY, nametableY, screenY)
            if state.isDrawScreen ~= false then
                for tileX = -1, 32 do
                    local screenTileX = baseScreenX + tileX * 8
                    local screenTileY = baseScreenY + tileY * 8
                    local tileXIndex = tileX + coarseScrollX
                    local effectiveNametableX = nametableX
                    if tileXIndex < 0 then
                        tileXIndex = tileXIndex + 32
                        effectiveNametableX = 1 - effectiveNametableX
                    elseif tileXIndex >= 32 then
                        tileXIndex = tileXIndex - 32
                        effectiveNametableX = 1 - effectiveNametableX
                    end
                    local localNamespace = 0x2000
                        + effectiveNametableX * 0x400 + effectiveNametableY * 0x800
                    local tileID, attributeValue = calculateTileAndAttributeAddresses(
                        tileXIndex, tileYIndex, localNamespace)
                    local tileAddr = backgroundTable * 0x1000 + tileID * 16 + fineY
                    local tile_lsb, tile_msb = tileSet[tileAddr], tileSet[tileAddr + 8]
                    if tile_lsb == nil then return end
                    drawTileRow(screenTileX, screenTileY, fineY, tile_lsb, tile_msb,
                        attributeValue, ptrScreenBuffer)
                end
            end
            scanLine = scanLine + 1
        end
        screenY = screenY + 1
    end
end



--# Draw Sprites Helper
local function getTileData(fineY, tileIndex, flipV, spriteHeight, use8x16Sprites, passSpritePattern)
    local actualFineY = (flipV and (spriteHeight - 1 - fineY) or fineY)
    local tileID = tileIndex
    local spriteTable

    if use8x16Sprites then
        spriteTable = band(tileID, 0x01) * 0x1000
        tileID = band(tileID, 0xFE)
        if actualFineY >= 8 then
            tileID = tileID + 1
            actualFineY = actualFineY - 8
        end
    else
        spriteTable = passSpritePattern * 0x1000
    end

    return actualFineY, tileID, spriteTable
end

--# Draw Sprites Helper
local function drawSpritePixels(ptrScreenBuffer, littleY, tileIndex, palette, x, flipH, flipV, spriteHeight, use8x16Sprites, tableBuffer, passSpritePattern)
    for fineY = 0, spriteHeight - 1 do
        local actualFineY, tileID , spriteTable = getTileData(fineY, tileIndex, flipV, spriteHeight, use8x16Sprites, passSpritePattern)
        local nAddress = spriteTable + tileID * 16 + actualFineY
        local tile_lsb = tableBuffer[nAddress]
        if tile_lsb == nil then return end
        local tile_msb = tableBuffer[nAddress + 8]

        for fineX = 7, 0, -1 do
            local pixel = bor(band(tile_lsb, 0x01), lshift(band(tile_msb, 0x01), 1))
            tile_msb = rshift(tile_msb, 1)
            tile_lsb = rshift(tile_lsb, 1)
            local xIndex = x + (flipH and (7 - fineX) or fineX)
            local yIndex = ((littleY) * 256) + fineY * 256
            local pixelIndex = (xIndex + yIndex)
            if pixel ~= 0 and pixelIndex < 61400 then -- If 0 ignore it (transparent) if at edge of screen also ignore it to protect the array size 
                Setup1DArray32(0x3F10 + palette * 4 + pixel, ptrScreenBuffer, pixelIndex)
            end
        end
    end
end

--# Draw Sprites Helper
local function getSpriteData(spriteIndex)
    return OAM[spriteIndex * 4 + 0], OAM[spriteIndex * 4 + 1], OAM[spriteIndex * 4 + 2], OAM[spriteIndex * 4 + 3]
end
local function getSpriteAttributes(attributes)
    return band(attributes, 0x03), band(attributes, 0x40) > 0, band(attributes, 0x80) > 0
end

--# Draw Sprites Helper
local function processSprite(ptrScreenBuffer, spriteIndex, spriteHeight, use8x16Sprites)
    local states = loopy.ppuStates
    if not states[1] then
        return
    end

    local scanLines, tileIndex, attributes, x = getSpriteData(spriteIndex)
    scanLines = scanLines + 1
    if scanLines <= 1 or scanLines > 239 then
        return
    end
    local passTableBuffer = states[#states].spriteTileSet
    local passSpritePattern = states[#states].spriteTable
    
    -- Iterate through states
    for i = 1, #states do
        local nextScanLine = states[i + 1] and states[i + 1].scanLine or 241
        -- Check if scanLines is between the scanLine of the current state and the next state
        if scanLines >= states[i].scanLine and scanLines < nextScanLine then
            -- Check the ACTUAL matching state, not stateFound=1
            if states[i].isDrawSprites == false then return end
            passTableBuffer = states[i].spriteTileSet
            passSpritePattern = states[i].spriteTable
            break -- Exit loop
        end
    end
    local palette, flipH, flipV = getSpriteAttributes(attributes)
    drawSpritePixels(ptrScreenBuffer, scanLines, tileIndex, palette, x, flipH, flipV, spriteHeight, use8x16Sprites, passTableBuffer, passSpritePattern)
end

local function getBit(number, position)
    -- Shift 1 to the target position and AND with number
    return (bit.band(number, bit.lshift(1, position)) ~= 0) and 1 or 0
end

--# 2. Draw a single pass of sprites that are labeled as behind the background
function PPUtoLove2d.DrawBehindSpritesOnly(ptrScreenBuffer)
    local numSprites = 64
    local spriteHeight = ((band(ppuIO.CTRL, 0x20) == 0x20) and 16 or 8)
    local use8x16Sprites = (spriteHeight == 16)

    for spriteIndex = numSprites - 1, 0, -1 do
        local _, _, attributes, _ = getSpriteData(spriteIndex)
        local background = getBit(attributes, 5) == 1 and true or false
        if background then
            processSprite(ptrScreenBuffer, spriteIndex, spriteHeight, use8x16Sprites)
        end
    end
end

--# 3. Draw a single pass of sprites that are labeled as in front of the background
function PPUtoLove2d.DrawInFrontSpritesOnly(ptrScreenBuffer)
    local numSprites = 64
    local spriteHeight = ((band(ppuIO.CTRL, 0x20) == 0x20) and 16 or 8)
    local use8x16Sprites = (spriteHeight == 16)

    for spriteIndex = numSprites - 1, 0, -1 do
        local _, _, attributes, _ = getSpriteData(spriteIndex)
        local forground = getBit(attributes, 5) == 0 and true or false
        
        if forground then
            processSprite(ptrScreenBuffer, spriteIndex, spriteHeight, use8x16Sprites)
        end
    end
end

function Setup1DArray32(colorAddress, ptrScreenBuffer, pixelPosition)
        local color32 = ramBuffer32[colorAddress] or 0x00000000
        ptrScreenBuffer[pixelPosition] = color32
end

function Setup1DArray(address,PointerArray, location)
    local color = ramBuffer[address]
    if color ~= nil then
    PointerArray[location],
    PointerArray[location + 1],
    PointerArray[location + 2],
    PointerArray[location + 3] = color[1], color[2], color[3], color[4]
    end
end

--& MAIN DRAW Buffer and Setup
-- DRAW SCREEN
local imageX = 256
local imageY = 240
-- Screen Buffer -- buffer to store the image data This STARTS Alpha 0
local screenBuffer = love.image.newImageData(imageX, imageY, "rgba8")
local screenImage = love.graphics.newImage(screenBuffer)
local nametableCanvasA = nil
local nametableCanvasB = nil
local nametableQuads = {}
local nametablePatternImages = {}
local nametablePatternBuffers = {}

local function getNametableQuad(tileId)
    local quad = nametableQuads[tileId]
    if quad then return quad end
    local offsetX = bit.lshift(bit.band(tileId, 0x0F), 3)
    local offsetY = bit.lshift(bit.band(bit.rshift(tileId, 4), 0x0F), 3)
    quad = love.graphics.newQuad(offsetX, offsetY, 8, 8, 128, 128)
    nametableQuads[tileId] = quad
    return quad
end

local function selectAttributeValue(attributeByte, tileX, tileY)
    local quadrantX = math.floor((tileX % 4) / 2)
    local quadrantY = math.floor((tileY % 4) / 2)
    return bit.band(bit.rshift(attributeByte or 0, quadrantY * 4 + quadrantX * 2), 0x03)
end

-- CHR ROM contains pattern bits only. Build separate sheets using the real
-- palette so nametable previews do not follow the CHR inspection palette.
local function updateNametablePatternImage(pattern, patternBase, paletteIndex)
    local buffer = nametablePatternBuffers[paletteIndex]
    local image = nametablePatternImages[paletteIndex]
    if not buffer then
        buffer = love.image.newImageData(128, 128, "rgba8")
        image = love.graphics.newImage(buffer)
        nametablePatternBuffers[paletteIndex] = buffer
        nametablePatternImages[paletteIndex] = image
    end

    local pointer = ffi.cast("uint8_t*", buffer:getFFIPointer())
    local base = paletteIndex * 4
    for tileY = 0, 15 do
        for tileX = 0, 15 do
            local tileAddress = patternBase + tileY * 256 + tileX * 16
            for fineY = 0, 7 do
                local lsb = pattern[tileAddress + fineY] or 0
                local msb = pattern[tileAddress + fineY + 8] or 0
                for fineX = 0, 7 do
                    local bitIndex = 7 - fineX
                    local pixel = bit.band(bit.rshift(lsb, bitIndex), 1)
                        + bit.lshift(bit.band(bit.rshift(msb, bitIndex), 1), 1)
                    local paletteAddress = pixel == 0 and 0 or (base + pixel)
                    local colorIndex = nameTable.tblPalette[paletteAddress] or 0
                    local rgb = colors[bit.band(colorIndex, 0x3F)] or colors[0]
                    local p = ((tileY * 8 + fineY) * 128 + tileX * 8 + fineX) * 4
                    pointer[p], pointer[p + 1], pointer[p + 2], pointer[p + 3] = rgb[1], rgb[2], rgb[3], 255
                end
            end
        end
    end
    image:replacePixels(buffer)
    return image
end

--^ HACK CHECK
function PPUtoLove2d.ScreenToNumbers(CHR1, CHR2)
    if loopy.ppuStates[1] == nil then return end
    local state = loopy.ppuStates[1]
    local pattern = state.spriteTileSet
    local patternBase = state.backgroundTable * 0x1000
    local patternImages = {}
    for palette = 0, 3 do
        patternImages[palette] = updateNametablePatternImage(pattern, patternBase, palette)
    end
    
    -- Create canvases once and reuse them. Tile quads are cached by tile ID.
    if not nametableCanvasA then
        nametableCanvasA = love.graphics.newCanvas(256, 240)
        nametableCanvasB = love.graphics.newCanvas(256, 240)
    end
    
    -- Draw to first canvas
    love.graphics.setCanvas(nametableCanvasA)
    love.graphics.clear()
    for y=0, 29 do
        for x=0, 31 do
            local id0 = nameTable.tblName[0][y*32+x]
            local attributeAddress = 0x03C0 + math.floor(y / 4) * 8 + math.floor(x / 4)
            local palette = selectAttributeValue(nameTable.tblName[0][attributeAddress], x, y)
            love.graphics.draw(
                patternImages[palette],
                getNametableQuad(id0),
                x * 8, y * 8, nil, 1
            )
        end
    end
    
    -- Draw to second canvas
    love.graphics.setCanvas(nametableCanvasB)
    love.graphics.clear()
    for y=0, 29 do
        for x=0, 31 do
            local id1 = nameTable.tblName[1][y*32+x]
            local attributeAddress = 0x03C0 + math.floor(y / 4) * 8 + math.floor(x / 4)
            local palette = selectAttributeValue(nameTable.tblName[1][attributeAddress], x, y)
            love.graphics.draw(
                patternImages[palette],
                getNametableQuad(id1),
                x * 8, y * 8, nil, 1
            )
        end
    end
    
    -- Reset canvas
    love.graphics.setCanvas()
    
    return nametableCanvasA, nametableCanvasB
end

--# Draw Screen Buffer to Love2d Screen
function PPUtoLove2d.FrameToScreen(buffer)
    screenImage:replacePixels(buffer,0,nil,nil,nil,false)
end


selectedState = 1
--# Draw Game Window and Scale it to fit the screen
function PPUtoLove2d.GameWindow()
    local screenScale = 2
    local screenX = 0
    local screenY = 15
    if EnableDebug then
        screenScale = 2
        screenX = 10
        screenY = 65
    else
        screenScale = math.floor(love.graphics.getHeight() / 240)  --* Integer scale to fit window height
        if screenScale < 1 then screenScale = 1 end
        local scaledW = screenImage:getWidth() * screenScale
        local scaledH = screenImage:getHeight() * screenScale
        screenX = math.floor((love.graphics.getWidth()  - scaledW) / 2)  --* Center horizontally
        screenY = math.floor((love.graphics.getHeight() - scaledH) / 2)  --* Center vertically
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(screenImage, screenX, screenY, 0, screenScale)
    if EnableDebug and DebugActiveTab == "ppu" then
        --print()
        for i = 1, #loopy.ppuStates do
            --print("STATE NOW ".. #loopy.ppuStates .. " " .. loopy.ppuStates[i].scanLine.."NameX " .. loopy.ppuStates[i].namespace_x .."OffsetX ".. loopy.ppuStates[i].offset_x .."FineX ".. loopy.ppuStates[i].fineOffset_x .. " NameY " .. loopy.ppuStates[i].namespace_y .."OffsetY ".. loopy.ppuStates[i].offset_y .." ".. loopy.ppuStates[i].fineOffset_y .. " mirror ".. 
            --loopy.ppuStates[i].mirror )
            love.graphics.setColor(1, 0, 0, 1)
            love.graphics.rectangle("fill",10,loopy.ppuStates[i].scanLine*2+screenY,10,10)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(i, 10,loopy.ppuStates[i].scanLine*2-2+screenY)
        end

        local i = #loopy.ppuStates
        --print("State Looked at "..i .. " of " .. #loopy.ppuStates)
        --print("namespace X " .. loopy.ppuStates[i].namespace_x .." ".. loopy.ppuStates[i].offset_x .." ".. loopy.ppuStates[i].fineOffset_x .. " Y " .. loopy.ppuStates[i].namespace_y .." ".. loopy.ppuStates[i].offset_y .." ".. loopy.ppuStates[i].fineOffset_y .. " mirror ".. 
          --  loopy.ppuStates[i].mirror )
            local x = 1
            local y = 0
            if selectedState < #loopy.ppuStates then
                x = loopy.ppuStates[selectedState].namespace_x* 256 + loopy.ppuStates[selectedState].offset_x * 8 + loopy.ppuStates[selectedState].fineOffset_x
                y = loopy.ppuStates[selectedState].namespace_y* 240 + loopy.ppuStates[selectedState].offset_y * 8 + loopy.ppuStates[selectedState].offsetY + loopy.ppuStates[selectedState].fineOffset_y
            end
            love.graphics.setColor(.5, 1, .8, .4)
            local x1 = 1000
            local y2 = 100
            if x1 + x + 256 > x1+512 then
                love.graphics.rectangle("fill",x1 + x,y2 + y,512-x,240)
                love.graphics.rectangle("fill",x1, y2+y,x-256,240)
            else
                love.graphics.rectangle("fill",x1 + x,y2 + y,256,240)
            end
    end
end

return PPUtoLove2d
