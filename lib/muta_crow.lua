-- MUTA Crow runtime helper module
-- V10.1 PHASE 5 CROW
--
-- Pure Crow value helpers. No direct crow.output calls, no clocks, no callbacks.
-- muta.lua keeps all real-time hardware IO so behavior remains unchanged.

local M = {}

local function clamp(x, lo, hi)
  x = tonumber(x) or 0
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function M.note_to_volts(note)
  return ((tonumber(note) or 60) - 60) / 12
end

function M.mutation_amount(active_mtx)
  active_mtx = type(active_mtx) == "table" and active_mtx or {}
  return clamp(
    ((active_mtx.grain or 0) +
     (active_mtx.fold or 0) +
     (active_mtx.fm or 0) +
     (active_mtx.phase or 0) +
     (active_mtx.noise or 0)) / 5,
    0, 1
  )
end

function M.evolution_amount(mut, st, global)
  st = type(st) == "table" and st or {}
  global = type(global) == "table" and global or {}
  return clamp(
    ((tonumber(mut) or 0) * 0.45) +
    ((st.mutation_prob or 0) * 0.20) +
    ((global.propagation_chance or 0.52) * 0.20) +
    ((global.mutation_spread or 0) / 4 * 0.15),
    0, 1
  )
end

function M.build_values(note, amp, st, global, density_value)
  st = type(st) == "table" and st or {}
  local active_mtx = (st.locks and st.locks.mutations) or st.mutations or {}
  local mut = M.mutation_amount(active_mtx)
  local evo = M.evolution_amount(mut, st, global)
  local dens = clamp(density_value or 0, 0, 1)
  local volts = M.note_to_volts(note)
  return {
    volts = volts,
    amp = clamp(amp or 0, 0, 1),
    mut = mut,
    evo = evo,
    dens = dens,
    phase = clamp(active_mtx.phase or 0, 0, 1),
    cv3 = mut * 5,
    cv4 = evo * 5,
  }
end

return M
