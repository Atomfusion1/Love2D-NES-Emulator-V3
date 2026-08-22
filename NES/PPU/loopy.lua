-- Drawing PPU image .. Create 1d Array 


local loopy = {}
loopy.ppuStates = {}
-- Canonical NES PPU scrolling registers.
-- v: current VRAM/rendering address, t: temporary address,
-- x: fine X scroll, w: shared $2005/$2006 write toggle.
loopy.v = 0x0000
loopy.t = 0x0000
loopy.x = 0x00
loopy.w = 0

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local function syncLegacyFields()
    local v = loopy.v
    loopy.course_x = band(v, 0x001F)
    loopy.course_y = rshift(band(v, 0x03E0), 5)
    loopy.nametable_x = rshift(band(v, 0x0400), 10)
    loopy.nametable_y = rshift(band(v, 0x0800), 11)
    loopy.fine_y = rshift(band(v, 0x7000), 12)
    loopy.fine_x = loopy.x
    loopy.register_vram_addr = v
    loopy.register_tram_addr = loopy.t
end

function loopy:SetV(value)
    self.v = band(value, 0x7FFF)
    syncLegacyFields()
end

function loopy:SetT(value)
    self.t = band(value, 0x7FFF)
    self.register_tram_addr = self.t
end

function loopy:SetX(value)
    self.x = band(value, 0x07)
    self.fine_x = self.x
end

function loopy:ResetWriteToggle()
    self.w = 0
end

function loopy:WriteControl(data)
    self:SetT(bor(band(self.t, 0x73FF), lshift(band(data, 0x03), 10)))
end

function loopy:WriteScroll(data)
    if self.w == 0 then
        self:SetT(bor(band(self.t, 0x7FE0), rshift(data, 3)))
        self:SetX(data)
        self.w = 1
        return false
    end

    self:SetT(bor(
        band(self.t, 0x0C1F),
        lshift(band(data, 0x07), 12),
        lshift(band(data, 0xF8), 2)
    ))
    self.w = 0
    return true
end

function loopy:WriteAddress(data)
    if self.w == 0 then
        self:SetT(bor(band(self.t, 0x00FF), lshift(band(data, 0x3F), 8)))
        self.w = 1
        return false
    end

    self:SetT(bor(band(self.t, 0x7F00), data))
    self:SetV(self.t)
    self.w = 0
    return true
end

function loopy:CopyHorizontalTToV()
    local value = bor(band(self.v, 0x7BE0), band(self.t, 0x041F))
    if value ~= self.v then self:SetV(value) end
end

function loopy:CopyVerticalTToV()
    local value = bor(band(self.v, 0x041F), band(self.t, 0x7BE0))
    if value ~= self.v then self:SetV(value) end
end

-- Advance whole tile rows using the PPU's non-linear coarse-Y rules.
-- Rows 30 and 31 address the attribute area as tile data. Only 29 -> 0
-- toggles the vertical nametable; 31 -> 0 stays in the same nametable.
function loopy.AdvanceVertical(coarseY, nametableY, rows)
    local y = coarseY
    local ntY = nametableY

    -- Rows 30 and 31 form a two-row path back to zero without toggling
    -- nametables.  Once in 0..29, whole 30-row spans can be folded directly.
    if y == 30 then
        if rows == 0 then return 30, ntY end
        if rows == 1 then return 31, ntY end
        y = 0
        rows = rows - 2
    elseif y == 31 then
        if rows == 0 then return 31, ntY end
        y = 0
        rows = rows - 1
    end

    local total = y + rows
    if total < 0 then return total, ntY end

    local wraps = math.floor(total / 30)
    if wraps % 2 ~= 0 then
        ntY = bit.bxor(ntY, 1)
    end

    return total % 30, ntY
end

function loopy:IncrementV(amount)
    -- $2007 can increment v hundreds or thousands of times during a transfer.
    -- The canonical address is all the bus needs; decoding every legacy field
    -- here was a substantial regression.  Full decoding still happens for
    -- scroll/address writes and rendering transfers through SetV.
    self.v = band(self.v + amount, 0x7FFF)
    self.register_vram_addr = self.v
end

function loopy:ResetScroll()
    self.v = 0x0000
    self.t = 0x0000
    self.x = 0x00
    self.w = 0
    syncLegacyFields()
end

function loopy:RestoreScroll(state)
    if state.v ~= nil or state.t ~= nil or state.x ~= nil or state.w ~= nil then
        self.t = band(state.t or 0x0000, 0x7FFF)
        self.x = band(state.x or 0x00, 0x07)
        self.w = band(state.w or 0, 0x01)
        self:SetV(state.v or 0x0000)
        return
    end

    -- Compatibility with save states made before v/t/x/w became canonical.
    local legacyV = state.register_vram_addr or 0x0000
    local legacyT = state.register_tram_addr or legacyV
    self.t = band(legacyT, 0x7FFF)
    self.x = band(state.fine_x or 0x00, 0x07)
    self.w = 0
    self:SetV(legacyV)
end

loopy.course_x = 0x00
loopy.course_y = 0x00
loopy.nametable_x = 0x00
loopy.nametable_y = 0x00
loopy.fine_x = 0x00
loopy.fine_y = 0x00
loopy.unused = 0x00
loopy.reg = 0x000
loopy.scanLine = 0
loopy.scanLinePixels = 0
loopy.drawScreen = false
loopy.drawSprites = false
loopy.register_vram_addr = 0x0000
loopy.register_tram_addr = 0x0000
loopy.sprite0HitOffset_x = 0x00
loopy.sprite0HitOffset_y = 0x00
loopy.startOffset_x = 0x00
loopy.startOffset_y = 0x00
loopy.startFineOffset_x = 0x00
loopy.startFineOffset_y = 0x00
loopy.sprite0Scanline = 0x00
loopy.startNamespace_x = 0x00
loopy.startNamespace_y = 0x00
loopy.sprite0Namespace_x = 0x00
loopy.sprite0Namespace_y = 0x00
loopy.preSrite0TileSet = {}
loopy.postSprite0TileSet = {}
loopy.preSprite0SpritePattern = 0
loopy.postSprite0SpritePattern = 0
loopy.preSprite0BackgroundPattern = 0
loopy.postSprite0BackgroundPattern = 0
loopy.prePPUAddress = 0x2000
loopy.postPPUAddress = 0x2000
loopy.inVBlank = false
loopy.offsetY = 0

syncLegacyFields()

-- Updated function to search through ppuStates for a matching scanLine number
function loopy:SearchPPUStatesInRangeAndReplace(startScanLine, endScanLine, state)
    for i = 1, #self.ppuStates do
        if self.ppuStates[i].scanLine >= startScanLine and self.ppuStates[i].scanLine <= endScanLine then
            -- Several register/mapper writes commonly form one split.  Preserve
            -- a completed $2006 split when a later write updates the same state.
            if self.ppuStates[i].is2006 and not state.is2006 then
                state.is2006 = true
                state.offsetY = self.ppuStates[i].offsetY
            end
            self.ppuStates[i] = state
            return true
        end
    end
    -- Insert in scanline order
    for i = 1, #self.ppuStates do
        if self.ppuStates[i].scanLine > state.scanLine then
            table.insert(self.ppuStates, i, state)
            return false
        end
    end
    table.insert(self.ppuStates, state)
    return false
end

function loopy:SearchPPUStatesInRange(startScanLine, endScanLine)
    for i = 1, #self.ppuStates do
        if self.ppuStates[i].scanLine >= startScanLine and self.ppuStates[i].scanLine <= endScanLine then
            return true
        end
    end
    return false
end

return loopy
