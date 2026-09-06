-- Optional local-ROM integration trace, run with LuaJIT from repository root.
-- CPU/PPU/controller are real; presentation and audio output are stubbed.
bit = require('bit')
package.path = package.path .. ';./?/init.lua'
local ffi = require('ffi')
local function image(w,h)
    local data = ffi.new('uint8_t[?]', w*h*4)
    return {getFFIPointer=function() return data end,
        getWidth=function() return w end,getHeight=function() return h end,
        replacePixels=function() end}
end
love = {timer={getTime=os.clock}, joystick={getJoysticks=function() return {} end},
    image={newImageData=image}, graphics={newImage=function(data) return data end},
    filesystem={read=function() return nil end}}
package.loaded['NES.Audio.apu'] = setmetatable({}, {__index=function() return function() return 0 end end})
UseSound, EnableDebug, PerformanceDetailEnabled = false,false,false
local cart = require('NES.Cartridge.Cartridge')
local bus = require('NES.BUS.bus')
local cpu = require('NES.CPU.cpumain')
local ppu = require('NES.PPU.ppu')
local controller = require('NES.Controller.controller')
local gun = require('NES.Controller.light_gun')
local oam = require('NES.PPU.ppuOAM')
cart.Initialize('Roms/Duck Hunt (World).nes')
require('NES.Cartridge.Mappers')[cart.mapper].mapper.INI()
bus.RefreshMapperCache()
require('NES.CPU.cpuram').Reset()
controller.Reset()
ppu.Reset()
cpu.Initialize()
controller.SetPort2Device('zapper')
gun.SetAim(128,100)
for frame=1,1200 do
    controller.Controller1State = (frame >= 500 and frame < 505) and 0x10 or 0
    if frame == 850 then
        for i=0,15 do
            print(string.format('OAM %d y=%d tile=%d attr=%d x=%d',i,oam[i*4],oam[i*4+1],oam[i*4+2],oam[i*4+3]))
        end
        gun.SetTrigger(true)
    elseif frame == 852 then gun.SetTrigger(false) end
    cpu.ExecuteCycles(29781)
end
print('PASS: 1000 Duck Hunt CPU/PPU frames completed')
