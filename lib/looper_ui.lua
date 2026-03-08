local defs = include("lib/looper_defs")

local ui = {}

local function strip_source_looper(loopers)
  local l1 = loopers[1]
  local l2 = loopers[2]

  if l1.selected and not l2.selected then
    return l1
  elseif l2.selected and not l1.selected then
    return l2
  else
    -- both selected, or none selected: default to loop 1
    return l1
  end
end

function ui.grid_get_nearest_yval(target, y_vals)
  local selected_y = nil
  local best_dist = math.huge
  for id, y in ipairs(y_vals) do
    local dist = math.abs(y - target)
    if dist < best_dist then
      best_dist = dist
      selected_y = id
    end
  end
  return selected_y
end

function ui.grid_match_any(x, y, coords)
  for i = 1, #coords do
    if x == coords[i][1] and y == coords[i][2] then
      return true
    end
  end
  return false
end

function ui.ring_idx_in_crop_span(L, idx)
  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local crop_len = L.loop_end - L.loop_start

  -- no crop: full loop active, so don't show special crop highlight
  if math.abs(crop_len - full_len) < 0.0001 then
    return false
  end

  local n = #defs.TAPEHEAD_RING_PTS

  local crop_start_frac = util.clamp((L.loop_start - L.full_loop_start) / full_len, 0.0, 1.0)
  local crop_end_frac   = util.clamp((L.loop_end   - L.full_loop_start) / full_len, 0.0, 1.0)

  local seg_start = (idx - 1) / n
  local seg_end   = idx / n

  -- overlap test between loop crop and this ring sector
  return (crop_start_frac < seg_end) and (crop_end_frac > seg_start)
end

