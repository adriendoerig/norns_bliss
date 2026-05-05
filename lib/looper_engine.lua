local defs = include("lib/looper_defs")

local engine = {}

engine.input_gain = 1.0

-- -------------------------------------------------------------------------
-- LOOPER STATE / CONSTRUCTION
-- -------------------------------------------------------------------------

function engine.reset_looper_state(L)
  L.has_loop = false
  L.is_recording = false
  L.is_overdubbing = false
  L.rec_start_time = 0

  L.drywet = 0.5
  L.dry_level = 0.5
  L.wet_level = 0.5

  L.additive_mode = false
  L.additive_amt = 0.835
  L.overdub = 1.0

  L.rate = 1.0
  L.rate_slew_mode = 1
  L.is_reversed = false

  L.dropper_amt = 0.0
  L.dropper_gain = 1.0
  L.dropper_target_gain = 1.0
  L.dropper_timer = 0.0

  L.tape_age = 3/7
  L.tape_lfo_phase_slow = 0.0
  L.tape_lfo_phase_fast = 0.0
  L.tape_drift = 0.0
  L.tape_wow_freq_jitter = 0.0
  L.tape_flutter_freq_jitter = 0.0

  L.dj_filter_freq = 0.0
  L.dj_filter_res = 1.0

  L.loop_start = 0.0
  L.loop_end = 1.0
  L.full_loop_start = 0.0
  L.full_loop_end = 1.0
  L.play_pos = 0.0
  L.write_pos = 0.0

  L.crop_start = 0.0
  L.crop_len = 1.0
  L.crop_wraps = false

  L.jump_div = 4
  L.jump_trigger_div = 0
  L.last_jump_step = nil
  L.jump_trigger_enabled = false

  L.held_ring_points = {}
  L.ring_crop_happened = false
  L.crop_ring_start_idx = nil
  L.crop_ring_end_idx = nil

  L.motion_has_data = false
  L.motion_playback = false
  L.motion_recording = false
  L.motion_data = {}
  L.motion_initial_state = {}
  L.motion_start_state = {}
  L.motion_time_start = nil
  L.motion_duration = nil
  L.motion_last_tick = nil
  L.motion_advancing = false
  
  L.clock_loop_ticks = nil
  L.clock_record_ticks = 0
  L.clock_play_ticks = 0

  L.clock_record_task = nil
  L.clock_pending_start = false
  L.clock_pending_stop = false
  L.clock_pending_stop_at_bar = false

  L.clock_paused = false
end

function engine.new_looper(id, play_voice, write_voice, buffer_id)
  local L = {
    id = id,
    play_voice = play_voice,
    write_voice = write_voice,
    buffer_id = buffer_id,
    selected = (id == 1),
    dj_dead = 0.1,
    dj_xfade = 0.01,
  }

  engine.reset_looper_state(L)
  return L
end

function engine.toggle_selected(L)
  L.selected = not L.selected
end

function engine.select_exclusive(loopers, idx)
  for i, L in ipairs(loopers) do
    L.selected = (i == idx)
  end
end

function engine.for_each_selected(loopers, fn)
  for _, L in ipairs(loopers) do
    if L.selected then
      fn(L)
    end
  end
end

function engine.reset_looper(L)
  softcut.play(L.play_voice, 0)
  softcut.play(L.write_voice, 0)

  softcut.rec(L.play_voice, 0)
  softcut.rec(L.write_voice, 0)

  softcut.rec_level(L.play_voice, 0.0)
  softcut.rec_level(L.write_voice, 0.0)

  softcut.pre_level(L.play_voice, 1.0)
  softcut.pre_level(L.write_voice, 1.0)

  softcut.level_cut_cut(L.play_voice, L.write_voice, 0.0)

  softcut.buffer_clear_channel(L.buffer_id)

  engine.reset_looper_state(L)

  softcut.loop_start(L.play_voice, 0.0)
  softcut.loop_end(L.play_voice, 1.0)
  softcut.position(L.play_voice, 0.0)

  softcut.loop_start(L.write_voice, 0.0)
  softcut.loop_end(L.write_voice, 1.0)
  softcut.position(L.write_voice, 0.0)
  
  L.scrub_continue = false
  L.scrub_velocity = 0.0
  L.scrub_last_arc_time = nil
  L.scrub_last_arc_n = nil

  engine.apply_rate(L)
  engine.apply_rate_slew(L)
  engine.set_dj_filter_rq(L, 1.0)
  engine.set_dj_filter_freq(L, 0.0)
  engine.update_output_mix(L)
  
  engine.clear_clock_state(L)
end

-- -------------------------------------------------------------------------
-- AUDIO / SOFTCUT SETUP
-- -------------------------------------------------------------------------

function engine.set_sources(adc, eng, tape)
  audio.level_adc_cut(adc or 0)
  audio.level_eng_cut(eng or 0)
  audio.level_tape_cut(tape or 0)
end

function engine.update_phase_quant(L)
  local loop_len = math.max(L.loop_end - L.loop_start, 0.001)
  softcut.phase_quant(L.play_voice, loop_len / defs.PHASE_STEPS)
end

local function apply_loop_fade(L)
  local rate_mag = math.max(math.abs(L.rate or 1.0), 1.0)
  local loop_len = math.max((L.loop_end or 1.0) - (L.loop_start or 0.0), defs.MIN_LEN)

  -- Play voice: compensate for faster read speed.
  local play_fade = math.min(defs.FADE * rate_mag, loop_len * 0.5)

  -- Write voice: keep boring/stable, but never longer than half the loop.
  local write_fade = math.min(defs.FADE, loop_len * 0.5)

  softcut.fade_time(L.play_voice, play_fade)
  softcut.fade_time(L.write_voice, write_fade)
end

function engine.set_loop_bounds(L, start_pos, end_pos)
  L.loop_start = start_pos
  L.loop_end = end_pos

  softcut.loop_start(L.play_voice, start_pos)
  softcut.loop_end(L.play_voice, end_pos)
  softcut.loop_start(L.write_voice, start_pos)
  softcut.loop_end(L.write_voice, end_pos)

  apply_loop_fade(L)
  engine.update_phase_quant(L)
end

function engine.set_loop_position(L, pos)
  softcut.position(L.play_voice, pos)
  softcut.position(L.write_voice, pos)
  L.play_pos = pos
  L.write_pos = pos
end

function engine.move_playhead_full_loop_from_pos(L, source_pos, delta_frac)
  local full_len = engine.get_full_len(L)

  local p = (source_pos - L.full_loop_start) / full_len
  p = p % 1.0
  if p < 0 then p = p + 1.0 end

  p = (p + delta_frac) % 1.0
  if p < 0 then p = p + 1.0 end

  local new_pos = L.full_loop_start + p * full_len
  engine.set_loop_position(L, new_pos)
  return new_pos
end

