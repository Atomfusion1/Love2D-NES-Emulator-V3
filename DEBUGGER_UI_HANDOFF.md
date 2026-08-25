# Debugger UI Redesign Handoff

## Goal

Replace the current always-on, all-in-one debug screen with a tabbed snapshot debugger that is easy to return to after time away from the project and has a much smaller impact on emulation performance.

The new debugger should keep keyboard shortcuts for speed, but all common actions must also be discoverable and usable with visible buttons, tabs, selectors, and address fields.

## Chosen Direction

Implement a snapshot-based debugger with an integrated tabbed layout.

- Emulation continues at the normal NES rate.
- The debugger reads from a captured state snapshot instead of repeatedly querying and rebuilding every diagnostic during every draw.
- While running, ordinary debugger data refreshes at a limited rate, initially 10 Hz.
- Expensive PPU images refresh only when their inputs change, when the PPU tab is opened, or when the user requests a refresh.
- While paused or single-stepping, the snapshot updates immediately.
- Only the active debugger tab performs tab-specific work or drawing.

## Primary User Experience

Suggested overall layout:

```text
+-----------------------------------------------------------------------+
| ROM: Battletoads   Run  Pause  Step  Frame  Reset   FPS: 60           |
+-------------------------+---------------------------------------------+
|                         | Overview | CPU | PPU | Memory | Performance |
|                         +---------------------------------------------+
|                         |                                             |
|      NES display        | Active tab content                          |
|                         |                                             |
|      integer-scaled     |                                             |
|                         |                                             |
+-------------------------+---------------------------------------------+
| Running | Audio: On | Save slot: 1 | F1: Help                         |
+-----------------------------------------------------------------------+
```

The exact dimensions may adapt to the window size. Do not depend on fixed coordinates for the final layout.

### Persistent toolbar

Provide visible controls for:

- Run
- Pause
- Step one CPU instruction
- Step one emulated frame
- Reset ROM
- Select/change ROM
- Add breakpoint
- Save state
- Load state
- Save-slot selector
- Mute/unmute
- Volume down/up
- Open Help/Commands

Buttons should show their shortcut in a tooltip or secondary label. Disabled actions should look disabled rather than silently doing nothing.

### Status bar

Show concise current state:

- Running, paused, or stepping
- Active ROM
- Audio state and volume
- Selected save slot
- Breakpoint count or active-breakpoint indication
- Current FPS
- `F1: Help`

### Tabs

#### Overview

This is the default low-cost tab.

- CPU registers and flags
- Current instruction and a short disassembly window
- Current PPU scanline and VBlank state
- Run/pause/step controls
- Active breakpoint summary
- Important warnings or errors

Do not show pattern tables or full nametables here.

#### CPU

- Registers and flags
- Disassembly centered on the program counter
- Stack preview
- Breakpoint list
- Add, enable/disable, and remove breakpoint controls
- Run, pause, step-instruction, and step-frame controls
- Optional jump-to-address field

The current instruction must be clearly highlighted.

#### PPU

- Pattern table 0 and pattern table 1
- Nametable/mirroring view
- Palette display and palette selection controls
- PPU state/scanline selector
- Previous and next state buttons
- Manual Refresh button
- Optional Auto Refresh toggle and rate selector

This is the expensive tab. Its resources must be cached and refreshed using dirty flags.

#### Memory

- Source selector: CPU, PPU, or OAM
- Hexadecimal address entry
- Previous/next page buttons
- Coarse navigation controls
- 16-by-16 byte grid
- Optional opcode/text interpretation toggle
- Current program-counter marker when relevant

Changing memory source or address should not require memorizing `T`, brackets, `O`, or `P`.

#### Performance

- Current frame/update time
- Smoothed average
- Peak time with a Reset Peak button
- Current FPS
- Lua memory usage
- Debugger refresh rate
- Profiling start/stop control and clear indication when profiling is active
- Optional small rolling frame-time graph

Do not label a maximum-frame measurement as the current frame percentage.

## Help and Command Discovery

Replace the large permanent key legend with a help overlay and searchable command list.

The help overlay should include:

- Search field
- Action name
- Current shortcut
- Short description
- Categories such as Emulation, CPU, PPU, Memory, Save State, Audio, and Performance

Every user-facing action should be registered in one action table rather than separately hard-coded into the help text and keyboard handler. A proposed action entry:

```lua
{
    id = "emulation.pause",
    label = "Pause emulation",
    category = "Emulation",
    shortcut = "f5",
    enabled = function(state) return state.running end,
    run = function() debugger.pause() end
}
```

The toolbar, menus/help overlay, and keyboard input should invoke the same action definitions. This prevents the displayed help from drifting away from the actual controls.

Suggested initial shortcuts:

