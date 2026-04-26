local Sprite0Hack = {}

local gamesSprite0Offset = {
    ["Roms/NinjaGaiden.nes"] = {
        sprite0Offset = 8,
        scanLineOffset = 8
    },
    ["Roms/Astyanax (U) .nes"] = {
        sprite0Offset = 0,
        scanLineOffset = 1
    },
    ["Roms/duck.nes"] = {
        sprite0Offset = -4,
        scanLineOffset = 8
    },
    ["Roms/Zelda II - The Adventure of Link (USA).nes"] = {
        sprite0Offset = 8,
        scanLineOffset = 8
    },
    ["Roms/smb.nes"] = {
        sprite0Offset = 6,
        scanLineOffset = 0
    },
    ["Roms/Super Mario Bros. 3 (USA).nes"] = {
        sprite0Offset = 0,
        scanLineOffset = 9
    },
    ["Roms/Battle of Olympus, The.nes"] = {
        sprite0Offset = -6,
        scanLineOffset = 8
    },
    ["Roms/Gradius.nes"] = {
        sprite0Offset = 0,
        scanLineOffset = 5
    },
    ["Roms/Teenage Mutant Ninja Turtles (U).nes"] = {
        sprite0Offset = 8,
        scanLineOffset = 0
    },
    ["Roms/Sword Master (USA).nes"] = {
        sprite0Offset = 0,
        scanLineOffset = 0
    },
    ["Roms/Simpsons - Bart vs. The Space Mutants, The.nes"] = {
        sprite0Offset = 0,
        scanLineOffset = 0
    },
    ["Roms/Tecmo Bowl (USA) (Rev 1).nes"] = {
        sprite0Offset = 5,
        scanLineOffset = 11
    },
    ["Roms/Lemmings.nes"] = {
        sprite0Offset = 5,
        scanLineOffset = 0
    },
}
function Sprite0Hack:CheckForSprite0Hit(gameName)
    if gamesSprite0Offset[gameName] then
        print("Sprite0 Offset loaded")
        return gamesSprite0Offset[gameName].sprite0Offset
    end
    print("NO Sprite0 Offset")
    return 2
end
function Sprite0Hack:CheckForScanLineOffset(gameName)
    if gamesSprite0Offset[gameName] then
        print("Scan Line Offset loaded")
        return gamesSprite0Offset[gameName].scanLineOffset
    end
    print("NO Scan Line Offset")
    return 0
end

return Sprite0Hack