function engine.setup_voice_pair(L)
  softcut.enable(L.play_voice, 1)
  softcut.buffer(L.play_voice, L.buffer_id)

  softcut.level(L.play_voice, L.wet_level)
  softcut.pan(L.play_voice, 0.0)
  softcut.loop(L.play_voice, 1)
  softcut.fade_time(L.play_voice, defs.FADE)

  engine.apply_rate(L)
  engine.apply_rate_slew(L)
  engine.set_dj_filter_rq(L, 1.0)
  engine.set_dj_filter_freq(L, 0.0)

  softcut.rec(L.play_voice, 0)
  softcut.rec_level(L.play_voice, 0.0)
  softcut.pre_level(L.play_voice, 1.0)

  softcut.enable(L.write_voice, 1)
  softcut.buffer(L.write_voice, L.buffer_id)

  softcut.level(L.write_voice, 0.0)
  softcut.pan(L.write_voice, 0.0)
  softcut.loop(L.write_voice, 1)
  softcut.fade_time(L.write_voice, defs.FADE)

  softcut.rate(L.write_voice, 1.0)
  softcut.rate_slew_time(L.write_voice, 0.0)
  softcut.recpre_slew_time(L.write_voice, 0.02)

  softcut.post_filter_dry(L.write_voice, 1.0)
  softcut.post_filter_lp(L.write_voice, 0.0)
  softcut.post_filter_hp(L.write_voice, 0.0)
  softcut.post_filter_bp(L.write_voice, 0.0)
  softcut.post_filter_br(L.write_voice, 0.0)
  softcut.post_filter_fc(L.write_voice, 12000)
  softcut.post_filter_rq(L.write_voice, 1.0)

  softcut.rec(L.write_voice, 0)
  softcut.rec_level(L.write_voice, 0.0)
  softcut.pre_level(L.write_voice, 1.0)

  softcut.loop_start(L.play_voice, 0.0)
  softcut.loop_end(L.play_voice, 1.0)
  softcut.position(L.play_voice, 0.0)

  softcut.loop_start(L.write_voice, 0.0)
  softcut.loop_end(L.write_voice, 1.0)
  softcut.position(L.write_voice, 0.0)

  L.loop_start = 0.0
  L.loop_end = 1.0

  engine.update_phase_quant(L)

  audio.level_adc_cut(1.0)

  softcut.level_input_cut(1, L.write_voice, 0.707 * engine.input_gain)
  softcut.level_input_cut(2, L.write_voice, 0.707 * engine.input_gain)
  
  softcut.level_input_cut(1, L.play_voice, 0.0)
  softcut.level_input_cut(2, L.play_voice, 0.0)
  
  softcut.level_cut_cut(L.play_voice, L.write_voice, 0.0)
  softcut.voice_sync(L.write_voice, L.play_voice, 0)
end

function engine.setup_softcut(loopers)
  engine.set_sources(1.0, 0.0, 0.0)
  audio.level_cut(1.0)

  for _, L in ipairs(loopers) do
    engine.setup_voice_pair(L)
    engine.set_drywet(L, 0.5)
  end
end

-- -------------------------------------------------------------------------
-- MIX / MODIFIER PARAMETERS
-- -------------------------------------------------------------------------

function engine.update_output_mix(L)
  audio.level_adc(L.dry_level * engine.input_gain)
  softcut.level(L.play_voice, L.wet_level * L.dropper_gain)
end

function engine.set_drywet(L, val)
  L.drywet = util.clamp(val, 0.0, 1.0)
  L.wet_level = L.drywet
  L.dry_level = 1.0 - L.drywet
  engine.update_output_mix(L)
end

function engine.set_overdub(L, val)
  L.overdub = util.clamp(val, 0.0, 1.0)
  engine.apply_write_mode(L)
end

function engine.set_tape_age(L, val)
  L.tape_age = util.clamp(val, 0.0, 1.0)
  if L.tape_age <= 0.0001 then
    L.tape_drift = 0.0
  end
end

function engine.set_dropper_amt(L, val)
  L.dropper_amt = util.clamp(val, 0.0, 1.0)
end

function engine.set_dj_filter_rq(L, val)
  L.dj_filter_res = util.clamp(val, 0.2, 1.2)
  softcut.post_filter_rq(L.play_voice, L.dj_filter_res)
end

function engine.set_dj_filter_freq(L, val)
  L.dj_filter_freq = util.clamp(val, -1.0, 1.0)

  local s = L.dj_filter_freq
  local a = math.abs(s)

  local wet = util.clamp((a - L.dj_dead) / L.dj_xfade, 0.0, 1.0)
  softcut.post_filter_dry(L.play_voice, 1.0 - wet)

  if wet < 0.001 then
    softcut.post_filter_lp(L.play_voice, 0)
    softcut.post_filter_hp(L.play_voice, 0)
    return
  end

  if s < 0 then
    local x = util.clamp(-s, 0.1, 1.0)
    local freq = util.linexp(0.1, 1.0, 12000, 80, x)
    softcut.post_filter_fc(L.play_voice, freq)
    softcut.post_filter_lp(L.play_voice, 1)
    softcut.post_filter_hp(L.play_voice, 0)
  else
    local x = util.clamp(s, 0.1, 1.0)
    local freq = util.linexp(0.1, 1.0, 20, 8000, x)
    softcut.post_filter_fc(L.play_voice, freq)
    softcut.post_filter_hp(L.play_voice, 1)
    softcut.post_filter_lp(L.play_voice, 0)
  end
end

function engine.apply_tape_warble(L, dt)
  local base_rate = L.is_reversed and -math.abs(L.rate) or math.abs(L.rate)

  -- Tape warble is safe as a playback effect, but during active overdub it
  -- makes the audible read head drift/jitter relative to the steady write head.
  -- That can create sizzling/comb-like artifacts in the recorded loop.
  if L.is_overdubbing then
    L.tape_drift = 0.0
    L.tape_wow_freq_jitter = 0.0
    L.tape_flutter_freq_jitter = 0.0
    softcut.rate(L.play_voice, base_rate)
    return
  end

  if L.tape_age <= 0.0001 then
    L.tape_drift = 0.0
    L.tape_wow_freq_jitter = 0.0
    L.tape_flutter_freq_jitter = 0.0
    softcut.rate(L.play_voice, base_rate)
    return
  end

  local wow_depth = 0.012 * L.tape_age
  local wow_hz_base = 0.08 + 0.17 * L.tape_age

  local flutter_depth = 0.0035 * L.tape_age
  local flutter_hz_base = 3.0 + 2.0 * L.tape_age

  local drift_step = 0.0008 * L.tape_age
  L.tape_drift = L.tape_drift + (math.random() * 2 - 1) * drift_step
  L.tape_drift = util.clamp(L.tape_drift, -0.01 * L.tape_age, 0.01 * L.tape_age)

  local wow_jitter_step = 0.003 * L.tape_age * dt
  L.tape_wow_freq_jitter = L.tape_wow_freq_jitter + (math.random() * 2 - 1) * wow_jitter_step
  L.tape_wow_freq_jitter = util.clamp(L.tape_wow_freq_jitter, -0.03, 0.03)

  local flutter_jitter_step = 0.08 * L.tape_age * dt
  L.tape_flutter_freq_jitter = L.tape_flutter_freq_jitter + (math.random() * 2 - 1) * flutter_jitter_step
  L.tape_flutter_freq_jitter = util.clamp(L.tape_flutter_freq_jitter, -0.6, 0.6)

  local wow_hz = math.max(0.01, wow_hz_base + L.tape_wow_freq_jitter)
  local flutter_hz = math.max(0.2, flutter_hz_base + L.tape_flutter_freq_jitter)

  L.tape_lfo_phase_slow = L.tape_lfo_phase_slow + dt * wow_hz * 2 * math.pi
  L.tape_lfo_phase_fast = L.tape_lfo_phase_fast + dt * flutter_hz * 2 * math.pi

  local wow = math.sin(L.tape_lfo_phase_slow) * wow_depth
  local flutter = math.sin(L.tape_lfo_phase_fast) * flutter_depth

  local mod = wow + flutter + L.tape_drift
  softcut.rate(L.play_voice, base_rate * (1.0 + mod))
