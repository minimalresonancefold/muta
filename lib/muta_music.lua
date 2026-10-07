-- MUTA music runtime helper module
-- V10.1 PHASE 6 MUSIC
local M = {}
local function clamp(x, lo, hi) x=tonumber(x) or 0; if x<lo then return lo end; if x>hi then return hi end; return x end
function M.scale_notes(scale_intervals, scale_index) if type(scale_intervals)~="table" then return {0} end; return scale_intervals[scale_index] or scale_intervals[1] or {0} end
function M.quantize_to_scale(note, pitch, scale_intervals)
  pitch=type(pitch)=="table" and pitch or {}; note=tonumber(note) or 60; local scale=tonumber(pitch.scale) or 1
  if scale==1 then return clamp(math.floor(note+0.5),12,108) end
  local root=tonumber(pitch.root) or 48; local root_pc=root%12; local notes=M.scale_notes(scale_intervals,scale); local best=note; local best_dist=999
  for oct=-6,6 do for _,iv in ipairs(notes) do local cand=root_pc+iv+oct*12; local dist=math.abs(cand-note); if dist<best_dist then best=cand; best_dist=dist end end end
  return clamp(best,12,108)
end
function M.quantize_to_scale_values(note, root, scale, scale_intervals)
  note=tonumber(note) or 60; scale=tonumber(scale) or 1
  if scale==1 then return clamp(math.floor(note+0.5),12,108) end
  root=tonumber(root) or 48
  local root_pc=root%12; local notes=M.scale_notes(scale_intervals,scale); local best=note; local best_dist=999
  for oct=-6,6 do for _,iv in ipairs(notes) do local cand=root_pc+iv+oct*12; local dist=math.abs(cand-note); if dist<best_dist then best=cand; best_dist=dist end end end
  return clamp(best,12,108)
end
function M.step_note_args(st,tr,pitch,crow_mod)
  st=type(st)=="table" and st or {}; tr=type(tr)=="table" and tr or {}; pitch=type(pitch)=="table" and pitch or {}; crow_mod=type(crow_mod)=="table" and crow_mod or {}
  local pl=st.locks and st.locks.pitch or nil
  local relative_lock=pl and pl.relative_note
  local root=(relative_lock and (pitch.root or 48)) or ((pl and pl.root) or pitch.root or 48)
  local scale=(relative_lock and (pitch.scale or 1)) or ((pl and pl.scale) or pitch.scale or 1)
  local octave=(relative_lock and (pitch.octave or 0)) or ((pl and pl.octave) or pitch.octave or 0)
  local rnd_amt=(pl and pl.rnd) or pitch.rnd or 0
  local note_off=(relative_lock and (pl.note_offset or pl.note)) or ((pl and pl.note) or st.note or 0)
  local track_root=tr.root or 48
  local rand_span=math.floor(rnd_amt*14+0.5); local rnd=rand_span>0 and math.random(-rand_span,rand_span) or 0; local crow_root_offset=crow_mod.root or 0
  return {root=root, scale=scale, raw=root+(track_root-48)+octave*12+note_off+rnd+crow_root_offset}
end
function M.euclid_hit(step,pulses,steps,rotation) pulses=tonumber(pulses) or 0; steps=math.max(1,tonumber(steps) or 16); rotation=tonumber(rotation) or 0; if pulses<=0 then return false end; if pulses>=steps then return true end; local idx=((tonumber(step) or 1)-1+rotation)%steps; return ((idx*pulses)%steps)<pulses end

-- V10.3 OPTIM: gentle, bounded drift of a sample playback region driven by the
-- step's existing mutation/chaos amounts. Pure function, no engine calls.
-- Keeps region width roughly intact (it nudges the window, it doesn't grow it)
-- and always clamps inside [0,1] so it can never read outside the buffer.
function M.drift_sample_region(start_pos, end_pos, muta_amt, chaos_amt)
  start_pos = clamp(tonumber(start_pos) or 0, 0, 0.999)
  end_pos = clamp(tonumber(end_pos) or 1, start_pos + 0.001, 1)
  muta_amt = clamp(tonumber(muta_amt) or 0, 0, 1)
  chaos_amt = clamp(tonumber(chaos_amt) or 0, 0, 1)
  if muta_amt <= 0 and chaos_amt <= 0 then return start_pos, end_pos end
  local width = end_pos - start_pos
  -- max drift: up to ~12% of buffer length at full muta, plus an occasional
  -- larger chaos jump (rare, so it reads as an event rather than noise).
  local drift = (math.random() - 0.5) * 2 * muta_amt * 0.12
  if chaos_amt > 0 and math.random() < chaos_amt * 0.10 then
    drift = drift + (math.random() - 0.5) * 2 * 0.30
  end
  local new_start = clamp(start_pos + drift, 0, 1 - width)
  return new_start, clamp(new_start + width, new_start + 0.001, 1)
end
return M
