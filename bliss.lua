-- bliss
--
-- two entertwined loopers
--
--    make them evolve 
--    make the collide.
-- 
-- version: 0.1.0
--
-- author: Adrien Doerig @irbis

-- -------------------------------------------------------------------------
-- LOCAL LIBRARIES
-- -------------------------------------------------------------------------

local defs = include("lib/looper_defs")
local looper_engine = include("lib/looper_engine")
local looper_ui = include("lib/looper_ui")

-- -------------------------------------------------------------------------
-- STATE
-- -------------------------------------------------------------------------

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

local send_1_to_2 = 0.33 -- default is quite high
local send_2_to_1 = 0.33 -- default is quite high
local send_1_to_2_enabled = false
local send_2_to_1_enabled = false

local snapshot_1 = nil
local snapshot_2 = nil
local snapshot_mode_delete = false
local snapshot_mode_overwrite = false
local snapshot_key_held = false
local snapshot_flash_kind = nil
local snapshot_flash_token = 0

local shift_held = false
local mod_shift_held = false

local k1_held = false
local k2_held = false
local k3_held = false

local k1_consumed = false
local k2_consumed = false
local k3_consumed = false

local k1_down_time = nil
local k2_down_time = nil
local k3_down_time = nil

local KEY_INFO_DELAY = 0.5

local trigger_snapshot_flash
local refresh_routing
local restore_performance_state

-- -------------------------------------------------------------------------
-- CLOCKING
-- -------------------------------------------------------------------------

local CLOCK_MODE_FREE = 1
local CLOCK_MODE_BEAT = 2
local CLOCK_MODE_BAR = 3
local CLOCK_MODE_N_BARS = 4

local clock_mode = CLOCK_MODE_FREE
local clock_bar_beats = 4
local clock_n_bars = 4
local clock_ignore_transport = false
local clock_transport_running = true
local clock_ui_beat_phase = 0.0
local clock_ui_is_downbeat = false
local last_clock_beat = nil
local clock_tick_task = nil
local pending_selected_resync = false

-- -------------------------------------------------------------------------
-- HELPERS
-- -------------------------------------------------------------------------

local function long_hold_shown(down_time)
  return down_time ~= nil and (util.time() - down_time >= KEY_INFO_DELAY)
end

local function redraw_all()
  redraw()

  looper_ui.grid_redraw(
    g, loopers, link_playheads,
    send_1_to_2, send_2_to_1,
    send_1_to_2_enabled, send_2_to_1_enabled,
    shift_held, mod_shift_held,
    snapshot_1 ~= nil, snapshot_2 ~= nil,
    snapshot_flash_kind,
    clock_mode, clock_ui_beat_phase, clock_ui_is_downbeat
  )

  looper_ui.arc_redraw(a, loopers, arc_page, send_1_to_2, send_2_to_1)
end

-- -------------------------------------------------------------------------
-- CLOCK HELPERS
-- -------------------------------------------------------------------------

local function is_clocked_mode()
  return clock_mode ~= CLOCK_MODE_FREE
end

local function current_quantum_beats()
  if clock_mode == CLOCK_MODE_BEAT then
    return 1
  elseif clock_mode == CLOCK_MODE_BAR or clock_mode == CLOCK_MODE_N_BARS then
    return clock_bar_beats
  end
  return nil
end

local function mode_label()
  if clock_mode == CLOCK_MODE_BEAT then
    return "BEAT"
  elseif clock_mode == CLOCK_MODE_BAR then
    return "BAR"
  elseif clock_mode == CLOCK_MODE_N_BARS then
    return tostring(clock_n_bars) .. " BARS"
  end
  return nil
end

local function handle_clock_tick()
  for _, L in ipairs(loopers) do
    if clock_transport_running and not L.clock_paused then
      if L.is_recording then
        L.clock_record_ticks = L.clock_record_ticks + 1

        if clock_mode == CLOCK_MODE_N_BARS then
          local target = clock_n_bars * clock_bar_beats
          if L.clock_record_ticks >= target then
            stop_record_now(L)
          end
        end
      elseif L.has_loop and L.clock_loop_ticks and not L.is_overdubbing then
        L.clock_play_ticks = L.clock_play_ticks + 1
        if L.clock_play_ticks >= L.clock_loop_ticks then
          looper_engine.reset_to_cycle_start(L)
          L.clock_play_ticks = 0
        end
      elseif L.has_loop and L.clock_loop_ticks and L.is_overdubbing then
        L.clock_play_ticks = L.clock_play_ticks + 1
        if L.clock_play_ticks >= L.clock_loop_ticks then
          looper_engine.reset_to_cycle_start(L)
          L.clock_play_ticks = 0
        end
      end
    end
  end
end

local function start_clock_tick_task()
  if clock_tick_task then
    clock.cancel(clock_tick_task)
  end

  clock_tick_task = clock.run(function()
    while true do
      clock.sync(1)
      handle_clock_tick()
    end
  end)
