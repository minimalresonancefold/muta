-- MUTA pure utility helper module
-- V10.1 PHASE 2
--
-- This module now provides the runtime source for pure helpers used by muta.lua.
-- muta.lua keeps local wrappers for safety and backwards compatibility.

local M = {}

function M.clamp(x, lo, hi)
  x = tonumber(x) or 0
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function M.wrap(x, lo, hi)
  x = tonumber(x) or lo
  if x < lo then return hi end
  if x > hi then return lo end
  return x
end

function M.deep_copy(obj)
  if type(obj) ~= "table" then return obj end
  local res = {}
  for k,v in pairs(obj) do res[k] = M.deep_copy(v) end
  return res
end

function M.rndf(lo, hi)
  return lo + math.random() * (hi - lo)
end

function M.safe_percent(v, default)
  local n = tonumber(v)
  if n == nil then n = default or 0 end
  return M.clamp(n, 0, 1)
end

function M.round(v)
  return math.floor((tonumber(v) or 0) + 0.5)
end

function M.bool_from_delta(d)
  return (tonumber(d) or 0) > 0
end

return M