| Action | Shortcut |
| --- | --- |
| Help/commands | F1 |
| Run or pause | F5 |
| Toggle breakpoint | F9 |
| Step CPU instruction | F10 |
| Step emulated frame | Shift+F10 |
| Reset ROM | Ctrl+R |
| Change ROM | Ctrl+O |
| Save selected slot | Ctrl+S |
| Load selected slot | Ctrl+L |
| Toggle debugger | F12 or current `L` during transition |

Existing shortcuts can remain as compatibility aliases during the transition.

## Snapshot Architecture

Create a debugger-owned snapshot that contains display-ready values. The UI should not call emulation bus reads throughout `love.draw()` unless a specific controlled read is necessary.

Suggested structure:

```lua
snapshot = {
    sequence = 0,
    capturedAt = 0,
    running = true,
    romName = "",
    cpu = {
        a = 0,
        x = 0,
        y = 0,
        pc = 0,
        sp = 0,
        flags = {},
        stack = {},
        disassembly = {}
    },
    ppu = {
        scanline = 0,
        vblank = false,
        mirrorMode = 0,
        selectedState = 1,
        states = {}
    },
    memory = {
        source = "cpu",
        startAddress = 0,
        bytes = {}
    },
    performance = {
        frameTime = 0,
        averageFrameTime = 0,
        peakFrameTime = 0,
        fps = 0,
        memoryMB = 0
    }
}
```

Keep large images and GPU objects in view caches, not in the general Lua snapshot.

### Refresh behavior

- Running and debugger visible: capture lightweight data every 0.1 seconds.
- Paused: capture immediately after pause.
- CPU instruction step: execute once, then capture immediately.
- Frame step: execute one frame, then capture immediately.
- Tab change: capture data required by the newly active tab.
- Debugger hidden: stop normal snapshot refreshes and all debug rendering.
- PPU graphics: refresh only when dirty or manually requested.
- Memory: refresh only while the Memory tab is active, after navigation, or on the limited refresh timer.

Snapshot capture must not mutate hardware state. Be careful with bus/register reads that have read side effects; use raw/peek accessors for debugging where required.

## Performance Requirements

### Mandatory rules

- Do not call `love.graphics.newFont`, `newCanvas`, `newQuad`, `newImage`, or similar resource constructors in the per-frame draw path.
- Create fonts once and reuse them.
- Create the two nametable canvases once and reuse them.
- Create and cache the 256 possible 8-by-8 CHR tile quads once.
- Do not rebuild pattern tables and nametables while another tab is active.
- Do not regenerate static help text every frame.
- Do not read and format a full memory page unless the Memory tab needs a refresh.
- Drawing functions should draw cached state; update/capture functions should prepare that state.
- Profiling must remain explicitly opt-in because the existing hook-based profiler disables or disrupts LuaJIT performance.

### Dirty flags

Suggested flags:

```lua
dirty = {
    snapshot = true,
    cpu = true,
    memory = true,
    patternTables = true,
    nametables = true,
    palette = true,
    helpText = true
}
```

Examples:

- Palette change marks palette, pattern tables, and nametables dirty.
- Selected PPU state change marks pattern tables and nametables dirty.
- Memory address/source change marks memory dirty.
- ROM reset/change marks every view dirty.
- Resizing marks layout and applicable canvases dirty, but should not rebuild emulator data.

### Initial performance targets

Measure on the same ROM and scene before and after the work.

- Debugger hidden should have effectively no debug rendering cost.
- Overview/CPU tab target: no more than roughly 10% additional average frame time.
- PPU tab target: no continuous GPU-resource allocation and no large recurring garbage-collection spikes.
- Switching to PPU may perform one visible refresh, but leaving it open should not rebuild unchanged resources every frame.
- Emulator should maintain its normal 60 FPS when the machine can already do so without the debugger.

These are initial engineering targets, not reasons to hide incorrect measurements. Record actual before/after timings.

## Known Current Hotspots

Start investigation in these places:

- `main.lua`: `DebugDraw()` unconditionally calls `ppu.DrawCharacterTiles()` whenever debugging is enabled.
- `Emulator/UI/Debug/testing.lua`: fixed-position monolithic UI, per-frame string formatting, disassembly reads, memory reads, and permanent shortcut guide.
- `NES/PPU/ppu.lua`: `DrawCharacterTiles()` rebuilds CHR and nametable diagnostics.
- `NES/PPU/PPUtoLove2d.lua`: `ScreenToNumbers()` creates two canvases and creates a new Quad for each nametable tile on every call.
- `Includes/displaytimer/init.lua`: `DrawPerformanceMetrics()` creates a new font on every frame, and the displayed frame percentage is derived from the peak measurement.
- `Includes/keyboard.lua`: actions, shortcuts, state changes, and a blocking breakpoint-address dialog are tightly coupled.

The breakpoint address UI currently runs its own event/draw loop. Replace it with ordinary non-blocking UI state handled by the normal LÖVE update/draw/input callbacks.