end

local function start_record_now(L)
  looper_engine.start_recording(L)
  L.clock_record_ticks = 0
  L.clock_play_ticks = 0
end

local function stop_record_now(L)
  if clock_mode == CLOCK_MODE_N_BARS then
    L.clock_loop_ticks = clock_n_bars * clock_bar_beats
  else
    L.clock_loop_ticks = math.max(L.clock_record_ticks, 1)
  end

  looper_engine.stop_recording_and_play_clocked(L, L.clock_loop_ticks)
  L.clock_play_ticks = 0
end

local function toggle_clocked_record(L)
  local quantum = current_quantum_beats()
  if quantum == nil then
    looper_engine.toggle(L)
    return
  end

  if not L.is_recording and not L.has_loop then
    if L.clock_record_task then clock.cancel(L.clock_record_task) end
    L.clock_pending_start = true
    L.clock_pending_stop = false
    L.clock_pending_stop_at_bar = false

    L.clock_record_task = clock.run(function()
      clock.sync(quantum)
      L.clock_pending_start = false
      start_record_now(L)
      redraw_all()
    end)
    redraw_all()
    return
  end

  if L.is_recording then
    if clock_mode == CLOCK_MODE_N_BARS then
      L.clock_pending_stop_at_bar = true
      if L.clock_record_task then clock.cancel(L.clock_record_task) end
      L.clock_record_task = clock.run(function()
        clock.sync(clock_bar_beats)
        L.clock_pending_stop_at_bar = false
        if L.is_recording then
          stop_record_now(L)
        end
        redraw_all()
      end)
    else
      L.clock_pending_stop = true
      if L.clock_record_task then clock.cancel(L.clock_record_task) end
      L.clock_record_task = clock.run(function()
        clock.sync(quantum)
        L.clock_pending_stop = false
        if L.is_recording then
          stop_record_now(L)
        end
        redraw_all()
      end)
    end
    redraw_all()
    return
  end

  if L.has_loop and not L.is_overdubbing then
    looper_engine.start_overdub(L)
  elseif L.is_overdubbing then
    looper_engine.stop_overdub(L)
  end
end

local function resync_quantum()
  if clock_mode == CLOCK_MODE_BAR or clock_mode == CLOCK_MODE_N_BARS then
    return clock_bar_beats
  end
  return 1
end

local function execute_selected_resync()
  pending_selected_resync = false
  for _, L in ipairs(loopers) do
    if L.selected and L.has_loop and not L.is_recording then
      looper_engine.reset_to_cycle_start(L)
      if L.clock_play_ticks ~= nil then
        L.clock_play_ticks = 0
      end
    end
  end
  redraw_all()
end

local function queue_selected_resync()
  if pending_selected_resync then
    return
  end
  pending_selected_resync = true

  clock.run(function()
    clock.sync(resync_quantum())
    if pending_selected_resync then
      execute_selected_resync()
    end
  end)

  redraw_all()
end

local function update_clock_param_visibility()
  params:hide("bliss_bar_beats")
  params:hide("bliss_n_bars")
  params:hide("bliss_ignore_transport")

  if clock_mode == CLOCK_MODE_BEAT then
    params:show("bliss_ignore_transport")
  elseif clock_mode == CLOCK_MODE_BAR then
    params:show("bliss_bar_beats")
    params:show("bliss_ignore_transport")
  elseif clock_mode == CLOCK_MODE_N_BARS then
    params:show("bliss_bar_beats")
    params:show("bliss_n_bars")
    params:show("bliss_ignore_transport")
  end

  _menu.rebuild_params()
end

-- -------------------------------------------------------------------------
-- PERFORMANCE STATE / SNAPSHOTS
-- -------------------------------------------------------------------------

local function capture_looper_state(L)
  return {
    selected = L.selected,

    has_loop = L.has_loop,
    is_overdubbing = L.is_overdubbing,

    drywet = L.drywet,
    dry_level = L.dry_level,
    wet_level = L.wet_level,

    additive_mode = L.additive_mode,
    overdub = L.overdub,

    rate = L.rate,
    rate_slew_mode = L.rate_slew_mode or 0,
    is_reversed = L.is_reversed,

    dropper_amt = L.dropper_amt,
    dropper_gain = L.dropper_gain,
    dropper_target_gain = L.dropper_target_gain,
    dropper_timer = L.dropper_timer,

    tape_age = L.tape_age,

    dj_filter_freq = L.dj_filter_freq,
    dj_filter_res = L.dj_filter_res,

    jump_div = L.jump_div,
    jump_trigger_div = L.jump_trigger_div,
    last_jump_step = L.last_jump_step,

    loop_start = L.loop_start,
    loop_end = L.loop_end,
    full_loop_start = L.full_loop_start,
    full_loop_end = L.full_loop_end,
    play_pos = L.play_pos,

    crop_start = L.crop_start,
    crop_len = L.crop_len,
    crop_wraps = L.crop_wraps,
  }
