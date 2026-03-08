# Bliss

A two-looper script for norns with grid + arc control.

## Requirements

- norns
- monome grid
- monome arc

## Features

- 2 independent loopers
- per-looper selection / arming
- linked playheads
- cross-sends between loopers
- loop cropping from grid and arc
- tape warble
- dropper
- random jump slicing
- additive overdub mode
- filter + resonance control
- arc pages for transport, speed/sends, and filter

## Files

- `bliss.lua` — main script
- `lib/looper_defs.lua` — constants and layout
- `lib/looper_engine.lua` — looper logic / softcut behavior
- `lib/looper_ui.lua` — grid / screen / arc drawing

## Current control idea

### Grid
- columns 1–7: main looper parameters
- ring areas:
  - left = looper 1
  - right = looper 2
- looper select buttons
- record / clear / shift / routing buttons

### Arc
- page 1: playhead + crop
- page 2: smooth speed + cross-send amounts
- page 3: filter + resonance
- arc button switches pages

## Notes

This is still an evolving script and the control scheme may change.

## TODO

- improve documentation
- clean up code further
- maybe add more arc pages / modifiers
- maybe add better visual feedback for some states