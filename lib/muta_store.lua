-- MUTA state storage helper
-- Uses the same principle as MLRE: norns PSET saves normal params, while large
-- script-owned tables are saved as companion session files with tab.save/load.
local M = {}
local tabutil = require "tabutil"

function M.mkdir_p(path)
  if type(path) ~= "string" or path == "" then return end
  -- Use util.make_dir when available; fallback to mkdir -p.
  if util and util.make_dir then
    pcall(function() util.make_dir(path) end)
  else
    os.execute("mkdir -p " .. string.format("%q", path))
  end
end

local function parent_dir(path)
  return tostring(path or ""):match("^(.+)/[^/]+$")
end

function M.save(tbl, filename)
  if type(tbl) ~= "table" then return false, "state is not a table" end
  if type(filename) ~= "string" or filename == "" then return false, "empty filename" end
  local dir = parent_dir(filename)
  if dir then M.mkdir_p(dir) end
  local ok, err = pcall(function()
    if tab and tab.save then
      tab.save(tbl, filename)
    elseif tabutil and tabutil.save then
      tabutil.save(tbl, filename)
    else
      error("no tab.save/tabutil.save available")
    end
  end)
  if not ok then return false, err end
  return true
end

function M.load(filename)
  if type(filename) ~= "string" or filename == "" then return nil, "empty filename" end
  local f = io.open(filename, "r")
  if f == nil then return nil, "file not found" end
  f:close()
  local ok, data = pcall(function()
    if tab and tab.load then
      return tab.load(filename)
    elseif tabutil and tabutil.load then
      return tabutil.load(filename)
    else
      error("no tab.load/tabutil.load available")
    end
  end)
  if not ok then return nil, data end
  if type(data) ~= "table" then return nil, "loaded data is not a table" end
  return data
end

return M
