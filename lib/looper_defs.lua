local defs = {}

-- ---------- grid layout ----------

defs.DRYWET_COL = 1
defs.OVERDUB_COL = 2
defs.TAPE_WARBLE_COL = 3
defs.FILTER_COL = 4
defs.STP_SPEED_COL = 5
defs.DROPPER_COL = 6
defs.JUMP_COL = 7

defs.ADDITIVE_KEY = {{16, 4}}

defs.LEFT_RING_TOPRIGHT  = {8, 3}
defs.RIGHT_RING_TOPRIGHT = {10, 1}

defs.LOOPER1_SELECT_KEY = {{9, 4}, {9, 5}, {9, 6}, {9, 7}, 
                           {10, 6}, {10, 7}, {11, 7}, {12, 7}}
defs.LOOPER2_SELECT_KEY = {{11, 2}, {12, 2}, {13, 2}, {13, 3}, 
                           {14, 2}, {14, 3}, {14, 4}, {14, 5}}
defs.LINK_PLAYHEADS_KEY = {{11, 4},{11, 5}, {12, 4},{12, 5}}
defs.SEND_1_TO_2_KEY = {{8, 1}, {8, 2}, {8, 3}, {9, 1}, {9, 2}, {10, 1}}
defs.SEND_2_TO_1_KEY = {{13, 8}, {14, 8}, {14, 7}, {15, 8}, {15, 7}, {15, 6}}

defs.REVERSE_KEY = {{16, 7}}
defs.SHORT_RATE_SLEW_KEY = {16,6}
defs.LONG_RATE_SLEW_KEY = {16,5}
defs.REC_KEY = {16,8}
defs.SHIFT_KEY = {16, 2}
defs.CLEAR_KEY = {16,1}

-- ---------- loop constants ----------

defs.FADE = 0.05
defs.MAX_LEN = 60.0
defs.MIN_LEN = 0.01
defs.PHASE_STEPS = 64

-- ---------- value maps ----------

defs.DRYWET_VALUES = {
  [1] = 1.0,
  [2] = 6/7,
  [3] = 5/7,
  [4] = 0.5,
  [5] = 0.5,
  [6] = 2/7,
  [7] = 1/7,
  [8] = 0.0
}

defs.OVERDUB_VALUES = {
  [1] = 1.0,
  [2] = 6/7,
  [3] = 5/7,
  [4] = 4/7,
  [5] = 3/7,
  [6] = 2/7,
  [7] = 1/7,
  [8] = 0.0
}

defs.TAPE_WARBLE_VALUES = {
  [1] = 1.0,
  [2] = 6/7,
  [3] = 5/7,
  [4] = 4/7,
  [5] = 3/7,
  [6] = 2/7,
  [7] = 1/7,
  [8] = 0.0
}

defs.FILTER_VALUES = {
  [1] = 0.75,
  [2] = 0.5,
  [3] = 0.25,
  [4] = 0.0,
  [5] = 0.0,
  [6] = -0.25,
  [7] = -0.5,
  [8] = -0.75
}

defs.STP_SPEED_VALUES = {
  [1] = 4.0,
  [2] = 2.0,
  [3] = 1.5,
  [4] = 1.0,
  [5] = 1.0,
  [6] = 0.75,
  [7] = 0.5,
  [8] = 0.25
}

defs.DROPPER_VALUES = {
  [1] = 1.0,
  [2] = 6/7,
  [3] = 5/7,
  [4] = 4/7,
  [5] = 3/7,
  [6] = 2/7,
  [7] = 1/7,
  [8] = 0.0
}

defs.JUMP_VALUES = {
  [1] = 32,
  [2] = 16,
  [3] = 8,
  [4] = 6,
  [5] = 4,
  [6] = 3,
  [7] = 2,
  [8] = 0
}

-- ---------- ring geometry ----------

defs.TAPEHEAD_RING_PTS = {
  {1,3}, {1,2}, {2,1}, {3,1}, {4,1}, {5,1}, {6,2}, {6,3},
  {6,4}, {6,5}, {5,6}, {4,6}, {3,6}, {2,6}, {1,5}, {1,4}
}

defs.TAPEHEAD_RING_LED_OFFSETS = {
  2, 1, 1, 0, 0, -1, -1, -2,
  -2, -1, -1, 0, 0, 1, 1, 2
}

return defs