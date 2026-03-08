local defs = include("lib/looper_defs")
local looper_engine = include("lib/looper_engine")
local looper_ui = include("lib/looper_ui")

local g
local a
local viz_metro

local arc_page = 1
local ARC_PAGE_MAX = 3

local loopers = {
  looper_engine.new_looper(1, 1, 2, 1),
  looper_engine.new_looper(2, 3, 4, 2),
}

local link_playheads = false

local send_1_to_2 = 0.0
local send_2_to_1 = 0.0
local send_1_to_2_enabled = false
local send_2_to_1_enabled = false


-- -------- helper functions --------

local function redraw_all()
  looper_ui.redraw(
    loopers, g, a, link_playheads,
    send_1_to_2, send_2_to_1,
    send_1_to_2_enabled, send_2_to_1_enabled,
    arc_page
  )

  looper_ui.grid_redraw(
    g, loopers, link_playheads,
    send_1_to_2, send_2_to_1,
    send_1_to_2_enabled, send_2_to_1_enabled,
    shift_held
  )

  looper_ui.arc_redraw(a, loopers, arc_page, send_1_to_2, send_2_to_1)
end

local function active_looper()
  return loopers[1]
end

local function refresh_routing()
  looper_engine.update_all_routing(
    loopers,
    send_1_to_2,
    send_2_to_1,
    send_1_to_2_enabled,
    send_2_to_1_enabled
  )
end

local function reset_all()
  for _, L in ipairs(loopers) do
    looper_engine.reset_looper(L)
    L.selected = false
  end

  loopers[1].selected = true

  link_playheads = false
  shift_held = false

  send_1_to_2 = 0.0
  send_2_to_1 = 0.0
  send_1_to_2_enabled = false
  send_2_to_1_enabled = false

  refresh_routing()
  redraw_all()
end

function key(n, z)
  if z ~= 1 then return end

  if n == 2 then
    looper_engine.for_each_selected(loopers, function(L)
      looper_engine.toggle(L)
    end)
    redraw_all()
  elseif n == 3 then
    looper_engine.for_each_selected(loopers, function(L)
      looper_engine.clear_loop(L)
    end)
    redraw_all()
  end
end

function enc(n, d)
  if n == 1 then
    local delta = d * 0.01

    if send_1_to_2_enabled then
      send_1_to_2 = util.clamp(send_1_to_2 + delta, 0.0, 1.0)
    end

    if send_2_to_1_enabled then
      send_2_to_1 = util.clamp(send_2_to_1 + delta, 0.0, 1.0)
    end

    refresh_routing()
    redraw_all()
    return
  end
  if n == 2 then
    looper_engine.for_each_selected(loopers, function(L)
      looper_engine.set_drywet(L, L.drywet + d * 0.01)
    end)
    redraw_all()
  elseif n == 3 then
    looper_engine.for_each_selected(loopers, function(L)
      local old_rate = L.rate
      L.rate = util.clamp(L.rate + d * 0.01, -2.0, 2.0)
      if old_rate * L.rate < 0 then
        L.is_reversed = not L.is_reversed
      end
      looper_engine.apply_rate(L)
    end)
    redraw_all()
  end
end

local function handle_ring_key(L, ring_idx, z)
  if z == 1 then
    L.held_ring_points[ring_idx] = true
    local n = looper_engine.count_held_ring_points(L)

    if n == 2 then
      L.ring_crop_happened = true
      looper_engine.update_ring_loop_cut(L)
    end
  else
    local n_before_release = looper_engine.count_held_ring_points(L)

    if n_before_release == 1 and L.held_ring_points[ring_idx] and not L.ring_crop_happened then
      looper_engine.clear_crop(L)
      looper_engine.set_playhead_from_ring_idx(L, ring_idx)
    end

    L.held_ring_points[ring_idx] = nil

    if looper_engine.count_held_ring_points(L) == 0 then
      L.ring_crop_happened = false
    end
  end
end

