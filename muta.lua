-- MUTA
-- v1.0.1 @minimalresonancefold
-- github.com/minimalresonancefold/muta
--
-- generative mutation sequencer for monome norns
-- sequence · transform · evolve

engine.name = "Muta"

-- v10.0 architecture release: late UI helpers are intentionally global, not local.
-- This keeps the Lua main chunk below norns' local-variable limit and prevents LOAD FAIL.
local MUTA_VERSION = "v1.0.1"
local MUTA_DEFINITION = "a self-evolving mutation sequencer"

function muta_module_report()
  return muta_manifest
end


local musicutil = require "musicutil"
local muta_store = include "lib/muta_store"
local muta_manifest = include "lib/muta_manifest"
local muta_utils = include "lib/muta_utils"
local muta_fx_runtime = include "lib/muta_fx_runtime"
local muta_crow = include "lib/muta_crow"
local muta_music = include "lib/muta_music"
local muta_draw = include "lib/muta_draw"
muta_ui = include "lib/muta_ui"       -- V12.0.1: global bridge avoids Lua 200-local main-chunk limit
local muta_arp_runtime = include "lib/muta_arp_runtime"
muta_euclid = include "lib/muta_euclid"
local muta_draw_pages = include "lib/muta_draw_pages"

local g = nil
local a = nil
local m = nil

local NUM_TRACKS = 6
local NUM_STEPS = 16

local page_names = {"SEQ", "SRC", "ENV", "EQ", "PITCH", "FX", "MTX", "ARP", "EUCLID", "MIX", "OUT", "GLOBAL"}
local PAGE_INTRO = 0
-- Page order: SEQ > SOURCE > ENV > EQ > PITCH > FX > MUTATION > ARP > EUCLID > MIX > OUT > CLOCK
local PAGE_SEQ, PAGE_SRC, PAGE_ENV, PAGE_EQ, PAGE_PITCH, PAGE_FX, PAGE_MTX, PAGE_ARP, PAGE_EUCLID, PAGE_MIX, PAGE_OUT, PAGE_GLOBAL = 1,2,3,4,5,6,7,8,9,10,11,12
-- Hidden legacy summary page kept for internal compatibility, but not exposed in E1/grid navigation.
local PAGE_TRACK = 13

local page = PAGE_INTRO
local subpage = 1
local selected_track = 1
local selected_step = 1
local play_step = 1
local playing = false
local shift = false
local fx_focus = 1
local mix_focus = 1
local mix_page = 1 -- 1 levels, 2 dynamics
local track_focus = 1
local arp_focus = 1
local arp_page = 1 -- 1 classic, 2 ARP MUTA
local euclid_focus = 1
local euclid_page = 1 -- 1 core, 2 MUTA
local src_focus = 1
local env_focus = 1
local eq_focus = 1
local pitch_focus = 1
local mtx_focus = 1
local global_focus = 1
local clock_page = 1 -- GLOBAL/CLOCK subpage: 1 transport, 2 clock out
local out_focus = 1
local sample_name = "none"
local sample_path = _path.audio .. "MUTA/"
local sample_browser = { open = false, files = {}, index = 1, offset = 1 }
local sample_edit = { open = false, focus = 1, waveform = {}, valid = false, message = "no waveform" }
local sample_rec = {
  state = "idle", -- idle / armed / recording / saving
  threshold_db = -32,
  threshold_amp = 0.025,
  max_time = 5.0,
  start_time = 0,
  duration = 0,
  voice = 6,
  buffer = 2,
  pos = 1,
  -- nil until the first amp poll arrives. Do not default to 0 here:
  -- dB polls are negative, and math.max(-12, 0) would incorrectly force
  -- linear mode and prevent threshold triggering.
  level_l = nil,
  level_r = nil,
  poll_count = 0,
  filename = nil,
  auto_normalize = false,
  poll_ready = false,
  softcut_ready = false,
  rec_input_gain = 2.4,
}
local preset_path = _path.data .. "MUTA/presets/"
local grid_mute_held = false
local grid_plock_mode = false
local grid_plock_flash = nil
local mtx_submode = 1 -- 1 mutations, 2 propagation (hold K1 on MTX)
local perf_flash = ""
local popup_message = nil
local popup_until = 0
local dirty = true
local clock_id = nil
local grid_intro_active = false
local p_lock_fx_active = false
local p_lock_delay_hold_until = 0
local p_lock_delay_hold_token = 0
local p_lock_reverb_hold_until = 0
local p_lock_reverb_hold_token = 0
MUTA_FX_COLUMN_TOKEN = 0
MUTA_ARC_FX_CACHE_KEY = nil
MUTA_ARC_FX_CACHE_VALUES = nil
local redraw_grid -- forward declaration for delayed grid gestures
local grid_step_hold = nil
local grid_copy_source = nil
local grid_copy_flash = nil
local standalone_step_clipboard = nil
local standalone_step_clipboard_token = 0

STEP_CLIPBOARD_TTL = 8
STEP_CLIPBOARD_WARN_AT = 5

local seq_k3_hold = nil

-- Audio safety: protects norns shield from CPU/voice spikes.
local audio_safe = {
  max_voices_per_step = 6,
  max_arp_rate = 4,
  min_release = 0.055,
  voices_this_step = 0,
}

local pitch = {
  root = 48,
  scale = 1,
  octave = 0,
  rnd = 0.0,
  range = 1, -- octave range used by intelligent randomization
  density = 1.0, -- percentage of steps affected by track/all randomization
}
local scale_names = {"chromatic", "minor", "major", "dorian", "pentatonic", "whole"}
local scale_intervals = {
  {0,1,2,3,4,5,6,7,8,9,10,11},
  {0,2,3,5,7,8,10},
  {0,2,4,5,7,9,11},
  {0,2,3,5,7,9,10},
  {0,3,5,7,10},
  {0,2,4,6,8,10},
}

local data = { tracks = {} }
local fx = {
  -- v8.8: neutral startup. All effect controls begin at 0 so the user decides
  -- when delay/reverb/damage enter the patch or a P-lock.
  delay_time = 0.0,
  delay_feedback = 0.0,
  delay_tone = 0.0,
  delay_mix = 0.0,
  reverb_size = 0.0,
  reverb_decay = 0.0,
  reverb_damp = 0.0,
  reverb_mix = 0.0,
  damage_crush = 0.0,
  damage_fold = 0.0,
  damage_instability = 0.0,
  damage_dropout = 0.0,
  delay_diffusion = 0.0,
  delay_smear = 0.0,
}

local eq = {
  -- V10: lightweight 4-point voice EQ.
  -- Gains are -1..1 mapped to +/-12 dB; x positions are 0..1 and mapped
  -- to safe musical filter frequencies in the SuperCollider engine.
  low = 0.0,
  lomid = 0.0,
  himid = 0.0,
  high = 0.0,
  low_x = 0.10,
  lomid_x = 0.36,
  himid_x = 0.64,
  high_x = 0.90,
}


local mix = {
  delay = 1.00, -- fixed native FX send, no longer exposed on MIX
  reverb = 1.00, -- fixed native FX send, no longer exposed on MIX
  main = 0.50,
  phones = 0.50, -- CUE value; kept internally as phones for preset compatibility
  comp = 0.65,
  threshold = 0.50,
  ratio = 0.35,
  limiter = 0.90,
}

local out = {
  -- dest: 1 NORNS, 2 NORNS+MIDI, 3 NORNS+CV, 4 MIDI, 5 CV, 6 MIDI+CV, 7 ALL
  dest = 1,
  -- midi_mode: 1 NOTE, 2 NOTE+CC, 3 CC
  midi_mode = 1,
  -- cv_mode: 1 1V/OCT, 2 MOD, 3 HYBRID
  cv_mode = 1,
  -- clock: 1 OFF, 2 MIDI, 3 CV, 4 BOTH
  clock = 1,
  cc_base = 20,
  crow_in1 = 2, -- 1 OFF, 2 CLOCK
  crow_in2 = 3, -- 1 OFF, 2 MUT, 3 EVO, 4 DENS, 5 ROOT, 6 PROP, 7 MUTATE, 8 VIRAL, 9 RND
}

local out_dest_names = {"NORNS", "N+MIDI", "N+CV", "MIDI", "CV", "MIDI+CV", "ALL"}
local midi_mode_names = {"NOTE", "NOTE+CC", "CC"}
local cv_mode_names = {"1V/OCT", "MOD", "HYBRID"}
local out_clock_names = {"OFF", "MIDI", "CV", "BOTH"}
CROW_IN1_MODE_NAMES = {"OFF", "CLOCK", "CLOCK CV"}
CROW_IN2_MODE_NAMES = {"OFF", "MUT", "EVO", "DENS", "ROOT", "PROP", "MUTATE", "VIRAL", "RND"}

local function sync_mix_engine()
  muta_fx_runtime.force_fixed_sends(fx, mix)
  -- v8.10: MIX page now exposes MASTER + CUE instead of pretending that
  -- norns main/phones are two independently addressable engine outputs.
  -- MASTER controls the actual software output trim. CUE is kept as a
  -- performance/recall value for future routing and UI consistency, but it no
  -- longer multiplies the final engine output and therefore cannot accidentally
  -- attenuate the main mix.
  if engine.main_l then engine.main_l(mix.main) end
  if engine.main_r then engine.main_r(mix.main) end
  if engine.phone_l then engine.phone_l(1.0) end
  if engine.phone_r then engine.phone_r(1.0) end
  if engine.comp_amount then engine.comp_amount(mix.comp or 0.65) end
  if engine.comp_threshold then engine.comp_threshold(mix.threshold or 0.50) end
  if engine.comp_ratio then engine.comp_ratio(mix.ratio or 0.35) end
  if engine.limiter_ceiling then engine.limiter_ceiling(mix.limiter or 0.90) end
end

local function sync_fx_engine()
  muta_fx_runtime.force_fixed_sends(fx, mix)
  if engine.delay_time then engine.delay_time(fx.delay_time) end
  if engine.delay_feedback then engine.delay_feedback(fx.delay_feedback) end
  if engine.delay_tone then engine.delay_tone(fx.delay_tone) end
  if engine.delay_diffusion then engine.delay_diffusion(fx.delay_diffusion) end
  if engine.delay_smear then engine.delay_smear(fx.delay_smear) end
  if engine.delay_mix then engine.delay_mix(fx.delay_mix) end
  if engine.reverb_size then engine.reverb_size(fx.reverb_size) end
  if engine.reverb_decay then engine.reverb_decay(fx.reverb_decay) end
  if engine.reverb_damp then engine.reverb_damp(fx.reverb_damp) end
  if engine.reverb_mix then engine.reverb_mix(fx.reverb_mix) end
  if engine.damage_crush then engine.damage_crush(fx.damage_crush) end
  if engine.damage_fold then engine.damage_fold(fx.damage_fold) end
  if engine.damage_instability then engine.damage_instability(fx.damage_instability) end
  if engine.damage_dropout then engine.damage_dropout(fx.damage_dropout) end
  sync_mix_engine()
end

local function sync_delay_engine_global()
  muta_fx_runtime.force_fixed_sends(fx, mix)
  if engine.delay_time then engine.delay_time(fx.delay_time) end
  if engine.delay_feedback then engine.delay_feedback(fx.delay_feedback) end
  if engine.delay_tone then engine.delay_tone(fx.delay_tone) end
  if engine.delay_diffusion then engine.delay_diffusion(fx.delay_diffusion) end
  if engine.delay_smear then engine.delay_smear(fx.delay_smear) end
  if engine.delay_mix then engine.delay_mix(fx.delay_mix) end
end

function muta_sync_reverb_engine_global()
  muta_fx_runtime.force_fixed_sends(fx, mix)
  if engine.reverb_size then engine.reverb_size(fx.reverb_size) end
  if engine.reverb_decay then engine.reverb_decay(fx.reverb_decay) end
  if engine.reverb_damp then engine.reverb_damp(fx.reverb_damp) end
  if engine.reverb_mix then engine.reverb_mix(fx.reverb_mix) end
end

function muta_sync_damage_engine_global()
  if engine.damage_crush then engine.damage_crush(fx.damage_crush) end
  if engine.damage_fold then engine.damage_fold(fx.damage_fold) end
  if engine.damage_instability then engine.damage_instability(fx.damage_instability) end
  if engine.damage_dropout then engine.damage_dropout(fx.damage_dropout) end
end

local function sync_fx_engine_without_delay()
  muta_fx_runtime.force_fixed_sends(fx, mix)
  if engine.reverb_size then engine.reverb_size(fx.reverb_size) end
  if engine.reverb_decay then engine.reverb_decay(fx.reverb_decay) end
  if engine.reverb_damp then engine.reverb_damp(fx.reverb_damp) end
  if engine.reverb_mix then engine.reverb_mix(fx.reverb_mix) end
  if engine.damage_crush then engine.damage_crush(fx.damage_crush) end
  if engine.damage_fold then engine.damage_fold(fx.damage_fold) end
  if engine.damage_instability then engine.damage_instability(fx.damage_instability) end
  if engine.damage_dropout then engine.damage_dropout(fx.damage_dropout) end
  sync_mix_engine()
end

-- V10.0 FX/P-lock architecture: FX locks are global-bus states.
-- Dry/non-locked tracks must never restore the bus during the same sequencer
-- column. Restoration is handled once per column after all tracks have fired.
function muta_normalize_fx_lock(lf)
  if type(lf) ~= "table" then return nil end
  if type(lf[1]) == "table" or type(lf[2]) == "table" or type(lf[3]) == "table" then return lf end
  -- Backward compatibility: early presets stored one flat FX table. Convert it
  -- virtually, without rewriting the saved preset.
  if lf.delay_time ~= nil or lf.reverb_size ~= nil or lf.damage_crush ~= nil then
    return {
      [1] = (lf.delay_time ~= nil or lf.delay_feedback ~= nil or lf.delay_mix ~= nil) and lf or nil,
      [2] = (lf.reverb_size ~= nil or lf.reverb_decay ~= nil or lf.reverb_mix ~= nil) and lf or nil,
      [3] = (lf.damage_crush ~= nil or lf.damage_fold ~= nil or lf.damage_dropout ~= nil) and lf or nil,
    }
  end
  return lf
end

local function fx_lock_active(lf)
  lf = muta_normalize_fx_lock(lf)
  if type(lf) ~= "table" then return false end

  -- A stored table is not necessarily an audible P-lock. Zeroed locks must
  -- return to the global FX bus so ensemble Delay/Reverb/Damage still apply.
  local d = type(lf[1]) == "table" and lf[1] or nil
  local r = type(lf[2]) == "table" and lf[2] or nil
  local g = type(lf[3]) == "table" and lf[3] or nil

  local delay_on = d and (tonumber(d.delay_mix) or 0) > 0.0001
  local reverb_on = r and (tonumber(r.reverb_mix) or 0) > 0.0001
  local damage_on = g and (
    (tonumber(g.damage_crush) or 0) > 0.0001 or
    (tonumber(g.damage_fold) or 0) > 0.0001 or
    (tonumber(g.damage_instability) or 0) > 0.0001 or
    (tonumber(g.damage_dropout) or 0) > 0.0001
  )

  return delay_on or reverb_on or damage_on
end

function restore_fx_bus(reason)
  local now = util.time()
  -- Damage has no acoustic tail and must always return to the global state at
  -- the end of the current sequencer column. It must never be held by a Delay
  -- or Reverb tail.
  muta_sync_damage_engine_global()
  if (p_lock_delay_hold_until or 0) <= now then sync_delay_engine_global() end
  if (p_lock_reverb_hold_until or 0) <= now then muta_sync_reverb_engine_global() end
end

local function fx_column_restore()
  restore_fx_bus("column")
  p_lock_fx_active = false
end

local function delay_lock_tail_seconds(d)
  return muta_fx_runtime.delay_tail_seconds(d, fx)
end

local function schedule_delay_plock_release(seconds)
  seconds = seconds or 0
  if seconds <= 0 then return end
  p_lock_delay_hold_token = p_lock_delay_hold_token + 1
  local token = p_lock_delay_hold_token
  p_lock_delay_hold_until = math.max(p_lock_delay_hold_until or 0, util.time() + seconds)
  clock.run(function()
    clock.sleep(seconds)
    local ok, err = pcall(function()
      if token == p_lock_delay_hold_token and util.time() >= (p_lock_delay_hold_until or 0) then
        sync_delay_engine_global()
        p_lock_delay_hold_until = 0
        if not p_lock_fx_active then dirty = true end
      end
    end)
    if not ok then print("MUTA DELAY HOLD RELEASE ERROR: " .. tostring(err)) end
  end)
end

local function reverb_lock_tail_seconds(r)
  return muta_fx_runtime.reverb_tail_seconds(r, fx)
end

local function schedule_reverb_plock_release(seconds)
  seconds = seconds or 0
  if seconds <= 0 then return end
  p_lock_reverb_hold_token = p_lock_reverb_hold_token + 1
  local token = p_lock_reverb_hold_token
  p_lock_reverb_hold_until = math.max(p_lock_reverb_hold_until or 0, util.time() + seconds)
  clock.run(function()
    clock.sleep(seconds)
    local ok, err = pcall(function()
      if token == p_lock_reverb_hold_token and util.time() >= (p_lock_reverb_hold_until or 0) then
        muta_sync_reverb_engine_global()
        p_lock_reverb_hold_until = 0
        if not p_lock_fx_active then dirty = true end
      end
    end)
    if not ok then print("MUTA REVERB HOLD RELEASE ERROR: " .. tostring(err)) end
  end)
end


local scenes = {nil, nil, nil, nil}
local scene_flash = ""

local global = {
  quantize = 16,
  swing = 0,
  main_out = -6,
  hp_out = -10,
  mutation_spread = 1,
  propagation_mode = 1, -- 1 linear, 2 organic, 3 fungal, 4 viral
  propagation_decay = 0.62,
  propagation_chance = 0.52,
  crow_enable = 1,
  midi_enable = 1,
  midi_channel = 1,
  tempo_source = 1, -- 1 internal, 2 link
  link_transport = 1,
  midi_transport_out = 1, -- 1 send MIDI Start/Stop with MIDI clock, 2 clock only
}

-- Crow input modulation state. Kept global to avoid increasing Lua main-chunk local pressure.
CROW_MOD = {
  value = 0,
  mutation = 0,
  evolution = 0,
  density = 1,
  root = 0,
  last_clock = 0,
  clock_count = 0,
  clock_stream_high = false,
  clock_pending = false,
  clock_mode = "none",
  last_clock_v = 0,
  last_clock_interval = 0.25,
  crow_quantize_counter = 0,
  in2_stream_high = false,
  last_in2 = nil,
  in2_count = 0,
  cv3 = 0,
  cv4 = 0,
}
OUT_PAGE = 1 -- OUT 1/4 routing, OUT 2/4 CV out, OUT 3/4 Crow clock input, OUT 4/4 Crow IN2 modulation


-- V10.1 PHASE 1: global context table.
-- This is a safe bridge for future modularization. The current runtime still
-- uses the established locals, while MUTA exposes stable references that future
-- modules can consume step by step.
MUTA = MUTA or {}

function muta_context_refresh()
  MUTA.version = MUTA_VERSION
  MUTA.definition = MUTA_DEFINITION
  MUTA.constants = {
    tracks = NUM_TRACKS,
    steps = NUM_STEPS,
    page_intro = PAGE_INTRO,
    page_track = PAGE_TRACK,
  }
  MUTA.pages = {
    names = page_names,
    seq = PAGE_SEQ,
    src = PAGE_SRC,
    env = PAGE_ENV,
    eq = PAGE_EQ,
    pitch = PAGE_PITCH,
    fx = PAGE_FX,
    mtx = PAGE_MTX,
    arp = PAGE_ARP,
    euclid = PAGE_EUCLID,
    mix = PAGE_MIX,
    out = PAGE_OUT,
    global = PAGE_GLOBAL,
  }
  MUTA.state = {
    data = data,
    fx = fx,
    eq = eq,
    mix = mix,
    out = out,
    global = global,
    pitch = pitch,
    scenes = scenes,
    crow_mod = CROW_MOD,
    audio_safe = audio_safe,
  }
  MUTA.ui = {
    page = function() return page end,
    selected_track = function() return selected_track end,
    selected_step = function() return selected_step end,
    play_step = function() return play_step end,
    playing = function() return playing end,
    grid_plock_mode = function() return grid_plock_mode end,
  }
  MUTA.helpers = {
    euclid_runtime = muta_euclid,
    draw_pages = muta_draw_pages,
    arp_runtime = muta_arp_runtime,
    draw_runtime = muta_draw,
    music_runtime = muta_music,
    crow_runtime = muta_crow,
    fx_runtime = muta_fx_runtime,
    utils = muta_utils,
    clamp = clamp,
    wrap = wrap,
    deep_copy = deep_copy,
    safe_quantize_value = safe_quantize_value,
    safe_swing_value = safe_swing_value,
    restore_fx_bus = restore_fx_bus,
  }
  return MUTA
end

function muta_context_report()
  muta_context_refresh()
  return {
    version = MUTA.version,
    pages = MUTA.pages.names,
    selected_track = MUTA.ui.selected_track(),
    selected_step = MUTA.ui.selected_step(),
    runtime = "local-first / context-bridge",
  }
end


-- V10.1 PHASE 2: pure utility helpers are now sourced from lib/muta_utils.
-- Local wrappers are intentionally kept so the existing monolithic runtime
-- keeps working unchanged while future modules can use muta_utils directly.
function deep_copy(obj)
  return muta_utils.deep_copy(obj)
end

local function clamp(x, lo, hi)
  return muta_utils.clamp(x, lo, hi)
end

local function wrap(x, lo, hi)
  return muta_utils.wrap(x, lo, hi)
end

local function rndf(lo, hi)
  return muta_utils.rndf(lo, hi)
end


-- V10.0 timing: quantize and swing are now real musical timing controls,
-- not only display values. Quantize is intentionally limited to standard
-- musical divisions so one encoder click always produces an audible change.
QUANTIZE_VALUES = {1, 2, 4, 8, 16, 32, 64}

function safe_quantize_value(v)
  local raw = math.floor((tonumber(v) or 16) + 0.5)
  local best = 16
  local best_dist = 999
  for _,q in ipairs(QUANTIZE_VALUES) do
    local dist = math.abs(q - raw)
    if dist < best_dist then
      best = q
      best_dist = dist
    end
  end
  return best
end

