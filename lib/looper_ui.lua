local defs = include("lib/looper_defs")

local ui = {}

local function ring_overlap_owner(x, y)
  local key = x .. "," .. y
  return defs.RING_OVERLAP_OWNERS[key]
end

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

function ui.grid_tapehead_viz(g, ring_owner_id, L, x_topright, y_topright, dimval, cropval, heldval, playval, offset_mult)
  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local p = (L.play_pos - L.full_loop_start) / full_len
  p = util.clamp(p, 0.0, 1.0)

  local curr = (math.floor(p * #defs.TAPEHEAD_RING_PTS) % #defs.TAPEHEAD_RING_PTS) + 1

  for i = 1, #defs.TAPEHEAD_RING_PTS do
    local px = x_topright + defs.TAPEHEAD_RING_PTS[i][1] - 1
    local py = y_topright + defs.TAPEHEAD_RING_PTS[i][2] - 1

    local owner = ring_overlap_owner(px, py)
    if owner ~= nil and owner ~= ring_owner_id then
      goto continue
    end

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
    ::continue::
  end
end

function ui.grid_ring_hit(x, y, ring_owner_id, x_topright, y_topright)
  local owner = ring_overlap_owner(x, y)
  if owner ~= nil and owner ~= ring_owner_id then
    return nil
  end

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
      local level = 0
      local active = false

      if on_y == 4 or on_y == 5 then
        active = (y == 4 or y == 5)
      elseif on_y < 4 then
        active = (y >= on_y and y <= 4)
      else -- on_y > 5
        active = (y >= 5 and y <= on_y)
      end

      if active then
        if dimval == -1 then
          level = (math.min(math.abs(y - 4), math.abs(y - 5)) + 1) * 2
        else
          level = dimval
        end
      end

      g:led(on_x, y, level)
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
        if y >= on_y then
          g:led(on_x, y, y == on_y and brightval or 9 - y)
        else
          g:led(on_x, y, 0)
        end
      else
        if y >= on_y then
          g:led(on_x, y, y == on_y and brightval or dimval)
        else
          g:led(on_x, y, 0)
        end
      end
    end
  end
end

function ui.split_grid_strip(g, on_x, top_on_y, bottom_on_y, dimval, brightval)
  local function draw_half(y_start, y_end, on_y)
    for y = y_start, y_end do
      local level = 0

      if on_y ~= nil and y >= on_y then
        if y == on_y then
          level = brightval
        elseif dimval == -1 then
          level = y_end - y + 1
        else
          level = dimval
        end
      end

      g:led(on_x, y, level)
    end
  end

  -- bottom half: rows 1..4
  draw_half(1, 4, bottom_on_y)

  -- top half: rows 5..8
  draw_half(5, 8, top_on_y)
end

function ui.grid_led_any(g, coords, level)
  for i = 1, #coords do
    g:led(coords[i][1], coords[i][2], level)
  end
end

-- ------------------------------------------------------------------
-- screen drawing
-- ------------------------------------------------------------------

local SCREEN_LEFT_CX  = 48
local SCREEN_LEFT_CY  = 28
local SCREEN_RIGHT_CX = 80
local SCREEN_RIGHT_CY = 36
local SCREEN_R        = 23
local SCREEN_RING_N   = 200

local function sample_circle(cx, cy, r, n)
  local pts = {}
  for i = 1, n do
    local frac = (i - 1) / n
    local a = -math.pi / 2 + frac * 2 * math.pi
    pts[i] = {
      x = cx + math.cos(a) * r,
      y = cy + math.sin(a) * r,
      nx = math.cos(a),
      ny = math.sin(a),
      frac = frac,
      a = a
    }
  end
  return pts
end

local SCREEN_PTS_1 = sample_circle(SCREEN_LEFT_CX, SCREEN_LEFT_CY, SCREEN_R, SCREEN_RING_N)
local SCREEN_PTS_2 = sample_circle(SCREEN_RIGHT_CX, SCREEN_RIGHT_CY, SCREEN_R, SCREEN_RING_N)

local SCREEN_PTS_1_INNER = sample_circle(SCREEN_LEFT_CX,  SCREEN_LEFT_CY,  SCREEN_R - 2, SCREEN_RING_N)
local SCREEN_PTS_2_INNER = sample_circle(SCREEN_RIGHT_CX, SCREEN_RIGHT_CY, SCREEN_R - 2, SCREEN_RING_N)

local SCREEN_UPPER_RIGHT_CROSS = { x = 66, y = 18, radius = 16, depth = 5 }
local SCREEN_LOWER_LEFT_CROSS  = { x = 62, y = 46, radius = 16, depth = 5 }
local SCREEN_CROSSINGS = { SCREEN_UPPER_RIGHT_CROSS, SCREEN_LOWER_LEFT_CROSS }

local function screen_dist2(x1, y1, x2, y2)
  local dx = x1 - x2
  local dy = y1 - y2
  return dx * dx + dy * dy
end

local function crossing_dent_mask(x, y, crossings)
  local mask = 1.0
  for i = 1, #crossings do
    local c = crossings[i]
    local d2 = screen_dist2(x, y, c.x, c.y)
    if d2 < c.radius * c.radius then
      local t = 1.0 - (d2 / (c.radius * c.radius)) -- 0 at edge, 1 at center
      mask = math.min(mask, 1.0 - t)               -- 1 at edge, 0 at center
    end
  end
  return mask
end

local function precompute_ring_masks(pts, owner_id)
  local masks = {}
  for i = 1, #pts do
    local p = pts[i]

    local owner_here = nil
    if screen_dist2(p.x, p.y, SCREEN_UPPER_RIGHT_CROSS.x, SCREEN_UPPER_RIGHT_CROSS.y) < SCREEN_UPPER_RIGHT_CROSS.radius * SCREEN_UPPER_RIGHT_CROSS.radius then
      owner_here = 2
    elseif screen_dist2(p.x, p.y, SCREEN_LOWER_LEFT_CROSS.x, SCREEN_LOWER_LEFT_CROSS.y) < SCREEN_LOWER_LEFT_CROSS.radius * SCREEN_LOWER_LEFT_CROSS.radius then
      owner_here = 1
    end

    if owner_here ~= nil and owner_here ~= owner_id then
      masks[i] = crossing_dent_mask(p.x, p.y, SCREEN_CROSSINGS)
    else
      masks[i] = 1.0
    end
  end
  return masks
end

local SCREEN_MASKS_1 = precompute_ring_masks(SCREEN_PTS_1, 1)
local SCREEN_MASKS_2 = precompute_ring_masks(SCREEN_PTS_2, 2)

local function screen_bucket_init()
  local buckets = {}
  for i = 1, 15 do
    buckets[i] = {}
  end
  return buckets
end

local function screen_bucket_px(buckets, x, y, level)
  x = math.floor(x + 0.5)
  y = math.floor(y + 0.5)
  level = math.floor(util.clamp(level, 0, 15) + 0.5)

  if x < 0 or x > 127 or y < 0 or y > 63 then
    return
  end

  if level <= 0 then
    return
  end

  local b = buckets[level]
  local n = #b
  b[n + 1] = x
  b[n + 2] = y
end

local function screen_bucket_flush(buckets)
  for level = 1, 15 do
    local pts = buckets[level]
    if #pts > 0 then
      screen.level(level)
      for i = 1, #pts, 2 do
        screen.pixel(pts[i], pts[i + 1])
      end
      screen.fill()
    end
  end
end

local function screen_pulse_boost(L)
  if L.is_recording or L.is_overdubbing then
    return ((math.sin(util.time() * math.pi * 4) + 1) * 0.5) * 2
  end
  return 0
end

local function screen_base_level(L)
  if L.is_recording or L.is_overdubbing then
    return 8 + screen_pulse_boost(L) * 7
  elseif L.has_loop then
    return 8
  else
    return 2
  end
end

local function screen_has_crop(L)
  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local crop_len = math.max(L.crop_len or full_len, 0.0001)
  return math.abs(crop_len - full_len) > 0.0001
end

local function screen_full_phase(L)
  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  return util.clamp((L.play_pos - L.full_loop_start) / full_len, 0.0, 0.999999)
end

local function screen_frac_in_crop(L, frac)
  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local crop_len = math.max(L.crop_len or full_len, 0.0001)

  if math.abs(crop_len - full_len) < 0.0001 then
    return false
  end

  local s = util.clamp((L.crop_start - L.full_loop_start) / full_len, 0.0, 1.0)
  local e = s + util.clamp(crop_len / full_len, 0.0, 1.0)

  if e <= 1.0 then
    return frac >= s and frac <= e
  else
    return frac >= s or frac <= (e - 1.0)
  end
end

local function frac_to_pt_idx(pts, frac)
  local n = #pts
  local idx = math.floor((frac % 1.0) * n + 0.5) + 1
  if idx > n then idx = 1 end
  return idx
end

local function draw_crop_boundary_bars(L, pts, buckets)
  if not screen_has_crop(L) then
    return
  end

  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local crop_start_frac = util.clamp((L.crop_start - L.full_loop_start) / full_len, 0.0, 1.0)
  local crop_len_frac = util.clamp((L.crop_len or full_len) / full_len, 0.0, 1.0)
  local crop_end_frac = (crop_start_frac + crop_len_frac) % 1.0

  local start_i = frac_to_pt_idx(pts, crop_start_frac)
  local end_i   = frac_to_pt_idx(pts, crop_end_frac)

  local bar_len = 3

  local function add_bar(p)
    for k = 0, bar_len do
      local x = p.x + p.nx * k
      local y = p.y + p.ny * k
      screen_bucket_px(buckets, x, y, 15)
    end
  end

  add_bar(pts[start_i])
  add_bar(pts[end_i])
end

local function draw_ring_segmented(L, pts, masks, buckets)
  local base = screen_base_level(L)
  local has_crop = screen_has_crop(L)
  local play_frac = screen_full_phase(L)

  local play_i = nil
  if L.has_loop then
    if L.has_loop then
      play_i = frac_to_pt_idx(pts, play_frac)
    end
  end

  for i = 1, #pts do
    local p = pts[i]
    local level = base

    if has_crop and screen_frac_in_crop(L, p.frac) then
      level = 15
    end

    level = level * masks[i]

    if L.has_loop and play_i ~= nil then
      local dist = math.abs(i - play_i)
      dist = math.min(dist, #pts - dist)

      if dist == 0 then
        level = 0
      elseif dist == 1 then
        level = math.max(0, level - 8)
      elseif dist == 2 then
        level = math.max(0, level - 4)
      end
    end

    screen_bucket_px(buckets, p.x, p.y, level)
  end

  draw_crop_boundary_bars(L, pts, buckets)
end

local function draw_link_overlap_glow(buckets)
  local t = util.time()
  local breath = 0.78 + 0.22 * math.sin(2 * math.pi * 0.5 * t)

  local cx1, cy1 = 40, 32
  local cx2, cy2 = 88, 32
  local r = 26

  local x0 = math.floor(math.min(cx1 - r, cx2 - r))
  local x1 = math.floor(math.max(cx1 + r, cx2 + r))
  local y0 = math.floor(math.min(cy1 - r, cy2 - r))
  local y1 = math.floor(math.max(cy1 + r, cy2 + r))

  for x = x0, x1 do
    for y = y0, y1 do
      local d1 = math.sqrt((x - cx1) * (x - cx1) + (y - cy1) * (y - cy1))
      local d2 = math.sqrt((x - cx2) * (x - cx2) + (y - cy2) * (y - cy2))

      if d1 <= r and d2 <= r then
        -- depth inside each circle
        local in1 = r - d1
        local in2 = r - d2

        -- overlap strength is limited by how deep we are in both discs
        local overlap = math.min(in1, in2) / r
        overlap = util.clamp(overlap, 0, 1)

        -- slightly stronger in the vertical middle of the lens
        local y_mid_weight = 1.0 - math.min(math.abs(y - 32) / 18, 1.0)
        local level = (2 + 10 * overlap * (0.65 + 0.35 * y_mid_weight)) * breath

        screen_bucket_px(buckets, x, y, level)
      end
    end
  end
end

local function draw_disc_fill(buckets, cx, cy, r, level)
  for x = math.floor(cx - r), math.floor(cx + r) do
    for y = math.floor(cy - r), math.floor(cy + r) do
      local dx = x - cx
      local dy = y - cy
      if dx * dx + dy * dy <= r * r then
        screen_bucket_px(buckets, x, y, level)
      end
    end
  end
end

local function draw_additive_plus(cx, cy, level)
  screen.level(level)
  screen.move(cx - 3, cy)
  screen.line(cx + 2, cy)
  screen.stroke()
  screen.move(cx, cy - 3)
  screen.line(cx, cy + 2)
  screen.stroke()
end

local function draw_interlocking_loops(L1, L2)
  local buckets = screen_bucket_init()

  -- extra inner ring to thicken selected loopers
  if L1.selected then
    draw_ring_segmented(L1, SCREEN_PTS_1_INNER, SCREEN_MASKS_1, buckets)
  end
  if L2.selected then
    draw_ring_segmented(L2, SCREEN_PTS_2_INNER, SCREEN_MASKS_2, buckets)
  end

  -- main rings
  draw_ring_segmented(L1, SCREEN_PTS_1, SCREEN_MASKS_1, buckets)
  draw_ring_segmented(L2, SCREEN_PTS_2, SCREEN_MASKS_2, buckets)

  screen_bucket_flush(buckets)

  -- additive markers
  if L1.additive_mode then
    draw_additive_plus(SCREEN_LEFT_CX, SCREEN_LEFT_CY, 1)
  end
  if L2.additive_mode then
    draw_additive_plus(SCREEN_RIGHT_CX, SCREEN_RIGHT_CY, 1)
  end
end

local function screen_label_triplet(x, y,
                                    line1_txt, line1_level,
                                    line2_txt, line2_level,
                                    line3_txt, line3_level,
                                    align_right)
  screen.level(line1_level)
  if align_right then
    screen.move(x, y)
    screen.text_right(line1_txt)
  else
    screen.move(x, y)
    screen.text(line1_txt)
  end

  screen.level(line2_level)
  if align_right then
    screen.move(x, y + 8)
    screen.text_right(line2_txt)
  else
    screen.move(x, y + 8)
    screen.text(line2_txt)
  end

  screen.level(line3_level)
  if align_right then
    screen.move(x, y + 16)
    screen.text_right(line3_txt)
  else
    screen.move(x, y + 16)
    screen.text(line3_txt)
  end
end

local function fmt_num(v)
  return string.format("%.2f", v or 0)
end

local function ui_active_level(is_on)
  return is_on and 12 or 4
end

local function ui_selected_looper(loopers)
  for _, L in ipairs(loopers) do
    if L.selected then
      return L
    end
  end
  return loopers[1]
end

local function ui_crop_frac(L)
  local full_len = math.max(L.full_loop_end - L.full_loop_start, 0.0001)
  local crop_len = math.max(L.crop_len or full_len, 0.0001)
  return util.clamp(crop_len / full_len, 0.0, 1.0)
end

local function ui_mix_on(L)
  return math.abs((L.drywet or 0.5) - 0.5) > 0.001
end

local function ui_dub_on(L)
  return math.abs((L.overdub or 1.0) - 1.0) > 0.001
end

local function ui_tape_on(L)
  return (L.tape_age or 0.0) > 0.001
end

local function ui_drop_on(L)
  return (L.dropper_amt or 0.0) > 0.001
end

local function ui_rate_on(L)
  return math.abs((L.rate or 1.0) - 1.0) > 0.001
end

local function draw_norns_help_labels(loopers, link_playheads,
                                      k1_held, k2_held, k3_held,
                                      k1_down_time, k2_down_time, k3_down_time)
  local now = util.time()
  local delay = 0.5

  local k1_show_shift = k1_held and k1_down_time ~= nil and (now - k1_down_time >= delay)
  local k2_show_shift = k2_held and k2_down_time ~= nil and (now - k2_down_time >= delay)
  local k3_show_shift = k3_held and k3_down_time ~= nil and (now - k3_down_time >= delay)

  local LS = ui_selected_looper(loopers)
  local L1 = loopers[1]
  local L2 = loopers[2]

  local tl_l1, tl_l1_level, tl_l2, tl_l2_level, tl_l3, tl_l3_level
  local bl_l1, bl_l1_level, bl_l2, bl_l2_level, bl_l3, bl_l3_level
  local br_l1, br_l1_level, br_l2, br_l2_level, br_l3, br_l3_level

  -- TOP LEFT = K1 / ENC1
  if k1_show_shift then
    tl_l1 = "sel"
    tl_l1_level = 4
    tl_l2 = "dub"
    tl_l2_level = ui_active_level(ui_dub_on(LS))
    tl_l3 = fmt_num(LS.overdub or 1.0)
    tl_l3_level = ui_active_level(ui_dub_on(LS))
  elseif k2_show_shift then
    tl_l1 = "rec"
    tl_l1_level = ui_active_level(LS.is_recording or LS.is_overdubbing)
    tl_l2 = "tape"
    tl_l2_level = ui_active_level(ui_tape_on(LS))
    tl_l3 = fmt_num(LS.tape_age or 0.0)
    tl_l3_level = ui_active_level(ui_tape_on(LS))
  elseif k3_show_shift then
    tl_l1 = "clr"
    tl_l1_level = 4
    tl_l2 = "drop"
    tl_l2_level = ui_active_level(ui_drop_on(LS))
    tl_l3 = fmt_num(LS.dropper_amt or 0.0)
    tl_l3_level = ui_active_level(ui_drop_on(LS))
  else
    tl_l1 = "sel"
    tl_l1_level = 4
    tl_l2 = "mix"
    tl_l2_level = ui_active_level(ui_mix_on(LS))
    tl_l3 = fmt_num(LS.drywet or 0.5)
    tl_l3_level = ui_active_level(ui_mix_on(LS))
  end

  -- BOTTOM LEFT = K2 / ENC2
  if k1_show_shift then
    bl_l1 = "sel1"
    bl_l1_level = ui_active_level(L1.selected)
    bl_l2 = "crop1"
    bl_l2_level = ui_active_level(screen_has_crop(L1))
    bl_l3 = fmt_num(ui_crop_frac(L1))
    bl_l3_level = ui_active_level(screen_has_crop(L1))
  elseif k2_show_shift then
    bl_l1 = "rec"
    bl_l1_level = ui_active_level(LS.is_recording or LS.is_overdubbing)
    bl_l2 = "step1"
    bl_l2_level = ui_active_level(ui_rate_on(L1))
    bl_l3 = fmt_num(L1.rate or 1.0)
    bl_l3_level = ui_active_level(ui_rate_on(L1))
  elseif k3_show_shift then
    bl_l1 = "add"
    bl_l1_level = ui_active_level(LS.additive_mode)
    bl_l2 = "free1"
    bl_l2_level = ui_active_level(ui_rate_on(L1))
    bl_l3 = fmt_num(L1.rate or 1.0)
    bl_l3_level = ui_active_level(ui_rate_on(L1))
  else
    bl_l1 = "rec"
    bl_l1_level = ui_active_level(LS.is_recording or LS.is_overdubbing)
    bl_l2 = "pos1"
    bl_l2_level = 4
    bl_l3 = fmt_num(screen_full_phase(L1))
    bl_l3_level = 4
  end

  -- BOTTOM RIGHT = K3 / ENC3
  if k1_show_shift then
    br_l1 = "sel2"
    br_l1_level = ui_active_level(L2.selected)
    br_l2 = "crop2"
    br_l2_level = ui_active_level(screen_has_crop(L2))
    br_l3 = fmt_num(ui_crop_frac(L2))
    br_l3_level = ui_active_level(screen_has_crop(L2))
  elseif k2_show_shift then
    br_l1 = "add"
    br_l1_level = ui_active_level(LS.additive_mode)
    br_l2 = "step2"
    br_l2_level = ui_active_level(ui_rate_on(L2))
    br_l3 = fmt_num(L2.rate or 1.0)
    br_l3_level = ui_active_level(ui_rate_on(L2))
  elseif k3_show_shift then
    br_l1 = "clr"
    br_l1_level = 4
    br_l2 = "free2"
    br_l2_level = ui_active_level(ui_rate_on(L2))
    br_l3 = fmt_num(L2.rate or 1.0)
    br_l3_level = ui_active_level(ui_rate_on(L2))
  else
    br_l1 = "clr"
    br_l1_level = 4
    br_l2 = "pos2"
    br_l2_level = 4
    br_l3 = fmt_num(screen_full_phase(L2))
    br_l3_level = 4
  end

  screen_label_triplet(0, 6,
    tl_l1, tl_l1_level,
    tl_l2, tl_l2_level,
    tl_l3, tl_l3_level,
    false
  )
  
  screen_label_triplet(0, 48,
    bl_l1, bl_l1_level,
    bl_l2, bl_l2_level,
    bl_l3, bl_l3_level,
    false
  )
  
  screen_label_triplet(128, 48,
    br_l1, br_l1_level,
    br_l2, br_l2_level,
    br_l3, br_l3_level,
    true
  )
end

local function motion_level(L)
  if L.motion_recording then
    return 15
  elseif L.motion_has_data and L.motion_playback then
    return 8
  elseif L.motion_has_data then
    return 3
  else
    return 1
  end
end

local function draw_status_stack(loopers, link_playheads,
                                 send_1_to_2, send_2_to_1,
                                 send_1_to_2_enabled, send_2_to_1_enabled)
  local L1 = loopers[1]
  local L2 = loopers[2]

  local x = 124
  local y0 = 8
  local dy = 8

  screen.font_size(8)

  -- row 1: linked playheads
  screen.level(link_playheads and 10 or 1)
  screen.move(x+1, y0)
  screen.font_size(11)
  screen.text_right("∞")
  screen.font_size(8)

  -- row 2: send scaffold + highlighted direction
  local s12 = send_1_to_2_enabled and (send_1_to_2 or 0) > 0.0001
  local s21 = send_2_to_1_enabled and (send_2_to_1 or 0) > 0.0001

  local y_send = y0 + dy
  local x_left  = x - 8
  local x_mid   = x - 4
  local x_right = x - 0
  
  -- faint scaffold
  screen.level(2)
  screen.move(x_left,  y_send) screen.text("<")
  screen.move(x_mid,   y_send) screen.text("-")
  screen.move(x_right, y_send) screen.text(">")
  
  -- brighten active directions exactly on top
  if s21 then
    screen.level(10)
    screen.move(x_left, y_send) screen.text("<")
    screen.move(x_mid,  y_send) screen.text("-")
  end
  
  if s12 then
    screen.level(10)
    screen.move(x_mid,   y_send) screen.text("-")
    screen.move(x_right, y_send) screen.text(">")
  end

  -- row 3: one bullet per looper
  local ml1 = motion_level(L1)
  local ml2 = motion_level(L2)

  screen.level(ml1)
  screen.move(x - 6, y0 + 2 * dy)
  screen.text("•")

  screen.level(ml2)
  screen.move(x - 1, y0 + 2 * dy)
  screen.text("•")
end

function ui.redraw(loopers, g, a, link_playheads,
                   send_1_to_2, send_2_to_1,
                   send_1_to_2_enabled, send_2_to_1_enabled, arc_page,
                   k1_held, k2_held, k3_held,
                   k1_down_time, k2_down_time, k3_down_time)
  local L1 = loopers[1]
  local L2 = loopers[2]

  screen.clear()
  draw_interlocking_loops(L1, L2)
  draw_norns_help_labels(
    loopers, link_playheads,
    k1_held, k2_held, k3_held,
    k1_down_time, k2_down_time, k3_down_time
  )
  draw_status_stack(
    loopers, link_playheads,
    send_1_to_2, send_2_to_1,
    send_1_to_2_enabled, send_2_to_1_enabled
  )
  screen.update()
end

-- ------------------------------------------------------------------
-- grid drawing
-- ------------------------------------------------------------------

function ui.grid_redraw(g, loopers, link_playheads,
                        send_1_to_2, send_2_to_1,
                        send_1_to_2_enabled, send_2_to_1_enabled,
                        shift_held, mod_shift_held,
                        snapshot_1_filled, snapshot_2_filled,
                        snapshot_flash_kind)
  if not g or not g.device then return end

  local L = strip_source_looper(loopers)
  
  local t = util.time()

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
  
  local jump_target_y = nil
  for y = 5, 8 do
    if defs.JUMP_TARGET_VALUES[y] == L.jump_div then
      jump_target_y = y
      break
    end
  end

  local jump_trigger_y = nil
  for y = 1, 4 do
    if defs.JUMP_TRIGGER_VALUES[y] == (L.jump_trigger_div or 0) then
      jump_trigger_y = y
      break
    end
  end

  ui.split_grid_strip(g, defs.JUMP_COL, jump_target_y, jump_trigger_y, -1, 15)
  
  local function ring_levels(L)
    local dimval, cropval
    if L.selected then
      if L.is_recording or L.is_overdubbing then
        local s = 0.5 + 0.5 * math.sin(2 * math.pi * 2.0 * t) -- 2 Hz pulse
        dimval  = math.floor(5 + s * 5)   -- about 5..10
        cropval = math.floor(9 + s * 4)   -- about 9..13
      else
        dimval  = 8
        cropval = 12
      end
    else
      dimval  = 3
      cropval = 5
    end
    return dimval, cropval
  end

  local l1_dim, l1_crop = ring_levels(loopers[1])
  local l2_dim, l2_crop = ring_levels(loopers[2])

  ui.grid_tapehead_viz(
    g, 1, loopers[1],
    defs.LEFT_RING_TOPRIGHT[1], defs.LEFT_RING_TOPRIGHT[2],
    l1_dim, l1_crop, 12, 15, 1
  )
  
  ui.grid_tapehead_viz(
    g, 2, loopers[2],
    defs.RIGHT_RING_TOPRIGHT[1], defs.RIGHT_RING_TOPRIGHT[2],
    l2_dim, l2_crop, 12, 15, -1
  )
  
  local s = 0.5 + 0.5 * math.sin(2 * math.pi * 1.0 * t)
  ui.grid_led_any(g, defs.LINK_PLAYHEADS_KEY, link_playheads and math.floor(1 + s * 3) or 0)

  -- ui.grid_led_any(g, defs.LINK_PLAYHEADS_KEY, link_playheads and 2 or 0)
  
  ui.grid_led_any(g, defs.SEND_1_TO_2_KEY, send_1_to_2_enabled and math.floor(1 + s * 3) or 0)
  ui.grid_led_any(g, defs.SEND_2_TO_1_KEY, send_2_to_1_enabled and math.floor(1 + s * 3) or 0)

  local function motion_led_level(L)
    if L.motion_recording then
      -- fast blink ~4 Hz
      return ((math.floor(t * 8) % 2) == 0) and 15 or 2
    elseif L.motion_playback and L.motion_has_data then
      -- breathe at 0.5 Hz
      local s = 0.5 + 0.5 * math.sin(2 * math.pi * 0.5 * t)
      return math.floor(3 + s * 12)
    elseif L.motion_has_data then
      return 6
    else
      return 1
    end
  end

  g:led(defs.MOTION1_KEY[1], defs.MOTION1_KEY[2], motion_led_level(loopers[1]))
  g:led(defs.MOTION2_KEY[1], defs.MOTION2_KEY[2], motion_led_level(loopers[2]))

  ui.grid_led_any(g, defs.ADDITIVE_KEY, L.additive_mode and 15 or 1)
  ui.grid_led_any(g, defs.REVERSE_KEY, L.is_reversed and 15 or 2)

  local slew_led = 2
  if L.rate_slew_mode == 1 then
    slew_led = 6
  elseif L.rate_slew_mode == 2 then
    slew_led = 12
  end
  
  g:led(defs.RATE_SLEW_KEY[1], defs.RATE_SLEW_KEY[2], slew_led)

  g:led(defs.REC_KEY[1], defs.REC_KEY[2], (L.is_recording or L.is_overdubbing) and 15 or 4)
  g:led(defs.MOD_SHIFT_KEY[1], defs.MOD_SHIFT_KEY[2], mod_shift_held and 8 or 2)
  g:led(defs.SHIFT_KEY[1], defs.SHIFT_KEY[2], shift_held and 8 or 3)
  
  local snap_level = 1
  if snapshot_1_filled and snapshot_2_filled then
    snap_level = 15
  elseif snapshot_2_filled then
    snap_level = 12
  elseif snapshot_1_filled then
    snap_level = 8
  end
  
  if snapshot_flash_kind == "store" then
    snap_level = 10
  elseif snapshot_flash_kind == "recall" then
    snap_level = 15
  elseif snapshot_flash_kind == "overwrite" then
    snap_level = 15
  elseif snapshot_flash_kind == "overwrite_2" then
    snap_level = 8
  elseif snapshot_flash_kind == "delete" then
    snap_level = 0
  end
  
  g:led(defs.SNAPSHOT_KEY[1], defs.SNAPSHOT_KEY[2], snap_level)

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

  local function speed_to_steps(rate)
    local mag = util.clamp(math.abs(rate) / 4.0, 0.0, 1.0)
    return math.max(1, math.floor(mag * 31.5 + 0.5))
  end

  local function signed_step_idx(steps, sign)
    local zero_idx = arc_rot(1)
    if sign >= 0 then
      return util.wrap(zero_idx + steps, 1, 64)
    else
      return util.wrap(zero_idx - steps, 1, 64)
    end
  end

  local function is_close(x, y, tol)
    return math.abs(x - y) <= tol
  end

  local octave_vals = {0.25, 0.5, 1.0, 2.0, 4.0}
  local fifth_vals  = {0.75, 1.5, 3.0}

  local r = L.is_reversed and -math.abs(L.rate) or math.abs(L.rate)
  r = util.clamp(r, -4.0, 4.0)

  local zero_idx = arc_rot(1)
  local abs_r = math.abs(r)

  -- tolerance for "we are on this musically meaningful value"
  local snap_tol = 0.04

  local on_octave = false
  local on_fifth = false

  for _, v in ipairs(octave_vals) do
    if is_close(abs_r, v, snap_tol) then
      on_octave = true
      break
    end
  end

  if not on_octave then
    for _, v in ipairs(fifth_vals) do
      if is_close(abs_r, v, snap_tol) then
        on_fifth = true
        break
      end
    end
  end

  local boost = on_octave and 2 or (on_fifth and 1 or 0)

  -- zero marker
  a:led(ring, zero_idx, math.min(15, 4 + boost))

  -- guide ticks: octaves bright, fifths dimmer
  for _, v in ipairs(octave_vals) do
    local steps = speed_to_steps(v)
    a:led(ring, signed_step_idx(steps,  1), math.min(15, 8 + boost))
    a:led(ring, signed_step_idx(steps, -1), math.min(15, 8 + boost))
  end

  for _, v in ipairs(fifth_vals) do
    local steps = speed_to_steps(v)
    a:led(ring, signed_step_idx(steps,  1), math.min(15, 2 + boost))
    a:led(ring, signed_step_idx(steps, -1), math.min(15, 2 + boost))
  end

  if abs_r < 0.0001 then
    a:led(ring, zero_idx, 15)
    return
  end

  local steps = speed_to_steps(r)

  if r > 0 then
    for k = 1, steps do
      local idx = util.wrap(zero_idx + k, 1, 64)
      a:led(ring, idx, math.min(15, 6 + boost))
    end
    a:led(ring, util.wrap(zero_idx + steps, 1, 64), 15)
  else
    for k = 1, steps do
      local idx = util.wrap(zero_idx - k, 1, 64)
      a:led(ring, idx, math.min(15, 6 + boost))
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