end

local function capture_performance_state()
  return {
    loopers = {
      capture_looper_state(loopers[1]),
      capture_looper_state(loopers[2]),
    },

    link_playheads = link_playheads,

    send_1_to_2 = send_1_to_2,
    send_2_to_1 = send_2_to_1,
    send_1_to_2_enabled = send_1_to_2_enabled,
    send_2_to_1_enabled = send_2_to_1_enabled,
  }
end

local function restore_looper_state(L, s)
  L.selected = s.selected

  L.has_loop = s.has_loop
  L.is_overdubbing = s.is_overdubbing

  L.drywet = s.drywet
  L.dry_level = s.dry_level
  L.wet_level = s.wet_level

  L.additive_mode = s.additive_mode
  L.overdub = s.overdub

  L.rate = s.rate
  L.rate_slew_mode = s.rate_slew_mode or 0
  L.is_reversed = s.is_reversed

  L.dropper_amt = s.dropper_amt
  L.dropper_gain = s.dropper_gain or 1.0
  L.dropper_target_gain = s.dropper_target_gain or 1.0
  L.dropper_timer = s.dropper_timer or 0.0

  L.tape_age = s.tape_age

  L.dj_filter_freq = s.dj_filter_freq
  L.dj_filter_res = s.dj_filter_res

  L.jump_div = s.jump_div
  L.jump_trigger_div = s.jump_trigger_div
  L.last_jump_step = s.last_jump_step

  L.full_loop_start = s.full_loop_start
  L.full_loop_end = s.full_loop_end
  L.crop_start = s.crop_start
  L.crop_len = s.crop_len
  L.crop_wraps = s.crop_wraps

  L.loop_start = s.loop_start
  L.loop_end = s.loop_end
  L.play_pos = s.play_pos

  -- clear transient UI-only ring state
  L.held_ring_points = {}
  L.ring_crop_happened = false
  L.crop_ring_start_idx = nil
  L.crop_ring_end_idx = nil

  -- restore softcut loop bounds and positions
  softcut.loop_start(L.play_voice, L.loop_start)
  softcut.loop_end(L.play_voice, L.loop_end)
  softcut.loop_start(L.write_voice, L.loop_start)
  softcut.loop_end(L.write_voice, L.loop_end)

  softcut.position(L.play_voice, L.play_pos)
  softcut.position(L.write_voice, L.play_pos)

  if L.has_loop then
    softcut.play(L.play_voice, 1)
    softcut.play(L.write_voice, 1)
  else
    softcut.play(L.play_voice, 0)
    softcut.play(L.write_voice, 0)
  end

  -- do not restore active recording; just restore passive state
  L.is_recording = false
  L.rec_start_time = 0

  if L.is_overdubbing then
    looper_engine.apply_write_mode(L)
  else
    L.is_overdubbing = false
    softcut.rec(L.play_voice, 0)
    softcut.rec(L.write_voice, 0)
    softcut.rec_level(L.play_voice, 0.0)
    softcut.rec_level(L.write_voice, 0.0)
    softcut.pre_level(L.play_voice, 1.0)
    softcut.pre_level(L.write_voice, 1.0)
    softcut.level_cut_cut(L.play_voice, L.write_voice, 0.0)
  end

  looper_engine.update_phase_quant(L)
  looper_engine.apply_rate(L)
  looper_engine.apply_rate_slew(L)
  looper_engine.set_dj_filter_rq(L, L.dj_filter_res)
  looper_engine.set_dj_filter_freq(L, L.dj_filter_freq)
  looper_engine.update_output_mix(L)
end

restore_performance_state = function(state)
  if state == nil then return end

  restore_looper_state(loopers[1], state.loopers[1])
  restore_looper_state(loopers[2], state.loopers[2])

  link_playheads = state.link_playheads

  send_1_to_2 = state.send_1_to_2
  send_2_to_1 = state.send_2_to_1
  send_1_to_2_enabled = state.send_1_to_2_enabled
  send_2_to_1_enabled = state.send_2_to_1_enabled

  refresh_routing()
  redraw_all()
end

local function state_deepcopy(x)
  if type(x) ~= "table" then return x end
  local out = {}
  for k, v in pairs(x) do
    out[state_deepcopy(k)] = state_deepcopy(v)
  end
  return out
end

local function snapshot_store(slot)
  local state = state_deepcopy(capture_performance_state())
  if slot == 1 then
    snapshot_1 = state
  elseif slot == 2 then
    snapshot_2 = state
  end
  trigger_snapshot_flash("store")
end

local function snapshot_recall(slot)
  if slot == 1 and snapshot_1 ~= nil then
    restore_performance_state(state_deepcopy(snapshot_1))
    trigger_snapshot_flash("recall")
  elseif slot == 2 and snapshot_2 ~= nil then
    restore_performance_state(state_deepcopy(snapshot_2))
    trigger_snapshot_flash("recall")
  end
