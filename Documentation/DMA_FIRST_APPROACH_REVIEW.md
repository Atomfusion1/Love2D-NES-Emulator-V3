# DMA First Approach Review

Date: 2026-08-26

## Scope

This document reviews the current emulator implementation and recommends the
first approach for improving DMA behavior. The request used the term "CMA"; the
codebase consistently refers to this feature as **DMA** (Direct Memory Access),
specifically OAM DMA through `$4014`. This review assumes DMA was intended.

## Current state

The project already contains a detailed staged plan in
`Documentation/DMA_IMPLEMENTATION_PLAN.md`. The current implementation is
functional enough for basic sprite copying, but it is not timing-correct:

- `NES/BUS/bus.lua` sends a `$4014` write directly to the PPU bus.
- `NES/PPU/ppuBus.lua` immediately calls `OAM.RefreshOAM`.
- `NES/PPU/ppuOAM.lua` copies 256 bytes directly from the internal 2 KiB CPU
  RAM table.
- `NES/CPU/cpumain.lua` executes whole instructions, advances the APU by the
  instruction cycle cost, and advances the PPU through a batched CPU-cycle
  debt. There is no DMA stall handling.
- There is no DMC sample reader or DMC DMA engine yet.

The most important consequence is that a game can copy sprites, but the CPU
continues running during the transfer. The source is also forced to the
internal RAM mirror, so DMA from cartridge-backed or other CPU-bus pages does
not behave correctly.

## Recommended first approach: Start DMA

Implement only the useful, low-risk OAM DMA behavior first. Keep the current
instruction-level CPU and add a queued DMA request consumed after the
instruction that writes `$4014` finishes.

### Step 1: Queue the request

Move ownership of the pending request into `NES/BUS/bus.lua`:

```lua
pendingOAMDMA = {
    page = data,
    oamAddress = ppuIO.OAMADDR
}
```

Expose a small consume function, such as `TakeOAMDMARequest()`. The `$4014`
write should no longer copy OAM immediately.

Capture `OAMADDR` when the request is written. This prevents later register
writes from changing the destination of an already-requested transfer.

### Step 2: Consume it after the instruction

In `NES/CPU/cpumain.lua`, check for the request after the current instruction
has completed. Transfer all 256 bytes, then add the DMA stall to the current
execution count and `cpu.totalCycles`.

Use 513 or 514 CPU cycles:

```text
1 halt cycle
+ optional alignment cycle
+ 256 source reads
+ 256 OAM writes
```

At this stage, determine the alignment from CPU-cycle parity. Do not use the
frame number or PPU scanline.

### Step 3: Read through the CPU bus

For each source byte, read:

```text
(page << 8) | index
```

through `bus.CPURead`, not directly from `cpuram.cpuRAM`. This immediately
improves behavior for mapper-backed memory and preserves bus/open-bus behavior
as far as the current architecture allows.

### Step 4: Write through a DMA-specific OAM method

Add a method in `NES/PPU/ppuOAM.lua` that writes one byte to a supplied OAM
address without invoking ordinary `$2004` behavior. The destination must wrap
at `$FF`, and the transfer must begin at the captured `OAMADDR`.

Do not implement DMA by repeatedly calling the normal PPU `$2004` register
handler; OAM DMA has different timing and destination semantics.

### Step 5: Advance the other clocks during the stall

The stall must advance:

- `cpu.totalCycles`;
- APU timing through `apu.Clock`;
- PPU timing through the existing `ppu.Update` path.

No opcode or interrupt should execute during the stall. NMI and IRQ conditions
may become pending and should be handled after the DMA completes.

## Why this is the right first milestone

This is the best compatibility-to-complexity step because it fixes the main
missing hardware effect—CPU time lost to sprite DMA—without requiring an
immediate rewrite of every 6502 instruction into individual bus cycles. It
also keeps the existing game-compatible execution path intact while creating a
clean boundary for later cycle-level work.

## Validation plan

Before moving to DMC or cycle-accurate DMA, verify:

1. A 256-byte transfer from `$0200-$02FF` reaches all OAM bytes correctly.
2. A nonzero `OAMADDR` starts at that address and wraps correctly.
3. A mapper-backed source page is read through the CPU bus.
4. CPU cycle count increases by exactly 513 or 514 cycles according to parity.
5. APU and PPU clocks advance during the stall.
6. No instruction executes during the stall.
7. Existing tests still pass, especially cartridge reset and PPU scroll tests.
8. Representative games still boot and render: Super Mario Bros. 3, Metroid,
   R.C. Pro-Am, one mapper 0 game, one mapper 1 game, and one mapper 4 game.

Commit this milestone separately before beginning the next stage. That makes a
regression easy to identify and provides a stable baseline for the eventual
shared CPU-cycle scheduler.

## Deliberate non-goals for the first change

Do not include these in the first patch:

- DMC audio or DMC DMA;
- OAM/DMC arbitration;
- exact per-cycle PPU/APU register side effects;
- CPU RDY behavior during write cycles;
- open-bus edge cases during DMA;
- a complete micro-operation rewrite of the CPU.

Those belong to the later stages already described in
`Documentation/DMA_IMPLEMENTATION_PLAN.md`. Mixing them into the first change
would make failures harder to isolate and would increase the risk to currently
working games.

## Review conclusion

Start with queued OAM DMA plus 513/514-cycle CPU stall accounting. The existing
`DMA_IMPLEMENTATION_PLAN.md` is directionally correct; this document narrows it
to the first independently testable implementation slice.

## DMC starter follow-up

The first DMC starter is now implemented in `NES/Audio/apu_dmc.lua` and wired
through `NES/Audio/apu.lua` and `NES/BUS/bus.lua`. It currently provides:

- `$4010-$4013` register state;
- `$4015` DMC enable and active status;
- sample address and length counters;
- CPU-bus sample reads;
- DMC timer and 7-bit output-level updates;
- looping and DMC IRQ flag behavior.

This starter does not yet make DMC reads steal CPU cycles, arbitrate against
OAM DMA, or stream the output through a dedicated Love2D audio source. Those
are separate follow-up tasks after the CPU-cycle scheduler is ready.