function ui.grid_tapehead_viz(g, L, x_topright, y_topright, dimval, cropval, heldval, playval, offset_mult)
  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local p = (L.play_pos - L.full_loop_start) / full_len
  p = util.clamp(p, 0.0, 1.0)

  local curr = (math.floor(p * #defs.TAPEHEAD_RING_PTS) % #defs.TAPEHEAD_RING_PTS) + 1

  for i = 1, #defs.TAPEHEAD_RING_PTS do
    local px = x_topright + defs.TAPEHEAD_RING_PTS[i][1] - 1
    local py = y_topright + defs.TAPEHEAD_RING_PTS[i][2] - 1

    local level = util.clamp(dimval + defs.TAPEHEAD_RING_LED_OFFSETS[i] * offset_mult, 0, 15)

    if ui.ring_idx_in_crop_span(L, i) then
      level = cropval
    end

    if L.held_ring_points[i] then
      level = heldval
    end

    if L.has_loop and i == curr then
      level = playval
    end

    g:led(px, py, level)
  end
end

function ui.grid_ring_hit(x, y, x_topright, y_topright)
  for i = 1, #defs.TAPEHEAD_RING_PTS do
    local px = x_topright + defs.TAPEHEAD_RING_PTS[i][1] - 1
    local py = y_topright + defs.TAPEHEAD_RING_PTS[i][2] - 1
    if x == px and y == py then
      return i
    end
  end
  return nil
end

function ui.grid_strip(g, on_x, on_y, bipolar, dimval, brightval)
  if bipolar then
    for y = 1, 8 do
      if dimval == -1 then
        g:led(on_x, y, math.min(math.abs(y-4), math.abs(y-5)) + 1)
      else
        g:led(on_x, y, dimval)
      end
    end
    if on_y == 4 or on_y == 5 then
      g:led(on_x, 4, brightval)
      g:led(on_x, 5, brightval)
    else
      g:led(on_x, on_y, brightval)
    end
  else
    for y = 1, 8 do
      if dimval == -1 then
        g:led(on_x, y, y == on_y and brightval or 9-y)
      else
        g:led(on_x, y, y == on_y and brightval or dimval)
      end
    end
  end
end

function ui.grid_led_any(g, coords, level)
  for i = 1, #coords do
    g:led(coords[i][1], coords[i][2], level)
  end
end

function ui.draw_loop_viz(L, cx, cy, r)
  screen.level(4)
  screen.move(cx + r, cy)
  screen.circle(cx, cy, r)
  screen.stroke()

  local denom = math.max(L.loop_end - L.loop_start, 0.0001)
  local p = (L.play_pos - L.loop_start) / denom
  p = util.clamp(p, 0.0, 1.0)

  local a = (-math.pi / 2) + (p * 2 * math.pi)
  local dx = cx + math.cos(a) * r
  local dy = cy + math.sin(a) * r

  screen.level(15)
  screen.circle(dx, dy, 2)
  screen.fill()
end

function ui.redraw(loopers, g, a, link_playheads, 
                   send_1_to_2, send_2_to_1,
                   send_1_to_2_enabled, send_2_to_1_enabled, arc_page)
  local L1 = loopers[1]
  local L2 = loopers[2]

  local function status_of(L)
    if L.is_recording then
      return "REC"
    elseif L.is_overdubbing then
      return "DUB"
    elseif L.has_loop then
      return "PLAY"
    else
      return "STOP"
    end
  end

  screen.clear()
  screen.level(15)

  screen.move(8, 10)
  screen.text("L1 " .. status_of(L1) .. "  r " .. string.format("%.2f", L1.rate))

  screen.move(8, 22)
  screen.text("L2 " .. status_of(L2) .. "  r " .. string.format("%.2f", L2.rate))

  screen.move(8, 36)
  screen.text(string.format("1>2 %.2f  2>1 %.2f", send_1_to_2, send_2_to_1))

  ui.draw_loop_viz(L1, 90, 48, 10)
  ui.draw_loop_viz(L2, 115, 48, 10)
  
  screen.move(8, 60)
  screen.text(link_playheads and "LINK ON" or "LINK OFF")

  screen.update()
end

function ui.grid_redraw(g, loopers, link_playheads, send_1_to_2, send_2_to_1, send_1_to_2_enabled, send_2_to_1_enabled, shift_held)
  if not g or not g.device then return end

  local L = strip_source_looper(loopers)

  g:all(0)

  local drywet_selected_y = ui.grid_get_nearest_yval(L.drywet, defs.DRYWET_VALUES)
  ui.grid_strip(g, defs.DRYWET_COL, drywet_selected_y, true, -1, 15)

  local overdub_selected_y = ui.grid_get_nearest_yval(L.overdub, defs.OVERDUB_VALUES)
  ui.grid_strip(g, defs.OVERDUB_COL, overdub_selected_y, false, -1, 15)

  local tape_selected_y = ui.grid_get_nearest_yval(L.tape_age, defs.TAPE_WARBLE_VALUES)
  ui.grid_strip(g, defs.TAPE_WARBLE_COL, tape_selected_y, false, -1, 15)

  local filter_selected_y = ui.grid_get_nearest_yval(L.dj_filter_freq, defs.FILTER_VALUES)
  ui.grid_strip(g, defs.FILTER_COL, filter_selected_y, true, -1, 15)

  local stp_speed_selected_y = ui.grid_get_nearest_yval(L.rate, defs.STP_SPEED_VALUES)
  ui.grid_strip(g, defs.STP_SPEED_COL, stp_speed_selected_y, true, -1, 15)
  
  local dropper_selected_y = ui.grid_get_nearest_yval(L.dropper_amt, defs.DROPPER_VALUES)
  ui.grid_strip(g, defs.DROPPER_COL, dropper_selected_y, false, -1, 15)
  
  local jump_selected_y = ui.grid_get_nearest_yval(L.jump_div, defs.JUMP_VALUES)
  ui.grid_strip(g, defs.JUMP_COL, jump_selected_y, false, -1, 15)
  
  ui.grid_tapehead_viz(
    g, loopers[1],
    defs.LEFT_RING_TOPRIGHT[1], defs.LEFT_RING_TOPRIGHT[2],
    6, 10, 12, 15, 1
  )

  ui.grid_tapehead_viz(
    g, loopers[2],
    defs.RIGHT_RING_TOPRIGHT[1], defs.RIGHT_RING_TOPRIGHT[2],
    6, 10, 12, 15, -1
  )
  
  ui.grid_led_any(g, defs.LOOPER1_SELECT_KEY, loopers[1].selected and 2 or 0)
  ui.grid_led_any(g, defs.LOOPER2_SELECT_KEY, loopers[2].selected and 2 or 0)

  ui.grid_led_any(g, defs.LINK_PLAYHEADS_KEY, link_playheads and 2 or 0)
  
  ui.grid_led_any(g, defs.SEND_1_TO_2_KEY, send_1_to_2_enabled and 2 or 0)
  ui.grid_led_any(g, defs.SEND_2_TO_1_KEY, send_2_to_1_enabled and 2 or 0)

  ui.grid_led_any(g, defs.ADDITIVE_KEY, L.additive_mode and 15 or 1)
  ui.grid_led_any(g, defs.REVERSE_KEY, L.is_reversed and 15 or 2)

  g:led(defs.SHORT_RATE_SLEW_KEY[1], defs.SHORT_RATE_SLEW_KEY[2], L.short_rate_slew and 15 or 2)
  g:led(defs.LONG_RATE_SLEW_KEY[1], defs.LONG_RATE_SLEW_KEY[2], L.long_rate_slew and 15 or 2)

  g:led(defs.REC_KEY[1], defs.REC_KEY[2], (L.is_recording or L.is_overdubbing) and 15 or 4)
  g:led(defs.SHIFT_KEY[1], defs.SHIFT_KEY[2], shift_held and 4 or 1)
  g:led(defs.CLEAR_KEY[1], defs.CLEAR_KEY[2], 4)

  g:refresh()
end

--------------------------------------------
-- ARC
--------------------------------------------

local function arc_rot(idx)
  return util.wrap(idx - 16, 1, 64)
end

local function frac_to_arc_idx(frac)
  return arc_rot(math.floor(frac * 64 + 0.5) + 1)
end

function ui.arc_draw_playhead(a, ring, L)
  for i = 1, 64 do
    a:led(ring, i, 0)
  end

  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local crop_start_frac = util.clamp((L.crop_start - L.full_loop_start) / full_len, 0.0, 1.0)
  local crop_len_frac = util.clamp(L.crop_len / full_len, 0.0, 1.0)
  local play_frac = util.clamp((L.play_pos - L.full_loop_start) / full_len, 0.0, 1.0)

  local start_idx = frac_to_arc_idx(crop_start_frac)
  local span = math.max(1, math.floor(crop_len_frac * 64 + 0.5))
  local pos = frac_to_arc_idx(play_frac)

  if crop_len_frac >= 0.999 then
    for i = 1, 64 do
      a:led(ring, i, 2)
    end
  else
    for k = 0, span do
      local idx = util.wrap(start_idx + k, 1, 64)
      a:led(ring, idx, 2)
    end
  end

  local offsets = {-3, -2, -1, 0, 1, 2, 3}
  local levels  = {2, 4, 7, 15, 7, 4, 2}
  for i = 1, #offsets do
    local idx = util.wrap(pos + offsets[i], 1, 64)
    a:led(ring, idx, levels[i])
  end
end

function ui.arc_draw_crop(a, ring, L)
  for i = 1, 64 do
    a:led(ring, i, 0)
  end

  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local frac = util.clamp((L.crop_len or full_len) / full_len, 0.0, 1.0)

  local lit = math.max(1, math.floor(frac * 64 + 0.5))
  if frac >= 0.999 then lit = 64 end

  for k = 0, lit - 1 do
    a:led(ring, arc_rot(1 + k), 10)
  end

  a:led(ring, arc_rot(lit), 15)
end

function ui.arc_draw_signed_speed(a, ring, L)
  for i = 1, 64 do
    a:led(ring, i, 1)
  end

  local r = L.is_reversed and -math.abs(L.rate) or math.abs(L.rate)
  r = util.clamp(r, -4.0, 4.0)

  local zero_idx = arc_rot(1)
  a:led(ring, zero_idx, 4)

  if math.abs(r) < 0.0001 then
    a:led(ring, zero_idx, 15)
    return
  end

  local mag = util.clamp(math.abs(r) / 4.0, 0.0, 1.0)
  local steps = math.max(1, math.floor(mag * 31.5 + 0.5))

  if r > 0 then
    for k = 1, steps do
      a:led(ring, util.wrap(zero_idx + k, 1, 64), 6)
    end
    a:led(ring, util.wrap(zero_idx + steps, 1, 64), 15)
  else
    for k = 1, steps do
      a:led(ring, util.wrap(zero_idx - k, 1, 64), 6)
    end
    a:led(ring, util.wrap(zero_idx - steps, 1, 64), 15)
  end
end

function ui.arc_draw_send(a, ring, amt)
  for i = 1, 64 do
    a:led(ring, i, 1)
  end

  local frac = util.clamp(amt / 0.5, 0.0, 1.0)
  local idx = util.clamp(math.floor(frac * 63) + 1, 1, 64)

  local zero_idx = arc_rot(1)

  for k = 0, idx - 1 do
    a:led(ring, util.wrap(zero_idx + k, 1, 64), 6)
  end

  a:led(ring, util.wrap(zero_idx + idx - 1, 1, 64), 15)
end

function ui.arc_draw_filter(a, ring, L)
  for i = 1, 64 do
    a:led(ring, i, 0)
  end

  local raw_idx = util.wrap(1 + math.floor(L.dj_filter_freq * 31.5), 1, 64)
  local idx = arc_rot(raw_idx)
  local zero_idx = arc_rot(1)

  local fill_lvl = 2

  if L.dj_filter_freq >= 0 then
    local steps = util.wrap(raw_idx - 1, 0, 63)
    for k = 1, steps do
      a:led(ring, arc_rot(1 + k), fill_lvl)
    end
  else
    local steps = util.wrap(1 - raw_idx, 0, 63)
    for k = 1, steps do
      a:led(ring, arc_rot(1 - k), fill_lvl)
    end
  end

  a:led(ring, zero_idx, 4)
  a:led(ring, idx, 15)
end

function ui.arc_draw_res(a, ring, L)
  for i = 1, 64 do
    a:led(ring, i, 1)
  end

  local rq_min, rq_max = 0.2, 1.2
  local res = util.clamp(1.0 - (L.dj_filter_res - rq_min) / (rq_max - rq_min), 0.0, 1.0)

  local lit = math.max(1, math.floor(res * 63) + 1)

  for i = 1, lit do
    a:led(ring, arc_rot(i), 8)
  end

  a:led(ring, arc_rot(lit), 15)
  a:led(ring, arc_rot(1), 4)
end

function ui.arc_redraw(a, loopers, arc_page, send_1_to_2, send_2_to_1)
  if not a or not a.device then return end
  a:all(0)

  if arc_page == 1 then
    ui.arc_draw_playhead(a, 1, loopers[1])
    ui.arc_draw_crop(a, 2, loopers[1])
    ui.arc_draw_playhead(a, 3, loopers[2])
    ui.arc_draw_crop(a, 4, loopers[2])

  elseif arc_page == 2 then
    ui.arc_draw_signed_speed(a, 1, loopers[1])
    ui.arc_draw_signed_speed(a, 2, loopers[2])
    ui.arc_draw_send(a, 3, send_1_to_2)
    ui.arc_draw_send(a, 4, send_2_to_1)

  elseif arc_page == 3 then
    ui.arc_draw_filter(a, 1, loopers[1])
    ui.arc_draw_res(a, 2, loopers[1])
    ui.arc_draw_filter(a, 3, loopers[2])
    ui.arc_draw_res(a, 4, loopers[2])
  end

  a:refresh()
end

return ui