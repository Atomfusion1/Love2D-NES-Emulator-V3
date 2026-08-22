package.path = package.path .. ";./?.lua;./?/init.lua"

local cpuRAM = require("NES.CPU.cpuram")
local controller = require("NES.Controller.controller")
local ppu = require("NES.PPU.ppu")
local ppuIO = require("NES.PPU.ppuIO")
local loopy = require("NES.PPU.loopy")
local OAM = require("NES.PPU.ppuOAM")
local nameTable = require("NES.PPU.ppunametable")

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

function love.load()
    cpuRAM.cpuRAM[0x123] = 0xAA
    controller.Controller1State = 0xFF
    controller.Controller2State = 0xFF
    loopy:SetT(0x7FFF)
    loopy:SetV(0x7FFF)
    loopy:SetX(7)
    loopy.w = 1
    loopy.drawScreen = true
    loopy.drawSprites = true
    ppuIO.CTRL = 0xFF
    ppuIO.MASKS = 0xFF
    ppuIO.STATUS = 0xFF
    nameTable.tblName[0][0x123] = 0xAA
    nameTable.tblPalette[0x0F] = 0x2A
    OAM[0] = 0x10

    cpuRAM.Reset()
    controller.Reset()
    ppu.Reset()

    assertEqual(cpuRAM.cpuRAM[0x123], 0x00, "CPU RAM power cycle")
    assertEqual(controller.Controller1State, 0x00, "controller 1 reset")
    assertEqual(controller.Controller2State, 0x00, "controller 2 reset")
    assertEqual(loopy.v, 0x0000, "PPU v reset")
    assertEqual(loopy.t, 0x0000, "PPU t reset")
    assertEqual(loopy.x, 0x00, "PPU fine X reset")
    assertEqual(loopy.w, 0, "PPU write toggle reset")
    assertEqual(loopy.drawScreen, false, "background rendering reset")
    assertEqual(loopy.drawSprites, false, "sprite rendering reset")
    assertEqual(ppuIO.CTRL, 0x00, "PPUCTRL reset")
    assertEqual(ppuIO.MASKS, 0x00, "PPUMASK reset")
    assertEqual(ppuIO.STATUS, 0x00, "PPUSTATUS reset")
    assertEqual(nameTable.tblName[0][0x123], 0x00, "nametable reset")
    assertEqual(nameTable.tblPalette[0x0F], 0x00, "palette reset")
    assertEqual(OAM[0], 0xF8, "OAM reset")

    print("Cartridge power-cycle reset tests passed")
    love.event.quit(0)
end
