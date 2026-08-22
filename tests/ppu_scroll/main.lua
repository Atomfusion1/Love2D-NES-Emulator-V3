package.path = package.path .. ";./?.lua;./?/init.lua"

local loopy = require("NES.PPU.loopy")
local band = bit.band

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected $%04X, got $%04X", label, expected, actual))
    end
end

function love.load()
    loopy:ResetScroll()

    loopy:WriteControl(0x03)
    assertEqual(band(loopy.t, 0x0C00), 0x0C00, "$2000 writes nametable bits to t")
    assertEqual(loopy.v, 0x0000, "$2000 does not immediately change v")

    loopy:WriteScroll(0x2D)
    assertEqual(band(loopy.t, 0x001F), 0x0005, "$2005 first write coarse X")
    assertEqual(loopy.x, 0x0005, "$2005 first write fine X")
    assertEqual(loopy.w, 1, "$2005 first write sets w")

    loopy:WriteScroll(0x9E)
    assertEqual(bit.rshift(band(loopy.t, 0x03E0), 5), 0x0013, "$2005 second write coarse Y")
    assertEqual(bit.rshift(band(loopy.t, 0x7000), 12), 0x0006, "$2005 second write fine Y")
    assertEqual(loopy.w, 0, "$2005 second write clears w")

    loopy:CopyHorizontalTToV()
    assertEqual(band(loopy.v, 0x041F), band(loopy.t, 0x041F), "dot 257 horizontal transfer")
    assertEqual(band(loopy.v, 0x7BE0), 0x0000, "horizontal transfer preserves vertical v")

    loopy:CopyVerticalTToV()
    assertEqual(loopy.v, loopy.t, "pre-render vertical transfer completes v")

    loopy:WriteScroll(0xFF)
    loopy:ResetWriteToggle()
    assertEqual(loopy.w, 0, "$2002 read resets shared write toggle")

    loopy:WriteAddress(0x7F)
    assertEqual(band(loopy.t, 0x4000), 0x0000, "$2006 first write clears t bit 14")
    loopy:WriteAddress(0xAA)
    assertEqual(loopy.v, 0x3FAA, "$2006 second write copies t to v")
    assertEqual(loopy.w, 0, "$2006 second write clears w")

    loopy:ResetWriteToggle()
    loopy:WriteAddress(0x0B)
    loopy:WriteAddress(0x00)
    assertEqual(bit.rshift(band(loopy.v, 0x03E0), 5), 0x0018, "$0B00 split coarse Y")

    loopy.ppuStates = {{scanLine = 195, is2006 = true, offsetY = 24}}
    loopy:SearchPPUStatesInRangeAndReplace(194, 196, {
        scanLine = 195,
        is2006 = false,
        offsetY = 0
    })
    assertEqual(loopy.ppuStates[1].is2006 and 1 or 0, 1, "same-line writes preserve $2006 split")
    assertEqual(loopy.ppuStates[1].offsetY, 24, "same-line writes preserve $2006 coarse Y")

    local y, ntY = loopy.AdvanceVertical(29, 0, 1)
    assertEqual(y, 0, "coarse Y 29 wraps to zero")
    assertEqual(ntY, 1, "coarse Y 29 toggles vertical nametable")

    y, ntY = loopy.AdvanceVertical(30, 0, 1)
    assertEqual(y, 31, "coarse Y 30 advances through attribute area")
    assertEqual(ntY, 0, "coarse Y 30 keeps vertical nametable")

    y, ntY = loopy.AdvanceVertical(30, 0, 2)
    assertEqual(y, 0, "coarse Y 31 wraps to zero")
    assertEqual(ntY, 0, "coarse Y 31 does not toggle vertical nametable")

    -- Check the constant-time implementation against the literal hardware
    -- transition rules over more than two complete vertical nametable spans.
    for startY = 0, 31 do
        for rows = 0, 64 do
            local expectedY, expectedNtY = startY, 0
            for _ = 1, rows do
                if expectedY == 29 then
                    expectedY = 0
                    expectedNtY = bit.bxor(expectedNtY, 1)
                elseif expectedY == 31 then
                    expectedY = 0
                else
                    expectedY = expectedY + 1
                end
            end
            local actualY, actualNtY = loopy.AdvanceVertical(startY, 0, rows)
            assertEqual(actualY, expectedY, "optimized vertical coarse Y")
            assertEqual(actualNtY, expectedNtY, "optimized vertical nametable Y")
        end
    end

    loopy:SetV(0x2000)
    loopy:IncrementV(32)
    assertEqual(loopy.v, 0x2020, "$2007 fast increment updates canonical v")
    assertEqual(loopy.register_vram_addr, loopy.v, "$2007 fast increment updates legacy address")

    print("PPU scroll register tests passed")
    love.event.quit(0)
end