function next_quantize_value(current, delta)
  local q = safe_quantize_value(current or 16)
  local idx = 5
  for i,v in ipairs(QUANTIZE_VALUES) do
    if v == q then idx = i; break end
  end
  if (tonumber(delta) or 0) > 0 then idx = math.min(#QUANTIZE_VALUES, idx + 1)
  elseif (tonumber(delta) or 0) < 0 then idx = math.max(1, idx - 1) end
  return QUANTIZE_VALUES[idx]
end

function safe_swing_value(v)
  local sw = tonumber(v) or 0
  -- Accept either percent values (0..75) or normalized values (0..0.75).
  if sw > 1 then sw = sw / 100 end
  if sw < 0 then sw = 0 end
  if sw > 0.75 then sw = 0.75 end
  return sw
end

function set_quantize_safe(v)
  global.quantize = safe_quantize_value(v)
  pcall(function() params:set("quantize", global.quantize, true) end)
  dirty = true
end

function set_swing_safe(v)
  global.swing = safe_swing_value(v)
  pcall(function() params:set("swing", math.floor(global.swing * 100 + 0.5), true) end)
  dirty = true
end

function safe_step_division()
  local q = safe_quantize_value(global and global.quantize or 16)
  local div = 4 / q
  if div ~= div or div <= 0 then div = 0.25 end
  if div < 1/128 then div = 1/128 end
  if div > 4 then div = 4 end
  return div
end

function safe_swing_delay_for_step(step, div)
  local sw = safe_swing_value(global and global.swing or 0)
  if sw <= 0 then return 0 end
  local d = tonumber(div) or safe_step_division()
  if d ~= d or d <= 0 then d = 0.25 end
  -- Delay even numbered sequencer columns. This is the classic 16th swing feel:
  -- 0% = straight, 50% = clear shuffle, 75% = heavy but still protected.
  local stp = tonumber(step) or 1
  if (stp % 2) == 0 then return math.max(0, math.min(d * sw, d * 0.75)) end
  return 0
end

function run_column_with_timing_delay(div)
  local delay = safe_swing_delay_for_step(play_step, div or safe_step_division())
  if delay > 0 then clock.sleep(delay) end
  run_sequencer_column()
end

function crow_quantize_multiplier()
  local q = safe_quantize_value(global and global.quantize or 16)
  if q > 16 then return math.max(1, math.floor((q / 16) + 0.5)) end
  return 1
end

function crow_quantize_should_advance()
  local q = safe_quantize_value(global and global.quantize or 16)
  if q >= 16 then return true end
  if not CROW_MOD then CROW_MOD = {} end
  local divider = math.max(1, math.floor((16 / q) + 0.5))
  CROW_MOD.crow_quantize_counter = ((CROW_MOD.crow_quantize_counter or 0) + 1) % divider
  return CROW_MOD.crow_quantize_counter == 0
end

local function default_env()
  return { attack = 0.02, decay = 0.18, sustain = 0.75, release = 0.28 }
end

local function ensure_step_env(st)
  if type(st.env) ~= "table" then st.env = default_env() end
  st.env.attack = clamp(tonumber(st.env.attack) or 0.02, 0, 1)
  st.env.decay = clamp(tonumber(st.env.decay) or 0.18, 0, 1)
  st.env.sustain = clamp(tonumber(st.env.sustain) or 0.75, 0, 1)
  st.env.release = clamp(tonumber(st.env.release) or 0.28, 0, 1)
  return st.env
end

local function default_eq()
  return { low = 0.0, lomid = 0.0, himid = 0.0, high = 0.0, low_x = 0.10, lomid_x = 0.36, himid_x = 0.64, high_x = 0.90 }
end

local function ensure_eq_table(t)
  if type(t) ~= "table" then t = default_eq() end
  t.low = clamp(tonumber(t.low) or 0, -1, 1)
  t.lomid = clamp(tonumber(t.lomid) or 0, -1, 1)
  t.himid = clamp(tonumber(t.himid) or 0, -1, 1)
  t.high = clamp(tonumber(t.high) or 0, -1, 1)
  t.low_x = clamp(tonumber(t.low_x) or 0.10, 0.00, 0.30)
  t.lomid_x = clamp(tonumber(t.lomid_x) or 0.36, 0.18, 0.52)
  t.himid_x = clamp(tonumber(t.himid_x) or 0.64, 0.48, 0.82)
  t.high_x = clamp(tonumber(t.high_x) or 0.90, 0.70, 1.00)
  return t
end

local function active_eq(st)
  -- The screen/Arc must show the selected step lock only while P-lock editing is
  -- active. Outside P-lock mode, edits target and display the global EQ.
  if grid_plock_mode and st and st.locks and type(st.locks.eq) == "table" then
    return ensure_eq_table(st.locks.eq)
  end
  return ensure_eq_table(eq)
end

function muta_playback_eq(st)
  -- Playback always honors the EQ lock stored on the sounding step, regardless
  -- of which page or P-lock editing mode is currently visible.
  if st and st.locks and type(st.locks.eq) == "table" then
    return ensure_eq_table(st.locks.eq)
  end
  return ensure_eq_table(eq)
end

local function eq_edit_target()
  local st = data.tracks[selected_track].steps[selected_step]
  if grid_plock_mode then
    st.locks = st.locks or {}
    st.locks.eq = st.locks.eq or deep_copy(ensure_eq_table(eq))
    return ensure_eq_table(st.locks.eq), true
  end
  return ensure_eq_table(eq), false
end


function muta_ensure_pitch_lock(st)
  st = type(st) == "table" and st or {}
  st.locks = st.locks or {}
  local pl = st.locks.pitch
  if type(pl) ~= "table" then
    -- V12.5.1: PITCH P-locks store a RELATIVE chromatic interval, not a
    -- frozen copy of the global pitch state. Global ROOT/SCALE/OCTAVE remain
    -- the live reference, so transposing the pattern also transposes every
    -- locked step while preserving its interval.
    pl = {
      relative_note = true,
      note_offset = clamp(tonumber(st.note) or 0, -36, 36),
      rnd = pitch.rnd or 0,
      range = pitch.range or 1,
      density = pitch.density or 1,
    }
    st.locks.pitch = pl
  elseif not pl.relative_note then
    -- Legacy migration: old PITCH locks froze root/octave plus a note offset.
    -- Convert that frozen audible displacement into one offset relative to the
    -- CURRENT global pitch. This preserves the old note at migration time, then
    -- lets it follow all later global transpositions.
    local legacy_root = tonumber(pl.root) or pitch.root or 48
    local legacy_oct = tonumber(pl.octave) or pitch.octave or 0
    local legacy_note = tonumber(pl.note) or tonumber(st.note) or 0
    local global_root = pitch.root or 48
    local global_oct = pitch.octave or 0
    pl.note_offset = clamp(legacy_note + (legacy_root - global_root) + ((legacy_oct - global_oct) * 12), -36, 36)
    pl.relative_note = true
  end
  pl.note_offset = clamp(tonumber(pl.note_offset) or tonumber(pl.note) or tonumber(st.note) or 0, -36, 36)
  -- Keep legacy fields readable in presets/sidecars, but playback no longer
  -- freezes global ROOT/SCALE/OCTAVE for relative-note locks.
  pl.note = pl.note_offset
  pl.rnd = clamp(tonumber(pl.rnd) or pitch.rnd or 0, 0, 1)
  pl.range = clamp(math.floor((tonumber(pl.range) or pitch.range or 1) + 0.5), 0, 3)
  pl.density = clamp(tonumber(pl.density) or pitch.density or 1, 0, 1)
  return pl
end

function muta_pitch_edit_target()
  local st = data.tracks[selected_track].steps[selected_step]
  if grid_plock_mode then
    return muta_ensure_pitch_lock(st), st, true
  end
  return pitch, st, false
end

function muta_pitch_view()
  local target, st, locked = muta_pitch_edit_target()
  local note_offset = locked and (target.note_offset or target.note or st.note or 0) or (st.note or 0)
  return {
    root = pitch.root or 48,
    scale = pitch.scale or 1,
    octave = pitch.octave or 0,
    rnd = locked and (target.rnd or pitch.rnd or 0) or (pitch.rnd or 0),
    range = locked and (target.range or pitch.range or 1) or (pitch.range or 1),
    density = locked and (target.density or pitch.density or 1) or (pitch.density or 1),
    note = note_offset,
  }, st, locked
end

-- V12.5.1: transpose the global pattern reference. Step note offsets (including
-- relative P-lock offsets) are deliberately untouched, so every interval is
-- preserved while the complete pattern moves up/down.
function muta_transpose_global_pitch(delta)
  delta = tonumber(delta) or 0
  if delta == 0 then return end
  pitch.root = clamp((pitch.root or 48) + delta, 24, 84)
end


-- V10.3 OPTIM: single macro that reads the existing GLOBAL/MTX "mutation
-- spread" + "propagation chance" params and turns them into one 0..1 chaos
-- amount. No new param, no new UI page -- it just lets the patch-wide
-- mutation knobs the user already has also nudge EUCLID and mutation-driven
-- sample drift, instead of only affecting note propagation.
function global_chaos_amount()
  local spread = clamp((tonumber(global.mutation_spread) or 0) / 4, 0, 1)
  local chance = clamp(tonumber(global.propagation_chance) or 0, 0, 1)
  return clamp((spread * 0.6) + (chance * 0.4), 0, 1)
end

local function default_sample_region()
  return {
    start = 0.0,
    finish = 1.0,
    path = nil,
    name = nil,
    slot = 0,
    rnd_pos = 0.0,   -- probability: randomize the play window position at sample trigger
    lfo_depth = 0.0, -- amount: modulate play window size at sample trigger
    lfo_rate = 0.20, -- slow Lua-rate LFO, evaluated only at trigger time
  }
end

local function ensure_step_sample(st)
  if type(st.sample) ~= "table" then st.sample = default_sample_region() end
  st.sample.start = clamp(tonumber(st.sample.start) or 0.0, 0, 1)
  st.sample.finish = clamp(tonumber(st.sample.finish) or 1.0, 0, 1)
  if st.sample.finish <= st.sample.start then st.sample.finish = clamp(st.sample.start + 0.01, 0.01, 1) end
  st.sample.path = type(st.sample.path) == "string" and st.sample.path or nil
  st.sample.name = type(st.sample.name) == "string" and st.sample.name or nil
  st.sample.rnd_pos = clamp(tonumber(st.sample.rnd_pos) or 0.0, 0, 1)
  st.sample.lfo_depth = clamp(tonumber(st.sample.lfo_depth) or 0.0, 0, 1)
  st.sample.lfo_rate = clamp(tonumber(st.sample.lfo_rate) or 0.20, 0.01, 4.0)
  st.sample_mode = clamp(tonumber(st.sample_mode) or 2, 1, 3)
  return st.sample
end

local function sample_region_for_trigger(st)
  -- Lightweight sample-window modulation: evaluated once per trigger, not audio-rate.
  local sr = ensure_step_sample(st)
  local base_start = clamp(sr.start or 0, 0, 1)
  local base_finish = clamp(sr.finish or 1, base_start + 0.01, 1)
  local base_width = clamp(base_finish - base_start, 0.01, 1.0)
  local width = base_width

  if (sr.lfo_depth or 0) > 0 then
    local rate = clamp(sr.lfo_rate or 0.20, 0.01, 4.0)
    local phase = math.sin(util.time() * rate * math.pi * 2)
    width = clamp(base_width * (1.0 + phase * (sr.lfo_depth or 0)), 0.01, 1.0)
  end

  local start
  if (sr.rnd_pos or 0) > 0 and math.random() < (sr.rnd_pos or 0) then
    start = math.random() * math.max(0, 1.0 - width)
  else
    local center = (base_start + base_finish) * 0.5
    start = clamp(center - width * 0.5, 0, math.max(0, 1.0 - width))
  end

  local finish = clamp(start + width, 0.01, 1)

  -- V10.3 OPTIM: tie the sample window to the same mutation/chaos amounts
  -- that already drive the synth sources (mtx.* + global chaos), so the
  -- sample source mutates over time instead of staying static. Purely
  -- additive: with no active mutation locks this is a no-op (drift = 0).
  local active_mtx = (st.locks and st.locks.mutations) or st.mutations or {}
  local mut_amt = muta_crow.mutation_amount(active_mtx)
  local chaos_amt = mut_amt > 0 and global_chaos_amount() or 0
  if mut_amt > 0 then
    start, finish = muta_music.drift_sample_region(start, finish, mut_amt, chaos_amt)
  end

  return {
    start = clamp(start, 0, 1),
    finish = clamp(finish, 0.01, 1),
  }
end

local last_loaded_sample_path = nil

local function load_sample_for_step_if_needed(st)
  local sr = ensure_step_sample(st)
  if type(sr.path) ~= "string" or sr.path == "" then return end
  if sr.path ~= last_loaded_sample_path then
    if engine.load_sample then engine.load_sample(sr.path) end
    last_loaded_sample_path = sr.path
  end
end


local function make_step(i)
  return {
    active = false,
    source = 1, -- 1 sine, 2 noise, 3 sub, 4 FM, 5 sample
    sample_mode = 2, -- 1 GATED, 2 ONE SHOT, 3 LOOP (sample source only)
    note = 0, -- scale degree offset from pitch.root, quantized at trigger time
    mutations = {
      -- v8.8: neutral mutation start. No grain/fold/FM/phase/noise is applied
      -- until the user explicitly sets it or captures it as a P-lock.
      grain = 0.0,
      fold = 0.0,
      fm = 0.0,
      phase = 0.0,
      noise = 0.0,
    },
    mutation_prob = 0.0, -- mutation chance, not trigger chance
    trig_prob = 1.0, -- actual probability that an active step triggers sound
    level = 0.75, -- per-step/source volume
    env = default_env(), -- per-step ADSR, works on every source including sample
    sample = default_sample_region(), -- per-step sample start/end region
    locks = {}, -- P-locks: optional per-step parameter overrides
    arp = { enabled = false, mode = 1, octaves = 1, rate = 1, gate = 0.78, index = 1, muta = 0.0, mem = 0.45, chaos = 0.12, muta_pos = 1, muta_dir = 1, motif_pos = 1, motif_id = 1, last_role = 1, micro = 0.0 },
    euclid = muta_euclid.default(),
  }
end

local function init_data()
  for t=1,NUM_TRACKS do
    data.tracks[t] = { level = 0.75, mute = false, root = 48 + (t-1)*3, euclid = muta_euclid.default(), steps = {} }
    for s=1,NUM_STEPS do data.tracks[t].steps[s] = make_step(s + t) end
  end
end

local function ensure_all_steps()
  if not data or type(data.tracks) ~= "table" then return end
  for t=1,NUM_TRACKS do
    local tr = data.tracks[t]
    if tr and type(tr.steps) == "table" then
      if type(tr.euclid) ~= "table" then
        -- Migration: preserve the first enabled legacy per-step Euclid setup.
        local legacy = nil
        for si=1,NUM_STEPS do
          local oldeu = tr.steps[si] and tr.steps[si].euclid
          if type(oldeu) == "table" and oldeu.enabled == true then legacy = oldeu; break end
        end
        tr.euclid = muta_euclid.ensure(legacy or muta_euclid.default())
      else
        tr.euclid = muta_euclid.ensure(tr.euclid)
      end
      for s=1,NUM_STEPS do
        if tr.steps[s] then ensure_step_env(tr.steps[s]); ensure_step_sample(tr.steps[s]); ensure_step_arp(tr.steps[s]) end
      end
    end
  end
end


local function strip_source_locks_from_state()
  if not data or type(data.tracks) ~= "table" then return end
  for t=1,NUM_TRACKS do
    local tr = data.tracks[t]
    if tr and type(tr.steps) == "table" then
      for s=1,NUM_STEPS do
        local st = tr.steps[s]
        if st and type(st.locks) == "table" then st.locks.source = nil end
      end
    end
  end
end


function muta_migrate_relative_pitch_locks()
  if not data or type(data.tracks) ~= "table" then return end
  for t=1,NUM_TRACKS do
    local tr = data.tracks[t]
    if tr and type(tr.steps) == "table" then
      for si=1,NUM_STEPS do
        local st = tr.steps[si]
        if st and st.locks and type(st.locks.pitch) == "table" and not st.locks.pitch.relative_note then
          muta_ensure_pitch_lock(st)
        end
      end
    end
  end
end

function strip_env_arp_euclid_locks_from_state()
  if not data or type(data.tracks) ~= "table" then return end
  for t=1,NUM_TRACKS do
    local tr = data.tracks[t]
    if tr and type(tr.steps) == "table" then
      for s=1,NUM_STEPS do
        local st = tr.steps[s]
        if st and type(st.locks) == "table" then
          st.locks.env = nil
          st.locks.arp = nil
          st.locks.euclid = nil
        end
      end
    end
  end
end

local function scale_notes()
  return muta_music.scale_notes(scale_intervals, pitch.scale)
end

local function quantize_to_scale(note)
  return muta_music.quantize_to_scale(note, pitch, scale_intervals)
end

local function step_note(t, s)
  local st = data.tracks[t].steps[s]
  local tr = data.tracks[t]
  local args = muta_music.step_note_args(st, tr, pitch, CROW_MOD)
  if args.scale == 1 then return clamp(math.floor(args.raw + 0.5), 12, 108) end
  return muta_music.quantize_to_scale_values(args.raw, args.root, args.scale, scale_intervals)
end

local function randomize_step_pitch(t, s)
  local notes = scale_notes()
  local scale_len = #notes
  local degree = math.random(0, scale_len - 1)
  local octave_range = clamp(tonumber(pitch.range) or 1, 0, 3)
  local oct = octave_range > 0 and math.random(-octave_range, octave_range) * 12 or 0
  local iv = notes[degree + 1]
  data.tracks[t].steps[s].note = clamp(iv + oct, -36, 36)
end

local function randomize_track_pitch(t)
  local dens = clamp(pitch.density or 1.0, 0, 1)
  for s=1,NUM_STEPS do
    if math.random() <= dens then randomize_step_pitch(t, s) end
  end
end

local function randomize_all_pitch()
  for t=1,NUM_TRACKS do randomize_track_pitch(t) end
  perf_flash = "rnd pitch all"
  dirty = true
end

local function euclid_hit(step, pulses, steps, rotation)
  return muta_euclid.hit(step, pulses, steps, rotation)
end

local function density()
  local hits = 0
  for t=1,NUM_TRACKS do
    local tr = data.tracks[t]
    for s=1,NUM_STEPS do if tr.steps[s].active then hits = hits + 1 end end
  end
  return hits / (NUM_TRACKS * NUM_STEPS)
end

local function mutate_step(t, s, amount, propagate_into_locks)
  local tr = data.tracks[t]
  if not tr or type(tr.steps) ~= "table" then return false end
  local st = tr.steps[s]
  if not st then return false end
  if type(st.mutations) ~= "table" then
    st.mutations = {grain=0, fold=0, fm=0, phase=0, noise=0}
  end
  local function nudge(v, amt) return clamp((tonumber(v) or 0) + rndf(-amt, amt), 0, 1) end
  local function nudge_mtx(mtx, amt)
    if type(mtx) ~= "table" then return end
    mtx.grain = nudge(mtx.grain, amt)
    mtx.fold = nudge(mtx.fold, amt)
    mtx.fm = nudge(mtx.fm, amt)
    mtx.phase = nudge(mtx.phase, amt)
    mtx.noise = nudge(mtx.noise, amt)
  end

  nudge_mtx(st.mutations, amount)

  -- Important V10 propagation audit fix:
  -- playback uses st.locks.mutations when a MUTATION P-lock exists. Earlier
  -- propagation only changed st.mutations, so any step with a mutation P-lock
  -- could be visibly contaminated but audibly unchanged. Propagation now also
  -- nudges the locked mutation block when present, preserving P-lock structure
  -- while making propagated changes actually reach the engine.
  if propagate_into_locks and st.locks and type(st.locks.mutations) == "table" then
    nudge_mtx(st.locks.mutations, amount)
  end

  st.mutation_prob = clamp((tonumber(st.mutation_prob) or 0) + rndf(-amount * 0.5, amount * 0.5), 0, 1)
  return true
end

local function propagate(t, s)
  local spread = math.floor(tonumber(global.mutation_spread) or 0)
  if spread <= 0 then return 0 end
  local evo = (CROW_MOD and CROW_MOD.evolution) or 0
  spread = clamp(spread + math.floor(evo * 3 + 0.5), 0, 4)
  local mode = clamp(math.floor(tonumber(global.propagation_mode) or 1), 1, 4)
  local decay = clamp((tonumber(global.propagation_decay) or 0.62) + evo * 0.20, 0.10, 1.00)
  local chance = clamp((tonumber(global.propagation_chance) or 0.52) + evo * 0.48, 0, 1)
  local hits = 0

  local function contaminate(tt, ss, amount)
    if mutate_step(wrap(tt, 1, NUM_TRACKS), wrap(ss, 1, NUM_STEPS), amount, true) then
      hits = hits + 1
    end
  end

  for d=1,spread do
    -- Slightly stronger than V9.1.3: the old 0.09 base often felt invisible,
    -- especially because changes are heard only when the target step later plays.
    local amount = 0.13 * (1 + (((CROW_MOD and CROW_MOD.evolution) or 0) * 1.4)) * (decay ^ (d - 1))
    if mode == 1 then -- linear: left/right neighbours
      contaminate(t, s - d, amount)
      contaminate(t, s + d, amount)
    elseif mode == 2 then -- organic: probable left/right drift
      if math.random() < chance then contaminate(t, s - d, amount) end
      if math.random() < chance then contaminate(t, s + d, amount) end
    elseif mode == 3 then -- fungal: same step leaks to neighbouring tracks
      if math.random() < chance then contaminate(t - d, s, amount * 0.75) end
      if math.random() < chance then contaminate(t + d, s, amount * 0.75) end
    elseif mode == 4 then -- viral: small random contamination around the grid
      for i=1,2 do
        if math.random() < chance then
          contaminate(math.random(1, NUM_TRACKS), s + math.random(-spread, spread), amount * 0.65)
        end
      end
    end
  end
  return hits
end

local function mutate_all(intensity)
  intensity = clamp(intensity or 0.20, 0.02, 1.0)
  for t=1,NUM_TRACKS do
    for s=1,NUM_STEPS do
      local st = data.tracks[t].steps[s]
      if st.active then
        mutate_step(t, s, 0.18 * intensity, true)
        if math.random() < 0.35 * intensity then st.mutation_prob = clamp(st.mutation_prob + rndf(-0.08, 0.08), 0, 1) end
        if math.random() < 0.25 * intensity then st.trig_prob = clamp((st.trig_prob or 1) + rndf(-0.12, 0.12), 0.05, 1) end
      end
    end
  end
  perf_flash = "mutate all"
  dirty = true
end

local function out_allows_audio()
  return out.dest == 1 or out.dest == 2 or out.dest == 3 or out.dest == 7
end

local function out_allows_midi()
  return global.midi_enable == 2 and (out.dest == 2 or out.dest == 4 or out.dest == 6 or out.dest == 7)
end

local function out_allows_cv()
  return global.crow_enable == 2 and (out.dest == 3 or out.dest == 5 or out.dest == 6 or out.dest == 7)
end

local function send_crow(t, note, amp, st)
  if not out_allows_cv() then return end
  if not crow then return end

  local cv = muta_crow.build_values(note, amp, st, global, density())
  local volts = cv.volts
  local mut = cv.mut
  local evo = cv.evo
  local dens = cv.dens

  CROW_MOD.cv3 = cv.cv3
  CROW_MOD.cv4 = cv.cv4

  pcall(function()
    if out.cv_mode == 1 then -- 1V/OCT + DNA modulation
      crow.output[1].volts = volts
      crow.output[2].action = "pulse(0.01,5)"
      crow.output[2]()
      crow.output[3].volts = mut * 5      -- MUTA DNA mutation amount
      crow.output[4].volts = evo * 5      -- MUTA DNA evolution/propagation energy
    elseif out.cv_mode == 2 then -- modulation organism only
      crow.output[1].volts = mut * 5
      crow.output[2].volts = cv.phase * 5
      crow.output[3].volts = cv.amp * 5
      crow.output[4].volts = dens * 5
      CROW_MOD.cv3 = cv.amp * 5
      CROW_MOD.cv4 = dens * 5
    else -- hybrid: pitch/gate + mutation/evolution
      crow.output[1].volts = volts
      crow.output[2].action = "pulse(0.01,5)"
      crow.output[2]()
      crow.output[3].volts = mut * 5
      crow.output[4].volts = evo * 5
    end
  end)
end

local function send_midi(note, vel, dur, st, track_id)
  if not out_allows_midi() or m == nil then return end
  local ch = global.midi_channel
  local cc = out.cc_base + ((track_id or 1) - 1) * 4
  local function cc_send(num, val)
    if m.cc then m:cc(num, clamp(math.floor(val * 127 + 0.5), 0, 127), ch) end
  end

  if out.midi_mode == 2 or out.midi_mode == 3 then
    local muts = st and st.mutations or {}
    cc_send(cc, muts.fm or 0)
    cc_send(cc + 1, muts.fold or 0)
    cc_send(cc + 2, muts.phase or 0)
    cc_send(cc + 3, muts.noise or 0)
  end

  if out.midi_mode == 1 or out.midi_mode == 2 then
    m:note_on(note, vel, ch)
    clock.run(function()
      clock.sleep(dur)
      m:note_off(note, 0, ch)
    end)
  end
end

-- v8.10.1: SOURCE locks must affect trigger and mutation probability at playback,
-- not only be stored for recall. These helpers read the locked SOURCE block when
-- present, while keeping legacy steps fully compatible.
local function step_trig_probability(st)
  local src_lock = st and st.locks and st.locks.source or nil
  local p = clamp((src_lock and src_lock.trig_prob) or (st and st.trig_prob) or 1.0, 0, 1)
  -- Crow IN2 DENS mode lets Eurorack voltage thin/fill the pattern without
  -- rewriting steps: 0V = sparse, 5V = original density.
  if CROW_MOD and CROW_MOD.density_active then
    p = p * (0.12 + clamp(CROW_MOD.density or 0, 0, 1) * 0.88)
  end
  return clamp(p, 0, 1)
end

local function step_mutation_probability(st)
  local p = clamp((st and st.mutation_prob) or 0.0, 0, 1)
  if CROW_MOD then
    p = p + ((CROW_MOD.mutation or 0) * 0.60) + ((CROW_MOD.evolution or 0) * 0.35)
  end
  return clamp(p, 0, 1)
end

-- v8.10.2: ARP/EUCLID locks must be used by playback, not only stored.
-- These helpers return locked copies when present and fall back to the live step.
local function active_arp(st)
  return ensure_step_arp(st)
end

local function active_euclid(t)
  local tr = data.tracks[t]
  if not tr then return muta_euclid.default() end
  tr.euclid = muta_euclid.ensure(tr.euclid)
  return tr.euclid
end

local step_division
local apply_step_locks

local function source_shape(st, tr, note)
  -- MUTA engine mapping for five source types.
  -- 1 sine, 2 noise, 3 sub, 4 FM, 5 sample.
  local mtx = (st.locks and st.locks.mutations) or st.mutations
  local src = st.source
  local shape = {
    note = note,
    amp_mul = 1.0,
    cutoff = 800 + mtx.fm * 6500,
    release = 0.07 + active_arp(st).gate * 0.35 + mtx.grain * 0.35,
    pw = 0.25 + mtx.fold * 0.55,
  }

  if src == 1 then -- sine-ish / clean
    shape.cutoff = 1200 + mtx.fm * 4200
    shape.release = shape.release * 0.9
    shape.pw = 0.50
  elseif src == 2 then -- noise-ish: short, bright, unstable
    shape.note = note + math.floor(rndf(-7, 8))
    shape.cutoff = 3200 + mtx.noise * 5600
    shape.release = 0.025 + mtx.grain * 0.18
    shape.pw = 0.08 + mtx.noise * 0.18
    shape.amp_mul = 0.72
  elseif src == 3 then -- sub: one octave lower, rounder
    shape.note = note - 12
    shape.cutoff = 350 + mtx.fm * 1800
    shape.release = 0.16 + mtx.grain * 0.55
    shape.pw = 0.60 + mtx.fold * 0.25
    shape.amp_mul = 1.08
  elseif src == 4 then -- FM: 2-op shield-safe harmonic source
    shape.cutoff = 950 + mtx.fm * 7200
    shape.release = 0.07 + mtx.grain * 0.34
    shape.pw = 0.30 + mtx.phase * 0.55
    shape.amp_mul = 0.84
  elseif src == 5 then -- sample: one-shot sample voice, pitch follows root/step
    shape.cutoff = 900 + mtx.phase * 7200
    shape.release = 0.10 + mtx.grain * 0.70
    shape.pw = 0.50
    shape.amp_mul = 0.90
  end

  shape.source = src
  shape.cutoff = clamp(shape.cutoff + density() * 2200, 100, 9000)
  shape.release = clamp(shape.release, audio_safe.min_release, 1.2)
  shape.pw = clamp(shape.pw, 0.05, 0.95)
  return shape
end


function ensure_step_arp(st)
  if type(st) ~= "table" then
    return { enabled=false, mode=1, octaves=1, rate=1, gate=0.78, index=1, muta=0, mem=0.45, chaos=0.12, muta_pos=1, muta_dir=1, motif_pos=1, motif_id=1, last_role=1, micro=0 }
  end
  if type(st.arp) ~= "table" then
    st.arp = { enabled=false, mode=1, octaves=1, rate=1, gate=0.78, index=1, muta=0, mem=0.45, chaos=0.12, muta_pos=1, muta_dir=1, motif_pos=1, motif_id=1, last_role=1, micro=0 }
  end
  return muta_arp_runtime.ensure(st.arp, audio_safe and audio_safe.max_arp_rate or 4)
end

function arp_mode_name(mode)
  return muta_arp_runtime.mode_name(mode)
end

function arp_scale_degree_count()
  local notes = scale_notes()
  return math.max(1, #notes), notes
end

function arp_note_from_degree(deg, arp)
  local n, notes = arp_scale_degree_count()
  local octaves = math.max(1, arp.octaves or 1)
  local span = math.max(1, n * octaves)
  local p = (deg or 0) % span
  local degree = p % n
  local octave = math.floor(p / n)
  return (notes[degree + 1] or 0) + octave * 12, p, span, n
end

function arp_weighted_choice(items)
  return muta_arp_runtime.weighted_choice(items)
end

function arp_harmonic_role_step(arp)
  -- Role offsets in scale degrees:
  -- 0 root, 2 third, 4 fifth, 6 seventh, 1 ninth-ish, 3 eleventh-ish, 5 thirteenth-ish.
  -- These are scale-degree roles, so they remain coherent in the selected mode.
  local muta = arp.muta or 0
  local mem = arp.mem or 0.45
  local chaos = arp.chaos or 0.12
  local last = arp.last_role or 1

  local motifs = {
    {1,3,5,3},
    {1,5,3,6},
    {1,3,4,5},
    {5,3,1,2},
    {1,4,6,5},
  }
  local motif = motifs[arp.motif_id or 1] or motifs[1]
  local motif_pos = ((arp.motif_pos or 1) - 1) % #motif + 1
  local role_from_motif = motif[motif_pos] or 1
  arp.motif_pos = motif_pos + 1

  -- Memory means motif identity and contour are preserved.
  if math.random() > mem then
    arp.motif_id = wrap((arp.motif_id or 1) + (math.random(0,1)==0 and -1 or 1), 1, #motifs)
  end

  -- MUTA progressively opens the harmonic palette from chord tones to extensions.
  local items = {
    {1, 6.0},                     -- root
    {3, 4.8 + muta * 2.0},        -- third
    {5, 5.6 + muta * 2.5},        -- fifth
    {6, 1.5 + muta * 4.0},        -- seventh
    {2, 0.6 + muta * 3.4},        -- ninth / passing
    {4, 0.3 + muta * 2.6},        -- eleventh / suspension
    {7, 0.2 + muta * 2.2},        -- thirteenth / color
  }

  local role
  if math.random() < mem then
    role = role_from_motif
  else
    role = arp_weighted_choice(items)
  end

  -- Voice-leading bias: avoid huge jumps unless CHAOS asks for it.
  if mem > 0.35 and math.random() < mem then
    local diff = role - last
    if math.abs(diff) > 3 then
      role = last + (diff > 0 and 2 or -2)
      role = wrap(role, 1, 7)
    end
  end

  -- Controlled accident: borrowed/side-step role, but still scale-aware.
  if chaos > 0 and math.random() < chaos * 0.55 then
    role = wrap(role + (math.random(0,1)==0 and -1 or 1), 1, 7)
  end

  arp.last_role = role
  return role
end

function arp_micro_offset_for_role(role, arp)
  return muta_arp_runtime.micro_offset_for_role(role, arp)
end

function arp_trio_offset(st, arp)
  local n = arp_scale_degree_count()
  local span = math.max(1, n * math.max(1, arp.octaves or 1))
  local pos = ((arp.muta_pos or arp.index or 1) - 1) % span

  local role = arp_harmonic_role_step(arp)
  local role_degree = ({0,2,4,6,1,3,5})[role] or 0

  local dir = arp.muta_dir or 1
  if math.random() > (arp.mem or 0.45) then dir = math.random(0,1)==0 and -1 or 1 end
  arp.muta_dir = dir

  -- MUTA determines how far the new harmonic role can pull from the classic arp contour.
  local pull = 1 + math.floor((arp.muta or 0) * 3.0 + 0.5)
  local target = role_degree + (math.floor(pos / n) * n)
  if math.abs(target - pos) > pull then
    pos = pos + (target > pos and pull or -pull)
  else
    pos = target
  end

  -- MEM stabilizes contour; lower MEM lets the phrase breathe more.
  if (arp.mem or 0) < 0.45 and math.random() < (0.45 - (arp.mem or 0)) then
    pos = pos + dir
  end

  -- CHAOS adds real movement: larger leaps, borrowed color, subtle microtonal offset.
  if (arp.chaos or 0) > 0 and math.random() < (arp.chaos or 0) then
    pos = pos + math.random(-3,3)
  end

  pos = pos % span
  arp.muta_pos = pos + 1
  arp.micro = arp_micro_offset_for_role(role, arp)
  local off = arp_note_from_degree(pos, arp)
  return off + (arp.micro or 0)
end

local function arp_offset(st)
  local arp = active_arp(st)
  if not arp.enabled then return 0 end
  local intervals = {0,3,7,10}
  local octaves = math.max(1,arp.octaves)
  local span = octaves * #intervals

  -- WALK/DNA primary modes and ARP MUTA injection all use the new TRIO engine.
  -- This is still one offset per sub-note: no extra voices, no audio-rate CPU cost.
  if arp.mode == 5 or arp.mode == 6 or ((arp.muta or 0) > 0 and math.random() < (arp.muta or 0)) then
    arp.index = arp.index + 1
    return arp_trio_offset(st, arp)
  end

  local idx=(arp.index-1)%span
  local degree=idx % #intervals
  local octave=math.floor(idx/#intervals)
  if arp.mode == 2 then
    degree=(#intervals-1)-degree; octave=(octaves-1)-octave
  elseif arp.mode == 3 then
    local cycle=span*2-2
    local pos=(arp.index-1)%math.max(1,cycle)
    if pos>=span then pos=cycle-pos end
    degree=pos%#intervals; octave=math.floor(pos/#intervals)
  elseif arp.mode == 4 then
    degree=math.random(0,#intervals-1); octave=math.random(0,octaves-1)
  end
  arp.index=arp.index+1
  return intervals[degree+1]+octave*12
end

local function fire_voice(t, st, note, amp_mul)
  if audio_safe.voices_this_step >= audio_safe.max_voices_per_step then return end
  audio_safe.voices_this_step = audio_safe.voices_this_step + 1
  local tr = data.tracks[t]
  local shape = source_shape(st, tr, note)
  local env = ensure_step_env(st)
  local attack = (env.attack or 0.02) ^ 2 * 1.5
  local decay = 0.01 + ((env.decay or 0.18) ^ 2 * 1.8)
  local sustain = clamp(env.sustain or 0.75, 0, 1)
  local release = math.max(0.02 + ((env.release or 0.28) ^ 2 * 3.0), shape.release * 0.35)
  local hz = musicutil.note_num_to_freq(shape.note)
  local mtx = (st.locks and st.locks.mutations) or st.mutations
  local step_level = st.level or 0.75
  amp_mul = clamp(tonumber(amp_mul) or 1.0, 0.55, 1.35)
  local amp = clamp(tr.level * step_level * (0.42 + mtx.grain * 0.58) * shape.amp_mul * amp_mul, 0, 1)

  -- Prefer one compact engine call per voice to avoid OSC bursts that can crackle on shield.
  if out_allows_audio() then
    if engine.trig then
      local sr
      if (shape.source or st.source) == 5 then
        load_sample_for_step_if_needed(st)
        sr = sample_region_for_trigger(st)
      else
        sr = ensure_step_sample(st)
      end
      local sample_mode = st.sample_mode or 2
      local eqv = muta_playback_eq(st)
      engine.trig(hz, amp, attack, decay, sustain, release, shape.cutoff, shape.pw, 0, shape.source or st.source,
        mtx.grain, mtx.fold, mtx.fm, mtx.phase, mtx.noise, sr.start or 0, sr.finish or 1, sample_mode,
        eqv.low or 0, eqv.lomid or 0, eqv.himid or 0, eqv.high or 0,
        eqv.low_x or 0.10, eqv.lomid_x or 0.36, eqv.himid_x or 0.64, eqv.high_x or 0.90,
        fx_lock_active(st and st.locks and st.locks.fx or nil) and 1 or 0)
    else
      engine.source(shape.source or st.source)
      engine.grain(mtx.grain)
      engine.fold(mtx.fold)
      engine.fm(mtx.fm)
      engine.phase(mtx.phase)
      engine.noise(mtx.noise)
      engine.release(release)
      engine.pw(shape.pw)
      engine.cutoff(shape.cutoff)
      engine.amp(amp)
      engine.hz(hz)
    end
  end

  send_midi(shape.note, math.floor(amp * 110), release * 0.5, st, t)
  send_crow(t, shape.note, amp, st)
end

function muta_euclid_fill_candidate(tr, s, eu)
  if tr.steps[s].active or not muta_euclid.base_hit(s, eu) then return false end
  local rank, count = 0, 0
  for i=1,NUM_STEPS do
    if (not tr.steps[i].active) and muta_euclid.base_hit(i, eu) then
      count = count + 1
      if i <= s then rank = rank + 1 end
    end
  end
  return muta_euclid.density_pick(rank, count, eu.add or 0.25)
end

function muta_euclid_fill_source(tr, output_step)
  -- Added events inherit the closest preceding written event, cyclically.
  -- This keeps FILL inside the musical vocabulary of the current pattern.
  for distance=1,NUM_STEPS do
    local source = ((output_step - distance - 1) % NUM_STEPS) + 1
    if tr.steps[source].active then return source end
  end
  return output_step
end

function muta_euclid_shift_source(tr, output_step, eu)
  local active_count = 0
  for i=1,NUM_STEPS do if tr.steps[i].active then active_count = active_count + 1 end end
  if active_count == 0 then return nil end
  local rank = 0
  for source=1,NUM_STEPS do
    if tr.steps[source].active then
      rank = rank + 1
      local target = source
      if muta_euclid.density_pick(rank, active_count, eu.morph or 0) then
        target = muta_euclid.nearest_hit(source, eu, NUM_STEPS)
      end
      if target == output_step then return source end
    end
  end
  return nil
end

local function trigger_track(t, s)
  local tr = data.tracks[t]
  if tr.mute then return end
  local eu = active_euclid(t)
  if eu.enabled and s == 1 then
    if eu.started then tr.euclid = muta_euclid.advance_cycle(eu); eu = tr.euclid
    else eu.started = true end
  end

  local source_step = s
  local should_fire = tr.steps[s].active
  local amp_mul = 1.0

  if eu.enabled then
    local mode = eu.mode or 1
    if mode == 1 then -- MASK: intersection SEQ x EUCLID
      should_fire = tr.steps[s].active and muta_euclid.base_hit(s, eu)
    elseif mode == 2 then -- FILL: preserve SEQ, add deterministic Euclid events
      should_fire = tr.steps[s].active or muta_euclid_fill_candidate(tr, s, eu)
      if not tr.steps[s].active and should_fire then
        source_step = muta_euclid_fill_source(tr, s)
        amp_mul = 0.82
      end
    elseif mode == 3 then -- SHIFT: move a MORPH-selected fraction toward Euclid hits
      source_step = muta_euclid_shift_source(tr, s, eu)
      should_fire = source_step ~= nil
    elseif mode == 4 then -- ORBIT: independent Euclid length/rotation crosses SEQ
      should_fire = tr.steps[s].active and muta_euclid.base_hit(s, eu)
      -- MORPH blends dry SEQ back into the orbit deterministically.
      if tr.steps[s].active and not should_fire then
        local active_rank, active_count = 0, 0
        for i=1,NUM_STEPS do
          if tr.steps[i].active then
            active_count = active_count + 1
            if i <= s then active_rank = active_rank + 1 end
          end
        end
        should_fire = not muta_euclid.density_pick(active_rank, active_count, eu.morph or 1)
      end
    end
  end

  if not should_fire then return end
  local st = tr.steps[source_step]
  if math.random() > step_trig_probability(st) then return end

  apply_step_locks(st)
  local active_mtx = (st.locks and st.locks.mutations) or st.mutations
  local active_ar = active_arp(st)
  local base_note = step_note(t, source_step) + math.floor((active_mtx.phase or 0) * 7)
  local rate = active_ar.enabled and math.min(math.max(1, active_ar.rate), audio_safe.max_arp_rate) or 1

  fire_voice(t, st, base_note + arp_offset(st), amp_mul)

  if active_ar.enabled and rate > 1 then
    clock.run(function()
      local div = step_division() / rate
      for i=2,rate do
        clock.sleep(div)
        fire_voice(t, st, base_note + arp_offset(st), amp_mul)
      end
    end)
  end

  if math.random() < step_mutation_probability(st) then
    mutate_step(t, source_step, 0.12, true)
    propagate(t, source_step)
  end
end

local function current_state()
  return {
    version = MUTA_VERSION,
    data = deep_copy(data),
    fx = deep_copy(fx),
    eq = deep_copy(eq),
    mix = deep_copy(mix),
    out = deep_copy(out),
    pitch = deep_copy(pitch),
    global = deep_copy(global),
    sample_rec = { threshold_db = sample_rec.threshold_db, auto_normalize = sample_rec.auto_normalize, rec_input_gain = sample_rec.rec_input_gain },
    sample_name = sample_name,
    selected_track = selected_track,
    selected_step = selected_step,
    page = page,
    subpage = subpage,
    mix_page = mix_page,
    clock_page = clock_page,
    arp_page = arp_page,
    out_page = OUT_PAGE or 1,
    scenes = deep_copy(scenes),
    focus = {
      fx = fx_focus,
      mix = mix_focus,
      track = track_focus,
      arp = arp_focus,
      euclid = euclid_focus,
      src = src_focus,
      env = env_focus,
      eq = eq_focus,
      pitch = pitch_focus,
      mtx = mtx_focus,
      global = global_focus,
      out = out_focus,
    }
  }
end

local function apply_state(st)
  if type(st) ~= "table" then return end
  if type(st.data) == "table" and type(st.data.tracks) == "table" then data = deep_copy(st.data); ensure_all_steps(); strip_source_locks_from_state(); strip_env_arp_euclid_locks_from_state(); muta_migrate_relative_pitch_locks(); mix.delay = 1.0; mix.reverb = 1.0 end
  if type(st.fx) == "table" then for k,v in pairs(st.fx) do fx[k] = v end end
  if type(st.eq) == "table" then for k,v in pairs(st.eq) do eq[k] = v end; ensure_eq_table(eq) end
  if type(st.mix) == "table" then for k,v in pairs(st.mix) do mix[k] = v end; mix.delay = 1.0; mix.reverb = 1.0 end
  if type(st.out) == "table" then for k,v in pairs(st.out) do out[k] = v end end
  if type(st.pitch) == "table" then for k,v in pairs(st.pitch) do pitch[k] = v end end
  if type(st.global) == "table" then for k,v in pairs(st.global) do global[k] = v end end
  if type(st.sample_rec) == "table" then
    sample_rec.threshold_db = tonumber(st.sample_rec.threshold_db) or sample_rec.threshold_db
    sample_rec.auto_normalize = st.sample_rec.auto_normalize == true
    sample_rec.rec_input_gain = clamp(tonumber(st.sample_rec.rec_input_gain) or sample_rec.rec_input_gain or 2.4, 0.5, 6.0)
    sample_rec.threshold_amp = (10 ^ ((sample_rec.threshold_db or -32) / 20))
  end
  if type(st.sample_name) == "string" then sample_name = st.sample_name end
  if type(st.scenes) == "table" then scenes = deep_copy(st.scenes) end
  selected_track = clamp(tonumber(st.selected_track) or selected_track, 1, NUM_TRACKS)
  selected_step = clamp(tonumber(st.selected_step) or selected_step, 1, NUM_STEPS)
  page = clamp(tonumber(st.page) or page, PAGE_SEQ, #page_names)
  subpage = clamp(tonumber(st.subpage) or subpage, 1, 3)
  mix_page = clamp(tonumber(st.mix_page) or mix_page, 1, 2)
  clock_page = clamp(tonumber(st.clock_page) or clock_page, 1, 2)
  arp_page = clamp(tonumber(st.arp_page) or arp_page, 1, 2)
  OUT_PAGE = clamp(tonumber(st.out_page) or OUT_PAGE or 1, 1, 4)
  if global.midi_transport_out == nil then global.midi_transport_out = 1 end
  if type(st.focus) == "table" then
    fx_focus = tonumber(st.focus.fx) or fx_focus
    mix_focus = tonumber(st.focus.mix) or mix_focus
    track_focus = tonumber(st.focus.track) or track_focus
    arp_focus = tonumber(st.focus.arp) or arp_focus
    euclid_focus = tonumber(st.focus.euclid) or euclid_focus
    src_focus = tonumber(st.focus.src) or src_focus
    env_focus = tonumber(st.focus.env) or env_focus
    eq_focus = tonumber(st.focus.eq) or eq_focus
    pitch_focus = tonumber(st.focus.pitch) or pitch_focus
    mtx_focus = tonumber(st.focus.mtx) or mtx_focus
    global_focus = tonumber(st.focus.global) or global_focus
    out_focus = tonumber(st.focus.out) or out_focus
  end
  playing = false
  sync_fx_engine()
  dirty = true
  if redraw_grid then redraw_grid() end
end

local function mkdir_for_file(filename)
  local dir = tostring(filename or ""):match("^(.+)/[^/]+$")
  if dir then util.make_dir(dir) end
end

-- Hardened native norns PSET integration.
--
-- norns only saves registered params in PARAMETERS > PSET. Most of MUTA's real
-- state is not a simple param: the 6x16 grid, step locks, arp/euclid state,
-- per-step pitch, mutes, sample selection, etc.
--
-- To make PSET/SAVE and PSET/LOAD reliable, MUTA now saves its complete state
-- twice:
--   1. inside the .pset itself as a hidden text param (self-contained);
--   2. next to the .pset as a sidecar fallback file.
--
-- The wrapper below updates the hidden text param BEFORE norns writes the .pset,
-- then applies it AFTER norns reads the .pset. This is more robust than relying
-- only on params.action_write/action_read.

-- MUTA preset management, rebuilt in a conservative MLRE/Eterna style.
--
-- Why: native norns PSET only stores registered params. MUTA's real musical state
-- lives in Lua tables: 6x16 steps, p-locks, source/sample state, mutations,
-- euclid, arp, mutes, pitch, OUT routing, etc. The official norns way to attach
-- complex table data to PSETs is params.action_write/read/delete + tab.save/load.
-- MLRE uses this exact companion-session pattern. Eterna keeps most recallable
-- state as regular params; MUTA needs both normal params and a companion table.
--
-- Important design change from previous attempts:
--   * do NOT override params.write/read/delete;
--   * do NOT depend on hidden text params;
--   * do NOT depend on the PSET name for recall;
--   * store by PSET slot number, with multiple fallbacks.

local function preset_number_from_filename(filename, fallback)
  local n = tonumber(fallback)
  if n then return n end
  if type(filename) == "string" then
    -- norns PSET filenames are usually /dust/data/SCRIPT/SCRIPT-01.pset
    local two = filename:match("%-(%d%d)%.pset$")
    if two then return tonumber(two) end
    local any = filename:match("(%d+)%.pset$")
    if any then return tonumber(any) end
  end
  local ok, slot = pcall(function() return params:get("muta_preset_slot") end)
  return (ok and tonumber(slot)) or 1
end

local function pset_slot_dir(number)
  local n = preset_number_from_filename(nil, number)
  local dir = _path.data .. "MUTA/sessions/" .. string.format("%02d", n) .. "/"
  muta_store.mkdir_p(dir)
  return dir
end

local function pset_slot_file(number)
  return pset_slot_dir(number) .. "muta_session.data"
end

local function manual_slot_file(slot)
  local n = tonumber(slot) or 1
  local dir = _path.data .. "MUTA/muta_slots/"
  muta_store.mkdir_p(dir)
  return dir .. "slot_" .. string.format("%02d", n) .. ".data"
end

local function legacy_slot_file(slot)
  local n = tonumber(slot) or 1
  muta_store.mkdir_p(preset_path)
  return preset_path .. "slot_" .. string.format("%02d", n) .. ".data"
end

local function after_preset_load()
  playing = false
  sync_fx_engine()
  set_clock_source_safe(global.tempo_source)
  dirty = true
  if redraw_grid then redraw_grid() end
  if redraw_arc then redraw_arc() end
end

local function save_muta_state_to(path)
  local ok, err = muta_store.save(current_state(), path)
  if ok then
    perf_flash = "saved"
    print("MUTA SAVE OK: " .. tostring(path))
  else
    perf_flash = "save error"
    print("MUTA SAVE ERROR: " .. tostring(err) .. " path=" .. tostring(path))
  end
  dirty = true
  return ok
end

local function load_muta_state_from(path)
  local st, err = muta_store.load(path)
  if type(st) == "table" then
    apply_state(st)
    after_preset_load()
    perf_flash = "loaded"
    print("MUTA LOAD OK: " .. tostring(path))
    return true
  else
    perf_flash = "load error"
    print("MUTA LOAD ERROR: " .. tostring(err) .. " path=" .. tostring(path))
    dirty = true
    return false
  end
end

local function save_manual_slot()
  local slot = params:get("muta_preset_slot") or 1
  -- save both to the new stable location and the old legacy location so older
  -- test versions can still find data.
  local ok = save_muta_state_to(manual_slot_file(slot))
  save_muta_state_to(legacy_slot_file(slot))
  return ok
end

local function load_manual_slot()
  local slot = params:get("muta_preset_slot") or 1
  if load_muta_state_from(manual_slot_file(slot)) then return true end
  return load_muta_state_from(legacy_slot_file(slot))
end

local function save_native_pset_slot()
  local slot = params:get("muta_preset_slot") or 1
  local name = "MUTA " .. string.format("%02d", slot)
  -- This calls norns' real PSET writer. After it writes the .pset, our
  -- params.action_write callback below saves the companion MUTA session table.
  print("MUTA calling params:write(" .. tostring(slot) .. ", " .. name .. ")")
  params:write(slot, name)
end

local function load_native_pset_slot()
  local slot = params:get("muta_preset_slot") or 1
  print("MUTA calling params:read(" .. tostring(slot) .. ")")
  params:read(slot)
  -- norns reads params but does not always call actions on older systems; bang
  -- regular params, then explicitly load our companion state as a fallback.
  params:bang()
  if not load_muta_state_from(pset_slot_file(slot)) then
    load_manual_slot()
  end
end

local function pset_write_callback(filename, name, number)
  local n = preset_number_from_filename(filename, number)
  print("MUTA action_write filename=" .. tostring(filename) .. " name=" .. tostring(name) .. " number=" .. tostring(number) .. " resolved=" .. tostring(n))
  save_muta_state_to(pset_slot_file(n))
  -- also mirror to the manual slot so the manual loader can rescue it.
  save_muta_state_to(manual_slot_file(n))
end

local function pset_read_callback(filename, silent, number)
  local n = preset_number_from_filename(filename, number)
  print("MUTA action_read filename=" .. tostring(filename) .. " number=" .. tostring(number) .. " resolved=" .. tostring(n))
  if not load_muta_state_from(pset_slot_file(n)) then
    load_muta_state_from(manual_slot_file(n))
  end
end

local function pset_delete_callback(filename, name, number)
  local n = preset_number_from_filename(filename, number)
  os.remove(pset_slot_file(n))
  os.remove(manual_slot_file(n))
  print("MUTA DELETE slot " .. tostring(n))
end

local function install_pset_hooks()
  -- Only the compact muta_store helper is required for session sidecars.
  params.action_write = pset_write_callback
  params.action_read = pset_read_callback
  params.action_delete = pset_delete_callback
end

local function scene_capture(slot)
  slot = clamp(tonumber(slot) or 1, 1, 4)
  local snap = current_state()
  snap.scenes = nil -- avoid recursive scene storage
  scenes[slot] = snap
  perf_flash = "scene " .. slot .. " saved"
  dirty = true
end

local function scene_recall(slot)
  slot = clamp(tonumber(slot) or 1, 1, 4)
  if type(scenes[slot]) == "table" then
    apply_state(scenes[slot])
    perf_flash = "scene " .. slot .. " load"
  else
    perf_flash = "scene " .. slot .. " empty"
  end
  dirty = true
end

local function ensure_locks(st)
  st.locks = st.locks or {}
  return st.locks
end

local function clear_step_locks(st)
  st.locks = {}
  perf_flash = "locks clear"
  dirty = true
end

local show_popup -- forward declaration for standalone step copy/paste popups

function muta_paste_step_snapshot(snapshot, dst_t, dst_s, src_t, src_s)
  if type(snapshot) ~= "table" or not data.tracks[dst_t] or not data.tracks[dst_t].steps[dst_s] then return false end
  data.tracks[dst_t].steps[dst_s] = deep_copy(snapshot)
  ensure_step_env(data.tracks[dst_t].steps[dst_s])
  ensure_step_sample(data.tracks[dst_t].steps[dst_s])
  ensure_step_arp(data.tracks[dst_t].steps[dst_s])
  selected_track = dst_t
  selected_step = dst_s
  grid_copy_flash = {src_t=src_t or dst_t, src_s=src_s or dst_s, dst_t=dst_t, dst_s=dst_s, count=4}
  perf_flash = "step pasted"
  dirty = true
  return true
end

local function clone_step(src_t, src_s, dst_t, dst_s, flash_text)
  if not (src_t and src_s and dst_t and dst_s) then return false end
  if src_t == dst_t and src_s == dst_s then return false end
  local src = data.tracks[src_t] and data.tracks[src_t].steps[src_s]
  if not src or not data.tracks[dst_t] then return false end
  return muta_paste_step_snapshot(deep_copy(src), dst_t, dst_s, src_t, src_s)
end

local function clear_standalone_step_clipboard(token)
  if token ~= nil and token ~= standalone_step_clipboard_token then return end
  standalone_step_clipboard = nil
  dirty = true
  if redraw_grid then redraw_grid() end
end

local function standalone_step_copy_paste()
  if standalone_step_clipboard == nil then
    standalone_step_clipboard = {
      t = selected_track,
      s = selected_step,
      step = deep_copy(data.tracks[selected_track].steps[selected_step]),
      expires_at = util.time() + STEP_CLIPBOARD_TTL,
      warn_at = util.time() + STEP_CLIPBOARD_WARN_AT,
    }
    standalone_step_clipboard_token = (standalone_step_clipboard_token or 0) + 1
    local token = standalone_step_clipboard_token
    -- No popup here: the filled dot in the header is the copy-buffer indicator.
    clock.run(function()
      clock.sleep(STEP_CLIPBOARD_TTL)
      if standalone_step_clipboard and token == standalone_step_clipboard_token then
        standalone_step_clipboard = nil
        dirty = true
        if redraw_grid then redraw_grid() end
      end
    end)
  else
    if standalone_step_clipboard.t == selected_track and standalone_step_clipboard.s == selected_step then
      standalone_step_clipboard = {
        t = selected_track,
        s = selected_step,
      step = deep_copy(data.tracks[selected_track].steps[selected_step]),
        expires_at = util.time() + STEP_CLIPBOARD_TTL,
        warn_at = util.time() + STEP_CLIPBOARD_WARN_AT,
      }
      standalone_step_clipboard_token = (standalone_step_clipboard_token or 0) + 1
      local token = standalone_step_clipboard_token
      -- Refresh copy, no popup.
      clock.run(function()
        clock.sleep(STEP_CLIPBOARD_TTL)
        if standalone_step_clipboard and token == standalone_step_clipboard_token then
          standalone_step_clipboard = nil
          dirty = true
          if redraw_grid then redraw_grid() end
        end
      end)
    else
      muta_paste_step_snapshot(
        standalone_step_clipboard.step or deep_copy(data.tracks[standalone_step_clipboard.t].steps[standalone_step_clipboard.s]),
        selected_track, selected_step,
        standalone_step_clipboard.t, standalone_step_clipboard.s
      )
      standalone_step_clipboard = nil
      standalone_step_clipboard_token = (standalone_step_clipboard_token or 0) + 1
      -- No STEP PASTED popup: visual feedback stays on the copied/pasted step only.
    end
  end
  dirty = true
  if redraw_grid then redraw_grid() end
end

local function arm_grid_step_hold(t, s)
  grid_step_hold = {t=t, s=s, armed=true, promoted=false}
  clock.run(function()
    clock.sleep(0.32)
    if grid_step_hold and grid_step_hold.t == t and grid_step_hold.s == s and grid_step_hold.armed then
      grid_copy_source = {
        t=t,
        s=s,
        step=deep_copy(data.tracks[t].steps[s]),
      }
      grid_step_hold.promoted = true
      perf_flash = "source armed T"..t..":"..s
      dirty = true
      redraw_grid()
    end
  end)
end

local function release_grid_step_hold(t, s)
  if grid_step_hold and grid_step_hold.t == t and grid_step_hold.s == s then
    local promoted = grid_step_hold.promoted
    grid_step_hold = nil
    if promoted then
      perf_flash = "copy T"..t..":"..s
      dirty = true
      redraw_grid()
    else
      local st = data.tracks[t].steps[s]
      st.active = not st.active
      selected_track = t
      selected_step = s
      dirty = true
      redraw_grid()
    end
    return true
  end
  return false
end

local fx_lock_snapshot

local function current_step_lock_fx(sp)
  local st = data.tracks[selected_track].steps[selected_step]
  if st and st.locks and st.locks.fx then
    if type(st.locks.fx[sp]) == "table" then return st.locks.fx[sp] end
    -- legacy v8.0-v8.2 locks sometimes stored a full FX table directly.
    if type(st.locks.fx.delay_time) == "number" or type(st.locks.fx.reverb_size) == "number" then return st.locks.fx end
  end
  return nil
end

local function fx_edit_target(sp)
  local st = data.tracks[selected_track].steps[selected_step]
  if grid_plock_mode then
    local locks = ensure_locks(st)
    -- P-lock live editing is now subpage-scoped. Editing REVERB must not
    -- silently create a DELAY lock, otherwise the Delay auto-prime / tail-hold
    -- code can fire while the user is only editing Reverb.
    locks.fx = locks.fx or {}
    locks.fx[sp] = locks.fx[sp] or deep_copy(fx_lock_snapshot()[sp])
    return locks.fx[sp], true
  end
  -- v8.10.2: outside P-lock mode, FX edits are always global.
  -- Existing step FX locks remain intact but are not edited accidentally.
  return fx, false
end

fx_lock_snapshot = function()
  return {
    [1] = {
      delay_time = fx.delay_time,
      delay_feedback = fx.delay_feedback,
      delay_tone = fx.delay_tone,
      delay_diffusion = fx.delay_diffusion,
      delay_smear = fx.delay_smear,
      delay_mix = fx.delay_mix,
    },
    [2] = {
      reverb_size = fx.reverb_size,
      reverb_decay = fx.reverb_decay,
      reverb_damp = fx.reverb_damp,
      reverb_mix = fx.reverb_mix,
    },
    [3] = {
      damage_crush = fx.damage_crush,
      damage_fold = fx.damage_fold,
      damage_instability = fx.damage_instability,
      damage_dropout = fx.damage_dropout,
    },
  }
end


local function fxv(v, fallback)
  -- Preserve intentional zero values in P-locks. Lua's `or` treats 0 as true,
  -- but keeping this explicit avoids accidental future regressions and makes
  -- FX lock fallback behavior uniform across Delay/Reverb/Damage.
  if v == nil then return fallback end
  return v
end

local function delay_lock_needs_prime(d)
  if type(d) ~= "table" then return false end
  local mixv = fxv(d.delay_mix, fx.delay_mix or 0)
  local timev = fxv(d.delay_time, fx.delay_time or 0)
  local feedv = fxv(d.delay_feedback, fx.delay_feedback or 0)
  -- If a Delay P-lock is only made audible by turning MIX up, the captured
  -- TIME/FEEDBACK can still be exactly zero. That produces a 20 ms comb with
  -- almost no tail, perceived as "Delay not working". Prime only this silent
  -- corner case; explicit non-zero time/feedback remain untouched.
  return (mixv or 0) >= 0.25 and (timev or 0) <= 0.005 and (feedv or 0) <= 0.01
end

local function prime_delay_lock_if_needed(d)
  -- Kept only for backward source compatibility. P-lock values are user data
  -- and must never be rewritten automatically, especially after a zero reset.
  return d
end

show_popup = function(msg, seconds)
  popup_message = msg
  popup_until = util.time() + (seconds or 2)
  dirty = true
end

local function commit_source_lock(st, tr)
  local locks = ensure_locks(st)
  locks.source = locks.source or {}
  locks.source.source = st.source
  locks.source.level = st.level
  locks.source.trig_prob = st.trig_prob
  locks.source.mutation_prob = st.mutation_prob
  locks.source.track_root = tr.root
  locks.source.sample = deep_copy(ensure_step_sample(st))
  locks.source.sample_mode = clamp(tonumber(st.sample_mode) or 2, 1, 3)
end

local function commit_pitch_lock(st)
  local locks = ensure_locks(st)
  locks.pitch = muta_ensure_pitch_lock(st)
end


local function commit_eq_lock(st)
  local locks = ensure_locks(st)
  -- EQ is edited directly through eq_edit_target() while P-lock mode is active.
  -- Do not replace that table with the global EQ after every encoder/Arc move.
  if type(locks.eq) ~= "table" then
    locks.eq = deep_copy(ensure_eq_table(eq))
  else
    locks.eq = ensure_eq_table(locks.eq)
  end
end

local function commit_mutation_lock(st)
  ensure_locks(st).mutations = deep_copy(st.mutations)
end


local function commit_page_lock(pg)
  local tr = data.tracks[selected_track]
  local st = tr.steps[selected_step]
  if pg == PAGE_SRC then return
  elseif pg == PAGE_EQ then commit_eq_lock(st)
  elseif pg == PAGE_PITCH then commit_pitch_lock(st)
  elseif pg == PAGE_MTX and not (shift or mtx_submode == 2) then commit_mutation_lock(st)
  end
  dirty = true
end

local capture_step_lock

local function popup_active()
  return popup_message ~= nil
end

local function toggle_plock_mode()
  if (page == PAGE_ENV or page == PAGE_ARP or page == PAGE_EUCLID) and not grid_plock_mode then
    show_popup("NO P-LOCK ON ENV/ARP/EUCLID", 2)
    dirty = true
    return
  end
  if page == PAGE_SRC then
    show_popup("NO P-LOCK ON SOURCE", 2)
    dirty = true
    if redraw_grid then redraw_grid() end
    return
  end
  grid_plock_mode = not grid_plock_mode
  perf_flash = ""
  if grid_plock_mode then
    -- Create only the active page lock. This gives EQ/PITCH a stable edit target
    -- immediately, without capturing or overwriting unrelated page locks.
    local st = data.tracks[selected_track].steps[selected_step]
    if page == PAGE_EQ then eq_edit_target()
    elseif page == PAGE_PITCH then muta_ensure_pitch_lock(st) end
    show_popup("MODE P-LOCK ON", 2)
  else
    show_popup("MODE P-LOCK OFF", 2)
  end
  dirty = true
  if redraw_grid then redraw_grid() end
  if grid_plock_mode then
    clock.run(function()
      while grid_plock_mode do
        clock.sleep(0.25)
        if redraw_grid then redraw_grid() end
      end
      if redraw_grid then redraw_grid() end
    end)
  end
end

capture_step_lock = function(popup_txt)
  local tr = data.tracks[selected_track]
  local st = tr.steps[selected_step]
  local locks = ensure_locks(st)

  -- v8.3: global step-lock capture. A single K1+K3 stores the complete
  -- identity of the selected step: source, pitch, ADSR, mutation and all FX.
  -- This keeps P-locks coherent and makes clone/preset recall predictable.
  -- SOURCE is deliberately excluded from P-lock capture/editing.
  locks.source = nil
  locks.pitch = {
    relative_note = true,
    note_offset = clamp(tonumber(st.note) or 0, -36, 36),
    note = clamp(tonumber(st.note) or 0, -36, 36), -- legacy-readable alias
    rnd = pitch.rnd,
    range = pitch.range,
    density = pitch.density,
  }
  locks.eq = deep_copy(ensure_eq_table(eq))
  locks.mutations = deep_copy(st.mutations)
  locks.fx = fx_lock_snapshot()

  -- Avoid persistent header text on SEQ; confirmation is handled by popup or grid flash.
  perf_flash = ""
  if popup_txt then show_popup(popup_txt, 2) end
  dirty = true
  redraw_grid()
end

apply_step_locks = function(st)
  local lf = muta_normalize_fx_lock(st and st.locks and st.locks.fx or nil)
  if not fx_lock_active(lf) then return false end

  p_lock_fx_active = true

  local ok, err = pcall(function()
    local d = type(lf[1]) == "table" and lf[1] or nil
    local r = type(lf[2]) == "table" and lf[2] or nil
    local dmg = type(lf[3]) == "table" and lf[3] or nil

    -- V12.4.3 FX CONTINUITY: the dedicated P-lock bus must sound exactly like
    -- the global FX bus before overrides are applied. A P-lock on one family
    -- (for example DELAY) therefore keeps the current global REVERB/DAMAGE
    -- instead of silently zeroing them and making the step sound suddenly dry.
    -- Locked families still preserve explicit zero values through fxv().
    local dt   = d and fxv(d.delay_time, fx.delay_time) or fx.delay_time
    local df   = d and fxv(d.delay_feedback, fx.delay_feedback) or fx.delay_feedback
    local dton = d and fxv(d.delay_tone, fx.delay_tone) or fx.delay_tone
    local ddif = d and fxv(d.delay_diffusion, fx.delay_diffusion) or fx.delay_diffusion
    local dsm  = d and fxv(d.delay_smear, fx.delay_smear) or fx.delay_smear
    local dmx  = d and fxv(d.delay_mix, fx.delay_mix) or fx.delay_mix
    local rsz  = r and fxv(r.reverb_size, fx.reverb_size) or fx.reverb_size
    local rdc  = r and fxv(r.reverb_decay, fx.reverb_decay) or fx.reverb_decay
    local rdp  = r and fxv(r.reverb_damp, fx.reverb_damp) or fx.reverb_damp
    local rmx  = r and fxv(r.reverb_mix, fx.reverb_mix) or fx.reverb_mix
    local dcr  = dmg and fxv(dmg.damage_crush, fx.damage_crush) or fx.damage_crush
    local dfo  = dmg and fxv(dmg.damage_fold, fx.damage_fold) or fx.damage_fold
    local din  = dmg and fxv(dmg.damage_instability, fx.damage_instability) or fx.damage_instability
    local ddo  = dmg and fxv(dmg.damage_dropout, fx.damage_dropout) or fx.damage_dropout

    if engine.plock_fx then
      engine.plock_fx(dt, df, dton, ddif, dsm, dmx, rsz, rdc, rdp, rmx, dcr, dfo, din, ddo)
    else
      -- Backward-safe fallback if Lua is temporarily paired with an older engine.
      if engine.plock_delay_time then engine.plock_delay_time(dt) end
      if engine.plock_delay_feedback then engine.plock_delay_feedback(df) end
      if engine.plock_delay_tone then engine.plock_delay_tone(dton) end
      if engine.plock_delay_diffusion then engine.plock_delay_diffusion(ddif) end
      if engine.plock_delay_smear then engine.plock_delay_smear(dsm) end
      if engine.plock_delay_mix then engine.plock_delay_mix(dmx) end
      if engine.plock_reverb_size then engine.plock_reverb_size(rsz) end
      if engine.plock_reverb_decay then engine.plock_reverb_decay(rdc) end
      if engine.plock_reverb_damp then engine.plock_reverb_damp(rdp) end
      if engine.plock_reverb_mix then engine.plock_reverb_mix(rmx) end
      if engine.plock_damage_crush then engine.plock_damage_crush(dcr) end
      if engine.plock_damage_fold then engine.plock_damage_fold(dfo) end
      if engine.plock_damage_instability then engine.plock_damage_instability(din) end
      if engine.plock_damage_dropout then engine.plock_damage_dropout(ddo) end
    end
  end)

  if not ok then
    print("MUTA FX PLOCK APPLY ERROR: " .. tostring(err))
    fx_column_restore()
    return false
  end
  return true
end

local function set_page(p, sp)
  page = clamp(p, 1, #page_names)
  if sp ~= nil then subpage = clamp(sp, 1, 3) end
  fx_focus = 1
  mix_focus = 1
  if page ~= PAGE_MIX then mix_page = 1 end
  if page ~= PAGE_ARP then arp_page = 1 end
  out_focus = 1
  track_focus = 1
  arp_focus = 1
  euclid_focus = 1
  src_focus = 1
  env_focus = 1
  pitch_focus = 1
  mtx_focus = 1
  global_focus = 1
  mtx_submode = 1
  dirty = true
end

local function clear_selected_track()
  for s=1,NUM_STEPS do
    data.tracks[selected_track].steps[s].active = false
  end
  dirty = true
end

local grid_intro_pattern = {
  "1111000100011111",
  "1111000111000111",
  "1111010111100111",
  "1111010101110111",
  "1111010111100111",
  "1111010111100111",
  "1111000111000111",
  "1111111111111111",
}

local function draw_grid_intro()
  if g == nil then return end
  g:all(0)
  -- Startup LED logo inspired by the user 16x8 grid sketch: dense blocks + central negative motif.
  for y=1,8 do
    local row = grid_intro_pattern[y]
    for x=1,16 do
      if row:sub(x,x) == "1" then g:led(x,y,8) end
    end
  end
  -- Bright accent pixels: a tiny MUTA pulse.
  for _,p in ipairs({{7,1},{8,2},{7,4},{8,6},{10,3},{12,5}}) do g:led(p[1], p[2], 15) end
  g:refresh()
end

redraw_grid = function()
  if g == nil then return end
  if grid_intro_active then draw_grid_intro(); return end
  g:all(0)

  -- Rows 1-6: main 6-track / 16-step sequencer.
  for t=1,NUM_TRACKS do
    local muted = data.tracks[t].mute
    for s=1,NUM_STEPS do
      local st = data.tracks[t].steps[s]
      local l = st.active and 7 or 1
      if st.locks and next(st.locks) ~= nil then l = st.active and 11 or 3 end
      if s == play_step then l = st.active and 15 or 4 end
      if t == selected_track and s == selected_step then l = 15 end
      if muted then
        -- muted tracks stay readable but dimmed to roughly 35%.
        if st.active then l = 3 else l = 1 end
        if s == play_step then l = 5 end
        if t == selected_track and s == selected_step then l = 6 end
      end
      if grid_copy_source and grid_copy_source.t == t and grid_copy_source.s == s then l = 15 end
      if grid_copy_flash then
        local is_src = (grid_copy_flash.src_t == t and grid_copy_flash.src_s == s)
        local is_dst = (grid_copy_flash.dst_t == t and grid_copy_flash.dst_s == s)
        if is_src or is_dst then l = 15 end
      end
      if grid_plock_flash and grid_plock_flash.t == t and grid_plock_flash.s == s then l = 15 end
      g:led(s, t, l)
    end
  end
  if grid_copy_flash then
    grid_copy_flash.count = (grid_copy_flash.count or 0) - 1
    if grid_copy_flash.count <= 0 then grid_copy_flash = nil end
  end
  if grid_plock_flash then
    grid_plock_flash.count = (grid_plock_flash.count or 0) - 1
    if grid_plock_flash.count <= 0 then grid_plock_flash = nil end
  end

  -- Row 7: Euclid live strip for the selected track.
  local eu = muta_euclid.ensure(data.tracks[selected_track].euclid)
  for x=1,NUM_STEPS do
    local hit = muta_euclid.base_hit(x, eu)
    local l = hit and 10 or 0
    if x == play_step then l = hit and 15 or 2 end
    g:led(x, 7, l)
  end
  -- Bright utility anchors: selected track, pulse controls, rotation controls, on/off.
  g:led(selected_track, 7, 15)
  g:led(7, 7, 2); g:led(8, 7, 3)
  g:led(9, 7, 2); g:led(10, 7, 3)
  g:led(13, 7, eu.enabled and 15 or 1)

  -- Row 8: navigation + essential live controls.
  -- Navigation buttons 1-12: active = 100%, available inactive = ~40%.
  -- Button 14 toggles P-LOCK, button 15 is hold-to-mute, button 16 is play/stop.
  -- Button 13 stays off.
  -- 1 SEQ / 2 SRC / 3 ENV / 4 EQ / 5 PITCH / 6 FX / 7 MTX / 8 ARP / 9 EUCLID / 10 MIX / 11 OUT / 12 CLOCK
  local nav = {
    {x=1, p=PAGE_SEQ},
    {x=2, p=PAGE_SRC},
    {x=3, p=PAGE_ENV},
    {x=4, p=PAGE_EQ},
    {x=5, p=PAGE_PITCH},
    {x=6, p=PAGE_FX},
    {x=7, p=PAGE_MTX},
    {x=8, p=PAGE_ARP},
    {x=9, p=PAGE_EUCLID},
    {x=10, p=PAGE_MIX},
    {x=11, p=PAGE_OUT},
    {x=12, p=PAGE_GLOBAL},
  }
  for _,it in ipairs(nav) do
    local on = (page == it.p)
    g:led(it.x, 8, on and 15 or 6)
  end
  g:led(13, 8, 0)
  local plock_level = 6
  if grid_plock_mode then
    plock_level = (math.floor(util.time() * 4) % 2 == 0) and 15 or 4
  end
  g:led(14, 8, plock_level)
  g:led(15, 8, grid_mute_held and 15 or 6)
  g:led(16, 8, playing and 15 or 6)
  g:refresh()
end

ARC_BASE_LEVEL = 9  -- approx. 60% brightness on norns/arc LEDs
ARC_IDLE_LEVEL = 1
ARC_MARKER_LEVEL = 15

function arc_ring(n, value, focus)
  if a == nil then return end
  value = clamp(value or 0, 0, 1)
  local count = math.floor(value * 64 + 0.5)
  local marker = math.max(1, count)
  for i=1,64 do
    -- Smooth 60% ring level, with only the current value marker at full intensity.
    local level = (i <= count) and ARC_BASE_LEVEL or ARC_IDLE_LEVEL
    if i == marker then level = ARC_MARKER_LEVEL end
    a:led(n, i, level)
  end
end

function redraw_arc()
  if a == nil then return end
  a:all(0)

  local tr = data.tracks[selected_track]
  local st = tr.steps[selected_step]
  local function ring_focus(index, focus, max_focus)
    if max_focus == 5 and index == 4 then return focus == 4 or focus == 5 end
    return focus == index
  end
  local function ring_param(index, focus, max_focus)
    if max_focus == 5 and index == 4 and focus == 5 then return 5 end
    return index
  end

  if page == PAGE_SRC then
    local max_focus = st.source == 5 and 5 or 4
    local values = {st.level or 0.75, ((tr.root or 48) - 24) / 60, st.trig_prob or 1, st.mutation_prob or 0, ((st.sample_mode or 2) - 1) / 2}
    for n=1,4 do local i=ring_param(n, src_focus, max_focus); arc_ring(n, values[i] or 0, ring_focus(n, src_focus, max_focus)) end

  elseif page == PAGE_ENV then
    local ev = ensure_step_env(st)
    local values = {ev.attack, ev.decay, ev.sustain, ev.release}
    for n=1,4 do arc_ring(n, values[n], env_focus == n) end

  elseif page == PAGE_EQ then
    local eqv = active_eq(st)
    local values
    if shift then values = {(eqv.low_x or 0.10)/0.30, ((eqv.lomid_x or 0.36)-0.18)/0.34, ((eqv.himid_x or 0.64)-0.48)/0.34, ((eqv.high_x or 0.90)-0.70)/0.30}
    else values = {(eqv.low or 0)*0.5+0.5, (eqv.lomid or 0)*0.5+0.5, (eqv.himid or 0)*0.5+0.5, (eqv.high or 0)*0.5+0.5} end
    for n=1,4 do arc_ring(n, values[n], eq_focus == n) end

  elseif page == PAGE_PITCH then
    local pv = muta_pitch_view()
    local values = {((pv.root or 48)-24)/60, ((pv.scale or 1)-1)/math.max(1,#scale_names-1), ((pv.note or 0)+36)/72, pv.rnd or 0}
    for n=1,4 do arc_ring(n, values[n], pitch_focus == n) end

  elseif page == PAGE_MTX then
    if shift or mtx_submode == 2 then
      local values = {((global.propagation_mode or 1)-1)/3, (global.mutation_spread or 1)/4, global.propagation_decay or 0.62, global.propagation_chance or 0.52}
      for n=1,4 do arc_ring(n, values[n], mtx_focus == n) end
    else
      local mtx = st.mutations or {}
      local values = {mtx.grain or 0, mtx.fold or 0, mtx.fm or 0, mtx.phase or 0, mtx.noise or 0}
      for n=1,4 do local i=ring_param(n, mtx_focus, 5); arc_ring(n, values[i] or 0, ring_focus(n, mtx_focus, 5)) end
    end

  elseif page == PAGE_ARP then
    local ar = ensure_step_arp(st)
    if (arp_page or 1) == 1 then
      local values = {ar.enabled and 1 or 0, ((ar.mode or 1)-1)/5, ((ar.octaves or 1)-1)/3, ((ar.rate or 1)-1)/math.max(1,audio_safe.max_arp_rate-1), ar.gate or 0.78}
      for n=1,4 do local i=ring_param(n, arp_focus, 5); arc_ring(n, values[i] or 0, ring_focus(n, arp_focus, 5)) end
    else
      local values = {ar.muta or 0, ar.mem or 0, ar.chaos or 0, 0}
      for n=1,4 do arc_ring(n, values[n] or 0, arp_focus == n) end
    end

  elseif page == PAGE_EUCLID then
    local eu = muta_euclid.ensure(data.tracks[selected_track].euclid)
    data.tracks[selected_track].euclid = eu
    if (euclid_page or 1) == 1 then
      local values = {eu.enabled and 1 or 0, ((eu.mode or 1)-1)/3, (eu.steps or 16)/32, (eu.pulses or 4)/math.max(1,eu.steps or 16), (eu.rotation or 0)/math.max(1,(eu.steps or 16)-1)}
      for n=1,4 do local i=ring_param(n, euclid_focus, 5); arc_ring(n, values[i] or 0, ring_focus(n, euclid_focus, 5)) end
    else
      local values = {eu.morph or 0, ((eu.drift or 0)+4)/8, eu.add or 0.25, 0}
      for n=1,4 do arc_ring(n, values[n] or 0, euclid_focus == n) end
    end

  elseif page == PAGE_FX then
    -- Cache is keyed only by the manually selected edit step. Transport/playhead
    -- changes cannot replace the Arc rings with another step's P-lock values.
    local cache_key = table.concat({selected_track, selected_step, subpage, grid_plock_mode and 1 or 0}, ":")
    local vals = MUTA_ARC_FX_CACHE_VALUES
    if MUTA_ARC_FX_CACHE_KEY ~= cache_key or type(vals) ~= "table" then
      local src = (grid_plock_mode and current_step_lock_fx(subpage)) or fx
      if subpage == 2 then vals = {fxv(src.reverb_size, fx.reverb_size), fxv(src.reverb_decay, fx.reverb_decay) / 10, fxv(src.reverb_damp, fx.reverb_damp), fxv(src.reverb_mix, fx.reverb_mix)}
      elseif subpage == 3 then vals = {fxv(src.damage_crush, fx.damage_crush), fxv(src.damage_fold, fx.damage_fold), fxv(src.damage_instability, fx.damage_instability), fxv(src.damage_dropout, fx.damage_dropout)}
      else vals = {fxv(src.delay_time, fx.delay_time) / 1.5, fxv(src.delay_feedback, fx.delay_feedback), fxv(src.delay_diffusion, fx.delay_diffusion), fxv(src.delay_mix, fx.delay_mix)} end
      MUTA_ARC_FX_CACHE_KEY = cache_key
      MUTA_ARC_FX_CACHE_VALUES = vals
    end
    for i=1,4 do arc_ring(i, vals[i], fx_focus == i) end

  elseif page == PAGE_MIX then
    if (mix_page or 1) == 1 then
      arc_ring(1, mix.main or 0.5, mix_focus == 1); arc_ring(2, mix.phones or 0.5, mix_focus == 2); arc_ring(3, 0, false); arc_ring(4, 0, false)
    else
      arc_ring(1, mix.comp or 0.65, mix_focus == 1); arc_ring(2, mix.threshold or 0.50, mix_focus == 2); arc_ring(3, mix.ratio or 0.35, mix_focus == 3); arc_ring(4, mix.limiter or 0.90, mix_focus == 4)
    end

  elseif page == PAGE_OUT then
    if OUT_PAGE == 2 then arc_ring(1,(out.cv_mode-1)/2,out_focus==5); arc_ring(2,(out.clock-1)/3,false); arc_ring(3,clamp(((CROW_MOD and CROW_MOD.cv3) or 0)/5,0,1),false); arc_ring(4,clamp(((CROW_MOD and CROW_MOD.cv4) or 0)/5,0,1),false)
    elseif OUT_PAGE == 3 then arc_ring(1,((out.crow_in1 or 1)-1)/math.max(1,#CROW_IN1_MODE_NAMES-1),out_focus==1); arc_ring(2,clamp(((CROW_MOD and CROW_MOD.last_clock_v) or 0)/5,0,1),false); arc_ring(3,((CROW_MOD and CROW_MOD.last_clock and (util.time()-CROW_MOD.last_clock<0.35)) and 1 or 0),false); arc_ring(4,playing and 1 or 0,false)
    elseif OUT_PAGE == 4 then arc_ring(1,((out.crow_in2 or 1)-1)/math.max(1,#CROW_IN2_MODE_NAMES-1),out_focus==1); arc_ring(2,(CROW_MOD and CROW_MOD.value) or 0,false); arc_ring(3,clamp(((CROW_MOD and CROW_MOD.last_in2) or 0)/5,0,1),false); arc_ring(4,((CROW_MOD and CROW_MOD.in2_count) or 0)%2,false)
    else arc_ring(1,(out.dest-1)/6,out_focus==1); arc_ring(2,(out.midi_mode-1)/2,out_focus==2); arc_ring(3,(out.cv_mode-1)/2,out_focus==3); arc_ring(4,(out.clock-1)/3,out_focus==4) end

  elseif page == PAGE_GLOBAL then
    if clock_page == 2 then arc_ring(1,(out.clock-1)/3,global_focus==1); arc_ring(2,(global.midi_transport_out or 1)==1 and 1 or 0,global_focus==2); arc_ring(3,playing and 1 or 0,global_focus==3); arc_ring(4,1,global_focus==4)
    else arc_ring(1,((global.tempo_source or 1)-1)/2,global_focus==1); arc_ring(2,(params:get("clock_tempo")-20)/280,global_focus==2); arc_ring(3,playing and 1 or 0,global_focus==3); arc_ring(4,global_focus==5 and global.swing or ((global.quantize or 16)/64),global_focus==4 or global_focus==5) end

  elseif page == PAGE_SEQ then
    arc_ring(1,selected_track/NUM_TRACKS,true); arc_ring(2,selected_step/NUM_STEPS,true); arc_ring(3,play_step/NUM_STEPS,false); arc_ring(4,playing and 1 or 0,true)
  end
  a:refresh()
end

function draw_header(title, sp, spmax)
  screen.level(15)
  screen.move(2, 8)
  screen.text(title)

  -- P-lock mode badge: bright square with reversed "PL" text.
  -- It stays visible on every page while P-lock mode is armed.
  if grid_plock_mode then
    screen.level(15)
    screen.rect(94, 1, 15, 10)
    screen.fill()
    screen.level(0)
    screen.move(101, 8)
    screen.text_center("PL")
    screen.level(15)
    screen.move(126, 8)
    screen.text_right(sp .. "/" .. spmax)
  else
    screen.move(118, 8)
    screen.text_right(sp .. "/" .. spmax)
  end

  screen.level(4)
  screen.move(0, 12)
  screen.line(128, 12)
  screen.stroke()
end

function selected_step_has_fx_lock()
  local tr = data.tracks[selected_track]
  local st = tr and tr.steps and tr.steps[selected_step] or nil
  return st and st.locks and type(st.locks.fx) == "table"
end

function draw_fx_lock_badge()
  if not selected_step_has_fx_lock() then return end
  screen.level(15)
  screen.rect(76, 1, 15, 10)
  screen.stroke()
  screen.move(83, 8)
  screen.text_center("FX")
end

-- V12 FIX: draw_knob was a verbatim duplicate of draw_knob_full (same body,
-- different comment header). All callers now use draw_knob_full directly.
-- draw_knob is kept as a thin alias so any future external call survives.
function draw_knob(x, y, label, value, focused, value_text)
  draw_knob_full(x, y, label, value, focused, value_text)
end


function draw_knob_full(x, y, label, value, focused, value_text)
  -- UI polish v8.11.9: complete circle, 20% brightness idle, 100% selected.
  -- Used only on SOURCE, ENV and FX pages so the rest of the interface is untouched.
  local r = 11
  value = clamp(value or 0, 0, 1)

  local function dot(px, py, size)
    size = size or 1
    screen.rect(math.floor(px + 0.5), math.floor(py + 0.5), size, size)
    screen.fill()
  end

  screen.level(focused and 15 or 3)
  local steps = 96
  for i = 0, steps - 1 do
    local a = (math.pi * 2) * (i / steps)
    dot(x + math.cos(a) * r, y + math.sin(a) * r, 1)
  end

  local a = (-math.pi / 2) + (value * math.pi * 2)
  local mx = x + math.cos(a) * (r - 1)
  local my = y + math.sin(a) * (r - 1)
  screen.level(focused and 15 or 3)
  screen.rect(math.floor(mx - 1.5 + 0.5), math.floor(my - 1.5 + 0.5), 3, 3)
  screen.fill()

  screen.level(focused and 15 or 3)
  screen.move(x, y + 3)
  screen.text_center(value_text or (math.floor(value * 100 + 0.5) .. "%"))

  screen.level(focused and 15 or 3)
  screen.move(x, y + 18)
  screen.text_center(label)
end

function draw_intro()
  -- Accueil MUTA v3.3 : graphisme brutaliste 128x64.
  -- Textes principaux à 100%, points et rectangles à 35%.
  screen.clear()

  -- Champ de pixels gauche / mutation noise, 35%.
  screen.level(5)
  local noise = {
    {3,5},{9,8},{17,6},{25,10},{36,7},{44,12},{7,17},{14,21},
    {22,18},{31,24},{42,23},{52,19},{5,31},{13,36},{20,34},{28,40},
    {38,35},{49,40},{8,48},{19,54},{35,57},{52,53},{60,48},{63,29},
    {2,42},{26,50},{45,48},{55,60},{12,27},{33,15},{57,9},{68,25},
    {71,55},{78,59}
  }
  for i=1,#noise do
    screen.rect(noise[i][1], noise[i][2], 1, 1)
    screen.fill()
  end

  -- Barres brutalistes à droite, 35% pour laisser ressortir le titre.
  screen.level(5)
  screen.rect(84, 7, 44, 3); screen.fill()
  screen.rect(93, 14, 35, 1); screen.fill()
  screen.rect(67, 24, 58, 3); screen.fill()
  screen.rect(73, 35, 22, 1); screen.fill()
  screen.rect(83, 38, 45, 2); screen.fill()
  screen.rect(92, 46, 36, 4); screen.fill()
  screen.rect(77, 55, 51, 1); screen.fill()
  screen.rect(94, 58, 34, 5); screen.fill()

  -- Textes principaux à blanc 100%.
  screen.level(15)
  screen.font_size(16)
  screen.move(49, 34)
  screen.text('MUTA')

  screen.font_size(8)
  screen.move(50, 45)
  screen.text('MUTATION')
  screen.move(50, 53)
  screen.text('SYNTH')
end

function draw_seq()
  draw_header("SEQ", 1, 1)
  -- Standalone step copy/paste indicator.
  -- A bright filled dot in the top band means the no-grid step clipboard is armed.
  if standalone_step_clipboard ~= nil then
    screen.level(clipboard_header_level())
    screen.circle(30, 6, 2)
    screen.fill()
  end
  for t=1,NUM_TRACKS do
    screen.level(t == selected_track and 15 or 5)
    screen.move(2, 15 + t*6)
    screen.text("T" .. t)
    for s=1,NUM_STEPS do
      local st = data.tracks[t].steps[s]
      local x = 20 + (s-1)*6
      local y = 15 + t*6
      -- Clearer SEQ display: active steps are now larger 3x3 blocks.
      -- Inactive steps remain tiny pixels so the pattern is more readable in performance.
      if t == selected_track and s == selected_step then
        screen.level(15)
        screen.rect(x-2, y-5, 6, 6)
        screen.stroke()
        if st.active then
          screen.rect(x, y-3, 3, 3)
          screen.fill()
        end
      elseif st.active then
        screen.level(s == play_step and 15 or 12)
        screen.rect(x-1, y-2, 3, 3)
        screen.fill()
      else
        screen.level(s == play_step and 7 or 2)
        screen.pixel(x, y)
        screen.fill()
      end
    end
  end
  screen.level(4)
  -- Footer labels spaced manually for homogeneous visual rhythm.
  screen.move(2, 59); screen.text("PLAY")
  screen.move(39, 59); screen.text("STEP")
  screen.move(80, 59); screen.text("E2>X")
  screen.move(116, 59); screen.text("E3>Y")
  if perf_flash ~= "" then
    screen.level(10)
    screen.move(64, 8); screen.text_center(perf_flash)
  end
end


function restore_fx_page_edit(d)
  -- FX restore: E3 always edits the selected FX knob on the current FX subpage.
  subpage = clamp(tonumber(subpage) or 1, 1, 3)
  fx_focus = clamp(tonumber(fx_focus) or 1, 1, 4)
  adjust_fx_value(subpage, fx_focus, (tonumber(d) or 0) / 50)
  MUTA_ARC_FX_CACHE_KEY = nil
  MUTA_ARC_FX_CACHE_VALUES = nil
  dirty = true
end

function restore_fx_page_next()
  -- FX restore: K3 cycles DELAY / REVERB / DAMAGE.
  subpage = wrap((tonumber(subpage) or 1) + 1, 1, 3)
  fx_focus = 1
  MUTA_ARC_FX_CACHE_KEY = nil
  MUTA_ARC_FX_CACHE_VALUES = nil
  dirty = true
end

function fx_values_labels(sp)
  local locked = grid_plock_mode and current_step_lock_fx(sp) or nil
  local src = locked or fx
  local mark = locked and " *" or ""
  if sp == 2 then
    return {fxv(src.reverb_size, fx.reverb_size), fxv(src.reverb_decay, fx.reverb_decay) / 10, fxv(src.reverb_damp, fx.reverb_damp), fxv(src.reverb_mix, fx.reverb_mix)}, {"size", "decay", "damp", "mix"}, "FX > REVERB" .. mark
  elseif sp == 3 then
    return {fxv(src.damage_crush, fx.damage_crush), fxv(src.damage_fold, fx.damage_fold), fxv(src.damage_instability, fx.damage_instability), fxv(src.damage_dropout, fx.damage_dropout)}, {"crush", "fold", "instab", "drop"}, "FX > DAMAGE" .. mark
  else
    return {fxv(src.delay_time, fx.delay_time) / 1.5, fxv(src.delay_feedback, fx.delay_feedback), fxv(src.delay_diffusion, fx.delay_diffusion), fxv(src.delay_mix, fx.delay_mix)}, {"time", "feed", "diff", "mix"}, "FX > DELAY" .. mark
  end
end

function draw_fx()
  local vals, labels, title = fx_values_labels(subpage)
  draw_header(title, subpage, 3)
  draw_fx_lock_badge()

  -- Clean panel: no decorative diagonal strokes over the controls.
  for i=1,4 do
    draw_knob_full(18 + (i-1)*31, 30, labels[i], vals[i], fx_focus == i)
  end

  screen.level(4)
  screen.move(2, 62)
  local next_name = subpage == 1 and "REVERB" or (subpage == 2 and "DAMAGE" or "DELAY")
  screen.text("K3:" .. next_name)
  screen.move(64, 62); screen.text_center("E2:SEL")
  screen.move(126, 62); screen.text_right("E3:VAL")
end

function page_ctx()
  return {
    selected_track = selected_track,
    selected_step = selected_step,
    fx = fx,
    mix = mix,
    out = out,
    global = global,
    eq = eq,
    data = data,
    audio_safe = audio_safe,
    fx_focus = fx_focus,
    mix_focus = mix_focus,
    mix_page = mix_page,
    out_focus = out_focus,
    OUT_PAGE = OUT_PAGE,
    clock_page = clock_page,
    global_focus = global_focus,
    arp_focus = arp_focus,
    arp_page = arp_page,
    eq_focus = eq_focus,
    shift = shift,
    CROW_MOD = CROW_MOD,
    out_dest_names = out_dest_names,
    midi_mode_names = midi_mode_names,
    cv_mode_names = cv_mode_names,
    out_clock_names = out_clock_names,
    CROW_IN1_MODE_NAMES = CROW_IN1_MODE_NAMES,
    CROW_IN2_MODE_NAMES = CROW_IN2_MODE_NAMES,
    arp_mode_name = arp_mode_name,
    ensure_step_arp = ensure_step_arp,
    eq_edit_target = eq_edit_target,
    ensure_eq_table = ensure_eq_table,
    clamp = clamp,
    muta_ui = muta_ui,
    muta_draw = muta_draw,
    draw_page_header = draw_page_header,
    draw_step_page_header = draw_step_page_header,
    draw_page_footer = draw_page_footer,
  }
end

function draw_page_header(title, right_text)
  muta_draw.page_header(title, right_text)
end

function draw_step_page_header(title, page_text)
  muta_draw.step_header(selected_track, selected_step, title, page_text)
end

function draw_page_footer(text)
  muta_draw.footer(text)
end

function draw_mix()
  muta_draw_pages.draw_mix(page_ctx())
end

function draw_list(title, rows, sp, spmax, focus)
  draw_header(title, sp, spmax)
  focus = focus or 1
  for i,row in ipairs(rows) do
    local y = 18 + i*7
    screen.level(i == focus and 15 or 10)
    if i == focus then
      screen.rect(3, y-5, 48, 7)
      screen.stroke()
    end
    screen.move(8, y)
    screen.text(row[1])
    screen.move(120, y)
    screen.text_right(row[2])
  end
  screen.level(4)
  screen.move(2, 62); screen.text("E2:SEL")
  screen.move(126, 62); screen.text_right("E3:VAL")
end

function draw_track()
  local tr = data.tracks[selected_track]
  local st = tr.steps[selected_step]
  draw_list("T"..selected_track.." > STEP "..selected_step.." > SUMMARY", {
    {"source", ({"sine", "noise", "sub", "fm", "sample"})[st.source]},
    {"trig", math.floor((st.trig_prob or 1)*100).."%"},
    {"arp", st.arp.enabled and "on" or "off"},
    {"euclid", (data.tracks[selected_track].euclid and data.tracks[selected_track].euclid.pulses or 4).."/"..(data.tracks[selected_track].euclid and data.tracks[selected_track].euclid.steps or 16)},
    {"level", string.format("%.2f", tr.level)},
  }, 1, 1, track_focus)
end

function draw_arp()
  muta_draw_pages.draw_arp(page_ctx())
end

function draw_euclid()
  local tr = data.tracks[selected_track]
  tr.euclid = muta_euclid.ensure(tr.euclid)
  local eu = tr.euclid
  draw_header("T" .. selected_track .. " > EUCLID", euclid_page, 2)

  if euclid_page == 1 then
    local vals = {
      eu.enabled and "ON" or "OFF",
      muta_euclid.mode_names[eu.mode or 1],
      tostring(eu.steps), tostring(eu.pulses), tostring(eu.rotation)
    }
    local labels = {"on", "mode", "length", "pulses", "rotate"}
    for i=1,5 do
      local y = 14 + i * 7
      screen.level(euclid_focus == i and 15 or 4)
      if euclid_focus == i then screen.rect(2, y-5, 42, 7); screen.stroke() end
      screen.move(7, y); screen.text(labels[i])
      screen.move(122, y); screen.text_right(vals[i])
    end
    screen.level(5); screen.move(64, 52); screen.text_center(muta_euclid.pattern_string(eu, 16))
    screen.level(4); screen.move(2, 62); screen.text("K3:MORPH")
    screen.move(64, 62); screen.text_center("E2:SEL")
    screen.move(126, 62); screen.text_right("E3:VAL")
  else
    local vals = {eu.morph or 0, ((eu.drift or 0)+4)/8, eu.add or 0.25}
    local labels = {"morph", "drift", "add"}
    for i=1,3 do
      if i == 2 then
        local x = 22 + (i-1)*42
        -- DRIFT is bipolar/integer: show its signed value inside the knob.
        -- The old extra value at y=50 overlapped the label at y=49.
        draw_knob(x, 31, labels[i], ((eu.drift or 0)+4)/8, euclid_focus == i, string.format("%+d", eu.drift or 0))
      else
        draw_knob(22 + (i-1)*42, 31, labels[i], vals[i], euclid_focus == i)
      end
    end
    screen.level(4); screen.move(2, 62); screen.text("K3:CORE")
    screen.move(64, 62); screen.text_center("E2:SEL")
    screen.move(126, 62); screen.text_right("E3:AMT")
  end
end

function draw_sample_edit()
  -- Full-screen SAMPLE EDIT popup.
  -- START/END define the base window. RND POS and LFO SIZE are evaluated only at trigger time.
  screen.clear()
  local st = data.tracks[selected_track].steps[selected_step]
  local sr = ensure_step_sample(st)
  draw_header("T"..selected_track.." STEP "..selected_step.." > SAMPLE", 1, 1)
  screen.level(5)
  screen.move(4, 18)
  screen.text(short_name(sr.name or sample_name or "none", 20))

  local x0, y0, w, h = 8, 23, 112, 20
  screen.level(2)
  screen.rect(x0, y0, w, h); screen.stroke()
  local sx = x0 + math.floor(sr.start * (w-1))
  local ex = x0 + math.floor(sr.finish * (w-1))
  if ex <= sx then ex = sx + 1 end
  screen.level(3)
  screen.rect(x0, y0, sx-x0, h); screen.fill()
  screen.rect(ex, y0, x0+w-ex, h); screen.fill()
  screen.level(5)
  screen.rect(sx, y0, ex-sx, h); screen.stroke()
  local cy = y0 + math.floor(h / 2)
  screen.level(2)
  screen.move(x0, cy); screen.line(x0 + w - 1, cy); screen.stroke()
  for i=1,w do
    local point = sample_edit.waveform[i]
    local minv, maxv = 0, 0
    if type(point) == "table" then
      minv = clamp(tonumber(point.min) or 0, -1, 1)
      maxv = clamp(tonumber(point.max) or 0, -1, 1)
    else
      -- Backward compatibility with old one-sided cached previews.
      local amp = clamp(tonumber(point) or 0, 0, 1)
      minv, maxv = -amp, amp
    end
    local half = math.max(1, math.floor((h - 3) / 2))
    local y_top = cy - math.floor(maxv * half + 0.5)
    local y_bottom = cy - math.floor(minv * half + 0.5)
    if y_bottom < y_top then y_top, y_bottom = y_bottom, y_top end
    local x = x0 + i - 1
    local inside = x >= sx and x <= ex
    screen.level(inside and 15 or 4)
    screen.move(x, y_top)
    screen.line(x, y_bottom)
    screen.stroke()
  end

  screen.level(sample_edit.focus == 1 and 15 or 7)
  screen.move(sx, y0-2); screen.line(sx, y0+h+2); screen.stroke()
  screen.level(sample_edit.focus == 2 and 15 or 7)
  screen.move(ex, y0-2); screen.line(ex, y0+h+2); screen.stroke()
  if sample_edit.focus == 1 or sample_edit.focus == 2 then
    screen.level(15)
    if sample_edit.focus == 1 then screen.rect(sx-2, y0+h+1, 5, 3); screen.fill() else screen.rect(ex-2, y0+h+1, 5, 3); screen.fill() end
  end

  local labels = {"S", "E", "RND", "LFO", "RATE"}
  local vals = {
    sr.start,
    sr.finish,
    sr.rnd_pos or 0,
    sr.lfo_depth or 0,
    (sr.lfo_rate or 0.20) / 4.0,
  }
  for i=1,5 do
    local x = 10 + (i-1)*24
    screen.level(sample_edit.focus == i and 15 or 5)
    screen.move(x, 49)
    screen.text(labels[i])
    screen.move(x, 56)
    if i == 5 then
      screen.text(string.format("%.1f", sr.lfo_rate or 0.20))
    else
      screen.text(string.format("%02d", math.floor((vals[i] or 0) * 99 + 0.5)))
    end
  end

  screen.level(4)
  screen.move(2, 63); screen.text("E2:SEL")
  screen.move(64, 63); screen.text_center("K2:LOAD")
  screen.move(126, 63); screen.text_right("K3:BACK")
end

function draw_sample_popup()
  local files = sample_browser.files
  local total = #files + 1 -- virtual first item: LIVE REC
  screen.level(0)
  screen.rect(7, 7, 114, 50)
  screen.fill()
  screen.level(15)
  screen.rect(7, 7, 114, 50)
  screen.stroke()
  screen.move(12, 16)
  screen.text("SAMPLE")

  local visible = 4
  if sample_browser.index < sample_browser.offset then sample_browser.offset = sample_browser.index end
  if sample_browser.index > sample_browser.offset + visible - 1 then sample_browser.offset = sample_browser.index - visible + 1 end
  sample_browser.offset = clamp(sample_browser.offset, 1, math.max(1, total - visible + 1))
  for i = 0, visible - 1 do
    local idx = sample_browser.offset + i
    local y = 27 + i * 7
    if idx <= total then
      local label
      if idx == 1 then label = "> LIVE REC"
      else label = files[idx - 1] end
      if label then
        if idx == sample_browser.index then
          screen.level(15)
          screen.rect(11, y - 6, 104, 7)
          screen.stroke()
        end
        screen.level(idx == sample_browser.index and 15 or 7)
        screen.move(14, y)
        screen.text(short_name(label, 18))
      end
    end
  end

  if #files == 0 then
    screen.level(4)
    screen.move(12, 48)
    screen.text("no files / rec only")
  end
  screen.level(5)
  screen.move(12, 54)
  screen.text("E2:SEL")
  screen.move(116, 54)
  screen.text_right("K3:OK")
end


function draw_source()
  local st = data.tracks[selected_track].steps[selected_step]
  local names = {"sine", "noise", "sub", "fm", "sample"}
  ensure_step_sample(st)
  draw_header("T"..selected_track.." > STEP "..selected_step.." > SOURCE", 1, 1)
  screen.level(15); screen.move(64, 18); screen.text_center(names[st.source])
  screen.level(4); screen.move(20,18); screen.text("<"); screen.move(108,18); screen.text(">")
  -- SOURCE page navigation:
  -- K2 cycles source. E2 selects vol/root/trig/mut/mode. E3 changes the selected setting.
  draw_knob_full(18, 34, "vol", st.level or 0.75, src_focus == 1)
  draw_knob_full(49, 34, "root", (data.tracks[selected_track].root-24)/60, src_focus == 2)
  draw_knob_full(80, 34, "trig", st.trig_prob or 1.0, src_focus == 3)
  draw_knob_full(111, 34, "mut", st.mutation_prob, src_focus == 4)
  screen.level(4)
  screen.move(2, 62); screen.text(st.source == 5 and "K2:EDIT" or "K2:SRC  E2:SEL")
  if st.source == 5 then
    -- Compact sample play-mode pictos, centered between left/right footer labels.
    -- ○ = GATED, ● = ONE SHOT, ∞ = LOOP. Inactive pictos stay at ~20%.
    -- Use text glyphs instead of stroked circle primitives: on norns/cairo the
    -- primitive circle path can inherit the previous footer move and draw a
    -- small unwanted line between "K2:EDIT" and the first picto.
    local sm = clamp(tonumber(st.sample_mode) or 2, 1, 3)
    local y = 62
    local x_gate, x_one, x_loop = 57, 64, 71

    local picto_selected = (src_focus == 5)
    local function picto_level(mode)
      if not picto_selected then return 4 end
      return sm == mode and 15 or 5
    end

    screen.level(picto_level(1))
    screen.move(x_gate, y)
    screen.text_center("○")

    screen.level(picto_level(2))
    screen.move(x_one, y)
    screen.text_center("●")

    screen.level(picto_level(3))
    screen.move(x_loop, y)
    screen.text_center("∞")
  end
  screen.level(4)
  screen.move(126, 62); screen.text_right("E3:VAL")
end

function draw_env()
  local st = data.tracks[selected_track].steps[selected_step]
  local ev = ensure_step_env(st)
  draw_header("T"..selected_track.." > STEP "..selected_step.." > ENV", 1, 1)
  draw_knob_full(18, 34, "atk", ev.attack, env_focus == 1)
  draw_knob_full(49, 34, "dec", ev.decay, env_focus == 2)
  draw_knob_full(80, 34, "sus", ev.sustain, env_focus == 3)
  draw_knob_full(111, 34, "rel", ev.release, env_focus == 4)
  screen.level(4)
  screen.move(2, 62); screen.text("E2:SEL")
  screen.move(64, 62); screen.text_center("K1+K3:PLOCK")
  screen.move(126, 62); screen.text_right("E3:VAL")
end


function draw_eq()
  muta_draw_pages.draw_eq(page_ctx())
end

function draw_pitch()
  local pv, st, locked = muta_pitch_view()
  local old_root, old_scale = pitch.root, pitch.scale
  pitch.root, pitch.scale = pv.root, pv.scale
  local qnote = quantize_to_scale((pv.root or 48) + (pv.octave or 0) * 12 + (pv.note or 0))
  pitch.root, pitch.scale = old_root, old_scale
  draw_header("T"..selected_track.." > STEP "..selected_step.." > PITCH" .. (locked and " *" or ""), 1, 1)
  local rows = {
    {"root", musicutil.note_num_to_name(pv.root, true)},
    {"scale", scale_names[pv.scale]},
    {"note", musicutil.note_num_to_name(qnote, true)},
    {"rnd", math.floor((pv.rnd or 0) * 100 + 0.5).."% r"..tostring(pv.range or 1).." d"..math.floor((pv.density or 1)*100+0.5).."%"},
  }
  for i,r in ipairs(rows) do
    local y = 17 + i * 8
    screen.level(i == pitch_focus and 15 or 9)
    if i == pitch_focus then screen.rect(3, y-5, 50, 7); screen.stroke() end
    screen.move(8, y); screen.text(r[1])
    screen.move(122, y); screen.text_right(r[2])
  end
  screen.level(4)
  screen.move(2, 62); screen.text("K2:RND STEP")
  screen.move(126, 62); screen.text_right("K3:RND TRK")
end

function draw_mutations()
  local st = data.tracks[selected_track].steps[selected_step]
  local mtx = st.mutations
  local view_mode = (shift or mtx_submode == 2) and 2 or 1

  if view_mode == 2 then
    local modes = {"linear", "organic", "fungal", "viral"}
    draw_header("T"..selected_track.." > STEP "..selected_step.." > PROP", 2, 2)
    local rows = {
      {"mode", modes[global.propagation_mode or 1]},
      {"spread", global.mutation_spread},
      {"decay", math.floor((global.propagation_decay or 0.62)*100).."%"},
      {"chance", math.floor((global.propagation_chance or 0.52)*100).."%"},
    }
    for i,r in ipairs(rows) do
      local y = 17 + i*8
      screen.level(i == mtx_focus and 15 or 9)
      if i == mtx_focus then screen.rect(3, y-5, 55, 7); screen.stroke() end
      screen.move(8, y); screen.text(r[1])
      screen.move(122, y); screen.text_right(r[2])
    end
    screen.level(4)
    screen.move(2, 62); screen.text("K3:MUT E2:SEL")
    screen.move(126, 62); screen.text_right("E3:VAL")
    return
  end

  draw_header("T"..selected_track.." > STEP "..selected_step.." > MUTATIONS", 1, 2)
  local rows = {{"grain",mtx.grain},{"fold",mtx.fold},{"fm",mtx.fm},{"phase",mtx.phase},{"noise",mtx.noise}}
  for i,r in ipairs(rows) do
    local y = 13 + i*7
    screen.level(i == mtx_focus and 15 or 8)
    if i == mtx_focus then
      screen.rect(3, y-5, 48, 7)
      screen.stroke()
    end
    screen.move(8, y)
    screen.text(r[1])
    screen.move(122, y)
    screen.text_right(math.floor(r[2] * 100 + 0.5) .. "%")
    screen.level(3)
    screen.rect(55, y-4, 44, 3)
    screen.stroke()
    screen.level(i == mtx_focus and 15 or 10)
    screen.rect(55, y-4, math.floor(44*r[2]), 3)
    screen.fill()
  end
  screen.level(4)
  screen.move(2, 62); screen.text("K3:PROP E2:SEL")
  screen.move(126, 62); screen.text_right("E3:VAL")
end

function clock_source_name()
  -- Crow is a MUTA-managed clock source, not a native norns clock_source value.
  -- Check it before native clock_source; otherwise CROW is masked as INTERNAL.
  if global.tempo_source == 3 then return "crow" end
  if global.tempo_source == 2 then return "link" end
  return "internal"
end

function using_link()
  return clock_source_name() == "link" or global.tempo_source == 2
end

function draw_out()
  muta_draw_pages.draw_out(page_ctx())
end

function midi_clock_status_label()
  if out.clock == 1 then return "off" end
  if out.clock == 2 or out.clock == 4 then
    if m == nil then return "no midi" end
    return playing and "sending" or "ready"
  end
  return playing and "cv" or "ready"
end

function draw_global()
  muta_draw_pages.draw_global(page_ctx())
end


function crow_cv_norm(v)
  return clamp((tonumber(v) or 0) / 5.0, 0, 1)
end

function crow_reset_mods()
  if not CROW_MOD then CROW_MOD = {} end
  local last_clock = CROW_MOD.last_clock or 0
  local clock_count = CROW_MOD.clock_count or 0
  local clock_stream_high = CROW_MOD.clock_stream_high == true
  local clock_pending = CROW_MOD.clock_pending == true
  local clock_mode = CROW_MOD.clock_mode or "none"
  local last_clock_v = CROW_MOD.last_clock_v or 0
  local in2_stream_high = CROW_MOD.in2_stream_high == true
  local last_in2 = CROW_MOD.last_in2
  local in2_count = CROW_MOD.in2_count or 0
  local cv3 = CROW_MOD.cv3 or 0
  local cv4 = CROW_MOD.cv4 or 0
  CROW_MOD.value = 0
  CROW_MOD.mutation = 0
  CROW_MOD.evolution = 0
  CROW_MOD.density = 1
  CROW_MOD.density_active = false
  CROW_MOD.root = 0
  CROW_MOD.last_clock = last_clock
  CROW_MOD.clock_count = clock_count
  CROW_MOD.clock_stream_high = clock_stream_high
  CROW_MOD.clock_pending = clock_pending
  CROW_MOD.clock_mode = clock_mode
  CROW_MOD.last_clock_v = last_clock_v
  CROW_MOD.in2_stream_high = in2_stream_high
  CROW_MOD.last_in2 = last_in2
  CROW_MOD.in2_count = in2_count
  CROW_MOD.cv3 = cv3
  CROW_MOD.cv4 = cv4
end

function crow_in2_stream(v)
  local mode = out.crow_in2 or 1
  local vv = tonumber(v) or 0
  local n = crow_cv_norm(vv)
  if not CROW_MOD then CROW_MOD = {} end
  CROW_MOD.last_in2 = vv
  CROW_MOD.value = n

  -- Reset continuous modulation lanes each stream update; event modes do not
  -- hold stale MUT/EVO/DENS/ROOT values after switching modes.
  CROW_MOD.mutation = 0
  CROW_MOD.evolution = 0
  CROW_MOD.density_active = false
  CROW_MOD.root = 0

  if mode == 2 then -- MUT: add mutation probability
    CROW_MOD.mutation = n
  elseif mode == 3 then -- EVO: mutation + propagation intensity
    CROW_MOD.mutation = n * 0.60
    CROW_MOD.evolution = n
  elseif mode == 4 then -- DENS: live trigger density
    CROW_MOD.density = n
    CROW_MOD.density_active = true
  elseif mode == 5 then -- ROOT: -12 to +12 semitone global transposition
    CROW_MOD.root = math.floor((n * 24) - 12 + 0.5)
  elseif mode >= 6 then
    -- Gate/event modes also use stream + Lua edge detection. This avoids
    -- crow.input.change differences between crow/norns builds and makes the
    -- live voltage visible on the OUT IN2 page.
    local high = vv >= 0.45
    local low = vv <= 0.20
    if high and not CROW_MOD.in2_stream_high then
      CROW_MOD.in2_stream_high = true
      crow_in2_event()
    elseif low then
      CROW_MOD.in2_stream_high = false
    end
  end
  dirty = true
end

function crow_in2_event()
  if not CROW_MOD then CROW_MOD = {} end
  CROW_MOD.in2_count = (CROW_MOD.in2_count or 0) + 1
  if CROW_MOD.last_in2 == nil then CROW_MOD.last_in2 = 5.0 end
  local mode = out.crow_in2 or 1
  if mode == 6 then -- PROP: propagate from current playhead/track
    pcall(function() propagate(selected_track, play_step) end)
    show_popup("CROW PROP", 0.7)
  elseif mode == 7 then -- MUTATE: mutate all active steps
    mutate_all(0.45)
    show_popup("CROW MUTATE", 0.7)
  elseif mode == 8 then -- VIRAL: temporary viral contamination burst
    local old_mode, old_spread, old_chance = global.propagation_mode, global.mutation_spread, global.propagation_chance
    global.propagation_mode = 4
    global.mutation_spread = math.max(global.mutation_spread or 1, 3)
    global.propagation_chance = math.max(global.propagation_chance or 0.52, 0.85)
    pcall(function() propagate(selected_track, play_step) end)
    global.propagation_mode, global.mutation_spread, global.propagation_chance = old_mode, old_spread, old_chance
    show_popup("CROW VIRAL", 0.7)
  elseif mode == 9 then -- RND: randomize pitch on selected track
    randomize_track_pitch(selected_track)
    show_popup("CROW RND", 0.7)
  end
  dirty = true
end

function crow_clock_advance()
  if not playing then return end
  local ok, err = pcall(function() run_sequencer_column() end)
  if not ok then
    print("MUTA CROW CLOCK ERROR: " .. tostring(err))
    show_popup("CROW CLOCK ERR", 1)
    playing = false
  end
end

function crow_clock_tick()
  local now = util.time()
  if not CROW_MOD then CROW_MOD = {} end
  -- Always record physical activity. This separates cable/threshold diagnosis
  -- from transport/source state.
  if CROW_MOD.last_clock and (now - CROW_MOD.last_clock) < 0.004 then return end
  local prev_clock = CROW_MOD.last_clock or 0
  CROW_MOD.last_clock = now
  if prev_clock > 0 then
    local interval = now - prev_clock
    if interval > 0.002 and interval < 8 then CROW_MOD.last_clock_interval = interval end
  end
  CROW_MOD.clock_count = (CROW_MOD.clock_count or 0) + 1
  dirty = true

  -- Crow IN1 advances only when the MUTA clock source is explicitly CROW.
  -- PLAY is an arm switch. Quantize is applied against an incoming 1/16 pulse
  -- reference: 1/16 = one step per pulse, 1/8 = every 2 pulses, 1/32 = two
  -- steps per pulse. Swing delays even columns after the incoming pulse.
  if global.tempo_source ~= 3 or not playing then return end
  if not crow_quantize_should_advance() then return end
  if CROW_MOD.clock_pending then return end
  CROW_MOD.clock_pending = true
  clock.run(function()
    local mult = crow_quantize_multiplier()
    local div = CROW_MOD.last_clock_interval or safe_step_division()
    local ok, err = pcall(function()
      local delay = safe_swing_delay_for_step(play_step, div)
      if delay > 0 then clock.sleep(delay) end
      for i=1,mult do
        crow_clock_advance()
        if i < mult then clock.sleep(0.001) end
      end
    end)
    CROW_MOD.clock_pending = false
    if not ok then print("MUTA CROW TIMING ERROR: " .. tostring(err)); show_popup("CROW TIMING ERR", 1) end
  end)
end

function crow_clock_stream(v)
  if not CROW_MOD then CROW_MOD = {} end
  local vv = tonumber(v) or 0
  CROW_MOD.last_clock_v = vv
  -- Stream fallback / CV clock mode. Lower thresholds are used because some
  -- Eurorack clock sources are attenuated before reaching crow.
  local high = vv >= 0.25
  local low = vv <= 0.10
  if high and not CROW_MOD.clock_stream_high then
    CROW_MOD.clock_stream_high = true
    crow_clock_tick()
  elseif low then
    CROW_MOD.clock_stream_high = false
  end
end

function setup_crow_inputs()
  if not crow or not crow.input then return false end
  local ok1 = pcall(function()
    if crow.input[1] then
      crow.input[1].change = nil
      crow.input[1].stream = nil
      CROW_MOD.clock_stream_high = false
      CROW_MOD.clock_pending = false
      CROW_MOD.crow_quantize_counter = 0
      CROW_MOD.clock_mode = "off"

      if out.crow_in1 == 2 then
        -- Primary clock mode: use crow's native edge detector. This is better
        -- for narrow trigger pulses than slow voltage streaming.
        CROW_MOD.clock_mode = "edge"
        crow.input[1].change = function(state)
          if state == nil or state == true or state == 1 then
            CROW_MOD.last_clock_v = 5.0
            crow_clock_tick()
          end
        end
        if crow.input[1].mode then crow.input[1].mode('change', 0.5, 0.1, 'rising') end
      elseif out.crow_in1 == 3 then
        -- Fallback mode: stream + Lua edge detection. Use this if a crow/norns
        -- build does not emit change callbacks.
        CROW_MOD.clock_mode = "stream"
        CROW_MOD.last_clock_v = 0
        crow.input[1].stream = function(v) crow_clock_stream(v) end
        if crow.input[1].mode then crow.input[1].mode('stream', 0.005) end
      else
        if crow.input[1].mode then crow.input[1].mode('none') end
      end
    end
  end)

  local ok2 = pcall(function()
    if crow.input[2] then
      crow.input[2].change = nil
      crow.input[2].stream = nil
      CROW_MOD.in2_stream_high = false
      local mode = out.crow_in2 or 1
      if mode >= 2 then
        -- Use stream for both voltage and event modes: it provides a visible
        -- live voltage and avoids change callback incompatibilities.
        crow.input[2].stream = function(v) crow_in2_stream(v) end
        if crow.input[2].mode then crow.input[2].mode('stream', 0.01) end
      else
        if crow.input[2].mode then crow.input[2].mode('none') end
      end
    end
  end)

  if not ok1 then print("MUTA CROW IN1 SETUP ERROR") end
  if not ok2 then print("MUTA CROW IN2 SETUP ERROR") end
  return ok1 and ok2
end

function set_clock_source_safe(source)
  -- norns core clock_source: 1=internal, 3=link. Crow clock is handled by crow.input[1].
  global.tempo_source = source
  if params.lookup and params.lookup["clock_source"] then
    if source == 2 then params:set("clock_source", 3) else params:set("clock_source", 1) end
  end
  if params.lookup and params.lookup["link_start_stop_sync"] then
    params:set("link_start_stop_sync", global.link_transport == 1 and 2 or 1)
  end
  dirty = true
  redraw_grid()
end

function set_clock_tempo_safe(bpm)
  bpm = clamp(bpm, 20, 300)
  params:set("clock_tempo", bpm)
  -- params:set is the canonical norns path: it updates internal or Link tempo depending on clock_source.
  -- These calls are guarded for older builds and make the UI/playhead react on the next sync tick.
  local src = clock_source_name()
  if clock then
    if src == "internal" and clock.internal and clock.internal.set_tempo then pcall(clock.internal.set_tempo, bpm) end
    if src == "link" and clock.link and clock.link.set_tempo then pcall(clock.link.set_tempo, bpm) end
  end
  dirty = true
  redraw_grid()
end

function midi_clock_enabled()
  -- MIDI clock is intentionally independent from MIDI note/CC enable.
  -- This lets MUTA sync pedals or external hardware without sending notes.
  return m ~= nil and (out.clock == 2 or out.clock == 4)
end

function midi_transport_enabled()
  return (global.midi_transport_out or 1) == 1
end

function midi_raw(status)
  if m == nil then return end
  pcall(function()
    if m.event then m:event({type = "raw", data = {status}}) end
  end)
end

function midi_send_clock()
  if not midi_clock_enabled() then return end
  pcall(function()
    if m.clock then m:clock() else midi_raw(0xF8) end
  end)
end

function midi_send_start()
  if not midi_clock_enabled() or not midi_transport_enabled() then return end
  pcall(function()
    if m.start then m:start() else midi_raw(0xFA) end
  end)
end

function midi_send_stop()
  if not midi_clock_enabled() or not midi_transport_enabled() then return end
  pcall(function()
    if m.stop then m:stop() else midi_raw(0xFC) end
  end)
end

function transport_start()
  if not playing then midi_send_start() end
  playing = true
  dirty = true
  redraw_grid()
end

function reset_transport_to_start()
  if playing then midi_send_stop() end
  playing = false
  play_step = 1
  dirty = true
  redraw_grid()
end

function midi_clock_loop()
  while true do
    if playing and midi_clock_enabled() then
      clock.sync(1/24)
      midi_send_clock()
    else
      clock.sync(1/4)
    end
  end
end

function force_boot_fx_sends()
  -- V12 FIX: Boot state aligns with the documented fixed-send architecture.
  -- mix.delay and mix.reverb are ALWAYS 1.0 (the FX pages control wet/dry
  -- directly via fx.delay_mix / fx.reverb_mix). Setting mix.* to 0.50 here
  -- was contradicting force_fixed_sends() called by sync_fx_engine().
  -- We keep fx.delay_mix/reverb_mix at 0.0 (neutral startup per v8.8 comment),
  -- and let the params page expose them as the actual wet controls.
  mix.delay = 1.0
  mix.reverb = 1.0
  fx.delay_mix = 0.0
  fx.reverb_mix = 0.0
  if params.lookup and params.lookup["delay_mix"] then params:set("delay_mix", 0, true) end
  if params.lookup and params.lookup["reverb_mix"] then params:set("reverb_mix", 0, true) end
  sync_fx_engine()
  dirty = true
end

function muta_cleanup_zero_fx_lock(sp)
  if not grid_plock_mode then return end
  local st = data.tracks[selected_track].steps[selected_step]
  if not st or not st.locks or type(st.locks.fx) ~= "table" then return end
  local lf = muta_normalize_fx_lock(st.locks.fx)
  local part = lf and lf[sp] or nil
  if type(part) ~= "table" then return end

  local audible = false
  if sp == 1 then
    audible = (tonumber(part.delay_mix) or 0) > 0.0001
  elseif sp == 2 then
    audible = (tonumber(part.reverb_mix) or 0) > 0.0001
  elseif sp == 3 then
    audible =
      (tonumber(part.damage_crush) or 0) > 0.0001 or
      (tonumber(part.damage_fold) or 0) > 0.0001 or
      (tonumber(part.damage_instability) or 0) > 0.0001 or
      (tonumber(part.damage_dropout) or 0) > 0.0001
  end

  if not audible then
    lf[sp] = nil
    if not fx_lock_active(lf) then st.locks.fx = nil end
  end
end

function adjust_fx_value(sp, idx, delta)
  local target, locked = fx_edit_target(sp)
  if sp == 2 then
    if idx == 1 then target.reverb_size = clamp((target.reverb_size or fx.reverb_size) + delta, 0, 1) end
    if idx == 2 then target.reverb_decay = clamp((target.reverb_decay or fx.reverb_decay) + delta * 5, 0.1, 10) end
    if idx == 3 then target.reverb_damp = clamp((target.reverb_damp or fx.reverb_damp) + delta, 0, 1) end
    if idx == 4 then target.reverb_mix = clamp((target.reverb_mix or fx.reverb_mix) + delta, 0, 1) end
  elseif sp == 3 then
    if idx == 1 then target.damage_crush = clamp((target.damage_crush or fx.damage_crush) + delta, 0, 1) end
    if idx == 2 then target.damage_fold = clamp((target.damage_fold or fx.damage_fold) + delta, 0, 1) end
    if idx == 3 then target.damage_instability = clamp((target.damage_instability or fx.damage_instability) + delta, 0, 1) end
    if idx == 4 then target.damage_dropout = clamp((target.damage_dropout or fx.damage_dropout) + delta, 0, 1) end
  else
    if idx == 1 then target.delay_time = clamp(fxv(target.delay_time, fx.delay_time) + delta, 0, 1.5) end
    if idx == 2 then target.delay_feedback = clamp(fxv(target.delay_feedback, fx.delay_feedback) + delta, 0, 0.95) end
    if idx == 3 then target.delay_diffusion = clamp(fxv(target.delay_diffusion, fx.delay_diffusion) + delta, 0, 1) end
    if idx == 4 then target.delay_mix = clamp(fxv(target.delay_mix, fx.delay_mix) + delta, 0, 1) end
    -- Explicit zero is sacred: editing MIX must never auto-rewrite TIME/FEEDBACK.
  end
  if locked then
    muta_cleanup_zero_fx_lock(sp)
    perf_flash = fx_lock_active(data.tracks[selected_track].steps[selected_step].locks and data.tracks[selected_track].steps[selected_step].locks.fx) and "edit p-lock" or "p-lock cleared"
  else
    -- Global FX always updates the main ensemble bus immediately.
    sync_fx_engine()
  end
end

function step_division()
  -- norns clock.sync is expressed in beats, where 1 beat = quarter note.
  -- Therefore 1/16 note = 0.25 beats, not 1/16 beat.
  return safe_step_division()
end

function draw_popup_overlay()
  if popup_message == nil then return end
  if util.time() >= popup_until then
    popup_message = nil
    popup_until = 0
    dirty = true
    return
  end
  screen.level(0)
  screen.rect(9, 22, 110, 22)
  screen.fill()
  screen.level(15)
  screen.rect(9, 22, 110, 22)
  screen.stroke()
  screen.font_size(8)
  screen.move(64, 35)
  screen.text_center(popup_message)
end


function clipboard_header_level()
  if not standalone_step_clipboard then return 0 end
  local now = util.time()
  local warn_at = standalone_step_clipboard.warn_at or ((standalone_step_clipboard.expires_at or now) - 3)
  if now >= warn_at then
    return (math.floor(now * 6) % 2 == 0) and 15 or 2
  end
  return 15
end

function redraw()
  screen.clear()
  if page == PAGE_INTRO then draw_intro()
  elseif page == PAGE_SEQ then draw_seq()
  elseif page == PAGE_FX then draw_fx()
  elseif page == PAGE_MIX then draw_mix()
  elseif page == PAGE_OUT then draw_out()
  elseif page == PAGE_TRACK then draw_track()
  elseif page == PAGE_ARP then draw_arp()
  elseif page == PAGE_EUCLID then draw_euclid()
  elseif page == PAGE_SRC then draw_source()
  elseif page == PAGE_ENV then draw_env()
  elseif page == PAGE_EQ then draw_eq()
  elseif page == PAGE_PITCH then draw_pitch()
  elseif page == PAGE_MTX then draw_mutations()
  elseif page == PAGE_GLOBAL then draw_global()
  end
  if sample_edit.open then draw_sample_edit() end
  if sample_browser.open then draw_sample_popup() end
  draw_sample_rec_popup()
  draw_popup_overlay()
  screen.update()
  dirty = false
end

function apply_params()
  global.quantize = safe_quantize_value(params:get("quantize"))
  global.swing = safe_swing_value(params:get("swing"))
  global.mutation_spread = params:get("mutation_spread")
  global.propagation_mode = params:get("propagation_mode")
  global.propagation_decay = params:get("propagation_decay") / 100
  global.propagation_chance = params:get("propagation_chance") / 100
  global.crow_enable = params:get("crow_enable")
  global.midi_enable = params:get("midi_enable")
  global.midi_channel = params:get("midi_channel")
  out.dest = params:get("out_dest")
  out.midi_mode = params:get("out_midi_mode")
  out.cv_mode = params:get("out_cv_mode")
  out.clock = params:get("out_clock")
  if params.lookup and params.lookup["out_crow_in1"] then out.crow_in1 = params:get("out_crow_in1") end
  if params.lookup and params.lookup["out_crow_in2"] then out.crow_in2 = params:get("out_crow_in2") end
  global.tempo_source = params:get("mg_clock_source")
  global.link_transport = params:get("mg_link_transport")
  crow_reset_mods()
  setup_crow_inputs()
  if params.lookup and params.lookup["midi_clock_transport"] then global.midi_transport_out = params:get("midi_clock_transport") end
  sample_rec.threshold_db = params:get("sample_rec_threshold")
  sample_rec.threshold_amp = (10 ^ ((sample_rec.threshold_db or -32) / 20))
  sample_rec.auto_normalize = params:get("sample_rec_normalize") == 2
  if params.lookup and params.lookup["sample_rec_input_gain"] then sample_rec.rec_input_gain = params:get("sample_rec_input_gain") end
  fx.delay_time = params:get("delay_time")
  fx.delay_feedback = params:get("delay_feedback") / 100
  fx.delay_tone = params:get("delay_tone") / 100
  fx.delay_mix = params:get("delay_mix") / 100
  -- V12 FIX: mix.delay / mix.reverb are FIXED SENDS (always 1.0).
  -- apply_params must never overwrite them with the user-param wet value.
  -- force_fixed_sends() is called inside sync_fx_engine() below, which restores both.
  fx.reverb_size = params:get("reverb_size") / 100
  fx.reverb_decay = params:get("reverb_decay")
  fx.reverb_damp = params:get("reverb_damp") / 100
  fx.reverb_mix = params:get("reverb_mix") / 100
  fx.damage_crush = params:get("damage_crush") / 100
  fx.damage_fold = params:get("damage_fold") / 100
  fx.damage_instability = params:get("damage_instability") / 100
  fx.damage_dropout = params:get("damage_dropout") / 100
  fx.delay_diffusion = params:get("delay_diffusion") / 100
  fx.delay_smear = params:get("delay_smear") / 100
  mix.main = params:get("mix_main") / 100
  mix.phones = params:get("mix_phones") / 100
  mix.comp = params:get("mix_comp") / 100
  mix.threshold = params:get("mix_threshold") / 100
  mix.ratio = params:get("mix_ratio") / 100
  mix.limiter = params:get("mix_limiter") / 100
  sync_fx_engine()
  dirty = true
end

function add_params()
  params:add_separator("muta_header", "MUTA")
  params:add_group("muta_presets_group", "MUTA PRESETS", 3)
  params:add_number("muta_preset_slot", "MUTA preset slot", 1, 64, 1)
  params:add_binary("muta_save_slot", "SAVE MUTA slot", "trigger")
  params:set_action("muta_save_slot", function() save_manual_slot() end)
  params:add_binary("muta_load_slot", "LOAD MUTA slot", "trigger")
  params:set_action("muta_load_slot", function() load_manual_slot() end)
  -- Do not override norns core clock_tempo action; it is what actually updates internal/Link tempo.
  params:add_number("quantize", "quantize", 1, 64, 16)
  params:set_action("quantize", function(v) global.quantize = safe_quantize_value(v); dirty = true end)
  params:add_control("swing", "swing", controlspec.new(0, 75, 'lin', 1, 0, '%'))
  params:set_action("swing", function(v) global.swing = safe_swing_value(v); dirty = true end)
  params:add_number("mutation_spread", "mutation spread", 0, 4, 1)
  params:set_action("mutation_spread", apply_params)
  params:add_option("propagation_mode", "propagation mode", {"linear", "organic", "fungal", "viral"}, 1)
  params:add_control("propagation_decay", "propagation decay", controlspec.new(10, 100, 'lin', 1, 62, '%'))
  params:add_control("propagation_chance", "propagation chance", controlspec.new(0, 100, 'lin', 1, 52, '%'))
  params:set_action("propagation_mode", apply_params)
  params:set_action("propagation_decay", apply_params)
  params:set_action("propagation_chance", apply_params)

  params:add_separator("muta_clock_sep", "MUTA CLOCK")
  params:add_option("mg_clock_source", "MG clock source", {"internal", "link", "crow"}, 1)
  params:set_action("mg_clock_source", function(x) global.tempo_source = x; set_clock_source_safe(x); dirty = true end)
  params:add_option("mg_link_transport", "Link transport", {"on", "off"}, 1)
  params:set_action("mg_link_transport", function(x) global.link_transport = x; set_clock_source_safe(global.tempo_source); dirty = true end)

  params:add_separator("muta_sampling_sep", "MUTA SAMPLING")
  params:add_number("sample_rec_threshold", "sample rec threshold dB", -80, -6, -32)
  params:set_action("sample_rec_threshold", function(v)
    sample_rec.threshold_db = v
    sample_rec.threshold_amp = (10 ^ ((v or -32) / 20))
    dirty = true
  end)
  params:add_option("sample_rec_normalize", "sample auto normalize", {"off", "on"}, 1)
  params:set_action("sample_rec_normalize", function(v)
    sample_rec.auto_normalize = (v == 2)
    dirty = true
  end)

  params:add_control("sample_rec_input_gain", "sample rec input gain", controlspec.new(0.5, 6.0, 'lin', 0.1, 2.4, "x"))
  params:set_action("sample_rec_input_gain", function(v)
    sample_rec.rec_input_gain = v
    sample_rec.softcut_ready = false
    dirty = true
  end)

  params:add_separator("muta_output_sep", "MUTA OUTPUT")
  params:add_option("crow_enable", "crow out", {"off", "on"}, 2)
  params:set_action("crow_enable", apply_params)
  params:add_option("midi_enable", "midi out", {"off", "on"}, 2)
  params:set_action("midi_enable", apply_params)
  params:add_number("midi_channel", "midi channel", 1, 16, 1)
  params:set_action("midi_channel", apply_params)
  params:add_option("out_dest", "OUT destination", out_dest_names, 1)
  params:add_option("out_midi_mode", "OUT midi mode", midi_mode_names, 1)
  params:add_option("out_cv_mode", "OUT cv mode", cv_mode_names, 1)
  params:add_option("out_clock", "OUT clock", out_clock_names, 1)
  params:add_option("out_crow_in1", "CROW in1", CROW_IN1_MODE_NAMES, 2)
  params:add_option("out_crow_in2", "CROW in2", CROW_IN2_MODE_NAMES, 3)
  params:add_option("midi_clock_transport", "MIDI clock transport", {"on", "off"}, 1)
  params:set_action("out_dest", apply_params)
  params:set_action("out_midi_mode", apply_params)
  params:set_action("out_cv_mode", apply_params)
  params:set_action("out_clock", apply_params)
  params:set_action("out_crow_in1", apply_params)
  params:set_action("out_crow_in2", apply_params)
  params:set_action("midi_clock_transport", apply_params)

  params:add_separator("muta_mix_sep", "MUTA MIX")
  params:add_control("mix_main", "main", controlspec.new(0, 100, 'lin', 1, 50, '%'))
  params:add_control("mix_phones", "cue", controlspec.new(0, 100, 'lin', 1, 50, '%'))
  params:add_control("mix_comp", "compressor", controlspec.new(0, 100, 'lin', 1, 65, '%'))
  params:add_control("mix_threshold", "comp threshold", controlspec.new(5, 100, 'lin', 1, 50, '%'))
  params:add_control("mix_ratio", "comp ratio", controlspec.new(10, 100, 'lin', 1, 35, '%'))
  params:add_control("mix_limiter", "limiter ceiling", controlspec.new(50, 100, 'lin', 1, 90, '%'))
  params:set_action("mix_main", apply_params)
  params:set_action("mix_phones", apply_params)
  params:set_action("mix_comp", apply_params)
  params:set_action("mix_threshold", apply_params)
  params:set_action("mix_ratio", apply_params)
  params:set_action("mix_limiter", apply_params)

  params:add_separator("muta_fx_delay_sep", "MUTA FX DELAY")
  params:add_control("delay_time", "delay time", controlspec.new(0, 1.5, 'lin', 0.005, 0, 's'))
  params:add_control("delay_feedback", "delay feedback", controlspec.new(0, 95, 'lin', 1, 0, '%'))
  params:add_control("delay_tone", "delay tone", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:add_control("delay_diffusion", "delay diffusion", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:add_control("delay_smear", "delay smear", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:add_control("delay_mix", "delay mix", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:set_action("delay_time", apply_params)
  params:set_action("delay_feedback", apply_params)
  params:set_action("delay_tone", apply_params)
  params:set_action("delay_diffusion", apply_params)
  params:set_action("delay_smear", apply_params)
  params:set_action("delay_mix", apply_params)

  params:add_separator("muta_fx_reverb_sep", "MUTA FX REVERB")
  params:add_control("reverb_size", "reverb size", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:add_control("reverb_decay", "reverb decay", controlspec.new(0, 10, 'lin', 0.1, 0, 's'))
  params:add_control("reverb_damp", "reverb damp", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:add_control("reverb_mix", "reverb mix", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:set_action("reverb_size", apply_params)
  params:set_action("reverb_decay", apply_params)
  params:set_action("reverb_damp", apply_params)
  params:set_action("reverb_mix", apply_params)

  params:add_separator("muta_fx_damage_sep", "MUTA FX DAMAGE")
  params:add_control("damage_crush", "damage crush", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:add_control("damage_fold", "damage fold", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:add_control("damage_instability", "damage instability", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:add_control("damage_dropout", "damage dropout", controlspec.new(0, 100, 'lin', 1, 0, '%'))
  params:set_action("damage_crush", apply_params)
  params:set_action("damage_fold", apply_params)
  params:set_action("damage_instability", apply_params)
  params:set_action("damage_dropout", apply_params)
end

function run_sequencer_column()
  -- One complete sequencer column. Used by the normal norns clock and by Crow IN1 clock.
  if not playing then return end
  audio_safe.voices_this_step = 0
  -- V12.4.4 CPU: global FX are stateful in Engine_Muta and are already
  -- synchronized when edited / loaded. Do NOT resend the complete FX state on
  -- every sequencer column: that used to generate ~18 redundant OSC commands
  -- per tick and could contribute to matron/CPU spikes on dense patterns.
  MUTA_FX_COLUMN_TOKEN = (MUTA_FX_COLUMN_TOKEN or 0) + 1
  p_lock_delay_hold_token = p_lock_delay_hold_token + 1
  p_lock_reverb_hold_token = p_lock_reverb_hold_token + 1
  p_lock_delay_hold_until = 0
  p_lock_reverb_hold_until = 0
  p_lock_fx_active = false
  for t=1,NUM_TRACKS do
    local ok, err = pcall(function() trigger_track(t, play_step) end)
    if not ok then
      print("MUTA SEQ/TRIGGER ERROR: " .. tostring(err))
      show_popup("SEQ SAFE MODE", 1)
    end
  end
  play_step = wrap(play_step + 1, 1, NUM_STEPS)
  -- UI refresh is coalesced by the 15 Hz redraw metro. Avoid refreshing all
  -- 128 Grid LEDs here and then doing it again a few milliseconds later.
  dirty = true
end

function seq_loop()
  -- Internal/Link sequencer clock. When MUTA clock source is CROW, Crow IN1
  -- advances the playhead and this loop idles safely. Quantize/swing are
  -- hardened here so a bad parameter value cannot kill the clock coroutine.
  while true do
    local div = safe_step_division()
    if global.tempo_source == 3 then
      clock.sleep(0.05)
    else
      local ok, err = pcall(function() clock.sync(div) end)
      if ok then
        local ok2, err2 = pcall(function() run_column_with_timing_delay(div) end)
        if not ok2 then print("MUTA SEQ LOOP ERROR: " .. tostring(err2)); clock.sleep(0.05) end
      else
        print("MUTA CLOCK SYNC ERROR: " .. tostring(err) .. " div=" .. tostring(div))
        clock.sleep(0.05)
      end
    end
  end
end



-- V11.0.1 SAMPLEFIX: robust sample browser/analyzer helpers.
-- V11.0 accidentally shipped without scan_sample_files() and
-- analyze_sample_waveform(), so opening the sample chooser or loading a sample
-- could call nil and stop the UI flow. Keep these helpers local to muta.lua
-- because they depend on norns paths/util/io and the current sample editor UI.
-- V11.0.3 SAMPLESTABLEFIX: restored from the stable sample branch.
-- draw_sample_popup() and draw_sample_edit() both rely on this helper; without
-- it, pressing K3 can set sample_browser.open=true but redraw crashes before
-- the popup appears.
function short_name(name, max_len)
  name = tostring(name or "")
  max_len = tonumber(max_len) or 16
  if string.len(name) <= max_len then return name end
  return string.sub(name, 1, max_len - 1) .. "~"
end

function is_audio_file(name)
  local n = string.lower(name or "")
  return n:match("%.wav$") or n:match("%.aif$") or n:match("%.aiff$") or n:match("%.flac$")
end

SAMPLE_EXTENSIONS = {
  wav = true, wave = true, aif = true, aiff = true, flac = true
}

function sample_file_supported(name)
  if type(name) ~= "string" then return false end
  local ext = name:match("%.([^%.]+)$")
  ext = ext and string.lower(ext) or ""
  return SAMPLE_EXTENSIONS[ext] == true
end

function scan_sample_files()
  pcall(function() util.make_dir(sample_path) end)
  local files = {}
  local ok, dir = pcall(function() return util.scandir(sample_path) end)
  if ok and dir then
    for _, f in ipairs(dir) do
      if is_audio_file(f) then table.insert(files, f) end
    end
  end
  table.sort(files)
  sample_browser.files = files
  -- +1 virtual first item: LIVE REC. This avoids K1/K2 conflicts with P-locks.
  sample_browser.index = clamp(sample_browser.index or 1, 1, math.max(1, #files + 1))
  sample_browser.offset = clamp(sample_browser.offset or 1, 1, math.max(1, #files + 1))
end

function muta_wav_u16(s, p)
  local a, b = s:byte(p, p + 1)
  if not a or not b then return nil end
  return a + b * 256
end

function muta_wav_u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  if not a or not b or not c or not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

function muta_wav_pcm_value(bytes, bits, format)
  if type(bytes) ~= "string" then return 0 end
  if format == 3 and bits == 32 and string.unpack then
    local ok, value = pcall(string.unpack, "<f", bytes)
    if ok and type(value) == "number" then return clamp(value, -1, 1) end
    return 0
  end
  if bits == 8 then
    return clamp(((bytes:byte(1) or 128) - 128) / 128, -1, 1)
  elseif bits == 16 then
    local a, b = bytes:byte(1, 2)
    if not a or not b then return 0 end
    local n = a + b * 256
    if n >= 32768 then n = n - 65536 end
    return clamp(n / 32768, -1, 1)
  elseif bits == 24 then
    local a, b, c = bytes:byte(1, 3)
    if not a or not b or not c then return 0 end
    local n = a + b * 256 + c * 65536
    if n >= 8388608 then n = n - 16777216 end
    return clamp(n / 8388608, -1, 1)
  elseif bits == 32 then
    local a, b, c, d = bytes:byte(1, 4)
    if not a or not b or not c or not d then return 0 end
    local n = a + b * 256 + c * 65536 + d * 16777216
    if n >= 2147483648 then n = n - 4294967296 end
    return clamp(n / 2147483648, -1, 1)
  end
  return 0
end

function analyze_sample_waveform(path)
  sample_edit.waveform = {}
  sample_edit.valid = false
  sample_edit.message = "reading waveform"

  if type(path) ~= "string" or path == "" then
    sample_edit.message = "no sample"
    return false
  end

  local f = io.open(path, "rb")
  if not f then
    sample_edit.message = "file missing"
    return false
  end

  local riff = f:read(12)
  if not riff or #riff < 12 or riff:sub(1, 4) ~= "RIFF" or riff:sub(9, 12) ~= "WAVE" then
    f:close()
    sample_edit.message = "waveform: WAV only"
    return false
  end

  local fmt, channels, bits, data_pos, data_size = nil, nil, nil, nil, nil
  while true do
    local header = f:read(8)
    if not header or #header < 8 then break end
    local id = header:sub(1, 4)
    local size = muta_wav_u32(header, 5)
    if not size then break end
    local chunk_pos = f:seek()

    if id == "fmt " then
      local body = f:read(math.min(size, 40))
      if body and #body >= 16 then
        fmt = muta_wav_u16(body, 1)
        channels = muta_wav_u16(body, 3)
        bits = muta_wav_u16(body, 15)
      end
    elseif id == "data" then
      data_pos = chunk_pos
      data_size = size
      break
    end

    f:seek("set", chunk_pos + size + (size % 2))
  end

  if not fmt or not channels or not bits or not data_pos or not data_size then
    f:close()
    sample_edit.message = "invalid WAV"
    return false
  end
  if fmt ~= 1 and fmt ~= 3 then
    f:close()
    sample_edit.message = "compressed WAV"
    return false
  end
  if channels < 1 or channels > 8 or (bits ~= 8 and bits ~= 16 and bits ~= 24 and bits ~= 32) then
    f:close()
    sample_edit.message = "unsupported WAV"
    return false
  end

  local bytes_per_sample = math.floor(bits / 8)
  local frame_size = bytes_per_sample * channels
  local frames = math.floor(data_size / frame_size)
  if frames < 1 then
    f:close()
    sample_edit.message = "empty sample"
    return false
  end

  local bins = 112
  local peak = 0
  for i = 1, bins do
    local first = math.floor((i - 1) * frames / bins)
    local last = math.max(first, math.floor(i * frames / bins) - 1)
    local count = last - first + 1
    -- Bounded analysis: up to 96 frames per screen column, distributed over
    -- the whole time bucket. This preserves short transients without decoding
    -- the complete file or blocking norns on long samples.
    local scans = math.min(96, count)
    local minv, maxv = 0, 0

    for j = 0, scans - 1 do
      local frame = first
      if scans > 1 then frame = first + math.floor(j * (count - 1) / (scans - 1)) end
      f:seek("set", data_pos + frame * frame_size)
      local frame_bytes = f:read(frame_size)
      if frame_bytes and #frame_bytes >= frame_size then
        for ch = 1, channels do
          local first_byte = ((ch - 1) * bytes_per_sample) + 1
          local bytes = frame_bytes:sub(first_byte, first_byte + bytes_per_sample - 1)
          local value = muta_wav_pcm_value(bytes, bits, fmt)
          if value < minv then minv = value end
          if value > maxv then maxv = value end
        end
      end
    end

    peak = math.max(peak, math.abs(minv), math.abs(maxv))
    sample_edit.waveform[i] = { min = minv, max = maxv }
  end
  f:close()

  -- Normalize only the display envelope. START/END and playback remain in the
  -- original sample time domain.
  if peak > 0.00001 then
    for i = 1, bins do
      local p = sample_edit.waveform[i]
      p.min = clamp(p.min / peak, -1, 1)
      p.max = clamp(p.max / peak, -1, 1)
    end
  end

  sample_edit.valid = true
  sample_edit.message = "true waveform"
  return true
end

-- V12 FIX: removed spurious `load_sample_file = nil` here.
-- The function is defined as a closure below (line ~3965) and referenced
-- at line ~3814 (sample_rec_finalize_saved_file). Lua closures handle
-- forward references correctly when the reference is inside another function
-- body evaluated at call time, not at parse time. The nil guard was a
-- leftover from an earlier refactor and served no purpose.

function sample_rec_next_path()
  util.make_dir(sample_path)
  for i=1,999 do
    local name = "muta_rec_" .. string.format("%03d", i) .. ".wav"
    local path = sample_path .. name
    local f = io.open(path, "r")
    if f then f:close() else return path, name end
  end
  local name = "muta_rec_" .. os.time() .. ".wav"
  return sample_path .. name, name
end

function sample_rec_level_exceeds()
  local l = tonumber(sample_rec.level_l)
  local r = tonumber(sample_rec.level_r)

  -- norns amp polls may report either dB-like negative values or linear amplitude
  -- depending on system version. The previous implementation defaulted missing
  -- channels to 0; this broke dB mode because max(-12, 0) became 0 and the
  -- threshold was tested as linear amplitude. Missing dB channels are now ignored.
  if (l ~= nil and l < 0) or (r ~= nil and r < 0) then
    local db_peak = -120
    if l ~= nil and l < 0 then db_peak = math.max(db_peak, l) end
    if r ~= nil and r < 0 then db_peak = math.max(db_peak, r) end
    return db_peak >= (sample_rec.threshold_db or -32)
  end

  local peak = math.max(l or 0, r or 0)
  return peak >= (sample_rec.threshold_amp or 0.025)
end

function sample_rec_setup_softcut()
  if sample_rec.softcut_ready then return true end
  local ok = pcall(function()
    audio.level_adc_cut(1)
    softcut.enable(sample_rec.voice, 1)
    if softcut.buffer then softcut.buffer(sample_rec.voice, sample_rec.buffer) end
    softcut.level(sample_rec.voice, 0)
    softcut.pan(sample_rec.voice, 0)
    softcut.level_input_cut(1, sample_rec.voice, sample_rec.rec_input_gain or 2.4)
    softcut.level_input_cut(2, sample_rec.voice, sample_rec.rec_input_gain or 2.4)
    softcut.rec_level(sample_rec.voice, 1.0)
    softcut.pre_level(sample_rec.voice, 0.0)
    softcut.loop(sample_rec.voice, 0)
    softcut.loop_start(sample_rec.voice, sample_rec.pos)
    softcut.loop_end(sample_rec.voice, sample_rec.pos + sample_rec.max_time + 0.1)
    softcut.position(sample_rec.voice, sample_rec.pos)
    softcut.rate(sample_rec.voice, 1.0)
    softcut.play(sample_rec.voice, 0)
    softcut.rec(sample_rec.voice, 0)
  end)
  sample_rec.softcut_ready = ok
  if not ok then show_popup("SOFTCUT REC ERROR", 2) end
  return ok
end

function sample_rec_setup_polls()
  if sample_rec.poll_ready then return true end
  local ok_l = pcall(function()
    poll.set("amp_in_l", function(v)
      sample_rec.level_l = tonumber(v)
      sample_rec.poll_count = (sample_rec.poll_count or 0) + 1
      if sample_rec.state == "armed" and sample_rec_level_exceeds() then sample_rec_start() end
    end)
    poll.start("amp_in_l")
  end)
  local ok_r = pcall(function()
    poll.set("amp_in_r", function(v)
      sample_rec.level_r = tonumber(v)
      sample_rec.poll_count = (sample_rec.poll_count or 0) + 1
      if sample_rec.state == "armed" and sample_rec_level_exceeds() then sample_rec_start() end
    end)
    poll.start("amp_in_r")
  end)
  sample_rec.poll_ready = ok_l or ok_r
  return sample_rec.poll_ready
end

function sample_rec_write_file(path, dur)
  local ok = pcall(function()
    if softcut.buffer_write_mono then
      -- norns builds differ slightly here. Try the modern signature first,
      -- then fall back to the older 3-argument form.
      local ok_mono = pcall(function()
        softcut.buffer_write_mono(path, sample_rec.pos, dur, sample_rec.buffer)
      end)
      if not ok_mono then softcut.buffer_write_mono(path, sample_rec.pos, dur) end
    elseif softcut.buffer_write_stereo then
      softcut.buffer_write_stereo(path, sample_rec.pos, dur)
    else
      error("buffer_write unavailable")
    end
  end)
  return ok
end

function sample_rec_finalize_saved_file(path)
  if type(path) ~= "string" then return end
  local st = data.tracks[selected_track].steps[selected_step]
  st.source = 5
  local sr = ensure_step_sample(st)
  sr.start = 0.0
  sr.finish = 1.0
  sr.path = path
  sr.name = string.match(path, "([^/]+)$") or "sample"
  load_sample_file(path)
  -- SOURCE page is excluded from P-lock editing/capture.
  show_popup("REC SAVED", 2)
  scan_sample_files()
  dirty = true
end

function sample_rec_stop(manual)
  if sample_rec.state ~= "recording" and sample_rec.state ~= "armed" then return end
  if sample_rec.state == "armed" then
    sample_rec.state = "idle"
    sample_rec.filename = nil
    sample_rec.level_l = nil
    sample_rec.level_r = nil
    sample_rec.poll_count = 0
    show_popup("REC CANCELLED", 2)
    dirty = true
    return
  end
  sample_rec.state = "saving"
  sample_rec.duration = clamp(util.time() - sample_rec.start_time, 0.05, sample_rec.max_time)
  pcall(function()
    softcut.rec(sample_rec.voice, 0)
    softcut.play(sample_rec.voice, 0)
  end)
  local path = sample_rec.filename
  local ok = false
  if path then ok = sample_rec_write_file(path, sample_rec.duration) end
  if ok then
    -- Give softcut a short moment to finish writing before the engine reads the file.
    local saved_path = path
    show_popup("REC SAVING", 1)
    clock.run(function()
      clock.sleep(0.35)
      sample_rec_finalize_saved_file(saved_path)
    end)
  else
    show_popup("REC SAVE ERROR", 2)
  end
  sample_rec.state = "idle"
  sample_rec.filename = nil
  sample_rec.level_l = nil
  sample_rec.level_r = nil
  sample_rec.poll_count = 0
  dirty = true
end

function sample_rec_start()
  if sample_rec.state ~= "armed" then return end
  if not sample_rec_setup_softcut() then return end
  local path = sample_rec_next_path()
  sample_rec.filename = path
  sample_rec.start_time = util.time()
  sample_rec.duration = 0
  local ok = pcall(function()
    audio.level_adc_cut(1)
    if softcut.buffer_clear_region_channel then
      softcut.buffer_clear_region_channel(sample_rec.buffer, sample_rec.pos, sample_rec.max_time + 0.1)
    elseif softcut.buffer_clear_region then
      softcut.buffer_clear_region(sample_rec.pos, sample_rec.max_time + 0.1)
    end
    softcut.enable(sample_rec.voice, 1)
    if softcut.buffer then softcut.buffer(sample_rec.voice, sample_rec.buffer) end
    softcut.level_input_cut(1, sample_rec.voice, sample_rec.rec_input_gain or 2.4)
    softcut.level_input_cut(2, sample_rec.voice, sample_rec.rec_input_gain or 2.4)
    softcut.pre_level(sample_rec.voice, 0.0)
    softcut.rec_level(sample_rec.voice, 1.0)
    softcut.position(sample_rec.voice, sample_rec.pos)
    softcut.rec(sample_rec.voice, 1)
    softcut.play(sample_rec.voice, 1)
  end)
  if not ok then
    sample_rec.state = "idle"
    sample_rec.filename = nil
    show_popup("REC START ERROR", 2)
    dirty = true
    return
  end
  sample_rec.state = "recording"
  show_popup("REC START", 1)
  clock.run(function()
    clock.sleep(sample_rec.max_time)
    if sample_rec.state == "recording" then sample_rec_stop(false) end
  end)
  dirty = true
end

function toggle_sample_rec_arm()
  if sample_rec.state == "recording" then sample_rec_stop(true); return end
  if sample_rec.state == "armed" then
    sample_rec.state = "idle"
    show_popup("REC CANCELLED", 2)
    dirty = true
    return
  end
  util.make_dir(sample_path)
  sample_rec_setup_softcut()
  sample_rec.level_l = nil
  sample_rec.level_r = nil
  sample_rec.poll_count = 0
  local polls_ok = sample_rec_setup_polls()
  local st = data.tracks[selected_track].steps[selected_step]
  st.source = 5
  sample_rec.state = "armed"
  show_popup(polls_ok and "LIVE REC ARMED" or "REC ARMED K3 START", 2)
  if polls_ok then
    clock.run(function()
      clock.sleep(0.75)
      if sample_rec.state == "armed" and (sample_rec.poll_count or 0) == 0 then
        show_popup("NO INPUT POLL - K3 START", 2)
      end
    end)
  end
  dirty = true
end

function draw_sample_rec_popup()
  if sample_rec.state == "idle" then return end
  screen.level(0)
  screen.rect(8, 18, 112, 31)
  screen.fill()
  screen.level(15)
  screen.rect(8, 18, 112, 31)
  screen.stroke()
  if sample_rec.state == "armed" then
    screen.move(64, 29); screen.text_center("REC ARM")
    screen.level(7)
    screen.move(64, 40); screen.text_center("THR " .. tostring(sample_rec.threshold_db) .. "dB")
    screen.level(4)
    local l = tonumber(sample_rec.level_l)
    local r = tonumber(sample_rec.level_r)
    if (l and l < 0) or (r and r < 0) then
      local db_peak = -120
      if l and l < 0 then db_peak = math.max(db_peak, l) end
      if r and r < 0 then db_peak = math.max(db_peak, r) end
      screen.move(64, 48); screen.text_center("IN " .. string.format("%.0f", db_peak) .. "dB  K3 START")
    else
      local peak = math.max(l or 0, r or 0)
      screen.move(64, 48); screen.text_center("IN " .. string.format("%.3f", peak) .. "  K3 START")
    end
  elseif sample_rec.state == "recording" then
    local elapsed = clamp(util.time() - sample_rec.start_time, 0, sample_rec.max_time)
    screen.move(64, 30); screen.text_center("REC")
    screen.level(7)
    screen.move(64, 42); screen.text_center(string.format("%.1f / %.1fs", elapsed, sample_rec.max_time))
  elseif sample_rec.state == "saving" then
    screen.move(64, 35); screen.text_center("SAVING")
  end
end


load_sample_file = function(path)
  if path == nil or path == "cancel" then return false end
  local f = io.open(path, "rb")
  if not f then
    show_popup("SAMPLE MISSING", 2)
    dirty = true
    return false
  end
  f:close()

  local name = string.match(path, "([^/]+)$") or "sample"
  sample_name = name
  local st = data.tracks[selected_track] and data.tracks[selected_track].steps[selected_step]
  if st then
    local sr = ensure_step_sample(st)
    sr.path = path
    sr.name = name
    st.source = 5
    -- SOURCE page is excluded from P-lock editing/capture.
  end

  local ok = true
  if engine.load_sample then
    ok = pcall(function() engine.load_sample(path) end)
  end
  if ok then
    -- v1.0.1: every newly loaded sample starts in ONE SHOT mode.
    -- This is deliberately applied only after a successful engine load so a
    -- missing/invalid file never destroys the playback mode already chosen
    -- for the current step. The user can freely select GATED/LOOP afterwards.
    if st then st.sample_mode = 2 end
    last_loaded_sample_path = path
    analyze_sample_waveform(path)
    show_popup("SAMPLE LOADED", 1)
  else
    show_popup("SAMPLE LOAD ERROR", 2)
  end
  dirty = true
  return ok
end

function open_sample_browser()
  scan_sample_files()
  sample_edit.open = false
  sample_browser.open = true
  dirty = true
end

function close_sample_browser(load)
  local loaded = false
  if load then
    if sample_browser.index == 1 then
      -- LIVE REC lives inside the sample chooser: no K1/K2 shortcut needed.
      sample_browser.open = false
      toggle_sample_rec_arm()
      dirty = true
      return false
    elseif #sample_browser.files > 0 then
      local file = sample_browser.files[sample_browser.index - 1]
      if file then
        load_sample_file(sample_path .. file)
        loaded = true
      end
    end
  end
  sample_browser.open = false
  dirty = true
  return loaded
end

function key(n,z)
  if n == 1 then shift = (z == 1); dirty = true end

  -- Standalone norns SEQ copy/paste: short K3 toggles the selected step;
  -- long K3 copies the selected step, then pastes it on the next long K3.
  -- This avoids conflicts with K1+K2 P-lock clear and K1+K3 P-lock mode.
  if n == 3 and z == 0 and seq_k3_hold ~= nil then
    local hold = seq_k3_hold
    seq_k3_hold = nil
    if not hold.fired and page == PAGE_SEQ and not shift then
      local st = data.tracks[selected_track].steps[selected_step]
      st.active = not st.active
      dirty = true
      if redraw_grid then redraw_grid() end
    end
    return
  end

  if z == 0 then return end
  if sample_rec.state == "armed" or sample_rec.state == "recording" then
    if sample_rec.state == "armed" then
      if n == 3 then sample_rec_start()
      elseif n == 2 then sample_rec_stop(true) end
    elseif sample_rec.state == "recording" then
      if n == 3 then sample_rec_stop(true) end
    end
    dirty = true
    return
  end
  if sample_edit.open then
    if n == 3 then sample_edit.open = false
    elseif n == 2 then sample_edit.open = false; open_sample_browser() end
    dirty = true
    return
  end
  if sample_browser.open then
    if n == 3 then
      local loaded = close_sample_browser(true)
      if loaded then sample_edit.open = true end
    elseif n == 2 then close_sample_browser(false)
    end
    dirty = true
    return
  end
  if shift and n == 2 and page == PAGE_PITCH then
    randomize_all_pitch()
    return
  elseif shift and n == 2 then
    clear_step_locks(data.tracks[selected_track].steps[selected_step])
    show_popup("P-LOCK CLEARED", 2)
    return
  end
  if page == PAGE_INTRO then
    set_page(PAGE_SEQ)
  elseif n == 2 and page == PAGE_SRC then
    -- SOURCE page: K2 cycles the sound source, without affecting transport.
    local st = data.tracks[selected_track].steps[selected_step]
    st.source = wrap(st.source + 1, 1, 5)
    if st.source ~= 5 and src_focus > 4 then src_focus = 1 end
    if st.source == 5 then st.sample_mode = clamp(tonumber(st.sample_mode) or 2, 1, 3) end
  elseif n == 2 and page == PAGE_PITCH then
    randomize_step_pitch(selected_track, selected_step)
  elseif n == 2 then
    if using_link() and clock and clock.link then
      if playing and clock.link.stop then clock.link.stop()
      elseif (not playing) and clock.link.start then clock.link.start()
      else if playing then reset_transport_to_start() else transport_start() end end
    else
      if playing then reset_transport_to_start() else transport_start() end
    end
  elseif n == 3 then
    if shift then
      toggle_plock_mode()
    elseif page == PAGE_SRC and data.tracks[selected_track].steps[selected_step].source == 5 then
      -- SOURCE/SAMPLE: K3 must always open the sample chooser. The editor is
      -- opened after a successful file selection, so K3 remains the direct
      -- sample-loading gesture even when another sample is already loaded.
      sample_edit.open = false
      open_sample_browser()
    elseif page == PAGE_PITCH then
      randomize_track_pitch(selected_track)
    elseif page == PAGE_MIX then
      mix_page = wrap(mix_page + 1, 1, 2)
      mix_focus = 1
    elseif page == PAGE_MTX then
      mtx_submode = wrap((mtx_submode or 1) + 1, 1, 2)
      mtx_focus = 1
    elseif page == PAGE_ARP then
      arp_page = wrap((arp_page or 1) + 1, 1, 2)
      arp_focus = 1
    elseif page == PAGE_EUCLID then
      euclid_page = wrap((euclid_page or 1) + 1, 1, 2)
      euclid_focus = 1
    elseif page == PAGE_GLOBAL then
      clock_page = wrap((clock_page or 1) + 1, 1, 2)
      global_focus = 1
    elseif page == PAGE_OUT then
      OUT_PAGE = wrap((OUT_PAGE or 1) + 1, 1, 4)
      out_focus = 1
    elseif page == PAGE_SEQ then
      -- Short K3 toggles on release. Long K3 copies/pastes the complete step.
      seq_k3_hold = { fired = false }
      local hold = seq_k3_hold
      clock.run(function()
        clock.sleep(0.55)
        if seq_k3_hold == hold and page == PAGE_SEQ and not shift then
          hold.fired = true
          standalone_step_copy_paste()
        end
      end)
      return
    elseif page == PAGE_FX then
      restore_fx_page_next()
    else
      -- v8.9.7: K3 no longer advances to the next page on single-page screens.
      -- Page changes are handled by E1 and Grid row 8. K3 is only used when a page
      -- has an explicit action/subpage: SEQ toggle, SOURCE sample edit, PITCH random,
      -- FX subpage, MTX submode, MIX subpage.
    end
  end
  dirty = true
end

function enc(n,d)
  if sample_rec.state == "armed" then
    if n == 2 or n == 3 then
      sample_rec.threshold_db = clamp(sample_rec.threshold_db + d, -80, -6)
      sample_rec.threshold_amp = (10 ^ ((sample_rec.threshold_db or -32) / 20))
      params:set("sample_rec_threshold", sample_rec.threshold_db, true)
      dirty = true
    end
    return
  end
  if sample_edit.open then
    local st = data.tracks[selected_track].steps[selected_step]
    local sr = ensure_step_sample(st)
    if n == 2 then sample_edit.focus = wrap(sample_edit.focus + d, 1, 5) end
    if n == 3 then
      if sample_edit.focus == 1 then
        sr.start = clamp(sr.start + d/200, 0, sr.finish - 0.01)
      elseif sample_edit.focus == 2 then
        sr.finish = clamp(sr.finish + d/200, sr.start + 0.01, 1)
      elseif sample_edit.focus == 3 then
        sr.rnd_pos = clamp((sr.rnd_pos or 0) + d/100, 0, 1)
      elseif sample_edit.focus == 4 then
        sr.lfo_depth = clamp((sr.lfo_depth or 0) + d/100, 0, 1)
      elseif sample_edit.focus == 5 then
        sr.lfo_rate = clamp((sr.lfo_rate or 0.20) + d/100, 0.01, 4.0)
      end
      -- SOURCE page is excluded from P-lock editing.
    end
    dirty = true
    return
  end
  if sample_browser.open then
    if n == 2 then
      sample_browser.index = wrap(sample_browser.index + d, 1, math.max(1, #sample_browser.files + 1))
      dirty = true
    end
    return
  end
  local tr = data.tracks[selected_track]
  local st = tr.steps[selected_step]
  if page == PAGE_INTRO then
    if n == 1 or n == 2 or n == 3 then set_page(PAGE_SEQ) end
  elseif n == 1 then set_page(wrap(page + d, 1, #page_names)) end
  if page == PAGE_SEQ then
    if n == 2 then selected_step = wrap(selected_step + d, 1, NUM_STEPS); MUTA_ARC_FX_CACHE_KEY = nil end
    if n == 3 then selected_track = wrap(selected_track + d, 1, NUM_TRACKS); MUTA_ARC_FX_CACHE_KEY = nil end

  elseif page == PAGE_SRC then
    if n == 2 then src_focus = wrap(src_focus + d, 1, 5) end
    if n == 3 then
      if src_focus == 1 then st.level = clamp((st.level or 0.75) + d/100, 0, 1) end
      if src_focus == 2 then tr.root = clamp((tr.root or 48) + d, 24, 84) end
      if src_focus == 3 then st.trig_prob = clamp((st.trig_prob or 1.0) + d/100, 0, 1) end
      if src_focus == 4 then st.mutation_prob = clamp((st.mutation_prob or 0.0) + d/100, 0, 1) end
      if src_focus == 5 and st.source == 5 then st.sample_mode = wrap((st.sample_mode or 2) + (d > 0 and 1 or -1), 1, 3) end
    end

  elseif page == PAGE_ENV then
    local ev = ensure_step_env(st)
    if n == 2 then env_focus = wrap(env_focus + d, 1, 4) end
    if n == 3 then
      if env_focus == 1 then ev.attack = clamp((ev.attack or 0.02) + d/100, 0, 1) end
      if env_focus == 2 then ev.decay = clamp((ev.decay or 0.18) + d/100, 0, 1) end
      if env_focus == 3 then ev.sustain = clamp((ev.sustain or 0.75) + d/100, 0, 1) end
      if env_focus == 4 then ev.release = clamp((ev.release or 0.28) + d/100, 0, 1) end
    end

  elseif page == PAGE_EQ then
    local eqv = eq_edit_target()
    if n == 2 then eq_focus = wrap(eq_focus + d, 1, 4) end
    if n == 3 then
      if shift then
        if eq_focus == 1 then eqv.low_x = clamp((eqv.low_x or 0.10) + d/100, 0.00, 0.30) end
        if eq_focus == 2 then eqv.lomid_x = clamp((eqv.lomid_x or 0.36) + d/100, 0.18, 0.52) end
        if eq_focus == 3 then eqv.himid_x = clamp((eqv.himid_x or 0.64) + d/100, 0.48, 0.82) end
        if eq_focus == 4 then eqv.high_x = clamp((eqv.high_x or 0.90) + d/100, 0.70, 1.00) end
      else
        if eq_focus == 1 then eqv.low = clamp((eqv.low or 0) + d/100, -1, 1) end
        if eq_focus == 2 then eqv.lomid = clamp((eqv.lomid or 0) + d/100, -1, 1) end
        if eq_focus == 3 then eqv.himid = clamp((eqv.himid or 0) + d/100, -1, 1) end
        if eq_focus == 4 then eqv.high = clamp((eqv.high or 0) + d/100, -1, 1) end
      end
    end

  elseif page == PAGE_PITCH then
    local pt, pst, plocked = muta_pitch_edit_target()
    if n == 2 then pitch_focus = wrap(pitch_focus + d, 1, 4) end
    if n == 3 then
      if pitch_focus == 1 then muta_transpose_global_pitch(d) end
      if pitch_focus == 2 then pitch.scale = wrap((pitch.scale or 1) + (d > 0 and 1 or -1), 1, #scale_names) end
      if pitch_focus == 3 then
        if plocked then
          pt.note_offset = clamp((pt.note_offset or pt.note or pst.note or 0) + d, -36, 36)
          pt.note = pt.note_offset
        else
          muta_transpose_global_pitch(d)
        end
      end
      if pitch_focus == 4 then pt.rnd = clamp((pt.rnd or pitch.rnd or 0) + d/100, 0, 1) end
    end

  elseif page == PAGE_MTX then
    if (shift or mtx_submode == 2) then
      if n == 2 then mtx_focus = wrap(mtx_focus + d, 1, 4) end
      if n == 3 then
        if mtx_focus == 1 then global.propagation_mode = wrap((global.propagation_mode or 1) + (d > 0 and 1 or -1), 1, 4) end
        if mtx_focus == 2 then global.mutation_spread = clamp((global.mutation_spread or 1) + d, 0, 4) end
        if mtx_focus == 3 then global.propagation_decay = clamp((global.propagation_decay or 0.62) + d/100, 0.10, 1.00) end
        if mtx_focus == 4 then global.propagation_chance = clamp((global.propagation_chance or 0.52) + d/100, 0, 1) end
      end
    else
      local mtx = st.mutations
      if n == 2 then mtx_focus = wrap(mtx_focus + d, 1, 5) end
      if n == 3 then
        if mtx_focus == 1 then mtx.grain = clamp((mtx.grain or 0) + d/100, 0, 1) end
        if mtx_focus == 2 then mtx.fold = clamp((mtx.fold or 0) + d/100, 0, 1) end
        if mtx_focus == 3 then mtx.fm = clamp((mtx.fm or 0) + d/100, 0, 1) end
        if mtx_focus == 4 then mtx.phase = clamp((mtx.phase or 0) + d/100, 0, 1) end
        if mtx_focus == 5 then mtx.noise = clamp((mtx.noise or 0) + d/100, 0, 1) end
      end
    end

  elseif page == PAGE_ARP then
    local ar = ensure_step_arp(st)
    if (arp_page or 1) == 1 then
      if n == 2 then arp_focus = wrap(arp_focus + d, 1, 5) end
      if n == 3 then
        if arp_focus == 1 then ar.enabled = d > 0 end
        if arp_focus == 2 then ar.mode = wrap((ar.mode or 1) + (d > 0 and 1 or -1), 1, 6) end
        if arp_focus == 3 then ar.octaves = clamp((ar.octaves or 1) + d, 1, 4) end
        if arp_focus == 4 then ar.rate = clamp((ar.rate or 1) + d, 1, audio_safe.max_arp_rate) end
        if arp_focus == 5 then ar.gate = clamp((ar.gate or 0.78) + d/100, 0.05, 1) end
        ensure_step_arp(st)
      end
    else
      if n == 2 then arp_focus = wrap(arp_focus + d, 1, 3) end
      if n == 3 then
        if arp_focus == 1 then ar.muta = clamp((ar.muta or 0) + d/100, 0, 1) end
        if arp_focus == 2 then ar.mem = clamp((ar.mem or 0) + d/100, 0, 1) end
        if arp_focus == 3 then ar.chaos = clamp((ar.chaos or 0) + d/100, 0, 1) end
        ensure_step_arp(st)
      end
    end

  elseif page == PAGE_EUCLID then
    local tr = data.tracks[selected_track]
    tr.euclid = muta_euclid.ensure(tr.euclid)
    if n == 2 then
      local max_focus = (euclid_page == 1) and 5 or 3
      euclid_focus = wrap(euclid_focus + d, 1, max_focus)
    end
    if n == 3 then
      tr.euclid = muta_euclid.edit(tr.euclid, euclid_focus, d, euclid_page)
    end

  elseif page == PAGE_FX then
    -- DELAY / REVERB / DAMAGE: E2 selects the knob, E3 changes only the selected value.
    if n == 2 then fx_focus = wrap((fx_focus or 1) + d, 1, 4) end
    if n == 3 then restore_fx_page_edit(d) end
  elseif page == PAGE_MIX then
    mix.delay = 1.0
    mix.reverb = 1.0
    if (mix_page or 1) == 1 then
      if n == 2 then mix_focus = wrap(mix_focus + d, 1, 2) end
      if n == 3 then
        if mix_focus == 1 then mix.main = clamp((mix.main or 0.5) + d/100, 0, 1) end
        if mix_focus == 2 then mix.phones = clamp((mix.phones or 0.5) + d/100, 0, 1) end
        sync_mix_engine()
      end
    else
      if n == 2 then mix_focus = wrap(mix_focus + d, 1, 4) end
      if n == 3 then
        if mix_focus == 1 then mix.comp = clamp((mix.comp or 0.65) + d/100, 0, 1) end
        if mix_focus == 2 then mix.threshold = clamp((mix.threshold or 0.50) + d/100, 0, 1) end
        if mix_focus == 3 then mix.ratio = clamp((mix.ratio or 0.35) + d/100, 0, 1) end
        if mix_focus == 4 then mix.limiter = clamp((mix.limiter or 0.90) + d/100, 0, 1) end
        sync_mix_engine()
      end
    end
  elseif page == PAGE_OUT then
    local max_focus = 4
    if OUT_PAGE == 2 then max_focus = 5
    elseif OUT_PAGE == 3 then max_focus = 5
    elseif OUT_PAGE == 4 then max_focus = 5 end

    if n == 2 then out_focus = wrap(out_focus + d, 1, max_focus) end
    if n == 3 then
      if OUT_PAGE == 2 then
        if out_focus == 5 then params:set("out_cv_mode", wrap((out.cv_mode or 1) + d, 1, #cv_mode_names)) end
      elseif OUT_PAGE == 3 then
        if out_focus == 1 then params:set("out_crow_in1", wrap((out.crow_in1 or 1) + d, 1, #CROW_IN1_MODE_NAMES)) end
      elseif OUT_PAGE == 4 then
        if out_focus == 1 then params:set("out_crow_in2", wrap((out.crow_in2 or 1) + d, 1, #CROW_IN2_MODE_NAMES)) end
      else
        if out_focus == 1 then params:set("out_dest", wrap(out.dest + d, 1, #out_dest_names)) end
        if out_focus == 2 then params:set("out_midi_mode", wrap(out.midi_mode + d, 1, #midi_mode_names)) end
        if out_focus == 3 then params:set("out_cv_mode", wrap(out.cv_mode + d, 1, #cv_mode_names)) end
        if out_focus == 4 then params:set("out_clock", wrap(out.clock + d, 1, #out_clock_names)) end
      end
      apply_params()
    end
  elseif page == PAGE_GLOBAL then
    local max_focus = clock_page == 2 and 4 or 5
    if n == 2 then global_focus = wrap(global_focus + d, 1, max_focus) end
    if n == 3 then
      if clock_page == 2 then
        if global_focus == 1 then params:set("out_clock", wrap(out.clock + (d > 0 and 1 or -1), 1, #out_clock_names)); apply_params() end
        if global_focus == 2 then params:set("midi_clock_transport", wrap((global.midi_transport_out or 1) + (d > 0 and 1 or -1), 1, 2)); apply_params() end
      else
        if global_focus == 1 then params:set("mg_clock_source", wrap(global.tempo_source + (d > 0 and 1 or -1), 1, 3)) end
        if global_focus == 2 then set_clock_tempo_safe(params:get("clock_tempo") + d) end
        if global_focus == 3 then if playing then reset_transport_to_start() else transport_start() end end
        if global_focus == 4 then set_quantize_safe(next_quantize_value(global.quantize or 16, d)) end
        if global_focus == 5 then set_swing_safe((global.swing or 0) + d/100) end
      end
    end
  end

  -- v8.10: P-lock mode commits only the currently edited page/category.
  -- This prevents ENV/SOURCE/PITCH/MUTATION edits from overwriting existing FX locks.
  if grid_plock_mode and n == 3
    and page ~= PAGE_FX and page ~= PAGE_SEQ and page ~= PAGE_GLOBAL and page ~= PAGE_MIX and page ~= PAGE_OUT
    and page ~= PAGE_ENV and page ~= PAGE_ARP and page ~= PAGE_EUCLID
    and not (page == PAGE_MTX and (shift or mtx_submode == 2)) then
    commit_page_lock(page)
  end

  dirty = true
  redraw_grid()
end


function mutation_burst()
  for s=1,NUM_STEPS do
    if data.tracks[selected_track].steps[s].active then mutate_step(selected_track, s, 0.18) end
  end
  perf_flash = "burst T" .. selected_track
end

function probability_fill()
  for s=1,NUM_STEPS do
    local st = data.tracks[selected_track].steps[s]
    if math.random() < 0.28 then st.active = not st.active end
  end
  perf_flash = "prob fill"
end

function grid_key(x,y,z)
  if z == 0 then
    if y == 8 and x == 15 then
      grid_mute_held = false
      perf_flash = ""
      dirty = true
      redraw_grid()
      return
    end
    if y >= 1 and y <= NUM_TRACKS then release_grid_step_hold(y, clamp(x, 1, NUM_STEPS)) end
    return
  end
  if page == PAGE_INTRO then set_page(PAGE_SEQ) end

  if y >= 1 and y <= NUM_TRACKS then
    selected_track = y
    selected_step = clamp(x, 1, NUM_STEPS)
    if grid_mute_held then
      data.tracks[y].mute = not data.tracks[y].mute
      perf_flash = data.tracks[y].mute and ("mute T"..y) or ("unmute T"..y)
    elseif grid_plock_mode then
      -- v8.10.2: Grid P-lock mode now matches encoder/Arc behavior.
      -- Touching a step selects it for locked editing; it no longer captures
      -- the whole step and therefore cannot overwrite unrelated locks.
      grid_plock_flash = {t=y, s=selected_step, count=4}
      perf_flash = "p-lock edit T"..y..":"..selected_step
    elseif grid_copy_source then
      if grid_copy_source.t == y and grid_copy_source.s == selected_step then
        grid_copy_source = nil
        perf_flash = "copy cancel"
      else
        muta_paste_step_snapshot(
          grid_copy_source.step or deep_copy(data.tracks[grid_copy_source.t].steps[grid_copy_source.s]),
          y, selected_step,
          grid_copy_source.t, grid_copy_source.s
        )
        grid_copy_source = nil
      end
      dirty = true
      redraw_grid()
    else
      -- Short press toggles step on release. Hold > 0.32s arms copy source;
      -- while held, tap one or many destinations to clone the complete step.
      arm_grid_step_hold(y, selected_step)
    end

  elseif y == 7 then
    -- Euclid live strip: track-level transformer.
    if x >= 1 and x <= NUM_TRACKS then
      selected_track = x
    else
      local tr = data.tracks[selected_track]
      tr.euclid = muta_euclid.ensure(tr.euclid)
      local eu = tr.euclid
      if x == 7 then
        eu.pulses = clamp(eu.pulses - 1, 0, eu.steps)
      elseif x == 8 then
        eu.pulses = clamp(eu.pulses + 1, 0, eu.steps)
      elseif x == 9 then
        eu.rotation = wrap(eu.rotation - 1, 0, eu.steps - 1)
      elseif x == 10 then
        eu.rotation = wrap(eu.rotation + 1, 0, eu.steps - 1)
      elseif x == 11 then
        eu.steps = clamp(eu.steps - 1, 2, 32)
        eu.pulses = clamp(eu.pulses, 0, eu.steps)
        eu.rotation = eu.rotation % eu.steps
      elseif x == 12 then
        eu.steps = clamp(eu.steps + 1, 2, 32)
      elseif x == 13 then
        eu.enabled = not eu.enabled
      elseif x == 14 then
        eu.add = clamp((eu.add or 0.25) - 0.05, 0, 1)
      elseif x == 15 then
        eu.add = clamp((eu.add or 0.25) + 0.05, 0, 1)
      elseif x == 16 then
        tr.euclid = muta_euclid.default(); tr.euclid.enabled = true
      end
    end

  elseif y == 8 then
    -- Direct navigation. This also updates the arc context because arc reads page/subpage.
    -- 1 SEQ / 2 SRC / 3 ENV / 4 EQ / 5 PITCH / 6 FX / 7 MTX / 8 ARP / 9 EUCLID / 10 MIX / 11 OUT / 12 CLOCK
    if x == 1 then set_page(PAGE_SEQ)
    elseif x == 2 then set_page(PAGE_SRC)
    elseif x == 3 then set_page(PAGE_ENV)
    elseif x == 4 then set_page(PAGE_EQ)
    elseif x == 5 then set_page(PAGE_PITCH)
    elseif x == 6 then
      if page == PAGE_FX then set_page(PAGE_FX, wrap(subpage + 1, 1, 3)) else set_page(PAGE_FX, 1) end
    elseif x == 7 then
      if page == PAGE_MTX then
        -- v8.11.3: grid MTX shortcut mirrors K3 behavior and toggles
        -- MUTATION 1/2 <-> PROPAGATION 2/2 instead of reloading page 1.
        mtx_submode = wrap((mtx_submode or 1) + 1, 1, 2)
        mtx_focus = 1
        dirty = true
      else
        set_page(PAGE_MTX)
        mtx_submode = 1
      end
    elseif x == 8 then
      if page == PAGE_ARP then
        arp_page = wrap((arp_page or 1) + 1, 1, 2)
        arp_focus = 1
        dirty = true
      else
        set_page(PAGE_ARP)
        arp_page = 1
        arp_focus = 1
      end
    elseif x == 9 then
      if page == PAGE_EUCLID then
        euclid_page = wrap((euclid_page or 1) + 1, 1, 2)
        euclid_focus = 1
        dirty = true
      else
        set_page(PAGE_EUCLID)
        euclid_page = 1
        euclid_focus = 1
      end
    elseif x == 10 then
      if page == PAGE_MIX then mix_page = wrap(mix_page + 1, 1, 2); mix_focus = 1; dirty = true else set_page(PAGE_MIX) end
    elseif x == 11 then
      if page == PAGE_OUT then OUT_PAGE = wrap((OUT_PAGE or 1) + 1, 1, 4); out_focus = 1; dirty = true else set_page(PAGE_OUT); OUT_PAGE = 1; out_focus = 1 end
    elseif x == 12 then
      if page == PAGE_GLOBAL then
        clock_page = wrap((clock_page or 1) + 1, 1, 2)
        global_focus = 1
        dirty = true
      else
        set_page(PAGE_GLOBAL)
        clock_page = 1
      end
    elseif x == 14 then
      toggle_plock_mode()
    elseif x == 15 then
      grid_mute_held = true
      perf_flash = "mute hold"
      dirty = true
    elseif x == 16 then
      if using_link() and clock and clock.link then
        if playing and clock.link.stop then clock.link.stop()
        elseif (not playing) and clock.link.start then clock.link.start()
        else if playing then reset_transport_to_start() else transport_start() end end
      else
        if playing then reset_transport_to_start() else transport_start() end
      end
    elseif x == 13 then
      dirty = true
    end
  end
  dirty = true
  redraw_grid()
end

ARC_SENSITIVITY = 0.50
MUTA_ARC_DISCRETE_ACCUM = MUTA_ARC_DISCRETE_ACCUM or {0,0,0,0}

function muta_arc_discrete_dir(n, raw_delta)
  n = clamp(math.floor(tonumber(n) or 1), 1, 4)
  local v = (MUTA_ARC_DISCRETE_ACCUM[n] or 0) + (tonumber(raw_delta) or 0) * ARC_SENSITIVITY
  local dir = 0
  if v >= 1 then dir = 1; v = v - 1
  elseif v <= -1 then dir = -1; v = v + 1 end
  MUTA_ARC_DISCRETE_ACCUM[n] = v
  return dir
end

function arc_delta(n,d)
  local raw_d = tonumber(d) or 0
  d = raw_d * ARC_SENSITIVITY
  local tr = data.tracks[selected_track]
  local st = tr.steps[selected_step]
  local dir = muta_arc_discrete_dir(n, raw_d)
  local function five_param_index(focus)
    return (n == 4 and focus == 5) and 5 or n
  end

  if page == PAGE_SRC then
    local max_focus = st.source == 5 and 5 or 4
    local i = max_focus == 5 and five_param_index(src_focus) or n
    src_focus = i
    if i == 1 then st.level = clamp((st.level or 0.75)+d/100,0,1)
    elseif i == 2 and dir ~= 0 then tr.root = clamp((tr.root or 48)+dir,24,84)
    elseif i == 3 then st.trig_prob = clamp((st.trig_prob or 1)+d/100,0,1)
    elseif i == 4 then st.mutation_prob = clamp((st.mutation_prob or 0)+d/100,0,1)
    elseif i == 5 and st.source == 5 and dir ~= 0 then st.sample_mode = wrap((st.sample_mode or 2)+dir,1,3) end

  elseif page == PAGE_ENV then
    env_focus=n; local ev=ensure_step_env(st)
    if n==1 then ev.attack=clamp((ev.attack or 0.02)+d/100,0,1) elseif n==2 then ev.decay=clamp((ev.decay or 0.18)+d/100,0,1) elseif n==3 then ev.sustain=clamp((ev.sustain or 0.75)+d/100,0,1) elseif n==4 then ev.release=clamp((ev.release or 0.28)+d/100,0,1) end

  elseif page == PAGE_EQ then
    eq_focus=n; local eqv=eq_edit_target()
    if shift then
      if n==1 then eqv.low_x=clamp((eqv.low_x or 0.10)+d/100,0,0.30) elseif n==2 then eqv.lomid_x=clamp((eqv.lomid_x or 0.36)+d/100,0.18,0.52) elseif n==3 then eqv.himid_x=clamp((eqv.himid_x or 0.64)+d/100,0.48,0.82) elseif n==4 then eqv.high_x=clamp((eqv.high_x or 0.90)+d/100,0.70,1) end
    else
      if n==1 then eqv.low=clamp((eqv.low or 0)+d/100,-1,1) elseif n==2 then eqv.lomid=clamp((eqv.lomid or 0)+d/100,-1,1) elseif n==3 then eqv.himid=clamp((eqv.himid or 0)+d/100,-1,1) elseif n==4 then eqv.high=clamp((eqv.high or 0)+d/100,-1,1) end
    end

  elseif page == PAGE_PITCH then
    pitch_focus=n
    local pt, pst, plocked = muta_pitch_edit_target()
    if n==1 and dir ~= 0 then muta_transpose_global_pitch(dir)
    elseif n==2 and dir ~= 0 then pitch.scale=wrap((pitch.scale or 1)+dir,1,#scale_names)
    elseif n==3 and dir ~= 0 then
      if plocked then pt.note_offset=clamp((pt.note_offset or pt.note or pst.note or 0)+dir,-36,36); pt.note=pt.note_offset
      else muta_transpose_global_pitch(dir) end
    elseif n==4 then pt.rnd=clamp((pt.rnd or pitch.rnd or 0)+d/100,0,1) end

  elseif page == PAGE_MTX then
    if shift or mtx_submode==2 then
      mtx_focus=n
      if n==1 and dir ~= 0 then global.propagation_mode=wrap((global.propagation_mode or 1)+dir,1,4) elseif n==2 and dir ~= 0 then global.mutation_spread=clamp((global.mutation_spread or 1)+dir,0,4) elseif n==3 then global.propagation_decay=clamp((global.propagation_decay or 0.62)+d/100,0.10,1) elseif n==4 then global.propagation_chance=clamp((global.propagation_chance or 0.52)+d/100,0,1) end
    else
      local i=five_param_index(mtx_focus); mtx_focus=i; local mtx=st.mutations
      if i==1 then mtx.grain=clamp((mtx.grain or 0)+d/100,0,1) elseif i==2 then mtx.fold=clamp((mtx.fold or 0)+d/100,0,1) elseif i==3 then mtx.fm=clamp((mtx.fm or 0)+d/100,0,1) elseif i==4 then mtx.phase=clamp((mtx.phase or 0)+d/100,0,1) elseif i==5 then mtx.noise=clamp((mtx.noise or 0)+d/100,0,1) end
    end

  elseif page == PAGE_ARP then
    local ar=ensure_step_arp(st)
    if (arp_page or 1)==1 then
      local i=five_param_index(arp_focus); arp_focus=i
      if i==1 and dir ~= 0 then ar.enabled=dir>0 elseif i==2 and dir ~= 0 then ar.mode=wrap((ar.mode or 1)+dir,1,6) elseif i==3 and dir ~= 0 then ar.octaves=clamp((ar.octaves or 1)+dir,1,4) elseif i==4 and dir ~= 0 then ar.rate=clamp((ar.rate or 1)+dir,1,audio_safe.max_arp_rate) elseif i==5 then ar.gate=clamp((ar.gate or 0.78)+d/100,0.05,1) end
    else
      arp_focus=math.min(n,3); if n==1 then ar.muta=clamp((ar.muta or 0)+d/100,0,1) elseif n==2 then ar.mem=clamp((ar.mem or 0)+d/100,0,1) elseif n==3 then ar.chaos=clamp((ar.chaos or 0)+d/100,0,1) end
    end
    ensure_step_arp(st)

  elseif page == PAGE_EUCLID then
    local tr=data.tracks[selected_track]
    tr.euclid=muta_euclid.ensure(tr.euclid)
    local max_focus=(euclid_page==1) and 5 or 3
    local i=max_focus==5 and five_param_index(euclid_focus) or math.min(n,max_focus)
    euclid_focus=i
    if i<=max_focus then
      local edit_delta = d
      if euclid_page == 1 or (euclid_page == 2 and i == 2) then edit_delta = dir end
      if edit_delta ~= 0 then tr.euclid=muta_euclid.edit(tr.euclid,i,edit_delta,euclid_page) end
    end

  elseif page == PAGE_FX then fx_focus=n; restore_fx_page_edit(d)
  elseif page == PAGE_MIX then
    mix.delay=1; mix.reverb=1; mix_focus=n
    if (mix_page or 1)==1 then if n==1 then mix.main=clamp((mix.main or 0.5)+d/100,0,1) elseif n==2 then mix.phones=clamp((mix.phones or 0.5)+d/100,0,1) end
    else if n==1 then mix.comp=clamp((mix.comp or 0.65)+d/100,0,1) elseif n==2 then mix.threshold=clamp((mix.threshold or 0.5)+d/100,0,1) elseif n==3 then mix.ratio=clamp((mix.ratio or 0.35)+d/100,0,1) elseif n==4 then mix.limiter=clamp((mix.limiter or 0.9)+d/100,0,1) end end
    sync_mix_engine()
  elseif page == PAGE_OUT then
    if OUT_PAGE==2 then out_focus=5; if n==1 and dir ~= 0 then params:set("out_cv_mode",wrap((out.cv_mode or 1)+dir,1,#cv_mode_names)) end
    elseif OUT_PAGE==3 then out_focus=1; if n==1 and dir ~= 0 then params:set("out_crow_in1",wrap((out.crow_in1 or 1)+dir,1,#CROW_IN1_MODE_NAMES)) end
    elseif OUT_PAGE==4 then out_focus=1; if n==1 and dir ~= 0 then params:set("out_crow_in2",wrap((out.crow_in2 or 1)+dir,1,#CROW_IN2_MODE_NAMES)) end
    else out_focus=n; if n==1 and dir ~= 0 then params:set("out_dest",wrap(out.dest+dir,1,#out_dest_names)) elseif n==2 and dir ~= 0 then params:set("out_midi_mode",wrap(out.midi_mode+dir,1,#midi_mode_names)) elseif n==3 and dir ~= 0 then params:set("out_cv_mode",wrap(out.cv_mode+dir,1,#cv_mode_names)) elseif n==4 and dir ~= 0 then params:set("out_clock",wrap(out.clock+dir,1,#out_clock_names)) end end
    apply_params()
  elseif page == PAGE_GLOBAL then
    global_focus=n
    if clock_page==2 then if n==1 and dir ~= 0 then params:set("out_clock",wrap(out.clock+dir,1,#out_clock_names));apply_params() elseif n==2 and dir ~= 0 then params:set("midi_clock_transport",wrap((global.midi_transport_out or 1)+dir,1,2));apply_params() elseif n==3 then if d>0 then transport_start() else reset_transport_to_start() end end
    else if n==1 and dir ~= 0 then params:set("mg_clock_source",wrap((global.tempo_source or 1)+dir,1,3)) elseif n==2 then set_clock_tempo_safe(params:get("clock_tempo")+d/2) elseif n==3 then if d>0 then transport_start() else reset_transport_to_start() end elseif n==4 then if global_focus==5 then set_swing_safe((global.swing or 0)+d/100) else set_quantize_safe(next_quantize_value(global.quantize or 16,d)) end end end
  elseif page == PAGE_SEQ then if n==1 and dir ~= 0 then selected_track=wrap(selected_track+dir,1,NUM_TRACKS) elseif n==2 and dir ~= 0 then selected_step=wrap(selected_step+dir,1,NUM_STEPS) elseif n==4 then if d>0 then transport_start() else reset_transport_to_start() end end end

  if grid_plock_mode and page~=PAGE_FX and page~=PAGE_SEQ and page~=PAGE_GLOBAL and page~=PAGE_MIX and page~=PAGE_OUT and page~=PAGE_ENV and page~=PAGE_ARP and page~=PAGE_EUCLID and not (page==PAGE_MTX and (shift or mtx_submode==2)) then commit_page_lock(page) end
  dirty=true; redraw_grid(); redraw_arc()
end

function arc_key(n,z)
  if n == 1 then
    shift = (z == 1)
    -- MTX page 1/2 is now toggled with K3; K1 remains a temporary modifier only.
  end
  if z == 1 and page == PAGE_INTRO then set_page(PAGE_SEQ)
  elseif z == 1 and n == 2 then set_page(wrap(page + 1, 1, #page_names))
  elseif z == 1 and n == 3 and page == PAGE_FX then restore_fx_page_next()
  elseif z == 1 and n == 4 and page == PAGE_SEQ then
    local st = data.tracks[selected_track].steps[selected_step]
    st.active = not st.active
  elseif z == 1 and n == 4 and page == PAGE_SRC and data.tracks[selected_track].steps[selected_step].source == 5 then
    src_focus = (src_focus == 5) and 4 or 5
  elseif z == 1 and n == 4 and page == PAGE_MTX and not (shift or mtx_submode == 2) then
    mtx_focus = (mtx_focus == 5) and 4 or 5
  elseif z == 1 and n == 4 and page == PAGE_ARP and (arp_page or 1) == 1 then
    arp_focus = (arp_focus == 5) and 4 or 5
  elseif z == 1 and n == 4 and page == PAGE_EUCLID and (euclid_page or 1) == 1 then
    euclid_focus = (euclid_focus == 5) and 4 or 5
  end
  dirty = true
end

function init()
  math.randomseed(os.time())
  if string.find(_path.code or "", " ") then
    print("MUTA WARNING: install folder contains spaces. Rename it to MUTA for native PSET reliability.")
  end
  init_data()
  -- Paint the MUTA identity screen immediately. This replaces the transient
  -- startup information screen with the project graphic as soon as init begins.
  page = PAGE_INTRO
  draw_intro()
  screen.update()
  util.make_dir(_path.data .. "MUTA/")
  util.make_dir(preset_path)
  add_params()
  install_pset_hooks()
  apply_params()
  -- Live input polling is initialized only when LIVE REC is armed.

  -- Safe initial MUTA engine state.
  engine.amp(0.75)
  engine.release(0.22)
  engine.cutoff(2400)
  engine.pw(0.5)
  engine.source(1)
  engine.grain(0)
  engine.fold(0)
  engine.fm(0)
  engine.phase(0)
  engine.noise(0)
  sync_fx_engine()
  force_boot_fx_sends()

  set_clock_source_safe(global.tempo_source)

  clock.transport.start = function()
    -- Ableton Link transport start: always launch from the current reset position.
    -- Since STOP resets play_step to 1, the next PLAY restarts the pattern cleanly.
    transport_start()
  end

  clock.transport.stop = function()
    -- Ableton Link transport stop: stop and return the sequencer to step 1.
    reset_transport_to_start()
  end

  clock.tempo_change_handler = function()
    dirty = true
    redraw_grid()
  end

  m = midi.connect(1)
  MUTA_MIDI_CLOCK_ID = clock.run(midi_clock_loop)
  g = grid.connect()
  if g then
    g.key = grid_key
    -- No preliminary startup-information/logo phase: Grid is immediately live.
    grid_intro_active = false
    redraw_grid()
  end
  a = arc.connect()
  if a then a.delta = arc_delta; a.key = arc_key end
  setup_crow_inputs()
  clock_id = clock.run(seq_loop)
  MUTA_REDRAW_METRO = metro.init(function()
    if dirty or popup_active() or grid_plock_mode or grid_plock_flash then redraw(); redraw_grid(); redraw_arc() end
  end, 1/15, -1)
  MUTA_REDRAW_METRO:start()
  muta_context_refresh()

end

function cleanup()
  pcall(function()
    if clock_id and clock.cancel then clock.cancel(clock_id); clock_id = nil end
    if MUTA_MIDI_CLOCK_ID and clock.cancel then clock.cancel(MUTA_MIDI_CLOCK_ID); MUTA_MIDI_CLOCK_ID = nil end
    if MUTA_REDRAW_METRO then MUTA_REDRAW_METRO:stop(); MUTA_REDRAW_METRO = nil end
  end)
  pcall(function()
    if sample_rec and sample_rec.state == "recording" then sample_rec_stop(true) end
    if softcut then softcut.rec(sample_rec.voice, 0); softcut.play(sample_rec.voice, 0) end
  end)
  if g then g:all(0); g:refresh() end
  if a then a:all(0); a:refresh() end
  pcall(function() if crow and crow.input then if crow.input[1] and crow.input[1].mode then crow.input[1].mode('none') end; if crow.input[2] and crow.input[2].mode then crow.input[2].mode('none') end end end)
end
