-- MUTA page drawing module
-- V10.1 PHASE 9ABC PAGES
--
-- First real page draw extraction.
-- State remains owned by muta.lua and is passed as ctx.

local M = {}

function M.draw_mix(ctx)
  local screen = screen
  local selected_track, selected_step = ctx.selected_track, ctx.selected_step
  local subpage = ctx.subpage or 1
  local fx, mix, out, global, eq = ctx.fx, ctx.mix, ctx.out, ctx.global, ctx.eq
  local data, audio_safe = ctx.data, ctx.audio_safe
  local fx_focus, mix_focus, mix_page, out_focus, OUT_PAGE = ctx.fx_focus, ctx.mix_focus, ctx.mix_page, ctx.out_focus, ctx.OUT_PAGE
  local clock_page, global_focus, arp_focus, arp_page, eq_focus, shift = ctx.clock_page, ctx.global_focus, ctx.arp_focus, ctx.arp_page, ctx.eq_focus, ctx.shift
  local CROW_MOD = ctx.CROW_MOD
  local out_dest_names, midi_mode_names, cv_mode_names, out_clock_names = ctx.out_dest_names, ctx.midi_mode_names, ctx.cv_mode_names, ctx.out_clock_names
  local CROW_IN1_MODE_NAMES, CROW_IN2_MODE_NAMES = ctx.CROW_IN1_MODE_NAMES, ctx.CROW_IN2_MODE_NAMES
  local arp_mode_name, ensure_step_arp = ctx.arp_mode_name, ctx.ensure_step_arp
  local eq_edit_target, ensure_eq_table = ctx.eq_edit_target, ctx.ensure_eq_table
  local clamp = ctx.clamp
  local muta_ui, muta_draw = ctx.muta_ui, ctx.muta_draw
  local draw_page_header, draw_step_page_header, draw_page_footer = ctx.draw_page_header, ctx.draw_step_page_header, ctx.draw_page_footer
  draw_header(mix_page == 2 and "MUTA > MIX > DYN" or "MUTA > MIX", mix_page, 2)

  if mix_page == 2 then
    local vals = {mix.comp, mix.threshold, mix.ratio, mix.limiter}
    local labels = {"comp", "thresh", "ratio", "limit"}
    for i=1,4 do
      draw_knob(18 + (i-1)*31, 30, labels[i], vals[i], mix_focus == i)
    end
    screen.level(4)
    screen.move(2, 62); screen.text("K3:LEVEL")
    screen.move(64, 62); screen.text_center("E2:SEL")
    screen.move(126, 62); screen.text_right("E3:VAL")
    return
  end

  local vals = {mix.main, mix.phones}
  local labels = {"master", "cue"}
  local cells = 12
  for i=1,2 do
    local y = 28 + i * 8
    screen.level(i == mix_focus and 15 or 9)
    if i == mix_focus then
      screen.rect(2, y-6, 45, 7)
      screen.stroke()
    end
    screen.move(7, y)
    screen.text(labels[i])
    screen.move(69, y)
    screen.text_right(math.floor(vals[i] * 100 + 0.5) .. "%")

    -- LED-style bargraph: lightweight rectangles, no continuous redraw cost.
    local filled = math.floor(vals[i] * cells + 0.5)
    local x0 = 74
    for c=1,cells do
      local x = x0 + (c-1) * 4
      screen.level(c <= filled and (i == mix_focus and 15 or 10) or 2)
      screen.rect(x, y-5, 2, 5)
      screen.fill()
    end
  end
  screen.level(4)
  screen.move(2, 62); screen.text("K3:DYN")
  screen.move(64, 62); screen.text_center("E2:SEL")
  screen.move(126, 62); screen.text_right("E3:VOL")
end