## Suggested Module Boundaries

Names may change, but keep responsibilities separated:

```text
Emulator/UI/Debug/
  debugger.lua          -- visibility, active tab, pause/run state, update/draw
  actions.lua           -- command registry and shortcuts
  snapshot.lua          -- safe snapshot capture and refresh scheduling
  layout.lua            -- responsive rectangles and scaling
  widgets.lua           -- buttons, tabs, text fields, tooltips, selectors
  cache.lua             -- fonts, Text objects, canvases, quads, dirty flags
  tabs/
    overview.lua
    cpu.lua
    ppu.lua
    memory.lua
    performance.lua
  help.lua              -- searchable action/help overlay
```

Avoid adding a large UI dependency unless there is a clear reason. A small set of native LÖVE widgets is enough for the first version.

## Implementation Plan

### Phase 1: Baseline and resource fixes

- Record average and peak frame times with debugger hidden and enabled.
- Move font creation out of `DrawPerformanceMetrics()`.
- Cache nametable canvases.
- Cache the 256 tile quads.
- Stop calling `ppu.DrawCharacterTiles()` when the active tab does not need it.
- Add counters or temporary instrumentation to confirm that GPU resources are not created every frame.

Deliverable: current debugger appearance may remain, but recurring resource allocation and unconditional PPU drawing are removed.

### Phase 2: Debugger shell and action registry

- Add debugger state: visible, active tab, running/paused, selected save slot.
- Add responsive toolbar, tab bar, content region, and status bar.
- Implement reusable buttons, tabs, tooltips, and simple text input.
- Create the central action registry.
- Route keyboard shortcuts and buttons through the same actions.
- Keep old shortcuts as aliases where useful.

Deliverable: clickable shell with functional run/pause/step/reset/save/load/audio/ROM/help actions.

### Phase 3: Snapshot system

- Add lightweight snapshot capture.
- Add 10 Hz refresh scheduling while running.
- Add immediate refresh after pause and stepping.
- Add safe peek accessors where debug reads could affect hardware state.
- Stop CPU/disassembly/register UI from querying live emulator state in `love.draw()`.

Deliverable: Overview and CPU tabs render from snapshots.

### Phase 4: Migrate tabs

- Build Overview tab.
- Build CPU tab and breakpoint editor.
- Build Memory tab with source selector and address field.
- Build PPU tab using cached resources and dirty flags.
- Build Performance tab with correct current, average, and peak metrics.

Deliverable: old monolithic debug UI is no longer the primary interface.

### Phase 5: Help, cleanup, and validation

- Add searchable Help/Commands overlay.
- Remove the permanent shortcut boxes.
- Remove obsolete duplicated key-handling and rendering code.
- Verify resizing and integer-scaled game rendering.
- Compare before/after performance.
- Test run, pause, both step modes, breakpoint entry, memory navigation, PPU state navigation, ROM change, reset, save/load, mute, and volume.

Deliverable: completed discoverable debugger with documented measurements.

## Acceptance Criteria

The redesign is complete when all of the following are true:

- A returning user can operate common debugging functions without knowing hidden keys.
- The debugger contains Overview, CPU, PPU, Memory, and Performance tabs.
- Only the active tab performs its tab-specific update and drawing work.
- Run, pause, instruction step, frame step, reset, change ROM, breakpoint, save/load, audio, and help have visible controls.
- Keyboard shortcuts and buttons use the same action implementation.
- Help is available through a visible control and `F1`.
- Debug UI drawing consumes a snapshot rather than repeatedly reading emulator state throughout `love.draw()`.
- Snapshot refresh is rate-limited while running and immediate while paused/stepping.
- Pattern tables and nametables use cached GPU resources and dirty refreshes.
- No fonts, canvases, quads, or images are created continuously in the draw loop.
- Breakpoint address entry is non-blocking.
- Memory debug reads do not accidentally trigger hardware read side effects.
- Performance metrics distinguish current, average, and peak values correctly.
- Debugger hidden mode avoids debug updates and diagnostic drawing.
- Before/after performance measurements are recorded in this document or a linked results document.

## Out of Scope for the First Version

- A separate operating-system debugger window or second process
- Docking/undocking panels
- Full source-level debugging
- Remote debugging protocol
- Rewind/history recording
- Complex theming system
- Replacing the emulator's core PPU implementation solely for UI performance

These may be revisited after the integrated snapshot debugger is stable.

## Handoff Notes

Preserve emulator correctness while moving diagnostics. Debug reads can be dangerous on NES hardware registers because some reads clear flags or advance internal state. Prefer copying internal state or adding explicit `Peek` methods instead of using normal CPU/PPU bus reads indiscriminately.

Implement this incrementally. Keep the current debugger available behind a temporary legacy flag until the new Overview, CPU, Memory, and PPU tabs are usable. Remove the legacy path only after the acceptance tests pass.