local function sync_linked_playheads()
  if not link_playheads then return end
  if #loopers < 2 then return end

  local L1 = loopers[1]
  local L2 = loopers[2]

  if not L1.has_loop or not L2.has_loop then return end
  if L1.is_recording or L2.is_recording then return end

  local len1 = math.max(L1.loop_end - L1.loop_start, 0.0001)
  local len2 = math.max(L2.loop_end - L2.loop_start, 0.0001)

  local p = (L1.play_pos - L1.loop_start) / len1
  p = util.clamp(p, 0.0, 1.0)

  local pos2 = L2.loop_start + p * len2

  softcut.position(L2.play_voice, pos2)
  softcut.position(L2.write_voice, pos2)
  L2.play_pos = pos2
end

--------------------------------------------
-- GRID
--------------------------------------------

local function grid_key(x, y, z)
  local L = active_looper()

  if x == defs.DRYWET_COL and z == 1 then
    local val = defs.DRYWET_VALUES[y]
    if val ~= nil then
      looper_engine.for_each_selected(loopers, function(LL)
        looper_engine.set_drywet(LL, val)
      end)
      redraw_all()
    end
    return
  end

    if x == defs.OVERDUB_COL and z == 1 then
    local val = defs.OVERDUB_VALUES[y]
    if val ~= nil then
      looper_engine.for_each_selected(loopers, function(LL)
        looper_engine.set_overdub(LL, val)
      end)
      refresh_routing()
      redraw_all()
    end
    return
  end

  if x == defs.TAPE_WARBLE_COL and z == 1 then
    local val = defs.TAPE_WARBLE_VALUES[y]
    if val ~= nil then
      looper_engine.for_each_selected(loopers, function(LL)
        looper_engine.set_tape_age(LL, val)
        looper_engine.apply_rate(LL)
      end)
      redraw_all()
    end
    return
  end

  if x == defs.FILTER_COL and z == 1 then
    local val = defs.FILTER_VALUES[y]
    if val ~= nil then
      looper_engine.for_each_selected(loopers, function(LL)
        looper_engine.set_dj_filter_freq(LL, val)
      end)
      redraw_all()
    end
    return
  end

  if x == defs.STP_SPEED_COL and z == 1 then
    local val = defs.STP_SPEED_VALUES[y]
    if val ~= nil then
      looper_engine.for_each_selected(loopers, function(LL)
        LL.rate = val
        looper_engine.apply_rate(LL)
      end)
      redraw_all()
    end
    return
  end
  
  if x == defs.DROPPER_COL and z == 1 then
    local val = defs.DROPPER_VALUES[y]
    if val ~= nil then
      looper_engine.for_each_selected(loopers, function(LL)
        looper_engine.set_dropper_amt(LL, val)
      end)
      redraw_all()
    end
    return
  end
  
  if x == defs.JUMP_COL and z == 1 then
    local val = defs.JUMP_VALUES[y]
    if val ~= nil then
      looper_engine.for_each_selected(loopers, function(LL)
        looper_engine.set_jump_div(LL, val)
      end)
      redraw_all()
    end
    return
  end
  
  local left_ring_idx = looper_ui.grid_ring_hit(
    x, y,
    defs.LEFT_RING_TOPRIGHT[1], defs.LEFT_RING_TOPRIGHT[2]
  )

  if left_ring_idx ~= nil then
    handle_ring_key(loopers[1], left_ring_idx, z)
    redraw_all()
    return
  end

  local right_ring_idx = looper_ui.grid_ring_hit(
    x, y,
    defs.RIGHT_RING_TOPRIGHT[1], defs.RIGHT_RING_TOPRIGHT[2]
  )

  if right_ring_idx ~= nil then
    handle_ring_key(loopers[2], right_ring_idx, z)
    redraw_all()
    return
  end
  
  if looper_ui.grid_match_any(x, y, defs.LOOPER1_SELECT_KEY) and z == 1 then
    if shift_held then
      looper_engine.select_exclusive(loopers, 1)
    else
      looper_engine.toggle_selected(loopers[1])
    end
    redraw_all()
    return
  end

  if looper_ui.grid_match_any(x, y, defs.LOOPER2_SELECT_KEY) and z == 1 then
    if shift_held then
      looper_engine.select_exclusive(loopers, 2)
    else
      looper_engine.toggle_selected(loopers[2])
    end
    redraw_all()
    return
  end
  
  if looper_ui.grid_match_any(x, y, defs.LINK_PLAYHEADS_KEY) and z == 1 then
    link_playheads = not link_playheads
    sync_linked_playheads()
    redraw_all()
    return
  end
  
  if looper_ui.grid_match_any(x, y, defs.SEND_1_TO_2_KEY) and z == 1 then
    send_1_to_2_enabled = not send_1_to_2_enabled
    refresh_routing()
    redraw_all()
    return
  end
  
  if looper_ui.grid_match_any(x, y, defs.SEND_2_TO_1_KEY) and z == 1 then
    send_2_to_1_enabled = not send_2_to_1_enabled
    refresh_routing()
    redraw_all()
    return
  end

  if looper_ui.grid_match_any(x, y, defs.ADDITIVE_KEY) and z == 1 then
    looper_engine.for_each_selected(loopers, function(LL)
      looper_engine.toggle_additive_mode(LL)
    end)
    refresh_routing()
    redraw_all()
    return
  end

  if looper_ui.grid_match_any(x, y, defs.REVERSE_KEY) and z == 1 then
    looper_engine.for_each_selected(loopers, function(LL)
      LL.is_reversed = not LL.is_reversed
      looper_engine.apply_rate(LL)
    end)
    redraw_all()
    return
  end

  if x == defs.SHORT_RATE_SLEW_KEY[1] and y == defs.SHORT_RATE_SLEW_KEY[2] and z == 1 then
    looper_engine.for_each_selected(loopers, function(LL)
      LL.short_rate_slew = not LL.short_rate_slew
      LL.long_rate_slew = false
      looper_engine.apply_rate_slew(LL)
    end)
    redraw_all()
    return
  end

  if x == defs.LONG_RATE_SLEW_KEY[1] and y == defs.LONG_RATE_SLEW_KEY[2] and z == 1 then
    looper_engine.for_each_selected(loopers, function(LL)
      LL.short_rate_slew = false
      LL.long_rate_slew = not LL.long_rate_slew
      looper_engine.apply_rate_slew(LL)
    end)
    redraw_all()
    return
  end

  if x == defs.REC_KEY[1] and y == defs.REC_KEY[2] and z == 1 then
    looper_engine.for_each_selected(loopers, function(LL)
      looper_engine.toggle(LL)
    end)
    refresh_routing()
    redraw_all()
    return
  end
  
  if x == defs.SHIFT_KEY[1] and y == defs.SHIFT_KEY[2] then
    shift_held = (z == 1)
    redraw_all()
    return
  end

  if x == defs.CLEAR_KEY[1] and y == defs.CLEAR_KEY[2] and z == 1 then
    if shift_held then
      reset_all()
    else
      looper_engine.for_each_selected(loopers, function(LL)
        looper_engine.clear_loop(LL)
      end)
      refresh_routing()
      redraw_all()
    end
    return
  end