end

function engine.apply_rate(L)
  engine.apply_tape_warble(L, 0)
  apply_loop_fade(L)
end

function engine.apply_rate_slew(L)
  local rate_slew = 0.0

  if L.rate_slew_mode == 1 then
    rate_slew = 0.1
  elseif L.rate_slew_mode == 2 then
    rate_slew = 2.0
  end

  softcut.rate_slew_time(L.play_voice, rate_slew)
end

function engine.apply_dropper(L, dt)
  if not L.has_loop or L.is_recording or L.dropper_amt <= 0.0001 then
    L.dropper_target_gain = 1.0
    L.dropper_timer = 0.0
  else
    if L.dropper_timer > 0 then
      L.dropper_timer = math.max(0, L.dropper_timer - dt)
      if L.dropper_timer == 0 then
        L.dropper_target_gain = 1.0
      end
    else
      local events_per_sec = util.linexp(0, 1, 0.3, 10.0, L.dropper_amt)
      local p = math.min(events_per_sec * dt, 1.0)

      if math.random() < p then
        if math.random() < 0.2 then
          L.dropper_timer = util.linlin(0, 1, 0.12, 0.28, math.random())
        else
          L.dropper_timer = util.linlin(0, 1, 0.02, 0.16, math.random())
        end

        L.dropper_target_gain = util.linlin(
          0, 1,
          1.0 - 0.9 * L.dropper_amt,
          0.0,
          math.random()
        )
      end
    end
  end

  local fade_hz = 7.0
  local alpha = math.min(1.0, fade_hz * dt)
  L.dropper_gain = L.dropper_gain + (L.dropper_target_gain - L.dropper_gain) * alpha

  engine.update_output_mix(L)
end

-- -------------------------------------------------------------------------
-- RECORD / OVERDUB / ROUTING
-- -------------------------------------------------------------------------

function engine.set_input_gain(loopers, gain)
  engine.input_gain = util.clamp(gain or 1.0, 0.0, 2.0)

  for _, L in ipairs(loopers) do
    softcut.level_input_cut(1, L.write_voice, 0.707 * engine.input_gain)
    softcut.level_input_cut(2, L.write_voice, 0.707 * engine.input_gain)

    -- keep play voices isolated from live input
    softcut.level_input_cut(1, L.play_voice, 0.0)
    softcut.level_input_cut(2, L.play_voice, 0.0)
  end
end

function engine.apply_write_mode(L)
  if not L.is_overdubbing then
    softcut.rec(L.write_voice, 0)
    softcut.rec_level(L.write_voice, 0.0)
    softcut.pre_level(L.write_voice, 1.0)
    return
  end

  softcut.rec(L.write_voice, 1)

  if L.additive_mode then
    softcut.rec_level(L.write_voice, 1.0)
    softcut.pre_level(L.write_voice, 0.0)
  else
    softcut.rec_level(L.write_voice, 1.0)
    softcut.pre_level(L.write_voice, L.overdub)
  end
end

function engine.toggle_additive_mode(L)
  L.additive_mode = not L.additive_mode
  engine.apply_write_mode(L)
end

function engine.update_all_routing(loopers, send_1_to_2, send_2_to_1, send_1_to_2_enabled, send_2_to_1_enabled)
  local L1 = loopers[1]
  local L2 = loopers[2]

  -- default everything off first
  softcut.level_cut_cut(L1.play_voice, L1.write_voice, 0.0)
  softcut.level_cut_cut(L2.play_voice, L2.write_voice, 0.0)
  softcut.level_cut_cut(L1.play_voice, L2.write_voice, 0.0)
  softcut.level_cut_cut(L2.play_voice, L1.write_voice, 0.0)

  -- self-routing for additive mode
  if L1.is_overdubbing and L1.additive_mode then
    softcut.level_cut_cut(L1.play_voice, L1.write_voice, L1.overdub * L1.additive_amt)
  end

  if L2.is_overdubbing and L2.additive_mode then
    softcut.level_cut_cut(L2.play_voice, L2.write_voice, L2.overdub * L2.additive_amt)
  end

  -- cross-routing
  if L2.is_overdubbing and send_1_to_2_enabled then
    softcut.level_cut_cut(L1.play_voice, L2.write_voice, send_1_to_2)
  end

  if L1.is_overdubbing and send_2_to_1_enabled then
    softcut.level_cut_cut(L2.play_voice, L1.write_voice, send_2_to_1)
  end
end

function engine.start_recording(L)
  L.held_ring_points = {}
  L.crop_ring_start_idx = nil
  L.crop_ring_end_idx = nil
  engine.clear_crop(L)

  L.dropper_gain = 1.0
  L.dropper_target_gain = 1.0
  L.dropper_timer = 0.0
  engine.update_output_mix(L)

  L.is_recording = true
  L.is_overdubbing = false
  L.rec_start_time = util.time()

  softcut.buffer_clear_channel(L.buffer_id)

  engine.set_loop_bounds(L, 0.0, defs.MAX_LEN)
  engine.set_loop_position(L, 0.0)
  
  softcut.play(L.play_voice, 0) -- mute play voice during furst recording to avoid artifacts
  softcut.rec(L.play_voice, 0)
  
  softcut.play(L.write_voice, 0)
  softcut.rec(L.write_voice, 1)
  softcut.rec_level(L.write_voice, 1.0)
  softcut.pre_level(L.write_voice, 0.0)

  softcut.level_cut_cut(L.play_voice, L.write_voice, 0.0)
end

function engine.stop_recording_and_play(L)
  L.is_recording = false
  L.has_loop = true
  L.is_overdubbing = false

  local len = util.time() - L.rec_start_time
  len = util.clamp(len, defs.MIN_LEN, defs.MAX_LEN)

  L.full_loop_start = 0.0
  L.full_loop_end = len
  L.crop_start = L.full_loop_start
  L.crop_len = L.full_loop_end - L.full_loop_start
  L.crop_wraps = false

  softcut.rec(L.write_voice, 0)
  softcut.rec_level(L.write_voice, 0.0)
  softcut.pre_level(L.write_voice, 1.0)

  engine.set_loop_bounds(L, 0.0, len)
  engine.set_loop_position(L, 0.0)

  softcut.play(L.play_voice, 1)
  engine.apply_rate(L)
  engine.update_output_mix(L)

  softcut.play(L.write_voice, 1)
  engine.apply_write_mode(L)
