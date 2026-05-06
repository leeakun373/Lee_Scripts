-- @description Splitter Dashboard
-- @author Lee
-- @version 0.1.0
-- @about
--   Unified dashboard for splitter settings and run workflow.

local _, script_path = reaper.get_action_context()
local script_dir = script_path:match("^(.*[\\/])")

local function show_error(message)
  reaper.MB(tostring(message), "Lee Splitter Dashboard", 0)
end

local ok, ui_or_error = xpcall(function()
  return dofile(script_dir .. "src/ui_dashboard.lua")
end, debug.traceback)

if not ok then
  show_error(ui_or_error)
  return
end

local ui = ui_or_error
local state

ok, state = xpcall(function()
  return ui.create()
end, debug.traceback)

if not ok then
  show_error(state)
  return
end

local function finish()
  local destroy_ok, destroy_error = xpcall(function()
    ui.destroy(state)
  end, debug.traceback)

  if not destroy_ok then
    show_error(destroy_error)
  end
end

local function loop()
  local frame_ok, keep_open = xpcall(function()
    return ui.frame(state)
  end, debug.traceback)

  if not frame_ok then
    finish()
    show_error(keep_open)
    return
  end

  if keep_open then
    reaper.defer(loop)
  else
    finish()
  end
end

reaper.defer(loop)
