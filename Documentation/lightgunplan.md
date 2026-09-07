The ~1000 µs cost comes mainly from this line in [cpumain.lua (line 144)](/P:/05 Programming/05 Love2D/05 Sketches/20 NES Emulation/NES Emu/Bestatm/NesEmulatorLove2D_08_25_26/NES/CPU/cpumain.lua:144):
local PPU_UPDATE_THRESHOLD = lightGun.IsEnabled() and 1 or 114
With the Zapper enabled, the CPU calls ppu.Update() almost every instruction instead of roughly every 114 CPU cycles. That can increase PPU update calls by around 30–40×. The actual light sample is much smaller: a radius of 2 samples only 25 pixels per frame.
The current implementation is also wrong in one architectural detail: enabling the Zapper permanently changes PPU stepping even while nobody is shooting.
The plan I recommend is:
1. Restore the normal PPU batch threshold of 114 cycles at all times.
2. Arm Zapper timing on the mouse-button rising edge.
3. Keep it armed for four complete emulated frames:
   - Trigger/current frame
   - Black frame
   - First white target frame
   - Second white target frame or safety frame
4. While armed, sample only when the emulated beam crosses the mouse’s 5×5 NES pixel area.
5. Immediately before each $4017 Zapper read, flush any pending PPU cycles. This gives Duck Hunt the current sensor state without updating the PPU after every instruction.
6. Let light remain active for about 20 scanlines, then decay naturally through visible lines and vblank.
7. Outside the armed window, report the sensor as dark while still reporting the trigger normally.
8. Keep the eight-frame trace temporarily so each shot reports:
   - PPU frame
   - Peak brightness at the aim point
   - $4017 read count
   - Reads that observed light
9. Validate direct hits, deliberate misses, both ducks, and the performance graph.
This should recover most of that 1000 µs while improving timing accuracy. Restricting sensing to four frames is a Duck Hunt focused optimization; Zapper test ROMs that inspect light without pulling the trigger would need a separate accurate mode.