end

function engine.stop_recording_and_play_clocked(L, tick_count)
  L.is_recording = false
  L.has_loop = true
  L.is_overdubbing = false

  local len = tick_count * clock.get_beat_sec()
  len = util.clamp(len, defs.MIN_LEN, defs.MAX_LEN)

  L.full_loop_start = 0.0
  L.full_loop_end = len
  L.crop_start = L.full_loop_start
  L.crop_len = L.full_loop_end - L.full_loop_start
  L.crop_wraps = false

  softcut.rec(L.write_voice, 0)
  softcut.rec_level(L.write_voice, 0.0)
  softcut.pre_level(L.write_voice, 1.0)

  engine.set_loop_bounds(L, 0.0, len)
  engine.set_loop_position(L, 0.0)

  softcut.play(L.play_voice, 1)
  engine.apply_rate(L)
  engine.update_output_mix(L)

  softcut.play(L.write_voice, 1)
  engine.apply_write_mode(L)
end

function engine.start_overdub(L)
  if not L.has_loop then return end

  -- Keep the write head aligned with what the performer is hearing.
  -- Without this, overdub can write into a slightly offset buffer position,
  -- causing comb/chorus/slapback artifacts over repeated passes.
  softcut.voice_sync(L.write_voice, L.play_voice, 0)

  L.write_pos = L.play_pos

  L.is_overdubbing = true
  softcut.play(L.play_voice, 1)
  softcut.play(L.write_voice, 1)
  engine.apply_write_mode(L)
end

function engine.stop_overdub(L)
  L.is_overdubbing = false
  engine.apply_write_mode(L)
end

function engine.toggle(L)
  if L.is_recording then
    engine.stop_recording_and_play(L)
  elseif L.has_loop and not L.is_overdubbing then
    engine.start_overdub(L)
  elseif L.is_overdubbing then
    engine.stop_overdub(L)
  else
    engine.start_recording(L)
  end
end

function engine.clear_modifiers(L)
  -- stop record / overdub, but keep loop audio and full loop geometry
  L.is_recording = false
  L.is_overdubbing = false
  L.rec_start_time = 0

  softcut.rec(L.play_voice, 0)
  softcut.rec(L.write_voice, 0)

  softcut.rec_level(L.play_voice, 0.0)
  softcut.rec_level(L.write_voice, 0.0)

  softcut.pre_level(L.play_voice, 1.0)
  softcut.pre_level(L.write_voice, 1.0)

  -- remove self-routing into write head
  softcut.level_cut_cut(L.play_voice, L.write_voice, 0.0)

  -- restore default playback modifiers
  L.drywet = 0.5
  L.dry_level = 0.5
  L.wet_level = 0.5

  L.additive_mode = false
  L.overdub = 1.0

  L.rate = 1.0
  L.rate_slew_mode = 1
  L.is_reversed = false

  L.dropper_amt = 0.0
  L.dropper_gain = 1.0
  L.dropper_target_gain = 1.0
  L.dropper_timer = 0.0

  L.tape_age = 3/7
  L.tape_lfo_phase_slow = 0.0
  L.tape_lfo_phase_fast = 0.0
  L.tape_drift = 0.0
  L.tape_wow_freq_jitter = 0.0
  L.tape_flutter_freq_jitter = 0.0

  L.dj_filter_freq = 0.0
  L.dj_filter_res = 1.0

  L.jump_div = 4
  L.jump_trigger_div = 0
  L.jump_trigger_enabled = false
  L.last_jump_step = nil

  -- clear crop and ring interaction, but keep the full recorded loop
  L.held_ring_points = {}
  L.ring_crop_happened = false
  L.crop_ring_start_idx = nil
  L.crop_ring_end_idx = nil

  L.crop_start = L.full_loop_start
  L.crop_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  L.crop_wraps = false

  L.loop_start = L.full_loop_start
  L.loop_end = L.full_loop_end

  softcut.loop_start(L.play_voice, L.full_loop_start)
  softcut.loop_end(L.play_voice, L.full_loop_end)
  softcut.loop_start(L.write_voice, L.full_loop_start)
  softcut.loop_end(L.write_voice, L.full_loop_end)
  apply_loop_fade(L)

  -- keep current playhead if possible, otherwise clamp to loop start
  if L.play_pos < L.full_loop_start or L.play_pos > L.full_loop_end then
    L.play_pos = L.full_loop_start
  end

  softcut.position(L.play_voice, L.play_pos)
  softcut.position(L.write_voice, L.play_pos)

  -- if audio exists, keep playing it
  if L.has_loop then
    softcut.play(L.play_voice, 1)
    softcut.play(L.write_voice, 1)
  else
    softcut.play(L.play_voice, 0)
    softcut.play(L.write_voice, 0)
  end

  engine.update_phase_quant(L)
  engine.apply_rate(L)
  engine.apply_rate_slew(L)
  engine.set_dj_filter_rq(L, 1.0)
  engine.set_dj_filter_freq(L, 0.0)
  engine.update_output_mix(L)
end

function engine.clear_loop(L)
  -- stop this looper
  L.is_recording = false
  L.is_overdubbing = false
  L.has_loop = false
  L.rec_start_time = 0

  softcut.play(L.play_voice, 0)
  softcut.play(L.write_voice, 0)

  softcut.rec(L.play_voice, 0)
  softcut.rec(L.write_voice, 0)

  softcut.rec_level(L.play_voice, 0.0)
  softcut.rec_level(L.write_voice, 0.0)

  softcut.pre_level(L.play_voice, 1.0)
  softcut.pre_level(L.write_voice, 1.0)

  -- remove any self-routing into the write head
  softcut.level_cut_cut(L.play_voice, L.write_voice, 0.0)

  -- clear only this looper's buffer
  softcut.buffer_clear_channel(L.buffer_id)

  -- reset loop geometry
  L.full_loop_start = 0.0
  L.full_loop_end = 1.0

  L.crop_start = L.full_loop_start
  L.crop_len = L.full_loop_end - L.full_loop_start
  L.crop_wraps = false

  L.loop_start = 0.0
  L.loop_end = 1.0
  L.play_pos = 0.0
  L.write_pos = 0.0

  -- reset crop/ring interaction state
  L.held_ring_points = {}
  L.ring_crop_happened = false
  L.crop_ring_start_idx = nil
  L.crop_ring_end_idx = nil

  -- reset transient dropper state but keep dropper_amt itself
  L.dropper_gain = 1.0
  L.dropper_target_gain = 1.0
  L.dropper_timer = 0.0

  -- re-apply clean full-loop state
  softcut.loop_start(L.play_voice, 0.0)
  softcut.loop_end(L.play_voice, 1.0)
  softcut.position(L.play_voice, 0.0)

  softcut.loop_start(L.write_voice, 0.0)
  softcut.loop_end(L.write_voice, 1.0)
  softcut.position(L.write_voice, 0.0)

  engine.update_phase_quant(L)
  engine.apply_rate(L)
  engine.apply_rate_slew(L)
  engine.update_output_mix(L)
  
  engine.clear_clock_state(L)
