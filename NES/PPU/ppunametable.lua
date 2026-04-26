local cart        = require("NES.Cartridge.Cartridge")

local nameTable = {}

nameTable.tblName    = {
    [0] = {},
    [1] = {}
}
nameTable.tblPalette = {}
-- Extra Feature Future 
nameTable.tblPattern = {
    [0] = {},
    [1] = {}
}
nameTable.nTX       = 1
nameTable.nTY       = 1
nameTable.courseX   = 0
nameTable.courseY   = 0
nameTable.fineX     = 0
nameTable.fineY     = 0

-- Initialize the arrays
for i = 0, 0x0400 do
    nameTable.tblName[0][i] = 0x00
    nameTable.tblName[1][i] = 0x00
end
-- Palette Table 
for i = 0, 0x20 do
    nameTable.tblPalette[i] = love.math.random(0,40)
end

-- Initialize Pattern Tables 
for i = 0, 0x1000 do
    nameTable.tblName[0][i] = 0x00
    nameTable.tblName[1][i] = 0x00
end

local tableName = nameTable.tblName
local band = bit.band
local rshift = bit.rshift

-- Mirror mapping arrays (pre-calculated)
local mirrorTable = {
    -- Horizontal (0): 0,0,1,1
    [0] = {[0]=0, [1]=0, [2]=1, [3]=1},
    -- Vertical (1): 0,1,0,1  
    [1] = {[0]=0, [1]=1, [2]=0, [3]=1},
    -- Single low (2): 0,0,0,0
    [2] = {[0]=0, [1]=0, [2]=0, [3]=0},
    -- Single high (3): 1,1,1,1
    [3] = {[0]=1, [1]=1, [2]=1, [3]=1}
}

function nameTable.NameTableMirrorRead(addr)
    local maskedAddr = band(addr, 0x0FFF)
    local section = rshift(maskedAddr, 10) -- Divide by 0x400 to get 0-3
    local tableIndex = mirrorTable[cart.Mirror][section]
    return tableName[tableIndex][band(maskedAddr, 0x3FF)]
end

function nameTable.NameTableMirrorWrite(addr, data)
    local maskedAddr = band(addr, 0x0FFF)
    local section = rshift(maskedAddr, 10)
    local tableIndex = mirrorTable[cart.Mirror][section]
    tableName[tableIndex][band(maskedAddr, 0x3FF)] = data
end

return nameTable

-- pallet table numbering byte == 4 2x2 grid
-- bits 1,0 top Right 3,2 Top Right 4,5 bottom left 6,7 bottom right 4 tiles must be same pallet (color)
-- pallet course 5 bit to 3 to get memory offset 3C0 and use the removed 2bits for location of memory tile
-- This is a tricky part to understand you will not get it till you do and when you do its not that bad 
-- see https://www.youtube.com/watch?v=-THeUXqR3zY&t=2709s&ab_channel=javidx9=2026 video
