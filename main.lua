--! Order Matters .. Cart First for setup  
local cart          = require("NES.Cartridge.Cartridge")
local mapper        = require("NES.Cartridge.Mappers")
local bus           = require("NES.BUS.bus")
local keyboard      = require("Includes.keyboard")
local cpu           = require("NES.CPU.cpumain")
local ppu           = require("NES.PPU.ppu")
local testing       = require("Emulator.UI.Debug.testing")
local apu           = require("NES.Audio.apu")
local pputolove     = require('NES.PPU.PPUtoLove2d')
local selectFile    = require('Emulator.UI.Emulator.selectfile')
--local loveSpeed     = require('Includes.loveSpeed')
local loveSpeed     = require('Includes.displaytimer')
local profile       = require("Includes.profile.profile")
local Sprite0Scanline = require("NES.PPU.Sprite0Hack")
--* Global Variables
LoveFileDir             = love.filesystem.getSourceBaseDirectory() .. "/" .. love.filesystem.getIdentity() .. "/"
GlobalFileName          = love.filesystem.read("Emulator/nesEmuState.txt")
G_CPUStep               = 2         --# 1 = 1 cycle, 2 = 1 frame
UseSound                = true      --# enable disable sound
EnableDebug             = false     --# enable Debug 
Profile                 = false     --# enable Profiling

-- NTSC NES timing is independent of the monitor refresh rate.  Keep emulation
-- on a fixed clock and let love.draw present the newest completed frame.
local NTSC_FRAME_RATE    = 60.0988
local NTSC_FRAME_TIME    = 1 / NTSC_FRAME_RATE
local NTSC_CPU_CYCLES    = 29781
local emulationTime      = 0
local MAX_CATCHUP_FRAMES = 4

local function RunEmulatedFrame()
    if Profile then profile.start() end
    apu.TimerCheck(NTSC_FRAME_TIME)
    cpu.ExecuteCycles(NTSC_CPU_CYCLES)
end

--& Run Once on Load
function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    --* Global Cartridge Startup   
    Initialize(GlobalFileName)
    print(love.graphics.getRendererInfo())
end

--& Main Update Loop
function love.update(dt)
    loveSpeed.StartTimer()  --* Start us Timer
    keyboard.Update(dt)     --* Keyboard Update
    local activeMapper = mapper[cart.mapper] and mapper[cart.mapper].mapper
    if activeMapper and activeMapper.UpdateBatterySave then
        activeMapper.UpdateBatterySave()
    end
    if G_SkipFrameAfterStateLoad then
        G_SkipFrameAfterStateLoad = false
        emulationTime = 0
        return
    end
    --* CPU Execution
    if G_CPUStep == 2 then      --# 2 = 1 frame at a time
        if OverRideSpeed then
            emulationTime = 0
            RunEmulatedFrame()
            return
        end

        -- Clamp long pauses so restoring/moving the window does not trigger a
        -- large burst of catch-up frames and audio state changes.
        emulationTime = emulationTime + math.min(dt, NTSC_FRAME_TIME * MAX_CATCHUP_FRAMES)
        local framesRun = 0
        while emulationTime >= NTSC_FRAME_TIME and framesRun < MAX_CATCHUP_FRAMES do
            RunEmulatedFrame()
            emulationTime = emulationTime - NTSC_FRAME_TIME
            framesRun = framesRun + 1
        end
    elseif G_CPUStep == 1 then  --# 1 = 1 cycle at a time
        cpu.ExecuteCycles(1)
        G_CPUStep = 0
    end
end

--& Draw Screen
function love.draw()
    DebugDraw()                 --* Debug Tiles and Window 
    pputolove.GameWindow()
    selectFile.DrawPopup()
    loveSpeed.DisplayScreen()   --* Display us Timer 
    cpu.drawFrame = false
end

function love.quit()
    local activeMapper = mapper[cart.mapper] and mapper[cart.mapper].mapper
    if activeMapper and activeMapper.FlushBatterySave then
        activeMapper.FlushBatterySave()
    end
end

--# Debug Function 
function DebugDraw()
    if EnableDebug then
        testing.DisplayUI()
        ppu.DrawCharacterTiles()
    end
end

--# Initialize Cartridge
function Initialize (file)
    local activeMapper = cart.mapper and mapper[cart.mapper] and mapper[cart.mapper].mapper
    if activeMapper and activeMapper.FlushBatterySave then
        activeMapper.FlushBatterySave()
    end

    for i = 1, 5 do
        print("") --* Clear Section of Console
    end
    print(file)
    ppu.sprite0Offset = Sprite0Scanline:CheckForSprite0Hit(file) or 0
    ppu.scanLineOffset = Sprite0Scanline:CheckForScanLineOffset(file) or 0
    local totalfile = LoveFileDir .. file
    cart.Initialize(totalfile) --* setup for mappers --
    print("mapper loaded:" .. cart.mapper)
    mapper[cart.mapper].mapper.INI()
    bus.RefreshMapperCache()  -- Cache mapper functions for hot-path optimization
    apu.Initialize()
    cpu.Initialize()
end

--^ This Uses VSCode BetterComments Colors 
-- You Can see The Settings in Documentation 
--! warning
--@ test 
--# Debug Function 
--% test f8ff97
--^ test BBC2CC
--$ help
--? test
--& test ff7d75
--* test
--TODO Test
-- test 