function M.draw_out(ctx)
  local screen = screen
  local selected_track, selected_step = ctx.selected_track, ctx.selected_step
  local subpage = ctx.subpage or 1
  local fx, mix, out, global, eq = ctx.fx, ctx.mix, ctx.out, ctx.global, ctx.eq
  local data, audio_safe = ctx.data, ctx.audio_safe
  local fx_focus, mix_focus, mix_page, out_focus, OUT_PAGE = ctx.fx_focus, ctx.mix_focus, ctx.mix_page, ctx.out_focus, ctx.OUT_PAGE
  local clock_page, global_focus, arp_focus, arp_page, eq_focus, shift = ctx.clock_page, ctx.global_focus, ctx.arp_focus, ctx.arp_page, ctx.eq_focus, ctx.shift
  local CROW_MOD = ctx.CROW_MOD
  local out_dest_names, midi_mode_names, cv_mode_names, out_clock_names = ctx.out_dest_names, ctx.midi_mode_names, ctx.cv_mode_names, ctx.out_clock_names
  local CROW_IN1_MODE_NAMES, CROW_IN2_MODE_NAMES = ctx.CROW_IN1_MODE_NAMES, ctx.CROW_IN2_MODE_NAMES
  local arp_mode_name, ensure_step_arp = ctx.arp_mode_name, ctx.ensure_step_arp
  local eq_edit_target, ensure_eq_table = ctx.eq_edit_target, ctx.ensure_eq_table
  local clamp = ctx.clamp
  local muta_ui, muta_draw = ctx.muta_ui, ctx.muta_draw
  local draw_page_header, draw_step_page_header, draw_page_footer = ctx.draw_page_header, ctx.draw_step_page_header, ctx.draw_page_footer
  -- V10.0 OUT/CLOCK UI fix:
  -- OUT has four real pages and each page owns its own focus range.
  -- Previous versions displayed OUT 4/4 in code but K3/Grid still wrapped 1..3,
  -- and pages 2/4..4/4 used out_focus == 1 for hidden editable rows. This made
  -- pages visible but effectively non-navigable. Focus now follows visible rows.
  if OUT_PAGE == 2 then
    draw_header("MUTA > CV OUT 2/4", 2, 4)
    local rows = {
      {"cv1", (out.cv_mode == 2) and "mutation" or "pitch"},
      {"cv2", (out.cv_mode == 2) and "phase" or "gate"},
      {"cv3", string.format("%.2fV", (CROW_MOD and CROW_MOD.cv3) or 0)},
      {"cv4", string.format("%.2fV", (CROW_MOD and CROW_MOD.cv4) or 0)},
      {"mode", cv_mode_names[out.cv_mode or 1]},
    }
    for i,r in ipairs(rows) do
      local y = 14 + i * 8
      local editable = (i == 5)
      local focused = (out_focus == i)
      screen.level(focused and 15 or (editable and 10 or 5))
      if focused then screen.rect(3, y-5, 44, 7); screen.stroke() end
      screen.move(8, y); screen.text(r[1])
      screen.move(122, y); screen.text_right(r[2])
    end
    screen.level(3)
    screen.move(2, 61); screen.text("K3:CLK")
    screen.move(126, 61); screen.text_right(out_focus == 5 and "E3:MODE" or "E2:SEL")
  elseif OUT_PAGE == 3 then
    draw_header("MUTA > CROW CLK 3/4", 3, 4)
    local clk_age = 999
    if CROW_MOD and CROW_MOD.last_clock and CROW_MOD.last_clock > 0 then
      clk_age = util.time() - CROW_MOD.last_clock
    end
    local clk_status = (out.crow_in1 and out.crow_in1 > 1 and clk_age < 0.35) and "pulse" or ((out.crow_in1 and out.crow_in1 > 1) and "wait" or "off")
    local volt = (CROW_MOD and CROW_MOD.last_clock_v) or 0
    local mode = (CROW_MOD and CROW_MOD.clock_mode) or "--"
    local rows = {
      {"in1", CROW_IN1_MODE_NAMES[out.crow_in1 or 1]},
      {"edge", clk_status .. " " .. tostring((CROW_MOD and CROW_MOD.clock_count) or 0)},
      {"volt", string.format("%.2fV", volt)},
      {"src", clock_source_name() .. " / " .. mode},
      {"run", playing and "armed" or "stopped"},
    }
    for i,r in ipairs(rows) do
      local y = 14 + i * 8
      local editable = (i == 1)
      local focused = (out_focus == i)
      screen.level(focused and 15 or (editable and 10 or 5))
      if focused then screen.rect(3, y-5, 44, 7); screen.stroke() end
      screen.move(8, y); screen.text(r[1])
      screen.move(122, y); screen.text_right(r[2])
    end
    screen.level(3)
    screen.move(2, 61); screen.text("K3:IN2")
    screen.move(126, 61); screen.text_right(out_focus == 1 and "E3:MODE" or "PLAY=ARM")
  elseif OUT_PAGE == 4 then
    draw_header("MUTA > CROW IN2 4/4", 4, 4)
    local in2_status = "--"
    if CROW_MOD and CROW_MOD.last_in2 ~= nil then
      in2_status = string.format("%.2fV", CROW_MOD.last_in2 or 0)
    end
    local mod_label = "--"
    if out.crow_in2 == 2 then mod_label = "mutation"
    elseif out.crow_in2 == 3 then mod_label = "evolution"
    elseif out.crow_in2 == 4 then mod_label = "density"
    elseif out.crow_in2 == 5 then mod_label = "root " .. tostring((CROW_MOD and CROW_MOD.root) or 0)
    elseif out.crow_in2 and out.crow_in2 >= 6 then mod_label = "event" end
    local rows = {
      {"in2", CROW_IN2_MODE_NAMES[out.crow_in2 or 1]},
      {"volt", in2_status},
      {"gate", tostring((CROW_MOD and CROW_MOD.in2_count) or 0)},
      {"mod", mod_label},
      {"amt", string.format("%d%%", math.floor(((CROW_MOD and CROW_MOD.value) or 0) * 100 + 0.5))},
    }
    for i,r in ipairs(rows) do
      local y = 14 + i * 8
      local editable = (i == 1)
      local focused = (out_focus == i)
      screen.level(focused and 15 or (editable and 10 or 5))
      if focused then screen.rect(3, y-5, 44, 7); screen.stroke() end
      screen.move(8, y); screen.text(r[1])
      screen.move(122, y); screen.text_right(r[2])
    end
    screen.level(3)
    screen.move(2, 61); screen.text("K3:OUT")
    screen.move(126, 61); screen.text_right(out_focus == 1 and "E3:MODE" or "E2:SEL")
  else
    draw_header("MUTA > OUT 1/4", 1, 4)
    local rows = {
      {"dest", out_dest_names[out.dest]},
      {"midi", midi_mode_names[out.midi_mode]},
      {"cv", cv_mode_names[out.cv_mode]},
      {"clock out", out_clock_names[out.clock]},
    }
    for i,r in ipairs(rows) do
      local y = 15 + i*9
      screen.level(i == out_focus and 15 or 10)
      if i == out_focus then screen.rect(3, y-6, 52, 8); screen.stroke() end
      screen.move(8, y); screen.text(r[1])
      screen.move(122, y); screen.text_right(r[2])
    end
    screen.level(3)
    screen.move(2, 61); screen.text("K3:CV")
    screen.move(126, 61); screen.text_right("E3:VAL")
  end
