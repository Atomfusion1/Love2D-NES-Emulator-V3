-- Run from the repository root with LuaJIT; uses deterministic PPU memory.
bit = require("bit")
local gun = require("NES.Controller.light_gun")
local memory = {}
local ioState = { MASKS = 0x1E, CTRL = 0 }
local oam = {}
for i = 0, 255 do oam[i] = 255 end
package.loaded["NES.PPU.ppuBus"] = { PPURead = function(a) return memory[a] or 0 end }
package.loaded["NES.PPU.ppuIO"] = ioState
package.loaded["NES.PPU.ppuOAM"] = oam
local loopy = require("NES.PPU.loopy")
loopy.ppuStates = {{scanLine = 0, v = 0, x = 0}}
local pixel = require("NES.PPU.light_gun_pixel")
local function equal(a, b, label) assert(a == b, label .. ": " .. tostring(a) .. " != " .. tostring(b)) end
local function isLight() return bit.band(gun.ReadState(), 8) == 0 end
memory[0x3F00], memory[0x3F01], memory[0x3F11] = 0x0F, 0x20, 0x20
-- White background tile at (128,120), all other tiles black.
memory[0x2000 + 15 * 32 + 16] = 1
for row = 0, 7 do memory[16 + row] = 255 end
assert(pixel.Read(128,120) > 0.9)
equal(pixel.Read(120,120), 0, "outside target")
gun.SetEnabled(true)
gun.SetSensorConfig(0, 0.75)
gun.SetAim(128,120)
gun.BeginFrame()
gun.AdvancePPU(120,0,128,pixel.Read)
equal(isLight(), false, "beam has not reached target")
gun.AdvancePPU(120,128,129,pixel.Read)
equal(isLight(), true, "current white target lights sensor")
gun.SetTrigger(true)
equal(gun.ReadState(), 16, "D4 high on press, D3 low on light")
gun.SetTrigger(false)
equal(isLight(), true, "release does not clear photosensor")
gun.BeginFrame()
equal(isLight(), true, "frame boundary does not clear photosensor")
for line = 241,260 do gun.AdvancePPU(line,0,341,pixel.Read) end
equal(isLight(), false, "sensor decays during vblank")
-- Same position, new palette/mask: no stale image may produce a hit.
ioState.MASKS = 0
gun.AdvancePPU(120,128,129,pixel.Read)
equal(isLight(), false, "black calibration frame stays dark")
ioState.MASKS = 0x1E
memory[0x3F01] = 0x0F
gun.AdvancePPU(120,128,129,pixel.Read)
equal(isLight(), false, "live palette changes apply immediately")
memory[0x3F01] = 0x20
gun.AdvancePPU(120,128,129,pixel.Read)
equal(isLight(), true, "white target next frame detected")
-- Sprite at y=100 is first visible on row 101; use bit 7 only.
oam[0],oam[1],oam[2],oam[3] = 100,2,0,80
memory[32] = 128
assert(pixel.Read(80,101) > 0.9)
equal(pixel.Read(80,100), 0, "OAM Y offset")
equal(pixel.Read(81,101), 0, "transparent sprite pixel")
oam[2] = 0x40
assert(pixel.Read(87,101) > 0.9)
equal(pixel.Read(80,101), 0, "horizontal sprite flip")
-- Verify every displayed pixel block at 4x and exclusive viewport bounds.
local mx,my = 0,0
love = {window={hasFocus=function() return true end}, mouse={
    getPosition=function() return mx,my end, isDown=function() return false end}}
for x=0,255 do
    mx,my = 38+x*4,20+120*4
    gun.UpdateMouse(38,20,1024,960)
    local ax,ay = gun.GetAim()
    equal(ax,x,"4x left edge of pixel")
    equal(ay,120,"4x row")
    mx=mx+3
    gun.UpdateMouse(38,20,1024,960)
    equal(gun.GetAim(),x,"4x right edge of pixel")
end
mx,my=1062,980
gun.UpdateMouse(38,20,1024,960)
equal(gun.GetAim(),nil,"outside right/bottom edge")
gun.SetEnabled(false)
equal(gun.ReadState(),0,"disabled port")
print("PASS: current PPU pixels, beam timing, black/white sequence, decay, trigger independence, sprites, 4x coordinates")