end

-- -------------------------------------------------------------------------
-- CLOCKED TRANSPORT PAUSE
-- -------------------------------------------------------------------------

function engine.pause_playback(L)
  softcut.play(L.play_voice, 0)
  softcut.play(L.write_voice, 0)
end

function engine.resume_playback(L)
  if L.has_loop then
    softcut.voice_sync(L.write_voice, L.play_voice, 0)
    L.write_pos = L.play_pos

    softcut.play(L.play_voice, 1)
    softcut.play(L.write_voice, 1)
    engine.apply_rate(L)
    engine.apply_write_mode(L)
  end
end

-- -------------------------------------------------------------------------
-- CROP / RING OPERATIONS
-- -------------------------------------------------------------------------

function engine.get_full_len(L)
  return math.max(L.full_loop_end - L.full_loop_start, 0.0001)
end

function engine.get_crop_len(L)
  return math.max(L.crop_len or engine.get_full_len(L), defs.MIN_LEN)
end

function engine.get_crop_fraction(L)
  local full_len = engine.get_full_len(L)
  local crop_len = engine.get_crop_len(L)
  return util.clamp(crop_len / full_len, defs.MIN_LEN / full_len, 1.0)
end

function engine.set_crop_fraction(L, frac)
  local full_len = engine.get_full_len(L)
  local min_frac = defs.MIN_LEN / full_len
  frac = util.clamp(frac, min_frac, 1.0)

  L.crop_len = frac * full_len
  engine.apply_crop_state(L)

  -- keep playhead inside crop
  if not L.crop_wraps then
    if L.play_pos < L.loop_start or L.play_pos > L.loop_end then
      engine.set_loop_position(L, L.loop_start)
    end
  end
end

function engine.move_crop(L, delta_frac)
  local full_len = engine.get_full_len(L)

  local crop_len = engine.get_crop_len(L)

  -- full crop = scrub as before
  if math.abs(crop_len - full_len) < 0.0001 then
    local p = util.clamp(
      (L.play_pos - L.full_loop_start) / full_len,
      0.0, 0.999999
    )
    p = (p + delta_frac) % 1.0
    local new_pos = L.full_loop_start + p * full_len
    engine.set_loop_position(L, new_pos)
    return
  end

  local rel = ((L.crop_start - L.full_loop_start) / full_len + delta_frac) % 1.0
  L.crop_start = L.full_loop_start + rel * full_len
  engine.apply_crop_state(L)

  -- keep playhead at start of moved crop for now
  softcut.position(L.play_voice, L.crop_start)
  softcut.position(L.write_voice, L.crop_start)
  L.play_pos = L.crop_start
end

function engine.apply_crop_state(L)
  local full_start = L.full_loop_start
  local full_end = L.full_loop_end
  local full_len = engine.get_full_len(L)

  local crop_len = util.clamp(engine.get_crop_len(L), defs.MIN_LEN, full_len)
  local crop_start = L.crop_start or full_start

  -- if crop is effectively the full loop, treat it as no crop
  if crop_len >= full_len - 0.0001 then
    L.crop_start = full_start
    L.crop_len = full_len
    L.crop_wraps = false

    L.loop_start = full_start
    L.loop_end = full_end

    softcut.loop_start(L.play_voice, full_start)
    softcut.loop_end(L.play_voice, full_end)
    softcut.loop_start(L.write_voice, full_start)
    softcut.loop_end(L.write_voice, full_end)
    apply_loop_fade(L)

    engine.update_phase_quant(L)
    return
  end

  -- wrap crop_start into full loop range
  local rel = (crop_start - full_start) % full_len
  crop_start = full_start + rel

  L.crop_start = crop_start
  L.crop_len = crop_len

  local crop_end_unwrapped = crop_start + crop_len

  if crop_end_unwrapped <= full_end then
    -- normal non-wrapping crop
    L.crop_wraps = false
    L.loop_start = crop_start
    L.loop_end = crop_end_unwrapped
    softcut.loop_start(L.play_voice, L.loop_start)
    softcut.loop_end(L.play_voice, L.loop_end)
    softcut.loop_start(L.write_voice, L.loop_start)
    softcut.loop_end(L.write_voice, L.loop_end)
    apply_loop_fade(L)
    engine.update_phase_quant(L)
  else
    -- wrapping crop: keep softcut on full loop, enforce wrap manually
    L.crop_wraps = true
    L.loop_start = crop_start
    L.loop_end = full_end
    softcut.loop_start(L.play_voice, full_start)
    softcut.loop_end(L.play_voice, full_end)
    softcut.loop_start(L.write_voice, full_start)
    softcut.loop_end(L.write_voice, full_end)
    apply_loop_fade(L)
    engine.update_phase_quant(L)
  end
end

function engine.clear_crop(L)
  L.crop_ring_start_idx = nil
  L.crop_ring_end_idx = nil

  L.crop_start = L.full_loop_start
  L.crop_len = L.full_loop_end - L.full_loop_start
  L.crop_wraps = false
  engine.apply_crop_state(L)
end

function engine.enforce_wrapped_crop(L)
  if not L.crop_wraps then return end

  local full_start = L.full_loop_start
  local full_end = L.full_loop_end
  local full_len = engine.get_full_len(L)

  local crop_start = L.crop_start
  local crop_len = engine.get_crop_len(L)
  local wrapped_end = crop_start + crop_len - full_len

  local p = L.play_pos

  -- if we passed the full-loop end region, wrap to start of crop
  if p >= full_end - 0.0005 then
    softcut.position(L.play_voice, full_start)
    softcut.position(L.write_voice, full_start)
    L.play_pos = full_start
    return
  end

  -- if we are in the middle "forbidden" region, jump back to crop start
  if p > wrapped_end and p < crop_start then
    softcut.position(L.play_voice, crop_start)
    softcut.position(L.write_voice, crop_start)
    L.play_pos = crop_start
  end
end

function engine.count_held_ring_points(L)
  local n = 0
  for _, _ in pairs(L.held_ring_points) do
    n = n + 1
  end
  return n
end