end

function M.draw_global(ctx)
  local screen = screen
  local selected_track, selected_step = ctx.selected_track, ctx.selected_step
  local subpage = ctx.subpage or 1
  local fx, mix, out, global, eq = ctx.fx, ctx.mix, ctx.out, ctx.global, ctx.eq
  local data, audio_safe = ctx.data, ctx.audio_safe
  local fx_focus, mix_focus, mix_page, out_focus, OUT_PAGE = ctx.fx_focus, ctx.mix_focus, ctx.mix_page, ctx.out_focus, ctx.OUT_PAGE
  local clock_page, global_focus, arp_focus, arp_page, eq_focus, shift = ctx.clock_page, ctx.global_focus, ctx.arp_focus, ctx.arp_page, ctx.eq_focus, ctx.shift
  local CROW_MOD = ctx.CROW_MOD
  local out_dest_names, midi_mode_names, cv_mode_names, out_clock_names = ctx.out_dest_names, ctx.midi_mode_names, ctx.cv_mode_names, ctx.out_clock_names
  local CROW_IN1_MODE_NAMES, CROW_IN2_MODE_NAMES = ctx.CROW_IN1_MODE_NAMES, ctx.CROW_IN2_MODE_NAMES
  local arp_mode_name, ensure_step_arp = ctx.arp_mode_name, ctx.ensure_step_arp
  local eq_edit_target, ensure_eq_table = ctx.eq_edit_target, ctx.ensure_eq_table
  local clamp = ctx.clamp
  local muta_ui, muta_draw = ctx.muta_ui, ctx.muta_draw
  local draw_page_header, draw_step_page_header, draw_page_footer = ctx.draw_page_header, ctx.draw_step_page_header, ctx.draw_page_footer
  if clock_page == 2 then
    draw_list("GLOBAL > CLOCK OUT", {
      {"clock out", out_clock_names[out.clock]},
      {"start/stop", global.midi_transport_out == 1 and "send" or "off"},
      {"midi ppqn", (out.clock == 2 or out.clock == 4) and "24" or "--"},
      {"status", midi_clock_status_label()},
    }, 2, 2, global_focus)
  else
    draw_list("GLOBAL > CLOCK", {
      {"source", clock_source_name()},
      {"tempo", string.format("%.1f BPM", params:get("clock_tempo"))},
      {"transport", playing and "run" or "stop"},
      {"quantize", "1/"..global.quantize},
      {"swing", math.floor(global.swing*100).."%"},
    }, 1, 2, global_focus)
  end