end

--------------------------------------------
-- ARC
--------------------------------------------

local function arc_key(n, z)
  if z ~= 1 then return end
  arc_page = (arc_page % ARC_PAGE_MAX) + 1
  redraw_all()
end

local function arc_delta(n, d)
  if arc_page == 1 then
    if n == 1 then
      local L = loopers[1]
      looper_engine.move_crop(L, d / (64 * 4))
      if link_playheads then
        sync_linked_playheads()
      end

    elseif n == 2 then
      local L = loopers[1]
      local frac = looper_engine.get_crop_fraction(L)
      frac = frac + d * 0.004
      looper_engine.set_crop_fraction(L, frac)
      if link_playheads then
        sync_linked_playheads()
      end

    elseif n == 3 then
      local L = loopers[2]
      looper_engine.move_crop(L, d / (64 * 4))

    elseif n == 4 then
      local L = loopers[2]
      local frac = looper_engine.get_crop_fraction(L)
      frac = frac + d * 0.004
      looper_engine.set_crop_fraction(L, frac)
    end

  elseif arc_page == 2 then
    if n == 1 then
      local L = loopers[1]
      L.rate = util.clamp(L.rate + d * 0.01, -4.0, 4.0)

      if math.abs(L.rate) < 0.001 then
        L.rate = 0.001
      end

      L.is_reversed = (L.rate < 0)
      looper_engine.apply_rate(L)

    elseif n == 2 then
      local L = loopers[2]
      L.rate = util.clamp(L.rate + d * 0.01, -4.0, 4.0)

      if math.abs(L.rate) < 0.001 then
        L.rate = 0.001
      end

      L.is_reversed = (L.rate < 0)
      looper_engine.apply_rate(L)

    elseif n == 3 then
      send_1_to_2 = util.clamp(send_1_to_2 + d * 0.0005, 0.0, 1.0)
      refresh_routing()

    elseif n == 4 then
      send_2_to_1 = util.clamp(send_2_to_1 + d * 0.0005, 0.0, 1.0)
      refresh_routing()
    end

  elseif arc_page == 3 then
    if n == 1 then
      looper_engine.set_dj_filter_freq(loopers[1], loopers[1].dj_filter_freq + d * 0.001)
    elseif n == 2 then
      looper_engine.set_dj_filter_rq(loopers[1], loopers[1].dj_filter_res - d * 0.001)
    elseif n == 3 then
      looper_engine.set_dj_filter_freq(loopers[2], loopers[2].dj_filter_freq + d * 0.001)
    elseif n == 4 then
      looper_engine.set_dj_filter_rq(loopers[2], loopers[2].dj_filter_res - d * 0.001)
    end
  end

  redraw_all()
