# Battletoads PPU split investigation

## Symptom

Battletoads displayed its sprites and status area, but the first-level
background was missing or was selected from the wrong vertical part of the
one-screen nametable.

The mapper-7 debug view showed that the level graphics existed in the selected
one-screen nametable. The problem was therefore frame reconstruction and scroll
state selection, rather than missing CHR or nametable data.

## Evidence collected

- Battletoads uses mapper 7 one-screen mirroring and changes the selected
  one-screen nametable during the visible frame.
- Mesen showed `$2005` writes around scanline 16 and a completed pair of `$2006`
  writes around scanline 35.
- The emulator recorded a corresponding state around scanline 36 with
  `v=$3200`.
- Decoding that state produced raw current PPU Y=131:
  coarse Y 16, fine Y 3.
- For the snapshot renderer, the intended top-of-viewport origin appeared to
  be Y=96. With this renderer's scanline convention, the observed relationship
  was `131 - (36 - 1) = 96`.
- The split must remain at approximately scanline 36. Moving the split itself
  by 16 pixels was not the correct fix.

## Changes that were tried

1. Frame reconstruction began with the mirror mode captured in the first PPU
   state instead of the mapper's final end-of-frame mirror mode.
2. Background drawing used the PPUMASK/background-enabled value saved in each
   scanline state instead of only the final value at frame end.
3. Mid-visible `$2001` writes were captured as PPU states.
4. Debug output was expanded to show raw and effective scroll X/Y, nametable,
   coarse/fine scroll, `v`, `t`, mirror mode, `$2006` status, and background
   enable state.
5. A completed mid-frame `$2006` state was converted from its current fetch Y
   to a top-of-viewport Y before the deferred renderer selected tiles.
6. Mirror-only states were prevented from resetting vertical scroll when their
   vertical `v` bits had not changed.

These changes made the Battletoads level background draw correctly.

## Why the approach was reverted

The deferred Love2D renderer does not have enough event information in every
saved PPU state to safely infer one universal vertical origin:

- RC Pro-Am relies on later states that genuinely select a different vertical
  background region. Preserving Y too broadly left it drawing the dashboard
  instead of the track.
- TMNT deliberately uses coarse Y values 30 and 31. Those values read the
  attribute-table area as tile data and then wrap without the ordinary
  nametable transition. Treating this as a linear Y coordinate changed the
  selected nametable and made its screen position worse.
- A state can be created by a mapper write, PPUMASK write, `$2000`, `$2005`,
  `$2006`, or a rendering transfer. The state structure does not currently
  retain a reliable cause/event type for every transition. Inferring the cause
  only from the final `v` value is ambiguous.

## Safer future implementation

Before trying the Battletoads fix again, record explicit state-change reasons
and keep the following operations independent:

- mapper mirror/bank change;
- PPUMASK background/sprite enable change;
- horizontal reload at dot 257;
- vertical reload during pre-render dots 280-304;
- completed `$2005` pair;
- completed `$2006` pair.

The renderer should then update only the component named by the event. Vertical
movement should use the PPU's coarse-Y transition rules, including rows 30/31,
rather than converting every state to a linear 0-479 coordinate.

Recommended regression games for another attempt:

- Battletoads: mapper-7 status/playfield split;
- RC Pro-Am: dashboard-to-track transition;
- TMNT: Y values above 239 and attribute-table reads;
- SMB3: mid-frame mirroring and scroll split;
- DuckTales or SMB: coarse-X scrolling.

## Reverted event-based implementation attempt

An implementation attempt kept explicit `changeEvents` payloads in each saved
PPU state. When nearby writes are merged, the original completed `$2006`
payload retains its own scanline, `v`, `t`, and fine-X latch rather than being
replaced by the latest general snapshot.

The deferred renderer now interprets events separately:

- `address_2006` changes the current fetch address and converts its current Y
  into the renderer's viewport origin;
- `horizontal_transfer` changes only the horizontal rendering address;
- `scroll_2005` changes fine X immediately while coarse X waits for the
  horizontal-transfer event;
- `control_2000` changes control/pattern state without treating `t` as an
  immediate vertical scroll;
- `mapper` changes mapper/CHR/mirroring state without resetting vertical Y;
- legacy and IRQ snapshots retain the former full-state behavior for games
  that have not yet been assigned more specific events.

The debug panel reports both the raw saved address and the renderer's effective
scroll origin. For Battletoads, the expected diagnostic is raw Y=131 and render
Y=96 on the state containing `address_2006`.

This implementation was reverted after regression testing. RC Pro-Am selected
the wrong mapper-7 one-screen page, while TMNT's coarse-Y 30/31 path was treated
as a linear viewport and repeated the wrong part of the screen. Adding mirror
fallback inference did not solve the underlying ambiguity.

The next attempt must not merge events into mutable snapshots. It should first
record an ordered, read-only event stream containing scanline, dot/cycle,
event type, and the affected fields. A separate experimental renderer can then
consume that stream with its own local mirror and vertical-fetch state, without
mutating `cart.Mirror` or replacing the known-good renderer.
