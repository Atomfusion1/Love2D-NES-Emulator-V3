-- Resolve the pixel under the Zapper from current PPU memory. The display
-- ImageData is a completed, older frame and must never drive the sensor.
local ppuBus = require("NES.PPU.ppuBus")
local io = require("NES.PPU.ppuIO")
local loopy = require("NES.PPU.loopy")
local oam = require("NES.PPU.ppuOAM")
local palette = require("NES.PPU.VGA_Pallette").Pallette
local band, rshift = bit.band, bit.rshift
local pixel = {}

local function pattern(address, x)
    local shift = 7 - x
    return band(rshift(ppuBus.PPURead(address), shift), 1)
        + 2 * band(rshift(ppuBus.PPURead(address + 8), shift), 1)
end

function pixel.Read(x, y)
    local mask, control = io.MASKS, io.CTRL
    local bg, colorAddress = 0, 0x3F00
    -- This PPU retains scroll origins in snapshots rather than incrementing
    -- v's vertical bits every row. Follow the current origin, not y + live v.
    local origin, originY = nil, 0
    for _, state in ipairs(loopy.ppuStates) do
        if (state.scanLine or 0) > y then break end
        if state.trigger ~= "inspect" and state.trigger ~= "mapper"
            and state.trigger ~= "$2001" then
            origin = state
            originY = state.is2006 and state.scanLine or 0
        end
    end
    local v = origin and origin.v or loopy.v
    local fineX = origin and origin.x or loopy.x
    if band(mask, 0x08) ~= 0 and (x >= 8 or band(mask, 0x02) ~= 0) then
        local sx = band(v, 31) * 8 + fineX + x
        local sy = band(rshift(v, 12), 7) + y - originY
        local cy, ny = loopy.AdvanceVertical(band(rshift(v, 5), 31),
            band(rshift(v, 11), 1), math.floor(sy / 8))
        local cx = math.floor(sx / 8) % 32
        local nx = (band(rshift(v, 10), 1) + math.floor(sx / 256)) % 2
        local nt = 0x2000 + nx * 0x400 + ny * 0x800
        local tile = ppuBus.PPURead(nt + cy * 32 + cx)
        bg = pattern(band(control, 0x10) * 256 + tile * 16 + sy % 8, sx % 8)
        if bg ~= 0 then
            local attr = ppuBus.PPURead(nt + 0x3C0 + math.floor(cy / 4) * 8 + math.floor(cx / 4))
            local shift = math.floor(cy % 4 / 2) * 4 + math.floor(cx % 4 / 2) * 2
            colorAddress = 0x3F00 + band(rshift(attr, shift), 3) * 4 + bg
        end
    end
    if band(mask, 0x10) ~= 0 and (x >= 8 or band(mask, 0x04) ~= 0) then
        local height = band(control, 0x20) ~= 0 and 16 or 8
        local visible = 0
        for index = 0, 63 do
            local base = index * 4
            local row = y - (oam[base] + 1)
            if row >= 0 and row < height then
                visible = visible + 1
                if visible > 8 then break end
                local col = x - oam[base + 3]
                if col >= 0 and col < 8 then
                    local tile, attr = oam[base + 1], oam[base + 2]
                    if band(attr, 0x80) ~= 0 then row = height - 1 - row end
                    if band(attr, 0x40) ~= 0 then col = 7 - col end
                    local bank = band(control, 0x08) * 512
                    if height == 16 then
                        bank = band(tile, 1) * 0x1000
                        tile = band(tile, 0xFE) + math.floor(row / 8)
                    end
                    local value = pattern(bank + tile * 16 + row % 8, col)
                    if value ~= 0 then
                        if bg == 0 or band(attr, 0x20) == 0 then
                            colorAddress = 0x3F10 + band(attr, 3) * 4 + value
                        end
                        break
                    end
                end
            end
        end
    end
    if band(mask, 0x18) == 0 and band(loopy.v, 0x3F00) == 0x3F00 then
        colorAddress = band(loopy.v, 0x3FFF)
    end
    local color = palette[ppuBus.PPURead(colorAddress)]
    return (0.299 * color[1] + 0.587 * color[2] + 0.114 * color[3]) / 255
end

return pixel