end

--------------------------------------------
-- INIT, REDRAW, CLEANUP
--------------------------------------------

function init()
  looper_engine.setup_softcut(loopers)

  softcut.event_phase(function(i, pos)
    looper_engine.phase_cb(loopers, i, pos)
  end)
  softcut.poll_start_phase()

  viz_metro = metro.init()
  viz_metro.time = 1/30
  viz_metro.event = function()
    for _, L in ipairs(loopers) do
      looper_engine.apply_tape_warble(L, viz_metro.time)
      looper_engine.apply_dropper(L, viz_metro.time)
      looper_engine.enforce_wrapped_crop(L)
      looper_engine.apply_jump(L)
    end
    sync_linked_playheads()
    redraw_all()
  end
  viz_metro:start()

  g = grid.connect()
  if g and g.device then
    g.key = grid_key
  end

  a = arc.connect()
  if a and a.device then
    a.delta = arc_delta
    a.key = arc_key
  end

  redraw_all()
end

function redraw()
  looper_ui.redraw(
    loopers, g, a, link_playheads,
    send_1_to_2, send_2_to_1,
    send_1_to_2_enabled, send_2_to_1_enabled,
    arc_page
  )
end

function cleanup()
  for _, L in ipairs(loopers) do
    softcut.rec(L.play_voice, 0)
    softcut.rec(L.write_voice, 0)

    softcut.rec_level(L.play_voice, 0.0)
    softcut.rec_level(L.write_voice, 0.0)

    softcut.pre_level(L.play_voice, 1.0)
    softcut.pre_level(L.write_voice, 1.0)

    softcut.play(L.play_voice, 0)
    softcut.play(L.write_voice, 0)

    softcut.level_cut_cut(L.play_voice, L.write_voice, 0.0)
    softcut.level(L.write_voice, 0.0)
  end

  audio.comp_off()

  if g and g.device then
    g.key = nil
    g:all(0)
    g:refresh()
  end
  g = nil

  if a and a.device then
    a:all(0)
    a:refresh()
  end
  a = nil
end