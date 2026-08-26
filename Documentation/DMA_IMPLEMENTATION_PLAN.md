# NES DMA Implementation Plan

## Purpose

Implement DMA in three controlled stages without sacrificing the games that
already run. Each stage has a clear stopping point and should be committed and
regression-tested before beginning the next stage.

The stages are:

1. **Start DMA**: useful OAM DMA with correct transfer size and CPU stall.
2. **Mid DMA**: OAM DMA as individual bus cycles and a functional DMC channel.
3. **Advanced DMA**: cycle-accurate RDY behavior, DMC/OAM arbitration, bus
   conflicts, abort behavior, and interrupt polling.

Passing every AccuracyCoin DMA test is an advanced-stage goal. Start DMA is
primarily a game-compatibility improvement.

## Current Emulator State

### CPU

`NES/CPU/cpumain.lua` executes a complete instruction and receives one total
cycle cost from the opcode implementation. It then advances the APU and PPU by
that total. Individual opcode fetch, operand, dummy, read, and write cycles are
not scheduled separately.

### OAM DMA

A write to `$4014` currently calls `OAM.RefreshOAM` immediately through
`NES/PPU/ppuBus.lua`. `NES/PPU/ppuOAM.lua` copies 256 bytes directly from
internal CPU RAM and does not stall the CPU.

Current limitations:

- No 513/514-cycle CPU stall.
- Source pages are forced through the internal 2 KiB RAM mirror.
- Mapper, PPU, APU, controller, and open-bus source pages are not read through
  the CPU bus.
- No alternating DMA get/put cycles.
- No DMA alignment cycle.
- No OAM/DMC arbitration.

### DMC DMA

There is no DMC sample reader or DMC DMA engine. `$4010-$4013` do not maintain
the state needed for sample fetching, and `$4015` bit 4 does not start or stop
a sample.

### Timing Constraint

The current instruction-level CPU can support a useful Start DMA. Exact DMA
requires a shared CPU-cycle scheduler so CPU, PPU, APU, mapper, interrupts, and
DMA all observe the same cycle.

---

## Stage 1: Start DMA

### Goal

Replace the immediate `$4014` copy with a queued OAM DMA that transfers 256
bytes and stalls the CPU for 513 or 514 cycles. Preserve the current
instruction-level CPU.

### Design

#### 1. Queue the request

In `NES/BUS/bus.lua`, a write to `$4014` should store a pending DMA request:

```lua
pendingOAMDMA = {
    page = data,
    oamAddress = ppuIO.OAMADDR
}
```

Do not perform the copy inside `bus.CPUWrite`. Expose a function such as:

```lua
function bus.TakeOAMDMARequest()
    local request = pendingOAMDMA
    pendingOAMDMA = nil
    return request
end
```

Keeping the queue in the bus avoids a circular dependency between the bus and
a future DMA module.

#### 2. Run DMA after the instruction

In `NES/CPU/cpumain.lua`, check for a pending request after the instruction that
wrote `$4014` completes.

Initial timing model:

```text
1 halt cycle
+ 1 alignment cycle when required by CPU-cycle parity
+ 256 read cycles
+ 256 write cycles
= 513 or 514 CPU cycles
```

The parity decision must use the CPU cycle on which DMA begins, not the frame
number or PPU scanline.

#### 3. Read through the CPU bus

The source address is:

```text
(page << 8) | index
```

Use `bus.CPURead` rather than reading `cpuRAM` directly. This makes cartridge
RAM and other CPU pages behave sensibly and updates the CPU open-bus latch.

At this stage the 256 reads occur as one operation rather than at their exact
cycles. This is acceptable for normal page `$02` sprite DMA but is not enough
for AccuracyCoin's I/O-page DMA tests.

#### 4. Write through a dedicated OAM method

Add a small method to `NES/PPU/ppuOAM.lua`, for example:

```lua
function ppu.OAM.DMAWrite(value, address)
    ppu.OAM[bit.band(address, 0xFF)] = bit.band(value, 0xFF)
end
```

The destination begins at the captured `OAMADDR` and wraps after `$FF`.
OAM DMA should not use the normal `$2004` rendering-time write behavior.

#### 5. Advance all clocks during the stall

The stall cycles must be added to:

- The current `ExecuteCycles` cycle count.
- `cpu.totalCycles`.
- `apu.Clock`.
- `ppu.Update` through the existing CPU-cycle-to-PPU-cycle path.

Do not execute an opcode or service an interrupt during the stall. NMI and IRQ
requests may become pending and are handled after DMA completes.