end

local function snapshot_clear(slot)
  if slot == 1 then
    snapshot_1 = nil
  elseif slot == 2 then
    snapshot_2 = nil
  end
  trigger_snapshot_flash("delete")
end

local function snapshot_exists(slot)
  if slot == 1 then
    return snapshot_1 ~= nil
  elseif slot == 2 then
    return snapshot_2 ~= nil
  end
  return false
end

local function snapshot_store_or_recall(slot)
  if snapshot_exists(slot) then
    snapshot_recall(slot)
  else
    snapshot_store(slot)
  end
end

local function snapshot_slot_from_modifier()
  if snapshot_key_held and mod_shift_held and not shift_held then
    return 1
  elseif snapshot_key_held and shift_held and not mod_shift_held then
    return 2
  end
  return nil
end

local function clear_snapshot_modes()
  snapshot_mode_delete = false
  snapshot_mode_overwrite = false
end

local function try_snapshot_mode_action()
  local slot = snapshot_slot_from_modifier()
  if slot == nil then return false end

  if snapshot_mode_delete then
    snapshot_clear(slot)
  elseif snapshot_mode_overwrite then
    local state = state_deepcopy(capture_performance_state())
    if slot == 1 then
      snapshot_1 = state
    elseif slot == 2 then
      snapshot_2 = state
    end
    trigger_snapshot_flash("overwrite")
  else
    snapshot_store_or_recall(slot)
  end

  clear_snapshot_modes()
  redraw_all()
  return true
end

trigger_snapshot_flash = function(kind)
  snapshot_flash_kind = kind
  snapshot_flash_token = snapshot_flash_token + 1
  local my_token = snapshot_flash_token

  redraw_all()

  clock.run(function()
    if kind == "overwrite" then
      clock.sleep(0.08)
      if snapshot_flash_token ~= my_token then return end
      snapshot_flash_kind = nil
      redraw_all()

      clock.sleep(0.06)
      if snapshot_flash_token ~= my_token then return end
      snapshot_flash_kind = "overwrite_2"
      redraw_all()

      clock.sleep(0.08)
      if snapshot_flash_token ~= my_token then return end
      snapshot_flash_kind = nil
      redraw_all()
    else
      clock.sleep(0.14)
      if snapshot_flash_token ~= my_token then return end
      snapshot_flash_kind = nil
      redraw_all()
    end
  end)
end

-- -------------------------------------------------------------------------
-- ROUTING / RESET
-- -------------------------------------------------------------------------

refresh_routing = function()
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

  send_1_to_2 = 0.33
  send_2_to_1 = 0.33
  send_1_to_2_enabled = false
  send_2_to_1_enabled = false

  snapshot_1 = nil
  snapshot_2 = nil

  refresh_routing()
  redraw_all()
end

local function clear_modifiers_all()
  for _, L in ipairs(loopers) do
    looper_engine.clear_modifiers(L)
  end

  link_playheads = false
  send_1_to_2 = 0.33
  send_2_to_1 = 0.33
  send_1_to_2_enabled = false
  send_2_to_1_enabled = false

  refresh_routing()
  redraw_all()
end

-- -------------------------------------------------------------------------
-- PARAMETER ADJUSTMENTS
-- -------------------------------------------------------------------------

local function stepped_speed_targets()
  return {0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 4.0}
end

local function motion_or_live_rate(L)
  if L.motion_recording and L.motion_recorded_rate ~= nil then
    return L.motion_recorded_rate
  end
  return L.rate
end

local function motion_or_live_is_reversed(L)
  if L.motion_recording and L.motion_recorded_is_reversed ~= nil then
    return L.motion_recorded_is_reversed
  end
  return L.is_reversed
end

local function set_signed_rate(L, signed_rate)
  signed_rate = util.clamp(signed_rate, -4.0, 4.0)

  if math.abs(signed_rate) < 0.001 then
    signed_rate = 0
  end

  local pending_is_reversed = (signed_rate < 0)

  if L.motion_recording then
    L.motion_recorded_rate = signed_rate
    L.motion_recorded_is_reversed = pending_is_reversed

    local live_mag = math.abs(signed_rate)
    L.rate = L.is_reversed and -live_mag or live_mag
    looper_engine.apply_rate(L)
    return
  end

  L.rate = signed_rate
  L.is_reversed = pending_is_reversed
  looper_engine.apply_rate(L)
end

local function toggle_reverse_state(L)
  if L.motion_recording then
    local new_is_reversed = not motion_or_live_is_reversed(L)
    local mag = math.abs(motion_or_live_rate(L))
    L.motion_recorded_is_reversed = new_is_reversed
    L.motion_recorded_rate = new_is_reversed and -mag or mag
    return
  end

  L.is_reversed = not L.is_reversed
  L.rate = L.is_reversed and -math.abs(L.rate) or math.abs(L.rate)
  looper_engine.apply_rate(L)
end

