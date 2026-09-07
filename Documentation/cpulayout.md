# 6502 CPU layout and optimization plan

This document describes the current CPU implementation and the order in which
it should be improved. The emulator uses the Ricoh 2A03 CPU in the NES, not a
generic MOS 6502. The 2A03 has no functional decimal arithmetic, and CPU bus
reads/writes, dummy reads, interrupts, DMA, and cycle counts affect PPU, APU,
mapper, and controller behavior.

## Current execution layout

`NES/CPU/cpumain.lua` owns the instruction loop and the cycle budget. Each
iteration currently does this:

1. Handle a pending NMI or IRQ.
2. Fetch the opcode through `bus.CPURead`.
3. Look up an opcode descriptor in `opcodeTable`.
4. Run its addressing-mode function.
5. Run its operation function.
6. Add base, addressing, and operation cycle adjustments.
7. Clock the APU and accumulate PPU debt.
8. Advance the PPU in batches of about 114 CPU cycles (341 PPU dots).
9. Consume OAM DMA requests and charge their 513/514 CPU cycles.

`NES/CPU/opcodes/opcodeTable.lua` stores one descriptor per opcode. A
descriptor contains mnemonic, addressing function, action function, byte
length, and base cycles. This is readable and should remain the source of
truth while correctness is being established.

`NES/CPU/opcodes/addressmodes.lua` performs operand and dummy bus reads and
returns an effective value/address plus an optional cycle adjustment.
`functionsA_G.lua`, `functionsH_N.lua`, `functionsO_T.lua`, and
`functionsU_Z.lua` implement official and unofficial operations. The bus is
the shared timing boundary for RAM, PPU registers, APU registers, controllers,
DMA, open bus, and cartridge mappers.

The table contains 244 explicit entries. The twelve missing byte values are
`$02,$12,$22,$32,$42,$52,$62,$72,$92,$B2,$D2,$F2`; they currently fall through
to `illegalOpcodes.Execute`, which behaves like a 1-byte, 2-cycle NOP. These
are the KIL/JAM family on common 6502 variants and should be represented as a
stopped CPU state if compatibility with software that probes unofficial
opcodes is required.

## Correctness findings to fix first

### Taken branches

`BranchFunction` adds one cycle for a taken branch but currently adds zero for a
page crossing. A taken branch costs 3 cycles; a taken branch crossing a page
costs 4. The old-page dummy read also needs to remain visible on the bus. This
is a timing and mapper correctness issue, not an optimization. See the NESdev
[instruction reference](https://www.nesdev.org/wiki/Instruction_reference).

### Indexed read-modify-write instructions

`ASL`, `LSR`, `ROL`, `ROR`, `INC`, and `DEC` absolute-X forms use the ordinary
indexed read addressing mode in several table entries. That mode adds a page
cross cycle, but absolute-X RMW instructions have a fixed 7-cycle timing. Use
an RMW-specific addressing mode that performs the required dummy read without
adding a page-cross adjustment. RMW instructions must preserve the original
value write followed by the modified value write.

### JSR bus sequence

`JSR` previously read both operand bytes through `GetAbsoluteAddressMode`, then
read them again inside `JSRFunction`. This creates duplicate bus reads and can
trigger mapper or I/O side effects. It now has a dedicated addressing mode:
the low byte is read once, the operation performs JSR's dummy stack read, pushes
the return address, and reads the high byte for the jump. This preserves the
six-cycle sequence without rereading the low byte.

### Indirect JMP wrap

`GetAbsoluteIndirectMode` does not mask `programCounter + 1` and `programCounter
+ 2` to 16 bits before reading. An indirect JMP at the end of memory can issue
addresses above `$FFFF`. Mask operand addresses with `band(..., 0xFFFF)` and
retain the 6502 page-wrap bug for the indirect vector high byte.

### NES-specific status behavior

The decimal flag may be stored and pushed, but ADC/SBC must remain binary on a
2A03. Interrupt stack status, BRK versus IRQ/NMI B-bit behavior, bit 5, reset,
NMI/IRQ latency, and vector reads need dedicated tests. The NES CPU also has
unofficial opcodes used by some commercial software. Do not remove them for a
dispatch optimization.

## Performance opportunities, in order

1. **Measure first.** Use a release-like run with LuaJIT enabled and the
   existing frame timer. The custom `Includes/profile/profile.lua` calls
   `jit.off()` and installs `debug.sethook`, so its timings describe the
   instrumented interpreter rather than normal JIT execution. Use LuaJIT's
   statistical profiler for hotspot sampling when available; it samples both
   interpreted and JIT code with low overhead. See the [LuaJIT profiler
   documentation](https://luajit.org/ext_profiler.html).
2. **Keep PPU batching.** `114` CPU cycles is approximately one 341-dot
   scanline. Do not use one-cycle updates in the normal path. The light-gun
   line pass can inspect the beam span inside each batch.
3. **Remove dead hot-path work.** The current threshold expression is
   `IsEnabled() and 114 or 114`; use a single constant. Remove the unused
   `opTable` local. Localize stable functions and bit operations once per
   `ExecuteCycles` call, as already done for the bus, APU, and opcode executor.
4. **Reduce descriptor calls only after tests pass.** A second representation
   can store compact parallel arrays (`readMode[opcode]`, `action[opcode]`,
   `bytes[opcode]`, `cycles[opcode]`) while keeping the descriptor table for
   debugging. This removes repeated descriptor field lookups without making
   the source opcode list unreadable.
5. **Use bit masks for common flags.** The repeated string-keyed
   `cpuInternal.SetFlag`/`GetFlag` calls are costly in ALU-heavy code. Add local
   helpers that update Z/N/C/V directly on `statusRegister`, then migrate one
   instruction family at a time and compare traces.
6. **Specialize only measured families.** Loads, stores, branches, and common
   zero-page operations are good candidates for compact handlers. Keep unusual
   opcodes, RMW bus sequences, and interrupt code explicit until instruction
   and bus tests cover them.
7. **Avoid allocation and logging in the loop.** Do not create tables or format
   strings per instruction. Keep opcode tracing, light-gun traces, and debug
   hooks behind flags that are false in normal play.

## Test gates

Before changing dispatch, add or run tests for:

- Official opcode results and Z/N/C/V flags.
- Branch taken, not taken, and page-cross cycle counts.
- Page-cross loads versus fixed-cycle indexed stores and RMW operations.
- Zero-page pointer wrapping for indexed-indirect modes.
- Indirect JMP page-wrap behavior and end-of-memory operand wrapping.
- JSR/RTS/RTI stack values and bus access order.
- BRK, IRQ, NMI, reset, and decimal-mode behavior on the 2A03.
- OAM DMA 513/514-cycle parity and PPU batch boundaries.
- Unofficial opcode families used by the existing accuracy ROMs.

Compare CPU register state, memory writes, cycle count, and relevant bus
addresses against a known-good trace. Only after those gates pass should a
dispatch or flag representation be benchmarked against the current readable
implementation.

## Recommended first implementation slice

Fix branch page-cross accounting, split RMW indexed addressing from indexed
loads, and correct indirect-JMP operand masking. Add focused regression tests
for those cases. Then profile a normal LuaJIT run and decide whether compact
parallel opcode metadata or direct flag masks produce a measurable gain. This
sequence keeps the 6502 bus contract intact while making each optimization
reviewable and reversible.
