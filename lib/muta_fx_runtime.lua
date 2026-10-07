-- MUTA FX runtime helper module
-- V10.1 PHASE 4 FX
--
-- Small FX helpers extracted from muta.lua.
-- They are pure table/value helpers: no engine calls, no clocks, no side effects.

local M = {}

function M.force_fixed_sends(fx, mix)
  if type(fx) == "table" then
    fx.delay_mix = 1.0
    fx.reverb_mix = 1.0
  end
  if type(mix) == "table" then
    mix.delay = 1.0
    mix.reverb = 1.0
  end
end

function M.delay_tail_seconds(lock, fx)
  if type(lock) ~= "table" then return 0 end
  fx = type(fx) == "table" and fx or {}
  local timev = tonumber(lock.delay_time) or fx.delay_time or 0
  local feedv = tonumber(lock.delay_feedback) or fx.delay_feedback or 0
  local mixv = tonumber(lock.delay_mix) or fx.delay_mix or 0
  if mixv <= 0.01 then return 0 end

  local tail = 0.35 + (timev * 2.2) + (feedv * 1.7)
  if tail < 0.45 then tail = 0.45 end
  if tail > 3.2 then tail = 3.2 end
  return tail
end

function M.reverb_tail_seconds(lock, fx)
  if type(lock) ~= "table" then return 0 end
  fx = type(fx) == "table" and fx or {}
  local sizev = tonumber(lock.reverb_size) or fx.reverb_size or 0
  local decayv = tonumber(lock.reverb_decay) or fx.reverb_decay or 0
  local mixv = tonumber(lock.reverb_mix) or fx.reverb_mix or 0
  if mixv <= 0.01 then return 0 end

  local tail = 0.50 + (sizev * 1.8) + (decayv * 2.2)
  if tail < 0.65 then tail = 0.65 end
  if tail > 4.0 then tail = 4.0 end
  return tail
end

return M