function engine.get_held_ring_indices(L)
  local inds = {}
  for idx, held in pairs(L.held_ring_points) do
    if held then
      inds[#inds + 1] = idx
    end
  end
  table.sort(inds)
  return inds
end

function engine.ring_idx_to_pos(L, idx)
  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local p = (idx - 1) / #defs.TAPEHEAD_RING_PTS
  return L.full_loop_start + p * full_len
end

function engine.set_playhead_from_ring_idx(L, idx)
  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local p = (idx - 1) / #defs.TAPEHEAD_RING_PTS
  local new_pos = L.full_loop_start + p * full_len
  engine.set_loop_position(L, new_pos)
end

function engine.cut_loop_between_ring_points(L, idx1, idx2)
  if idx1 == idx2 then return end

  L.crop_ring_start_idx = math.min(idx1, idx2)
  L.crop_ring_end_idx = math.max(idx1, idx2)

  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local step_len = full_len / #defs.TAPEHEAD_RING_PTS

  local pos1 = engine.ring_idx_to_pos(L, idx1)
  local pos2 = engine.ring_idx_to_pos(L, idx2)

  local new_start = math.min(pos1, pos2)
  local new_end = math.max(pos1, pos2) + step_len

  if new_end > L.full_loop_end then
    new_end = L.full_loop_end
  end

  if (new_end - new_start) < defs.MIN_LEN then
    new_end = math.min(new_start + defs.MIN_LEN, L.full_loop_end)
  end

  L.crop_start = new_start
  L.crop_len = new_end - new_start
  L.crop_wraps = false
  engine.apply_crop_state(L)
  engine.set_loop_position(L, new_start)
end

function engine.update_ring_loop_cut(L)
  local inds = engine.get_held_ring_indices(L)
  if #inds == 2 then
    engine.cut_loop_between_ring_points(L, inds[1], inds[2])
  end
end

-- -------------------------------------------------------------------------
-- MOTION RECORDING
-- -------------------------------------------------------------------------

-- Motion is a per-looper event sequencer.
-- It is intentionally NOT tied to the audio playhead phase: crop, reverse,
-- speed changes, and jumps should not bend the automation timeline itself.
-- It also records only explicit user gestures. Engine setters do not
-- automatically stamp events, because motion playback calls those same setters.

local MOTION_STEPS = 512

local MOTION_REPLACE_BY_KIND = {
  drywet = true,
  overdub = true,
  tape_age = true,
  dropper_amt = true,
  rate = true,
  rate_slew = true,
  dj_filter_freq = true,
  dj_filter_res = true,
  crop_set = true,
  crop_clear = true,
  loc = true,
  jump_div = true,
  jump_trigger_div = true,
  additive_mode = true,
}

local function motion_baseline_kind(kind)
  if kind == "crop_set" or kind == "crop_clear" then
    return "crop"
  end
  return kind
end

local function capture_motion_initial_event(L, kind)
  local baseline_kind = motion_baseline_kind(kind)
  if L.motion_initial_state[baseline_kind] ~= nil then return end

  -- Important: reset targets must come from the state at the moment motion
  -- recording started, not from the state after the first gesture has already
  -- changed the parameter. Otherwise, e.g. a stepped-speed move 1x -> 1.5x -> 2x
  -- would incorrectly reset to 1.5x instead of the true starting value.
  if L.motion_start_state ~= nil and L.motion_start_state[baseline_kind] ~= nil then
    local e = L.motion_start_state[baseline_kind]
    local out = {}
    for k, v in pairs(e) do
      out[k] = v
    end
    L.motion_initial_state[baseline_kind] = out
    return
  end

  if baseline_kind == "drywet" then
    L.motion_initial_state[baseline_kind] = { kind = "drywet", value = L.drywet }

  elseif baseline_kind == "overdub" then
    L.motion_initial_state[baseline_kind] = { kind = "overdub", value = L.overdub }

  elseif baseline_kind == "tape_age" then
    L.motion_initial_state[baseline_kind] = { kind = "tape_age", value = L.tape_age }

  elseif baseline_kind == "dropper_amt" then
    L.motion_initial_state[baseline_kind] = { kind = "dropper_amt", value = L.dropper_amt }

  elseif baseline_kind == "rate" then
    L.motion_initial_state[baseline_kind] = { kind = "rate", value = L.rate }

  elseif baseline_kind == "rate_slew" then
    L.motion_initial_state[baseline_kind] = { kind = "rate_slew", value = L.rate_slew_mode }

  elseif baseline_kind == "dj_filter_freq" then
    L.motion_initial_state[baseline_kind] = { kind = "dj_filter_freq", value = L.dj_filter_freq }

  elseif baseline_kind == "dj_filter_res" then
    L.motion_initial_state[baseline_kind] = { kind = "dj_filter_res", value = L.dj_filter_res }

  elseif baseline_kind == "jump_div" then
    L.motion_initial_state[baseline_kind] = { kind = "jump_div", value = L.jump_div }

  elseif baseline_kind == "jump_trigger_div" then
    L.motion_initial_state[baseline_kind] = { kind = "jump_trigger_div", value = L.jump_trigger_div }

  elseif baseline_kind == "additive_mode" then
    L.motion_initial_state[baseline_kind] = { kind = "additive_mode", value = L.additive_mode }

  elseif baseline_kind == "loc" then
    local full_len = engine.get_full_len(L)
    L.motion_initial_state[baseline_kind] = {
      kind = "loc",
      pos_frac = util.clamp((L.play_pos - L.full_loop_start) / full_len, 0.0, 0.999999),
    }

  elseif baseline_kind == "crop" then
    local full_len = engine.get_full_len(L)
    local crop_len = engine.get_crop_len(L)
    if crop_len >= full_len - 0.0001 then
      L.motion_initial_state[baseline_kind] = { kind = "crop_clear" }
    else
      L.motion_initial_state[baseline_kind] = {
        kind = "crop_set",
        start_frac = util.clamp((L.crop_start - L.full_loop_start) / full_len, 0.0, 1.0),
        len_frac = util.clamp(crop_len / full_len, defs.MIN_LEN / full_len, 1.0),
      }
    end
  end
end

local function restore_motion_initial_state(L)
  if L.motion_initial_state == nil then return end

  -- Restore only the parameter families that were explicitly automated.
  -- This makes each automation lane cycle start from the same parameter state
  -- without reapplying a heavy full-looper snapshot.
  local order = {
    "drywet", "overdub", "tape_age", "dropper_amt",
    "rate_slew", "rate", "dj_filter_freq", "dj_filter_res",
    "jump_div", "jump_trigger_div", "additive_mode", "crop", "loc",
  }

  for _, kind in ipairs(order) do
    local e = L.motion_initial_state[kind]
    if e ~= nil then
      engine.apply_motion_event(L, e)
    end
  end

  -- If the performer clears/stops an automation while overdubbing, keep the
  -- write head aligned with the audible play head. This avoids stale write-head
  -- offsets from a previous cropped/reversed/speed-modulated motion pass.
  if L.has_loop then
    softcut.voice_sync(L.write_voice, L.play_voice, 0)
    L.write_pos = L.play_pos
  end
end

local function motion_tick_after(tick)
  if tick >= MOTION_STEPS then
    return 1
  end
  return tick + 1
end

local function motion_tick_from_time(L, now)
  local duration = math.max(L.motion_duration or engine.get_full_len(L), 0.0001)
  local start_time = L.motion_time_start or now
  local elapsed = now - start_time
  local phase = (elapsed / duration) % 1.0
  local tick = math.floor(phase * MOTION_STEPS) + 1
  return tick, elapsed
end

local function append_motion_event_at_tick(L, tick, event)
  if event == nil or event.kind == nil then return end

  if L.motion_data[tick] == nil then
    L.motion_data[tick] = {}
  end

  -- Continuous gestures can produce multiple values inside one tick.
  -- Keep the last value for that parameter, but preserve ordering for
  -- genuinely different event kinds.
  if MOTION_REPLACE_BY_KIND[event.kind] then
    for i = #L.motion_data[tick], 1, -1 do
      if L.motion_data[tick][i].kind == event.kind then
        L.motion_data[tick][i] = event
        return
      end
    end
  end

  table.insert(L.motion_data[tick], event)
end

local function copy_motion_event(e)
  if e == nil then return nil end
  local out = {}
  for k, v in pairs(e) do
    out[k] = v
  end
  return out
end

local function capture_motion_start_state(L)
  local full_len = engine.get_full_len(L)
  local crop_len = engine.get_crop_len(L)
  local crop_event

  if crop_len >= full_len - 0.0001 then
    crop_event = { kind = "crop_clear" }
  else
    crop_event = {
      kind = "crop_set",
      start_frac = util.clamp((L.crop_start - L.full_loop_start) / full_len, 0.0, 1.0),
      len_frac = util.clamp(crop_len / full_len, defs.MIN_LEN / full_len, 1.0),
    }
  end

  return {
    drywet = { kind = "drywet", value = L.drywet },
    overdub = { kind = "overdub", value = L.overdub },
    tape_age = { kind = "tape_age", value = L.tape_age },
    dropper_amt = { kind = "dropper_amt", value = L.dropper_amt },
    rate = { kind = "rate", value = L.rate },
    rate_slew = { kind = "rate_slew", value = L.rate_slew_mode },
    dj_filter_freq = { kind = "dj_filter_freq", value = L.dj_filter_freq },
    dj_filter_res = { kind = "dj_filter_res", value = L.dj_filter_res },
    jump_div = { kind = "jump_div", value = L.jump_div },
    jump_trigger_div = { kind = "jump_trigger_div", value = L.jump_trigger_div },
    additive_mode = { kind = "additive_mode", value = L.additive_mode },
    crop = crop_event,
    loc = {
      kind = "loc",
      pos_frac = util.clamp((L.play_pos - L.full_loop_start) / full_len, 0.0, 0.999999),
    },
  }
end

local function append_motion_reset_events(L)
  if L.motion_initial_state == nil then return end

  -- At the end of the automation lane, explicitly return only the parameter
  -- families that were touched during recording to their pre-motion values.
  -- This keeps the lane repeatable without restoring a heavy full-looper state.
  local order = {
    "drywet", "overdub", "tape_age", "dropper_amt",
    "rate_slew", "rate", "dj_filter_freq", "dj_filter_res",
    "jump_div", "jump_trigger_div", "additive_mode", "crop", "loc",
  }

  for _, kind in ipairs(order) do
    local e = copy_motion_event(L.motion_initial_state[kind])
    if e ~= nil then
      if L.motion_data[MOTION_STEPS] == nil then
        L.motion_data[MOTION_STEPS] = {}
      end
      -- Do not coalesce here: if the performer deliberately recorded an event
      -- very near the end, the reset should still happen after it.
      table.insert(L.motion_data[MOTION_STEPS], e)
    end
  end
end

function engine.record_motion_event(L, event)
  if not L.motion_recording then return end
  if event == nil or event.kind == nil then return end

  capture_motion_initial_event(L, event.kind)

  local tick = motion_tick_from_time(L, util.time())
  append_motion_event_at_tick(L, tick, event)
end

function engine.record_crop_motion_event(L)
  if not L.motion_recording then return end

  local full_len = engine.get_full_len(L)
  local crop_len = engine.get_crop_len(L)

  if crop_len >= full_len - 0.0001 then
    engine.record_motion_event(L, { kind = "crop_clear" })
    return
  end

  engine.record_motion_event(L, {
    kind = "crop_set",
    start_frac = util.clamp((L.crop_start - L.full_loop_start) / full_len, 0.0, 1.0),
    len_frac = util.clamp(crop_len / full_len, defs.MIN_LEN / full_len, 1.0),
  })
end

function engine.record_playhead_motion_event(L)
  if not L.motion_recording then return end

  local full_len = engine.get_full_len(L)
  engine.record_motion_event(L, {
    kind = "loc",
    pos_frac = util.clamp((L.play_pos - L.full_loop_start) / full_len, 0.0, 0.999999),
  })
end

function engine.apply_motion_event(L, e)
  if e == nil or e.kind == nil then return end

  if e.kind == "drywet" then
    engine.set_drywet(L, e.value)

  elseif e.kind == "overdub" then
    engine.set_overdub(L, e.value)

  elseif e.kind == "tape_age" then
    engine.set_tape_age(L, e.value)
    engine.apply_rate(L)

  elseif e.kind == "dropper_amt" then
    engine.set_dropper_amt(L, e.value)

  elseif e.kind == "rate" then
    L.rate = util.clamp(e.value or L.rate or 1.0, -4.0, 4.0)
    if math.abs(L.rate) < 0.001 then L.rate = 0 end
    L.is_reversed = (L.rate < 0)
    engine.apply_rate(L)

  elseif e.kind == "rate_slew" then
    L.rate_slew_mode = e.value or 0
    engine.apply_rate_slew(L)

  elseif e.kind == "dj_filter_freq" then
    engine.set_dj_filter_freq(L, e.value)

  elseif e.kind == "dj_filter_res" then
    engine.set_dj_filter_rq(L, e.value)

  elseif e.kind == "crop_set" then
    local full_len = engine.get_full_len(L)
    L.crop_start = L.full_loop_start + util.clamp(e.start_frac or 0.0, 0.0, 1.0) * full_len
    L.crop_len = util.clamp((e.len_frac or 1.0) * full_len, defs.MIN_LEN, full_len)
    engine.apply_crop_state(L)

  elseif e.kind == "crop_clear" then
    L.crop_start = L.full_loop_start
    L.crop_len = L.full_loop_end - L.full_loop_start
    L.crop_wraps = false
    engine.apply_crop_state(L)

  elseif e.kind == "loc" then
    local full_len = engine.get_full_len(L)
    local frac = util.clamp(e.pos_frac or 0.0, 0.0, 0.999999)
    engine.set_loop_position(L, L.full_loop_start + frac * full_len)

  elseif e.kind == "jump_div" then
    L.jump_div = e.value or 0
    L.last_jump_step = nil

  elseif e.kind == "jump_trigger_div" then
    L.jump_trigger_div = e.value or 0
    L.jump_trigger_enabled = (L.jump_trigger_div ~= 0)
    L.last_jump_step = nil

  elseif e.kind == "additive_mode" then
    L.additive_mode = e.value and true or false
    engine.apply_write_mode(L)
  end
end

function engine.apply_motion_tick(L, tick)
  local events = L.motion_data[tick]
  if events == nil then return end

  for _, e in ipairs(events) do
    engine.apply_motion_event(L, e)
  end
end

function engine.start_motion_recording(L)
  if not L.has_loop then return end

  L.motion_has_data = false
  L.motion_playback = false
  L.motion_recording = true
  L.motion_data = {}
  L.motion_initial_state = {}
  L.motion_start_state = capture_motion_start_state(L)
  L.motion_duration = engine.get_full_len(L)
  L.motion_time_start = util.time()
  L.motion_last_tick = nil
  L.motion_advancing = false
end

function engine.stop_motion_recording(L)
  if not L.motion_recording then return end

  L.motion_recording = false
  L.motion_has_data = next(L.motion_data) ~= nil

  if L.motion_has_data then
    append_motion_reset_events(L)
    restore_motion_initial_state(L)
  end

  L.motion_playback = L.motion_has_data
  L.motion_time_start = util.time()
  L.motion_last_tick = MOTION_STEPS
  L.motion_advancing = false
end

function engine.clear_motion(L)
  local should_restore = L.motion_has_data or L.motion_playback or L.motion_recording

  L.motion_playback = false
  L.motion_recording = false
  L.motion_advancing = false

  if should_restore then
    restore_motion_initial_state(L)
  elseif L.has_loop then
    softcut.voice_sync(L.write_voice, L.play_voice, 0)
    L.write_pos = L.play_pos
  end

  L.motion_has_data = false
  L.motion_data = {}
  L.motion_initial_state = {}
  L.motion_start_state = {}
  L.motion_time_start = nil
  L.motion_duration = nil
  L.motion_last_tick = nil
end

function engine.motion_key_press(L)
  if L.motion_recording then
    engine.stop_motion_recording(L)
  else
    engine.start_motion_recording(L)
  end
end

function engine.restart_motion_playback(L)
  if not L.motion_has_data then return end
  restore_motion_initial_state(L)
  L.motion_playback = true
  L.motion_time_start = util.time()
  L.motion_last_tick = MOTION_STEPS
  L.motion_advancing = false
end

function engine.advance_motion_state(L)
  if L.motion_advancing then return end

  if L.motion_recording then
    local _, elapsed = motion_tick_from_time(L, util.time())
    if elapsed >= (L.motion_duration or engine.get_full_len(L)) then
      engine.stop_motion_recording(L)
    end
    return
  end

  if not (L.motion_playback and L.motion_has_data) then
    return
  end

  local tick = motion_tick_from_time(L, util.time())
  if tick == L.motion_last_tick then return end

  L.motion_advancing = true

  local last = L.motion_last_tick or MOTION_STEPS
  local t = motion_tick_after(last)
  while true do
    engine.apply_motion_tick(L, t)
    if t == tick then break end
    t = motion_tick_after(t)
  end

  L.motion_last_tick = tick
  L.motion_advancing = false
end

function engine.phase_cb(loopers, i, pos)
  for _, L in ipairs(loopers) do
    if i == L.play_voice then
      if L.scrub_continue then
        return
      end

      L.play_pos = pos
      return
    end
  end
end

-- -------------------------------------------------------------------------
-- CLOCK
-- -------------------------------------------------------------------------

function engine.clear_clock_state(L)
  if L.clock_record_task then
    clock.cancel(L.clock_record_task)
    L.clock_record_task = nil
  end

  L.clock_loop_ticks = nil
  L.clock_record_ticks = 0
  L.clock_play_ticks = 0

  L.clock_pending_start = false
  L.clock_pending_stop = false
  L.clock_pending_stop_at_bar = false
  L.clock_paused = false
end

function engine.current_reset_target(L)
  if L.crop_start ~= nil and L.crop_len ~= nil and L.crop_len < (L.full_loop_end - L.full_loop_start - 0.0001) then
    return L.crop_start
  end
  return L.full_loop_start
end

function engine.reset_to_cycle_start(L)
  local pos = engine.current_reset_target(L)
  softcut.position(L.play_voice, pos)
  softcut.position(L.write_voice, pos)
  L.play_pos = pos
end

-- -------------------------------------------------------------------------
-- JUMP
-- -------------------------------------------------------------------------

function engine.set_jump_div(L, div)
  L.jump_div = div or 0
  L.last_jump_step = nil
end

function engine.set_jump_trigger_div(L, div)
  L.jump_trigger_div = div or 0
  L.jump_trigger_enabled = (L.jump_trigger_div ~= 0)
  L.last_jump_step = nil
end

function engine.get_crop_phase(L)
  local crop_len = math.max(L.crop_len or (L.loop_end - L.loop_start), defs.MIN_LEN)
  local p = L.play_pos

  if not L.crop_wraps then
    return util.clamp((p - L.crop_start) / crop_len, 0.0, 0.999999)
  end

  local rel
  if p >= L.crop_start then
    rel = p - L.crop_start
  else
    rel = (L.full_loop_end - L.crop_start) + (p - L.full_loop_start)
  end

  return util.clamp(rel / crop_len, 0.0, 0.999999)
end

function engine.crop_phase_to_pos(L, phase)
  local full_len = engine.get_full_len(L)
  local pos = L.crop_start + (phase % 1.0) * L.crop_len

  while pos >= L.full_loop_end do
    pos = pos - full_len
  end
  while pos < L.full_loop_start do
    pos = pos + full_len
  end

  return pos
end

function engine.jump_to_crop_phase(L, phase)
  local pos = engine.crop_phase_to_pos(L, phase)
  softcut.position(L.play_voice, pos)
  softcut.position(L.write_voice, pos)
  L.play_pos = pos
end

function engine.apply_jump(L)
  if not L.has_loop or L.is_recording or L.motion_recording then
    L.last_jump_step = nil
    return
  end

  local target_div = L.jump_div or 0
  local trigger_div = L.jump_trigger_div or 0

  if target_div <= 0 or trigger_div <= 0 then
    L.last_jump_step = nil
    return
  end

  local phase = engine.get_crop_phase(L)

  local trigger_step = math.floor(phase * trigger_div)
  if trigger_step >= trigger_div then trigger_step = trigger_div - 1 end

  if L.last_jump_step == nil then
    L.last_jump_step = trigger_step
    return
  end

  if trigger_step ~= L.last_jump_step then
    local target_step = math.random(0, target_div - 1)

    if target_div > 1 then
      local current_target_step = math.floor(phase * target_div)
      if current_target_step >= target_div then current_target_step = target_div - 1 end

      while target_step == current_target_step do
        target_step = math.random(0, target_div - 1)
      end
    end

    local target_phase = target_step / target_div
    engine.jump_to_crop_phase(L, target_phase)

    local new_phase = engine.get_crop_phase(L)
    local new_trigger_step = math.floor(new_phase * trigger_div)
    if new_trigger_step >= trigger_div then
      new_trigger_step = trigger_div - 1
    end

    L.last_jump_step = new_trigger_step
  end
end

return engine