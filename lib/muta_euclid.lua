-- MUTA Euclid runtime module
-- V12.4 EUCLID MORPH
-- Deterministic rhythmic transformer: MASK / FILL / SHIFT / ORBIT.
-- No random gate layer: SEQ probability and MUTATION remain separate systems.

local M = {}

local function clamp(x, lo, hi)
  x = tonumber(x) or 0
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function wrap(x, lo, hi)
  x = tonumber(x) or lo
  if x < lo then return hi end
  if x > hi then return lo end
  return x
end

M.mode_names = {"MASK", "FILL", "SHIFT", "ORBIT"}

function M.default()
  return {
    enabled=false,
    mode=1,
    steps=16,
    pulses=4,
    rotation=0,
    morph=0.0,
    drift=0,
    add=0.25,
    cycle=0,
    runtime_rotation=0,
    started=false,
  }
end

function M.ensure(eu)
  if type(eu) ~= "table" then eu = M.default() end
  eu.enabled = eu.enabled == true
  eu.mode = clamp(math.floor((tonumber(eu.mode) or 1) + 0.5), 1, #M.mode_names)
  eu.steps = clamp(math.floor((tonumber(eu.steps) or 16) + 0.5), 2, 32)
  eu.pulses = clamp(math.floor((tonumber(eu.pulses) or 4) + 0.5), 0, eu.steps)
  eu.rotation = math.floor((tonumber(eu.rotation) or 0) + 0.5) % eu.steps
  eu.morph = clamp(tonumber(eu.morph) or 0, 0, 1)
  eu.drift = clamp(math.floor((tonumber(eu.drift) or 0) + 0.5), -4, 4)
  eu.add = clamp(tonumber(eu.add) or 0.25, 0, 1)
  eu.cycle = math.max(0, math.floor((tonumber(eu.cycle) or 0) + 0.5))
  eu.runtime_rotation = math.floor((tonumber(eu.runtime_rotation) or eu.rotation) + 0.5) % eu.steps
  eu.started = eu.started == true
  return eu
end

function M.hit(step, pulses, steps, rotation)
  pulses = tonumber(pulses) or 0
  steps = math.max(1, tonumber(steps) or 16)
  rotation = tonumber(rotation) or 0
  if pulses <= 0 then return false end
  if pulses >= steps then return true end
  local idx = ((tonumber(step) or 1) - 1 + rotation) % steps
  return ((idx * pulses) % steps) < pulses
end

function M.live_rotation(eu)
  eu = M.ensure(eu)
  return (eu.rotation + eu.cycle * eu.drift) % eu.steps
end

function M.base_hit(step, eu)
  eu = M.ensure(eu)
  return M.hit(step, eu.pulses, eu.steps, M.live_rotation(eu))
end

function M.advance_cycle(eu)
  eu = M.ensure(eu)
  eu.cycle = eu.cycle + 1
  eu.runtime_rotation = M.live_rotation(eu)
  return eu
end

-- Deterministic density selection. rank is 1..count.
function M.density_pick(rank, count, amount)
  count = math.max(0, math.floor(tonumber(count) or 0))
  rank = math.max(1, math.floor(tonumber(rank) or 1))
  amount = clamp(tonumber(amount) or 0, 0, 1)
  if count == 0 or amount <= 0 then return false end
  if amount >= 1 then return rank <= count end
  local wanted = math.floor(count * amount + 0.5)
  if wanted <= 0 then return false end
  -- Spread selected ranks across the candidate list instead of taking a block.
  local before = math.floor((rank - 1) * wanted / count)
  local after = math.floor(rank * wanted / count)
  return after > before
end

function M.nearest_hit(step, eu, width)
  eu = M.ensure(eu)
  width = math.max(1, math.floor(tonumber(width) or 16))
  if eu.pulses <= 0 then return step end
  local best, best_d = step, width + 1
  for pos=1,width do
    if M.base_hit(pos, eu) then
      local direct = math.abs(pos - step)
      local d = math.min(direct, width - direct)
      if d < best_d or (d == best_d and pos < best) then
        best, best_d = pos, d
      end
    end
  end
  return best
end

function M.pattern_string(eu, width)
  eu = M.ensure(eu)
  width = width or math.min(32, eu.steps)
  local s = {}
  for i=1,width do
    local step = math.floor(((i-1) / width) * eu.steps) + 1
    s[#s+1] = M.base_hit(step, eu) and "x" or "-"
  end
  return table.concat(s)
end

function M.edit(eu, focus, delta, page)
  eu = M.ensure(eu)
  page = page or 1
  local dir = delta > 0 and 1 or (delta < 0 and -1 or 0)
  if page == 1 then
    if focus == 1 then eu.enabled = delta > 0 end
    if focus == 2 then eu.mode = wrap(eu.mode + dir, 1, #M.mode_names) end
    if focus == 3 then eu.steps = clamp(eu.steps + delta, 2, 32); eu.pulses = clamp(eu.pulses, 0, eu.steps); eu.rotation = eu.rotation % eu.steps end
    if focus == 4 then eu.pulses = clamp(eu.pulses + delta, 0, eu.steps) end
    if focus == 5 then eu.rotation = wrap(eu.rotation + delta, 0, eu.steps - 1) end
  else
    if focus == 1 then eu.morph = clamp(eu.morph + delta/100, 0, 1) end
    if focus == 2 then eu.drift = clamp(eu.drift + dir, -4, 4) end
    if focus == 3 then eu.add = clamp(eu.add + delta/100, 0, 1) end
  end
  eu.runtime_rotation = M.live_rotation(eu)
  return M.ensure(eu)
end

return M