local function apply_free_speed(L, d)
  local rate = motion_or_live_rate(L)
  set_signed_rate(L, rate + d * 0.005)
end

local function apply_stepped_speed(L, d)
  local targets = stepped_speed_targets()

  local rate = motion_or_live_rate(L)
  local sign = (rate < 0) and -1 or 1
  local mag = math.abs(rate)
  if mag < 0.001 then mag = 1.0 end

  local best_i = 1
  local best_d = math.huge
  for i, v in ipairs(targets) do
    local dd = math.abs(v - mag)
    if dd < best_d then
      best_d = dd
      best_i = i
    end
  end

  if d > 0 then
    best_i = math.min(#targets, best_i + 1)
  elseif d < 0 then
    best_i = math.max(1, best_i - 1)
  end

  set_signed_rate(L, sign * targets[best_i])
end

local function adjust_selected_drywet(d)
  looper_engine.for_each_selected(loopers, function(L)
    looper_engine.set_drywet(L, L.drywet + d * 0.01)
  end)
end

local function adjust_selected_overdub(d)
  looper_engine.for_each_selected(loopers, function(L)
    looper_engine.set_overdub(L, L.overdub + d * 0.04)
  end)
  refresh_routing()
end

local function adjust_selected_tape(d)
  looper_engine.for_each_selected(loopers, function(L)
    looper_engine.set_tape_age(L, L.tape_age + d * 0.04)
    looper_engine.apply_rate(L)
  end)
end

local function adjust_selected_dropper(d)
  looper_engine.for_each_selected(loopers, function(L)
    looper_engine.set_dropper_amt(L, L.dropper_amt + d * 0.04)
  end)
end

local function move_playhead_for_looper(idx, d)
  local L = loopers[idx]
  looper_engine.move_crop(L, d * 2 / (64 * 4))
  if idx == 1 and link_playheads then
    sync_linked_playheads()
  end
end

local function change_crop_len_for_looper(idx, d)
  local L = loopers[idx]
  local frac = looper_engine.get_crop_fraction(L)
  frac = frac + d * 0.004
  looper_engine.set_crop_fraction(L, frac)
  if idx == 1 and link_playheads then
    sync_linked_playheads()
  end
end

local function apply_stepped_speed_for_looper(idx, d)
  apply_stepped_speed(loopers[idx], d)
end

local function apply_free_speed_for_looper(idx, d)
  apply_free_speed(loopers[idx], d)
end

-- -------------------------------------------------------------------------
-- Norns KEYS / ENCODERS
-- -------------------------------------------------------------------------

local function all_keys_held()
  return k1_held and k2_held and k3_held
end

function key(n, z)
  if n == 1 then
    if z == 1 then
      k1_held = true
      k1_consumed = false
      k1_down_time = util.time()
    else
      k1_held = false
      k1_down_time = nil
    end
    redraw()
    return
  end

  if n == 2 then
    if z == 1 then
      k2_held = true
      k2_consumed = false
      k2_down_time = util.time()

      if all_keys_held() then
        k1_consumed = true
        k2_consumed = true
        k3_consumed = true
        reset_all()
        redraw()
        return
      end

      if k1_held then
        k1_consumed = true
        k2_consumed = true
        loopers[1].selected = not loopers[1].selected
        redraw()
        return
      end

      if k3_held then
        k2_consumed = true
        k3_consumed = true
        looper_engine.for_each_selected(loopers, function(L)
          looper_engine.motion_key_press(L)
        end)
        redraw()
        return
      end
    else
      local suppress_tap = k2_consumed or long_hold_shown(k2_down_time)
      k2_held = false
      k2_down_time = nil

      if not suppress_tap then
        looper_engine.for_each_selected(loopers, function(L)
          looper_engine.toggle(L)
        end)
        refresh_routing()
        redraw()
      else
        redraw()
      end
    end
    return
  end

  if n == 3 then
    if z == 1 then
      k3_held = true
      k3_consumed = false
      k3_down_time = util.time()

      if all_keys_held() then
        k1_consumed = true
        k2_consumed = true
        k3_consumed = true
        reset_all()
        redraw()
        return
      end

      if k1_held then
        k1_consumed = true
        k3_consumed = true
        loopers[2].selected = not loopers[2].selected
        redraw()
        return
      end

      if k2_held then
        k2_consumed = true
        k3_consumed = true
        looper_engine.for_each_selected(loopers, function(L)
          looper_engine.toggle_additive_mode(L)
        end)
        refresh_routing()
        redraw()
        return
      end
    else
      local suppress_tap = k3_consumed or long_hold_shown(k3_down_time)
      k3_held = false
      k3_down_time = nil

      if not suppress_tap then
        looper_engine.for_each_selected(loopers, function(L)
          looper_engine.clear_loop(L)
        end)
        refresh_routing()
        redraw()
      else
        redraw()
      end
    end
    return
  end
end

function enc(n, d)
  if n == 1 then
    if k1_held then
      k1_consumed = true
      adjust_selected_overdub(d)
    elseif k2_held then
      k2_consumed = true
      adjust_selected_tape(d)
    elseif k3_held then
      k3_consumed = true
      adjust_selected_dropper(d)
    else
      adjust_selected_drywet(d)
    end
    return
  end

  if n == 2 then
    if k1_held then
      k1_consumed = true
      change_crop_len_for_looper(1, d)
    elseif k2_held then
      k2_consumed = true
      apply_stepped_speed_for_looper(1, d)
    elseif k3_held then
      k3_consumed = true
      apply_free_speed_for_looper(1, d)
    else
      move_playhead_for_looper(1, d)
    end
    return
  end

  if n == 3 then
    if k1_held then
      k1_consumed = true
      change_crop_len_for_looper(2, d)
    elseif k2_held then
      k2_consumed = true
      apply_stepped_speed_for_looper(2, d)
    elseif k3_held then
      k3_consumed = true
      apply_free_speed_for_looper(2, d)
    else
      move_playhead_for_looper(2, d)
    end
    return
  end
end

-- -------------------------------------------------------------------------
-- LOOP / RING HELPERS
-- -------------------------------------------------------------------------

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

-- -------------------------------------------------------------------------
-- GRID
-- -------------------------------------------------------------------------

local function grid_key(x, y, z)
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
        local sign = motion_or_live_is_reversed(LL) and -1 or 1
        set_signed_rate(LL, sign * val)
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
    local target_vals = shift_held and defs.JUMP_TARGET_VALUES_SHIFT or defs.JUMP_TARGET_VALUES
    local trigger_vals = shift_held and defs.JUMP_TRIGGER_VALUES_SHIFT or defs.JUMP_TRIGGER_VALUES

    local target_val = target_vals[y]
    local trigger_val = trigger_vals[y]

    if target_val ~= nil then
      looper_engine.for_each_selected(loopers, function(LL)
        looper_engine.set_jump_div(LL, target_val)
      end)
      redraw_all()
      return
    end

    if trigger_val ~= nil then
      looper_engine.for_each_selected(loopers, function(LL)
        local current_div = LL.jump_trigger_div or 0
        local pressed_normal = defs.JUMP_TRIGGER_VALUES[y]
        local pressed_shift = defs.JUMP_TRIGGER_VALUES_SHIFT[y]

        local is_same_as_current =
          LL.jump_trigger_enabled and
          (
            current_div == pressed_normal or
            current_div == pressed_shift
          )

        if is_same_as_current then
          LL.jump_trigger_enabled = false
          looper_engine.set_jump_trigger_div(LL, 0)
        else
          LL.jump_trigger_enabled = true
          looper_engine.set_jump_trigger_div(LL, trigger_val)
        end
      end)
      redraw_all()
      return
    end
  end

  local left_ring_idx = looper_ui.grid_ring_hit(
    x, y, 1,
    defs.LEFT_RING_TOPRIGHT[1], defs.LEFT_RING_TOPRIGHT[2]
  )

  if left_ring_idx ~= nil then
    handle_ring_key(loopers[1], left_ring_idx, z)
    redraw_all()
    return
  end

  local right_ring_idx = looper_ui.grid_ring_hit(
    x, y, 2,
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

  if x == defs.MOTION1_KEY[1] and y == defs.MOTION1_KEY[2] and z == 1 then
    local L = loopers[1]

    if shift_held then
      looper_engine.clear_motion(L)
    elseif mod_shift_held then
      if L.motion_has_data then
        L.motion_playback = not L.motion_playback
        if L.motion_playback then
          L.motion_last_step = nil
        end
      end
    else
      looper_engine.motion_key_press(L)
    end

    redraw_all()
    return
  end

  if x == defs.MOTION2_KEY[1] and y == defs.MOTION2_KEY[2] and z == 1 then
    local L = loopers[2]

    if shift_held then
      looper_engine.clear_motion(L)
    elseif mod_shift_held then
      if L.motion_has_data then
        L.motion_playback = not L.motion_playback
        if L.motion_playback then
          L.motion_last_step = nil
        end
      end
    else
      looper_engine.motion_key_press(L)
    end

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
      toggle_reverse_state(LL)
    end)
    redraw_all()
    return
  end

  if x == defs.RATE_SLEW_KEY[1] and y == defs.RATE_SLEW_KEY[2] and z == 1 then
    looper_engine.for_each_selected(loopers, function(LL)
      LL.rate_slew_mode = (LL.rate_slew_mode + 1) % 3
      looper_engine.apply_rate_slew(LL)
    end)
    redraw_all()
    return
  end

  if x == defs.REC_KEY[1] and y == defs.REC_KEY[2] then
    -- snapshot toggle
    if snapshot_key_held then
      if z == 1 then
        snapshot_mode_overwrite = true
        snapshot_mode_delete = false
      else
        snapshot_mode_overwrite = false
      end
      redraw_all()
      return
    end
  
    if z == 1 then
      -- restart paused playback
      if shift_held and mod_shift_held then
        looper_engine.for_each_selected(loopers, function(LL)
          if LL.has_loop then
            softcut.play(LL.play_voice, 1)
            softcut.play(LL.write_voice, 1)
            looper_engine.apply_rate(LL)
            looper_engine.apply_write_mode(LL)
          end
        end)
        refresh_routing()
        redraw_all()
        return
  
      -- resync loops
      elseif mod_shift_held then
        if clock_mode == CLOCK_MODE_FREE then
          execute_selected_resync()
        else
          queue_selected_resync()
        end
        redraw_all()
        return
  
      -- clocking mode toggle
      elseif shift_held then
        local next_mode = clock_mode + 1
        if next_mode > CLOCK_MODE_N_BARS then
          next_mode = CLOCK_MODE_FREE
        end
        params:set("bliss_clock_mode", next_mode)
        redraw_all()
        return
      end
  
      looper_engine.for_each_selected(loopers, function(LL)
        if is_clocked_mode() then
          toggle_clocked_record(LL)
        else
          looper_engine.toggle(LL)
        end
      end)
      refresh_routing()
      redraw_all()
      return
    end
  end

  if x == defs.SNAPSHOT_KEY[1] and y == defs.SNAPSHOT_KEY[2] then
    snapshot_key_held = (z == 1)

    if z == 1 then
      clear_snapshot_modes()
    else
      clear_snapshot_modes()
    end

    redraw_all()
    return
  end

  if x == defs.MOD_SHIFT_KEY[1] and y == defs.MOD_SHIFT_KEY[2] then
    mod_shift_held = (z == 1)

    if z == 1 and snapshot_key_held then
      if try_snapshot_mode_action() then
        return
      end
    end

    redraw_all()
    return
  end

  if x == defs.SHIFT_KEY[1] and y == defs.SHIFT_KEY[2] then
    shift_held = (z == 1)

    if z == 1 and snapshot_key_held then
      if try_snapshot_mode_action() then
        return
      end
    end

    redraw_all()
    return
  end

  if x == defs.CLEAR_KEY[1] and y == defs.CLEAR_KEY[2] then
    if snapshot_key_held then
      if z == 1 then
        snapshot_mode_delete = true
        snapshot_mode_overwrite = false
      else
        snapshot_mode_delete = false
      end
      redraw_all()
      return
    end

    if z == 1 then
      if shift_held and mod_shift_held then
        looper_engine.for_each_selected(loopers, function(LL)
          LL.is_recording = false
          LL.is_overdubbing = false
          LL.rec_start_time = 0

          softcut.rec(LL.play_voice, 0)
          softcut.rec(LL.write_voice, 0)

          softcut.rec_level(LL.play_voice, 0.0)
          softcut.rec_level(LL.write_voice, 0.0)

          softcut.pre_level(LL.play_voice, 1.0)
          softcut.pre_level(LL.write_voice, 1.0)

          softcut.play(LL.play_voice, 0)
          softcut.play(LL.write_voice, 0)

          softcut.level_cut_cut(LL.play_voice, LL.write_voice, 0.0)
        end)
        refresh_routing()
        redraw_all()
      elseif shift_held then
        reset_all()
      elseif mod_shift_held then
        clear_modifiers_all()
      else
        looper_engine.for_each_selected(loopers, function(LL)
          looper_engine.clear_loop(LL)
          looper_engine.clear_motion(LL)
        end)
        refresh_routing()
        redraw_all()
      end
      return
    end
  end
end

-- -------------------------------------------------------------------------
-- ARC
-- -------------------------------------------------------------------------

local function arc_key(n, z)
  if z ~= 1 then return end
  arc_page = (arc_page % ARC_PAGE_MAX) + 1
  redraw_all()
end

local function snap_rate_with_dents(r)
  local targets = {
    -4.0, -3.0, -2.0, -1.5, -1.0, -0.75, -0.5, -0.25,
    0,
    0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0
  }

  local snap_width = 0.005

  for _, t in ipairs(targets) do
    if math.abs(r - t) <= snap_width then
      return t
    end
  end

  return r
end

local function arc_delta(n, d)
  if arc_page == 1 then
    if n == 1 then
      local L = loopers[1]
      looper_engine.move_crop(L, d * 0.5 / (64 * 4))
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
      looper_engine.move_crop(L, d * 0.5 / (64 * 4))

    elseif n == 4 then
      local L = loopers[2]
      local frac = looper_engine.get_crop_fraction(L)
      frac = frac + d * 0.004
      looper_engine.set_crop_fraction(L, frac)
    end

  elseif arc_page == 2 then
    if n == 1 then
      local L = loopers[1]
      local rate = motion_or_live_rate(L)
      set_signed_rate(L, rate + d * 0.005)
      local snapped = motion_or_live_rate(L)
      snapped = snap_rate_with_dents(snapped)
      set_signed_rate(L, snapped)
  
    elseif n == 2 then
      local L = loopers[2]
      local rate = motion_or_live_rate(L)
      set_signed_rate(L, rate + d * 0.005)
      local snapped = motion_or_live_rate(L)
      snapped = snap_rate_with_dents(snapped)
      set_signed_rate(L, snapped)
  
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

  looper_ui.arc_redraw(a, loopers, arc_page, send_1_to_2, send_2_to_1)
end

-- -------------------------------------------------------------------------
-- INIT / REDRAW / CLEANUP
-- -------------------------------------------------------------------------

function init()
  looper_engine.setup_softcut(loopers)

  softcut.event_phase(function(i, pos)
    looper_engine.phase_cb(loopers, i, pos)
  end)
  softcut.poll_start_phase()

-- metronome
  viz_metro = metro.init()
  viz_metro.time = 1 / 20
  viz_metro.event = function()
    for _, L in ipairs(loopers) do
      looper_engine.apply_tape_warble(L, viz_metro.time)
      looper_engine.apply_dropper(L, viz_metro.time)
      looper_engine.enforce_wrapped_crop(L)
      looper_engine.apply_jump(L)
    end
    sync_linked_playheads()
    
    if is_clocked_mode() then
  local beat = clock.get_beats()
  clock_ui_beat_phase = beat - math.floor(beat)

  if clock_mode == CLOCK_MODE_BAR or clock_mode == CLOCK_MODE_N_BARS then
      local beat_index = math.floor(beat)
      local beat_in_bar = (beat_index % clock_bar_beats) + 1
      clock_ui_is_downbeat = (beat_in_bar == 1)
    else
      clock_ui_is_downbeat = false
    end
  else
    clock_ui_beat_phase = 0
    clock_ui_is_downbeat = false
  end
    
    redraw_all()
  end
  viz_metro:start()

  -- grid/arc
  g = grid.connect()
  if g and g.device then
    g.key = grid_key
  end

  a = arc.connect()
  if a and a.device then
    a.delta = arc_delta
    a.key = arc_key
  end
  
  -- transport/clock
  start_clock_tick_task()
  
  clock.transport.start = function()
    if clock_ignore_transport then return end
  
    clock_transport_running = true
  
    for _, L in ipairs(loopers) do
      if L.clock_paused then
        L.clock_paused = false
  
        if L.has_loop then
          looper_engine.resume_playback(L)
        end
      end
    end
  
    redraw_all()
  end
  
  clock.transport.stop = function()
    if clock_ignore_transport then return end
  
    clock_transport_running = false
  
    for _, L in ipairs(loopers) do
      if L.is_recording then
        stop_record_now(L)
      end
  
      if L.has_loop then
        looper_engine.pause_playback(L)
      end
  
      L.clock_paused = true
    end
  
    redraw_all()
  end
  
  -- editable params
  params:add_separator("bliss_clock_sync_section", "Clock sync")
  params:add_option("bliss_clock_mode", "clock mode", {"FREE", "BEAT", "BAR", "N_BARS"}, 1)
  params:set_action("bliss_clock_mode", function(v)
    local new_mode = v
  
    if new_mode ~= CLOCK_MODE_FREE and clock_mode == CLOCK_MODE_FREE then
      local all_empty = true
      for _, L in ipairs(loopers) do
        if L.has_loop or L.is_recording or L.is_overdubbing then
          all_empty = false
        end
      end
      if not all_empty then
        params:set("bliss_clock_mode", clock_mode)
        return
      end
    end
  
    if new_mode == CLOCK_MODE_FREE and clock_mode ~= CLOCK_MODE_FREE then
      for _, L in ipairs(loopers) do
        looper_engine.clear_clock_state(L)
      end
    end
  
    clock_mode = new_mode
    update_clock_param_visibility()
    redraw_all()
  end)
  
  params:add_number("bliss_bar_beats", "bar beats", 1, 16, 4)
  params:set_action("bliss_bar_beats", function(v)
    clock_bar_beats = v
    redraw_all()
  end)
  
  params:add_number("bliss_n_bars", "n bars", 1, 16, 4)
  params:set_action("bliss_n_bars", function(v)
    clock_n_bars = v
    redraw_all()
  end)
  
  params:add_option("bliss_ignore_transport", "ignore transport", {"off", "on"}, 1)
  params:set_action("bliss_ignore_transport", function(v)
    clock_ignore_transport = (v == 2)
  end)
  
  update_clock_param_visibility()

  redraw_all()
end

function redraw()
  looper_ui.redraw(
    loopers, g, a,
    link_playheads,
    send_1_to_2, send_2_to_1,
    send_1_to_2_enabled, send_2_to_1_enabled,
    arc_page,
    k1_held, k2_held, k3_held,
    k1_down_time, k2_down_time, k3_down_time,
    mode_label(), clock_ui_beat_phase, clock_ui_is_downbeat, clock_mode
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