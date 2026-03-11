# bliss

**bliss** is a two-looper instrument for **norns + grid + arc**.

It takes inspiration from the Chase Bliss Blooper and Instruō Lubadh, but it is not a straight clone. The idea is to treat two loopers as a small coupled ecosystem: you can record into either one, crop them from grid or arc, alter their speed and direction, add tape-style instability, inject random jumps, overdub additively, send one into the other, store snapshots, and capture motion over one loop.

The script is designed to feel like an instrument rather than a list of parameters: fast access, a clear visual identity, a thought-out set of gestures that combine well and, importantly, no menu diving. I didn't even include editable parameters in norns's parameters menu. The aim is to combine the immediacy of a guitar pedal with the flexibility of norns/grid/arc. This is really made with grid in mind, although you should be able to have fun with just norns too. Arc offers easy access to a bunch of parameters that do improve the experience, but is not essential.

## Requirements

- norns
- monome grid (128) - recommended
- monome arc - cool addition

## Main features

- 2 independent loopers
- per-looper or dual selection
- recording / overdubbing / additive overdub
- ring-based crop and playhead control on grid and arc
- linked playheads
- cross-sends between loopers
- stepped and free speed control
- reverse
- 3-stage rate slew
- tape warble
- dropper
- random jump / shuffle
- DJ-style filter + resonance
- 2 performance snapshots
- per-looper motion capture over one loop
- custom grid, arc, and norns screen UI

## Files

- `bliss.lua` — main script
- `lib/looper_defs.lua` — layout / constants / value maps
- `lib/looper_engine.lua` — looper logic / softcut behavior
- `lib/looper_ui.lua` — grid / screen / arc drawing

## Quick start

1. Connect **grid** and **arc**.
2. Launch `bliss` on norns.
3. Press **K2** to record the selected looper(s). Press again to stop recording / start overdub; press again to stop overdub.
4. Use the ring areas on grid or page 1 on arc to move the playhead and crop the loop.
5. Shape the selected looper(s) from the grid columns.
6. Add speed, sends, or filtering from arc pages 2 and 3.

## Core concept

There are always **two loopers**.

Most parameter changes apply to the **selected looper(s)**. You can select one looper, the other, or both. Once selected, a looper can be recorded, cropped, overdubbed, reversed, fed into the other looper, or animated with motion capture.

## Norns controls

### Keys

- **K2 tap**: record / stop / overdub on selected looper(s)
- **K3 tap**: clear selected looper(s)
- **K1 + K2**: toggle selection of looper 1
- **K1 + K3**: toggle selection of looper 2
- **K2 + K3**: toggle additive mode on selected looper(s) if **K3** is the second key pressed; start motion recording on selected looper(s) if **K2** is the second key pressed
- **K1 + K2 + K3**: reset everything

### Encoders

Without key holds:
- **E1**: dry / wet
- **E2**: move playhead in looper 1
- **E3**: move playhead in looper 2

With held keys:
- **hold K1 + E1**: overdub amount
- **hold K2 + E1**: tape amount
- **hold K3 + E1**: dropper amount

- **hold K1 + E2**: crop length looper 1
- **hold K2 + E2**: stepped speed looper 1
- **hold K3 + E2**: free speed looper 1

- **hold K1 + E3**: crop length looper 2
- **hold K2 + E3**: stepped speed looper 2
- **hold K3 + E3**: free speed looper 2

## Grid manual

### Columns 1–7

These operate on the **selected looper(s)**.

- **col 1**: dry / wet
- **col 2**: overdub amount
- **col 3**: tape warble
- **col 4**: filter frequency
- **col 5**: stepped speed
- **col 6**: dropper amount
- **col 7**: jump / shuffle
  - lower half = jump trigger density
  - upper half = jump target division

### Ring areas

- **left ring** = looper 1
- **right ring** = looper 2

Gestures:
- **single press on ring**: set playhead there and clear crop
- **hold 2 ring points**: define crop between them
- release both to keep the crop

### Looper selection

- press inside the **left loop shape** to select / deselect looper 1
- press inside the **right loop shape** to select / deselect looper 2
- hold **shift** while pressing a loop shape for exclusive selection