### Start DMA Non-goals

- Correct reads from `$4000-$401F` during OAM DMA.
- Correct PPU-register side effects at a specific DMA cycle.
- DMC DMA.
- OAM/DMC arbitration.
- DMA delayed by individual CPU write cycles.
- Exact CPU address-bus value during the halt cycle.

### Expected Improvements

- Normal `$0200-$02FF` sprite DMA remains functional.
- Games now lose the correct approximate CPU time during OAM DMA.
- Mapper-backed source pages can be copied.
- CPU/PPU synchronization tests may advance further.
- `Rendering Flag Behavior` and `BG Serial In` may stop locking if their main
  blocker is the missing OAM stall, but they are not expected to pass because
  they also require dot-level rendering behavior.

### Start DMA Validation

Regression-test at minimum:

- Super Mario Bros. 3: boots and enters gameplay.
- Metroid: title and first area render correctly without resetting.
- R.C. Pro-Am: track/dashboard split remains stable.
- A sprite-heavy mapper 0 game.
- A mapper 1 game and a mapper 4 game.
- AccuracyCoin Address `$2004` behavior still reaches at least its current
  failure number.

Do not proceed to Mid DMA until these games remain stable.

---

## Stage 2: Mid DMA

### Goal

Give OAM DMA real per-cycle get/put behavior and implement a functional DMC
sample reader. This stage introduces a shared DMA scheduler but does not yet
require every CPU instruction to be expressed as micro-operations.

### Shared CPU-Cycle Clock

Create one function responsible for advancing a single CPU cycle, for example:

```lua
clockCPUCycle(busAction)
```

Each call should:

1. Perform the requested CPU or DMA bus action.
2. Advance the APU by one CPU cycle.
3. Advance the PPU by one CPU cycle through its existing 3:1 clock conversion.
4. Allow mapper IRQ state and NMI edges to become pending.
5. Increment `cpu.totalCycles`.

OAM DMA can then run one halt/alignment cycle followed by 256 alternating
source-read and OAM-write cycles.

### Mid-level OAM DMA

Track explicit state:

```text
pending
active
page
index
latched byte
destination OAM address
phase: halt, align, get, put
```

On a get cycle:

```text
latched byte = CPURead((page << 8) | index)
```

On a put cycle:

```text
OAM[destination] = latched byte
index++
destination = (destination + 1) & $FF
```

This permits PPU/APU/controller read side effects to occur at their actual
positions within the DMA instead of being applied in a batch.

### Functional DMC Channel

Add CPU-visible state for:

- `$4010`: IRQ enable, loop flag, timer-rate index.
- `$4011`: output level/DAC.
- `$4012`: sample start address, `$C000 + value * 64`.
- `$4013`: sample length, `value * 16 + 1`.
- `$4015` bit 4: start/restart when idle and stop active sample fetching.
- `$4015` bit 7: DMC IRQ flag.

Track:

```text
current sample address
bytes remaining
sample buffer and empty flag
shift register
bits remaining
silence flag
timer
DMC IRQ flag
```

The sample address wraps from `$FFFF` to `$8000`. At the end of the sample,
either reload it when looping or set the DMC IRQ flag when enabled.

Use the NTSC DMC rate table initially:

```text
428, 380, 340, 320, 286, 254, 226, 214,
190, 160, 142, 128, 106, 85, 72, 54
```

### Mid DMA Arbitration

At this stage, use a documented deterministic priority:

1. DMC sample get when it is due.
2. OAM DMA phase.
3. CPU execution.

Model the normal DMC halt/dummy/get sequence well enough that a DMC fetch
stalls CPU reads and updates the CPU data bus. Leave unusual overlap and abort
behavior for Advanced DMA.

### Expected Improvements

- DMC audio and basic DMC IRQ behavior work.
- AccuracyCoin DMC prerequisite/synchronization tests begin progressing.
- Interrupt Flag Latency can reach its CPU-polling checks instead of failing
  because no DMC IRQ occurs.
- DMA plus open bus/register/controller tests can begin distinguishing real
  bus behavior.
- OAM DMA starts to interact correctly with PPU and controller registers.

### Mid DMA Validation

- Start DMA regression list remains stable.
- `$4015` correctly reports and controls DMC active/IRQ state.
- One-byte and looping DMC samples complete without hangs.
- Sample address wraps `$FFFF -> $8000`.
- OAM DMA always transfers exactly 256 bytes and wraps `OAMADDR`.
- AccuracyCoin Page 13 advances beyond the DMC prerequisite failures.
- AccuracyCoin Page 14 DMC test advances beyond test 1.