end

function M.draw_fx(ctx)
  -- Disabled in V10.2 EUCLID V2 FXAUDITFIX.
  -- FX is drawn locally in muta.lua because it depends on local helper state.
  return
end


function M.draw_arp(ctx)
  local screen = screen
  local selected_track, selected_step = ctx.selected_track, ctx.selected_step
  local subpage = ctx.subpage or 1
  local fx, mix, out, global, eq = ctx.fx, ctx.mix, ctx.out, ctx.global, ctx.eq
  local data, audio_safe = ctx.data, ctx.audio_safe
  local fx_focus, mix_focus, mix_page, out_focus, OUT_PAGE = ctx.fx_focus, ctx.mix_focus, ctx.mix_page, ctx.out_focus, ctx.OUT_PAGE
  local clock_page, global_focus, arp_focus, arp_page, eq_focus, shift = ctx.clock_page, ctx.global_focus, ctx.arp_focus, ctx.arp_page, ctx.eq_focus, ctx.shift
  local CROW_MOD = ctx.CROW_MOD
  local out_dest_names, midi_mode_names, cv_mode_names, out_clock_names = ctx.out_dest_names, ctx.midi_mode_names, ctx.cv_mode_names, ctx.out_clock_names
  local CROW_IN1_MODE_NAMES, CROW_IN2_MODE_NAMES = ctx.CROW_IN1_MODE_NAMES, ctx.CROW_IN2_MODE_NAMES
  local arp_mode_name, ensure_step_arp = ctx.arp_mode_name, ctx.ensure_step_arp
  local eq_edit_target, ensure_eq_table = ctx.eq_edit_target, ctx.ensure_eq_table
  local clamp = ctx.clamp
  local muta_ui, muta_draw = ctx.muta_ui, ctx.muta_draw
  local draw_page_header, draw_step_page_header, draw_page_footer = ctx.draw_page_header, ctx.draw_step_page_header, ctx.draw_page_footer
  local st = data.tracks[selected_track].steps[selected_step]
  local ar = ensure_step_arp(st)
  local p = arp_page or 1
  local title = p == 1 and "ARP" or "ARP MUTA"

  screen.level(15)
  screen.move(2, 9)
  screen.text("T" .. selected_track .. " > STEP " .. selected_step .. " > " .. title)
  screen.level(4)
  screen.move(126, 9)
  screen.text_right(p .. "/2")

  screen.level(2)
  screen.move(0, 13)
  screen.line(128, 13)
  screen.stroke()

  if p == 1 then
    local left_names = {"ON", "MODE", "OCT"}
    local left_vals = {
      ar.enabled and "ON" or "OFF",
      arp_mode_name(ar.mode),
      tostring(ar.octaves),
    }
    local right_names = {"RATE", "GATE"}
    local right_vals = {
      tostring(ar.rate),
      math.floor((ar.gate or 0.78) * 100 + 0.5) .. "%",
    }

    for i=1,3 do
      local f = i
      screen.level(arp_focus == f and 15 or 4)
      screen.move(8, 26 + (i-1) * 9)
      screen.text(left_names[i])
      screen.move(54, 26 + (i-1) * 9)
      screen.text_right(left_vals[i])
    end

    for i=1,2 do
      local f = i + 3
      screen.level(arp_focus == f and 15 or 4)
      screen.move(72, 26 + (i-1) * 9)
      screen.text(right_names[i])
      screen.move(122, 26 + (i-1) * 9)
      screen.text_right(right_vals[i])
    end

    screen.level(2)
    screen.move(0, 55)
    screen.line(128, 55)
    screen.stroke()
    screen.level(4)
    screen.move(64, 62)
    screen.text_center("K3:MUTA  E2:SEL  E3:VAL")
  else
    local names = {"MUTA", "MEM", "CHAOS"}
    local vals = {
      math.floor((ar.muta or 0) * 100 + 0.5) .. "%",
      math.floor((ar.mem or 0) * 100 + 0.5) .. "%",
      math.floor((ar.chaos or 0) * 100 + 0.5) .. "%",
    }

    for i=1,3 do
      screen.level(arp_focus == i and 15 or 4)
      screen.move(20, 27 + (i-1) * 10)
      screen.text(names[i])
      screen.move(108, 27 + (i-1) * 10)
      screen.text_right(vals[i])
    end

    screen.level(2)
    screen.move(0, 55)
    screen.line(128, 55)
    screen.stroke()
    screen.level(4)
    screen.move(64, 62)
    screen.text_center("K3:ARP  E2:SEL  E3:VAL")
  end
