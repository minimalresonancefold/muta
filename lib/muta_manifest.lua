-- MUTA runtime manifest

local M = {}

M.version = "v1.0.1"

M.runtime_modules = {
  "muta_store",
  "muta_manifest",
  "muta_utils",
  "muta_fx_runtime",
  "muta_crow",
  "muta_music",
  "muta_draw",
  "muta_ui",
  "muta_arp_runtime",
  "muta_euclid",
  "muta_draw_pages",
}

M.project_files = {
  "muta.lua",
  "lib/Engine_Muta.sc",
  "lib/muta_store.lua",
  "lib/muta_manifest.lua",
  "lib/muta_utils.lua",
  "lib/muta_fx_runtime.lua",
  "lib/muta_crow.lua",
  "lib/muta_music.lua",
  "lib/muta_draw.lua",
  "lib/muta_ui.lua",
  "lib/muta_arp_runtime.lua",
  "lib/muta_euclid.lua",
  "lib/muta_draw_pages.lua",
}

return M
