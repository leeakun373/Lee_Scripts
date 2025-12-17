-- @description RadialMenu Tool - Runtime input helpers
-- @about
--   Keyboard/mouse related helpers for runtime loop.

local M = {}

-- Detect and intercept trigger key.
-- @return integer|nil key
function M.detect_and_intercept_trigger_key(script_start_time)
  if not script_start_time then return nil end
  if not reaper.JS_VKeys_GetState or not reaper.JS_VKeys_GetDown then return nil end

  local key_state = reaper.JS_VKeys_GetState(script_start_time - 1)
  local down_state = reaper.JS_VKeys_GetDown(script_start_time)

  for i = 1, 255 do
    if key_state:byte(i) ~= 0 or down_state:byte(i) ~= 0 then
      if reaper.JS_VKeys_Intercept then
        reaper.JS_VKeys_Intercept(i, 1)
      end
      return i
    end
  end

  return nil
end

function M.key_held(key, script_start_time)
  if not key or not script_start_time then return false end
  if not reaper.JS_VKeys_GetState then return false end
  local key_state = reaper.JS_VKeys_GetState(script_start_time - 1)
  return key_state:byte(key) ~= 0
end

return M
