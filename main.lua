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
local cpuRAM        = require("NES.CPU.cpuram")
local controller    = require("NES.Controller.controller")
local cheats        = require("Emulator.cheats")
--* Global Variables
LoveFileDir             = love.filesystem.getSourceBaseDirectory() .. "/" .. love.filesystem.getIdentity() .. "/"
GlobalFileName          = love.filesystem.read("Emulator/nesEmuState.txt")
G_CPUStep               = 2         --# 1 = 1 cycle, 2 = 1 frame
G_FrameStepRequested    = false     --# execute one complete emulated frame, then pause
UseSound                = true      --# enable disable sound
EnableDebug             = false     --# enable Debug 
Profile                 = false     --# enable Profiling
PerformanceDetailEnabled = false    --# enable detailed CPU/PPU timing only on request
EmulationReady          = false     --# true after a supported cartridge loads

-- NTSC NES timing is independent of the monitor refresh rate.  Keep emulation
-- on a fixed clock and let love.draw present the newest completed frame.
local NTSC_FRAME_RATE    = 60.0988
local NTSC_FRAME_TIME    = 1 / NTSC_FRAME_RATE
local NTSC_CPU_CYCLES    = 29781
local emulationTime      = 0
local MAX_CATCHUP_FRAMES = 4
local lastDebugPPURefresh = 0

local function RunEmulatedFrame()
    cheats.ApplyRAM(cpuRAM.cpuRAM)
    loveSpeed.RecordCounter("emulatedFrames", 1)
    if Profile then profile.start() end
    local apuStart = love.timer.getTime()
    apu.TimerCheck(NTSC_FRAME_TIME)
    loveSpeed.RecordComponent("apu", love.timer.getTime() - apuStart)
    local cpuStart = love.timer.getTime()
    cpu.ExecuteCycles(NTSC_CPU_CYCLES)
    cheats.ApplyRAM(cpuRAM.cpuRAM)
    local cpuElapsed = love.timer.getTime() - cpuStart
    loveSpeed.RecordComponent("cpuCore", cpuElapsed)
    loveSpeed.RecordComponent("cpu", cpuElapsed)
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
    if not EmulationReady then
        emulationTime = 0
        return
    end
    local activeMapper = mapper[cart.mapper] and mapper[cart.mapper].mapper
    if activeMapper and activeMapper.UpdateBatterySave then
        activeMapper.UpdateBatterySave()
    end
    if G_SkipFrameAfterStateLoad then
        G_SkipFrameAfterStateLoad = false
        emulationTime = 0
        return
    end
    if G_FrameStepRequested then
        G_FrameStepRequested = false
        RunEmulatedFrame()
        G_CPUStep = 0
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
        cheats.ApplyRAM(cpuRAM.cpuRAM)
        cpu.ExecuteCycles(1)
        cheats.ApplyRAM(cpuRAM.cpuRAM)
        G_CPUStep = 0
    end
end

--& Draw Screen
function love.draw()
    DebugDraw()                 --* Debug Tiles and Window 
    if EmulationReady then
        pputolove.GameWindow()
    end
    -- Draw modal help last so the game image cannot cover it.
    testing.DrawHelpOverlay()
    selectFile.DrawPopup()
    loveSpeed.DisplayScreen()   --* Display us Timer 
    cpu.drawFrame = false
end

function love.quit()
    local activeMapper = mapper[cart.mapper] and mapper[cart.mapper].mapper
    if activeMapper and activeMapper.FlushBatterySave then
        activeMapper.FlushBatterySave()
    end
    local batteryMapper = mapper[1] and mapper[1].mapper
    if batteryMapper and batteryMapper.ShutdownBatteryWriter then
        batteryMapper.ShutdownBatteryWriter()
    end
end

--# Debug Function 
function DebugDraw()
    if EnableDebug then
        testing.DisplayUI()
        local now = love.timer.getTime()
        if testing.GetActiveTab() == "ppu" then
            if now - lastDebugPPURefresh >= 0.1 then
                local debugPPUStart = love.timer.getTime()
                ppu.UpdateCharacterTiles()
                loveSpeed.RecordComponent("ppuDebug", love.timer.getTime() - debugPPUStart)
                lastDebugPPURefresh = now
            end
            -- Draw the last completed diagnostic images every frame so the
            -- panel persists between limited-rate refreshes.
            ppu.DrawCharacterTiles()
            testing.DrawPPUDiagnostics()
        end
    end
end

-- The file picker installs callbacks while loading. Keep popup input handling,
-- then route debugger input through the shell as well.
function love.mousepressed(x, y, button, istouch)
    selectFile.MousePressed(x, y, button)
    if not selectFile.isPopupVisible then
        testing.MousePressed(x, y, button)
    end
end

function love.keypressed(key, scancode, isrepeat)
    selectFile.KeyboardInput(key)
    if selectFile.isPopupVisible then return end
    if key == "f1" then
        testing.ToggleHelp()
        return
    end
    if testing.HandleKeyPressed and testing.HandleKeyPressed(key) then return end
    keyboard.HandleKeyPressed(key)
end

--# Initialize Cartridge
function Initialize (file)
    local totalfile = LoveFileDir .. tostring(file or "")
    local romInfo, inspectError = cart.Inspect(totalfile)
    if not romInfo then
        local message = "Cannot load " .. tostring(file or "(no file)") .. ": " .. inspectError
        print(message)
        selectFile.ShowError(message)
        return false, message
    end

    local mapperEntry = mapper[romInfo.mapper]
    if not mapperEntry or not mapperEntry.mapper then
        local supported = {}
        for mapperId, entry in pairs(mapper) do
            if entry and entry.mapper then
                supported[#supported + 1] = mapperId
            end
        end
        table.sort(supported)

        local message = string.format(
            "Unsupported mapper %d for %s. Supported mappers: %s",
            romInfo.mapper,
            tostring(file),
            table.concat(supported, ", ")
        )
        print(message)
        selectFile.ShowError(message)
        return false, message
    end

    local activeMapper = cart.mapper and mapper[cart.mapper] and mapper[cart.mapper].mapper
    if activeMapper and activeMapper.FlushBatterySave then
        activeMapper.FlushBatterySave()
    end

    for i = 1, 5 do
        print("") --* Clear Section of Console
    end
    print(file)
    cart.Initialize(totalfile) --* setup for mappers --
    cheats.LoadForCartridge()
    cheats.ApplyROM(cart.ROM)
    print("mapper loaded:" .. cart.mapper)
    mapperEntry.mapper.INI()
    bus.RefreshMapperCache()  -- Cache mapper functions for hot-path optimization
    cpuRAM.Reset()
    controller.Reset()
    ppu.Reset()

    -- Reset clears the prior title's overrides; apply those for the new title.
    ppu.sprite0Offset = Sprite0Scanline:CheckForSprite0Hit(file) or 0
    ppu.scanLineOffset = Sprite0Scanline:CheckForScanLineOffset(file) or 0
    ppu.backgroundEnableOffset = Sprite0Scanline:CheckForBackgroundEnableOffset(file) or 0
    emulationTime = 0
    apu.Initialize()
    cpu.Initialize()
    EmulationReady = true
    selectFile.ClearError()
    return true
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