---

## Stage 3: Advanced DMA

### Goal

Model CPU RDY behavior and DMA arbitration at individual CPU bus cycles closely
enough for AccuracyCoin's overlap, conflict, and abort tests.

### Required CPU Refactor

The CPU must expose every instruction cycle as a bus micro-operation:

- Opcode fetch.
- Operand fetch.
- Dummy read.
- Data read.
- Data write.
- Read-modify-write old and new writes.
- Stack read/write.
- Interrupt vector reads.

DMA can halt the CPU only on a readable cycle. If the CPU is performing a
write, DMA waits while the write completes. During a halt, the CPU retains the
address appropriate to the interrupted bus cycle.

An instruction may still have a fast path for normal gameplay, but the result
must be identical to the micro-operation path. Do not maintain two unrelated
opcode implementations.

### Advanced OAM/DMC Arbitration

Implement explicit phases and priorities for simultaneous DMA activity:

- CPU halt and alignment cycles.
- OAM get and put cycles.
- DMC halt, dummy, and sample-get cycles.
- DMC priority on eligible get cycles.
- OAM priority on put cycles.
- Extra OAM alignment after DMC steals a get cycle when required.
- Combined halt behavior when both DMAs begin together.

### Bus Conflicts and Sensitive Registers

The CPU address bus, OAM source address, and DMC source address are distinct
internal sources. Which source activates the external register decode matters.
Advanced DMA must cover:

- Open-bus values during DMA.
- `$2002` reads clearing VBlank.
- `$2007` reads and its internal read buffer.
- `$4015` reads clearing the frame IRQ flag.
- `$4016/$4017` controller clocking.
- OAM DMA sourced from `$4000-$40FF`.
- DMC DMA bus conflicts with APU and controller registers.

### Abort and Overlap Behavior

Implement and save enough state for:

- Explicit DMC abort through `$4015`.
- Implicit reload aborts.
- DMC DMA overlapping OAM DMA.
- DMA beginning near CPU write cycles.
- Interrupts becoming pending during DMA.

### Interrupt Polling

Once the CPU is cycle-based, connect interrupt polling to the correct final
instruction cycles. This is also the proper point to fix:

- CLI/SEI/PLP interrupt-flag latency.
- NMI enabled during VBlank.
- NMI suppression around `$2002` reads.
- NMI hijacking BRK/IRQ vector fetches.

These are related to the same cycle scheduler even though they are not all DMA
features.

### Save States

Mid and Advanced DMA require save-state fields for all pending and active DMA
state. Loading a state during DMA must either resume exactly or explicitly
reject/migrate older states. Do not silently discard an active DMA request.

### Advanced Validation Targets

AccuracyCoin:

- Page 12: Interrupt Flag Latency and NMI overlap tests.
- Page 13: DMA plus open bus/registers, DMC/OAM overlap, explicit abort, and
  implicit abort.
- Page 14: DMC channel and DMA-dependent controller/APU behavior.
- Page 16/18: OAM and rendering synchronization prerequisites.
- Page 17: exact VBlank/NMI timing after CPU/PPU cycle integration.

Also run CPU instruction and dummy-cycle tests after every CPU scheduler
change. DMA accuracy is not useful if ordinary opcode timing regresses.

---

## Recommended Implementation Order

1. Commit the current working emulator baseline.
2. Add a queued `$4014` request without changing transfer behavior yet.
3. Move the existing copy out of `ppuBus.CPUWrite` and consume it after the
   instruction.
4. Add 513/514 stall accounting and clock the PPU/APU during the stall.
5. Change source reads from direct CPU RAM access to `bus.CPURead`.
6. Run the Start DMA regression list and commit.
7. Introduce the one-CPU-cycle clock helper.
8. Convert OAM DMA to halt/align/get/put phases and commit.
9. Add DMC registers and functional sample playback without overlap quirks.
10. Add DMC DMA requests and basic arbitration; regress and commit.
11. Convert CPU instructions to reusable bus micro-operations.
12. Implement advanced arbitration, conflicts, aborts, and interrupt polling.

## Stop Points

It is valid to stop after any completed stage:

- **After Start DMA:** best effort-to-compatibility ratio for this emulator.
- **After Mid DMA:** functional DMC and substantially better bus behavior.
- **After Advanced DMA:** accuracy-test-oriented architecture.

Do not patch individual AccuracyCoin answers by detecting the test ROM, program
counter, scanline, or known memory values. Every change should represent a
general NES hardware rule and be checked against normal games.