end

function M.draw_eq(ctx)
  local screen = screen
  local selected_track, selected_step = ctx.selected_track, ctx.selected_step
  local subpage = ctx.subpage or 1
  local fx, mix, out, global, eq = ctx.fx, ctx.mix, ctx.out, ctx.global, ctx.eq
  local data, audio_safe = ctx.data, ctx.audio_safe
  local fx_focus, mix_focus, mix_page, out_focus, OUT_PAGE = ctx.fx_focus, ctx.mix_focus, ctx.mix_page, ctx.out_focus, ctx.OUT_PAGE
  local clock_page, global_focus, arp_focus, arp_page, eq_focus, shift = ctx.clock_page, ctx.global_focus, ctx.arp_focus, ctx.arp_page, ctx.eq_focus, ctx.shift
  local CROW_MOD = ctx.CROW_MOD
  local out_dest_names, midi_mode_names, cv_mode_names, out_clock_names = ctx.out_dest_names, ctx.midi_mode_names, ctx.cv_mode_names, ctx.out_clock_names
  local CROW_IN1_MODE_NAMES, CROW_IN2_MODE_NAMES = ctx.CROW_IN1_MODE_NAMES, ctx.CROW_IN2_MODE_NAMES
  local arp_mode_name, ensure_step_arp = ctx.arp_mode_name, ctx.ensure_step_arp
  local eq_edit_target, ensure_eq_table = ctx.eq_edit_target, ctx.ensure_eq_table
  local clamp = ctx.clamp
  local muta_ui, muta_draw = ctx.muta_ui, ctx.muta_draw
  local draw_page_header, draw_step_page_header, draw_page_footer = ctx.draw_page_header, ctx.draw_step_page_header, ctx.draw_page_footer
  local vals = eq_edit_target()
  local names = {"LOW", "LOW MID", "HIGH MID", "HIGH"}
  local keys = {"low", "lomid", "himid", "high"}
  local xkeys = {"low_x", "lomid_x", "himid_x", "high_x"}
  draw_header("T"..selected_track.." > STEP "..selected_step.." > EQ", 1, 1)

  -- Frameless 4-point EQ editor. K1/SHIFT changes horizontal frequency
  -- placement; normal mode changes gain. The graph is slightly lower and
  -- shorter so value text never collides with the header/status strip.
  local gx0, gx1 = 10, 118
  local cy = 39
  local amp = 11
  screen.level(2)
  screen.move(gx0, cy); screen.line(gx1, cy); screen.stroke()
  screen.level(1)
  screen.move(gx0, cy - amp); screen.line(gx1, cy - amp); screen.stroke()
  screen.move(gx0, cy + amp); screen.line(gx1, cy + amp); screen.stroke()

  local px, py = {}, {}
  for i,k in ipairs(keys) do
    local xnorm = clamp(vals[xkeys[i]] or ({0.10,0.36,0.64,0.90})[i], 0, 1)
    local v = clamp(vals[k] or 0, -1, 1)
    px[i] = gx0 + math.floor(xnorm * (gx1 - gx0))
    py[i] = cy - math.floor(v * amp)
  end

  -- Soft curve: multiple short segments make the EQ shape feel less rigid on
  -- the norns display while staying very cheap to draw.
  screen.level(7)
  for i=1,3 do
    local x1, y1, x2, y2 = px[i], py[i], px[i+1], py[i+1]
    local steps = math.max(2, math.floor((x2 - x1) / 6))
    local lastx, lasty = x1, y1
    for j=1,steps do
      local t = j / steps
      local smooth = t * t * (3 - 2 * t)
      local x = x1 + (x2 - x1) * t
      local y = y1 + (y2 - y1) * smooth
      screen.move(lastx, lasty); screen.line(x, y); screen.stroke()
      lastx, lasty = x, y
    end
  end

  for i,k in ipairs(keys) do
    local active = i == eq_focus
    screen.level(active and 15 or 6)
    screen.circle(px[i], py[i], active and 3 or 2); screen.fill()
    if active then
      screen.level(4)
      screen.move(px[i], py[i] - 5); screen.line(px[i], py[i] + 5); screen.stroke()
    end
  end

  local key = keys[eq_focus]
  local xkey = xkeys[eq_focus]
  local v = clamp(vals[key] or 0, -1, 1)
  local db
  if eq_focus == 1 or eq_focus == 4 then
    db = v < 0 and (v * 24) or (v * 12)
  else
    db = v * 18
  end
  local ranges = {{0.00,0.30,30,300},{0.18,0.52,100,2000},{0.48,0.82,500,8000},{0.70,1.00,2000,16000}}
  local rr = ranges[eq_focus]
  local xn = clamp(((vals[xkey] or rr[1]) - rr[1]) / math.max(0.0001, rr[2] - rr[1]), 0, 1)
  local hz = rr[3] * ((rr[4] / rr[3]) ^ xn)
  local freq_txt = hz >= 1000 and string.format("%.1fk", hz / 1000) or string.format("%dHz", math.floor(hz + 0.5))
  local db_txt = string.format("%+.0fdB", db)
  if (eq_focus == 1 or eq_focus == 4) and v <= -0.98 then db_txt = (eq_focus == 1) and "HPF" or "LPF" end
  screen.level(15)
  screen.move(64, 19)
  if shift then
    screen.text_center(names[eq_focus] .. "  " .. freq_txt)
  else
    screen.text_center(names[eq_focus] .. "  " .. db_txt)
  end

  -- Keep all mode/help text in the footer so the graph area stays clean.
  screen.level(4)
  screen.level(grid_plock_mode and 10 or 5)
  screen.level(4)
  screen.level(4)
  screen.move(64, 62)
  screen.text_center(shift and "E2:SEL   X MODE   E3:FREQ" or "E2:SEL   HOLD K1:X   E3:Y")
end

return M