### Link / sends / motion

- overlap area between the rings: toggle **linked playheads**
- upper-left send path: toggle **send 1 -> 2**
- lower-right send path: toggle **send 2 -> 1**
- **(8,8)**: motion capture for looper 1
- **(15,1)**: motion capture for looper 2

Linked playhead is also show as an infinity sign on the top right of norns's screen.
Send direction is shown there using arrows.
Motion capture is represented by two dots (one per looper).

### Utility column 16

- **16,8**: record / stop / overdub selected looper(s)
- **16,7**: reverse
- **16,6**: rate slew cycle (`off -> short -> long -> off`)
- **16,5**: additive mode
- **16,4**: snapshot button
- **16,3**: mod shift
- **16,2**: shift
- **16,1**: clear

### Clear / shift actions

- **clear**: clear selected looper(s) and clear their motion capture
- **shift + clear**: full reset
- **mod shift + clear**: clear modifiers

### Snapshots

Snapshot save everything except the audio (modifiers, loop location, crops, additive mode toggle, sends, etc). There are two slots which can be instantly stored and recalled.

Gestures are intentionally strict (i.e. order matters!):

- **snapshot -> mod shift**: slot 1 store / recall
- **snapshot -> shift**: slot 2 store / recall
- **snapshot -> rec -> mod shift**: overwrite slot 1
- **snapshot -> rec -> shift**: overwrite slot 2
- **snapshot -> clear -> mod shift**: delete slot 1
- **snapshot -> clear -> shift**: delete slot 2

Again: order matters: **press snapshot first**.

### Motion capture

Each looper has its own motion recorder. Over the course of one loop, you can record any parameter changes you like (including modifiers, loop location, crops, additive mode toggle, sends, etc). The way it works is that parameters are saved at the corresponding phase of the loop where they were entered. That means that, if you set speed x2 half way through the loop, then the second half with play 2x faster, shortening the total length in absolute time. This is the intended behaviour, and can lead to some pretty wild results depending on what you try. There is one motion capture lane per looper.

- *motion capture key*: start recording a new one-loop motion pass
- *press again while recording*: stop early and start playback
- *after one full loop*, recording stops automatically and playback begins
- *press again during playback* to record a new pass
- *mod shift -> motion capture*: pause / resume playback
- *shift -> motion capture*: clear motion capture

Motion capture status is visible on norns; recording, playback, and stored-but-stopped states are shown as dots at different brightness levels in the top right of the screen.

## Arc manual

Press the **arc button** to cycle pages.

### Page 1 — crop / window

- **ring 1**: move playhead looper 1
- **ring 2**: crop length looper 1
- **ring 3**: move playhead looper 2
- **ring 4**: crop length looper 2

### Page 2 — speed / sends

- **ring 1**: free speed looper 1 (octaves are shown as bright lights, and fifths as dimmer lights; there are virtual notches at these locations and the lights slightly increase to help you find these musical intervals)
- **ring 2**: free speed looper 2 (same octaves/fifths shenanigans as above)
- **ring 3**: send 1 -> 2 amount
- **ring 4**: send 2 -> 1 amount

### Page 3 — filter

- **ring 1**: filter frequency looper 1
- **ring 2**: filter resonance looper 1
- **ring 3**: filter frequency looper 2
- **ring 4**: filter resonance looper 2

## Screen / UI notes

The norns screen shows:

- the two interlocking loop circles
- playheads and crops
- selected loopers with doubled rings
- additive mode with a small `+` in the corresponding circle
- a compact status stack in the top-right:
  - `∞` = linked playheads
  - `<->` = sends
  - `• •` = motion state for looper 1 / 2

The grid mirrors the same logic in a more performance-oriented way.

## Tips

- Start simple: record one loop in each looper, then explore crop and speed.
- Linked playheads is great for synced loops, and will keep looper 2 phase-locked to looper 1.
- Additive mode combined with overdub increases the intensity of applied modifiers on each loop pass. For example, if you are speeding up the loop, it get sped up again at every pass.

## Status

This is still an evolving project. Comments are welcome, and small layout and behavior details may continue to change.