-- @description RadialMenu Tool - 主运行时（控制器）
-- @author Lee
-- @about
--   轮盘菜单的主循环（编排层）。
--   重型绘制逻辑已迁移到 `runtime.draw`，以降低维护/阅读成本。

local M = {}

local config_manager = require("config_manager")
local styles = require("gui.styles")
local list_view = require("gui.list_view")
local execution = require("logic.execution")

local draw = require("runtime.draw")
local config_reload = require("runtime.config_reload")
local input = require("runtime.input")

-- Runtime state (kept as a single table for easier modularization)
local R = {
  ctx = nil,
  config = nil,
  is_open = false,

  window_width = 500,
  window_height = 500,

  clicked_sector = nil,
  show_submenu = false,
  is_pinned = false,
  center_drag_started = false,

  is_first_display = true,

  -- long-press
  script_start_time = nil,
  key = nil,

  -- hot reload
  last_config_update_time = nil,

  -- animation
  anim_open_start_time = 0,
  sector_anim_states = {},
  last_frame_time = nil,
  current_frame_dt = 0.0,

  -- perf
  perf_frame_count = 0,
  perf_wheel_time = 0.0,
  perf_ui_time = 0.0,
  perf_last_text = "",

  -- draw scheduling
  anim_active = false,
  last_interact_time = 0,
  last_hover_sector_id = nil,
  last_mouse_x = nil,
  last_mouse_y = nil,
  idle_frame_accumulator = 0.0,

  -- context tracking
  last_valid_context = -1,
}

local IDLE_FPS = 20

-- queued execution support
local queued_slot = nil
local orig_trigger_slot = nil
if execution and execution.trigger_slot then
  orig_trigger_slot = execution.trigger_slot
  execution.trigger_slot = function(slot)
    queued_slot = slot
    return true
  end
end

local function key_held()
  return input.key_held(R.key, R.script_start_time)
end

local function track_shortcut_key()
  if not key_held() then
    if not R.is_pinned then
      M.cleanup()
      return false
    end
  end
  return true
end

-- When we close UI while a hotkey is still held (e.g. queued execution path),
-- keep the key intercepted and keep Running=1 until the key is released.
local function defer_release_key_and_running()
  if not (R.key and reaper.JS_VKeys_GetState) then
    -- Nothing to release; ensure Running is cleared.
    reaper.SetExtState("RadialMenu_Tool", "Running", "0", false)
    return
  end

  local key = R.key
  -- IMPORTANT:
  -- JS_VKeys_GetState's time argument acts like a "since time" look-back window.
  -- Using a sliding (now - 1) window can mis-detect a long-held key as released
  -- after ~1s. Align with Pie3000: use the (fixed) script start time baseline.
  local start_time = R.script_start_time or reaper.time_precise()

  local function step()
    -- Query current key state (time argument is a look-back window)
    local st = reaper.JS_VKeys_GetState(start_time - 1)
    local is_down = st and st:byte(key) ~= 0

    if is_down then
      reaper.defer(step)
      return
    end

    -- Key released: restore intercept + clear running lock
    if reaper.JS_VKeys_Intercept then
      reaper.JS_VKeys_Intercept(key, -1)
    end
    reaper.SetExtState("RadialMenu_Tool", "Running", "0", false)

    -- Clear key fields so atexit does not double-release (safe either way)
    R.key = nil
    R.script_start_time = nil
  end

  reaper.defer(step)
end

function M.init()
  -- Force clear "Running" state on startup to fix "Script not opening" issues
  reaper.SetExtState("RadialMenu_Tool", "Running", "0", false)

  local ext_state = reaper.GetExtState("RadialMenu_Tool", "Running")
  if ext_state == "1" then return false end

  reaper.SetExtState("RadialMenu_Tool", "Running", "1", false)

  reaper.atexit(function()
    reaper.SetExtState("RadialMenu_Tool", "Running", "0", false)
    if R.key and reaper.JS_VKeys_Intercept then
      reaper.JS_VKeys_Intercept(R.key, -1)
    end
    if R.ctx and reaper.ImGui_DestroyContext then
      reaper.ImGui_DestroyContext(R.ctx)
    end

    -- Best-effort restore of trigger wrapper
    if execution and orig_trigger_slot then
      execution.trigger_slot = orig_trigger_slot
    end
  end)

  if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("错误: ReaImGui 未安装", "初始化失败", 0)
    return false
  end

  if not reaper.JS_VKeys_GetState then
    reaper.ShowMessageBox("错误: JS_ReaScriptAPI 扩展未安装\n\n请安装 JS_ReaScriptAPI 扩展以支持长按模式", "初始化失败", 0)
    return false
  end

  R.ctx = reaper.ImGui_CreateContext("RadialMenu_Wheel", reaper.ImGui_ConfigFlags_None())
  R.config = config_manager.load()
  styles.init_from_config(R.config)

  local diameter = (R.config.menu.outer_radius or 200) * 2 + 20
  R.window_width = diameter
  R.window_height = diameter

  R.script_start_time = reaper.time_precise()
  R.anim_open_start_time = reaper.time_precise()

  if R.config.menu.start_sectors then
    for _, sector_id in ipairs(R.config.menu.start_sectors) do
      R.sector_anim_states[sector_id] = 1.0
    end
  end

  -- Detect and intercept trigger key
  R.key = input.detect_and_intercept_trigger_key(R.script_start_time)

  if not R.key then
    reaper.ShowMessageBox("错误: 无法检测到触发按键", "初始化失败", 0)
    return false
  end

  _G.RadialMenuRuntimeState = _G.RadialMenuRuntimeState or {}
  _G.RadialMenuRuntimeState.search = _G.RadialMenuRuntimeState.search or { actions = "", fx = "" }

  R.is_open = true
  return true
end

function M.loop()
  if not R.ctx then return end

  -- dt for dt-driven animations
  local now = reaper.time_precise()
  R.current_frame_dt = 0.0
  if R.last_frame_time then
    R.current_frame_dt = now - R.last_frame_time
    R.current_frame_dt = math.min(math.max(R.current_frame_dt, 0.0), 0.05)
  end
  R.last_frame_time = now

  -- hot reload (ExtState-driven)
  config_reload.maybe_reload(R)

  -- long-press close
  if not track_shortcut_key() then
    return
  end

  -- ESC close
  if reaper.ImGui_IsKeyPressed(R.ctx, reaper.ImGui_Key_Escape()) then
    if not R.is_pinned then
      M.cleanup()
      return
    end
    if not list_view.is_dragging() then
      R.show_submenu = false
      R.clicked_sector = nil
    end
  end

  -- context tracking for execution module
  local current_context = reaper.GetCursorContext()
  if current_context >= 0 and current_context <= 2 then
    R.last_valid_context = current_context
  end
  if execution.set_last_valid_context then
    execution.set_last_valid_context(R.last_valid_context)
  end

  local window_flags = reaper.ImGui_WindowFlags_NoDecoration() |
    reaper.ImGui_WindowFlags_NoSavedSettings() |
    reaper.ImGui_WindowFlags_NoFocusOnAppearing()

  reaper.ImGui_SetNextWindowBgAlpha(R.ctx, 0.0)
  reaper.ImGui_SetNextWindowSize(R.ctx, R.window_width, R.window_height, reaper.ImGui_Cond_Always())

  if R.is_first_display then
    local native_x, native_y = reaper.GetMousePosition()
    if native_x and native_y then
      local mouse_x, mouse_y = reaper.ImGui_PointConvertNative(R.ctx, native_x, native_y, false)
      local window_x = mouse_x - R.window_width / 2
      local window_y = mouse_y - R.window_height / 2

      local viewport = reaper.ImGui_GetMainViewport(R.ctx)
      if viewport then
        local vp_x, vp_y = reaper.ImGui_Viewport_GetPos(viewport)
        local vp_w, vp_h = reaper.ImGui_Viewport_GetSize(viewport)

        if window_x < vp_x then window_x = vp_x end
        if window_x + R.window_width > vp_x + vp_w then window_x = vp_x + vp_w - R.window_width end
        if window_y < vp_y then window_y = vp_y end
        if window_y + R.window_height > vp_y + vp_h then window_y = vp_y + vp_h - R.window_height end
      end

      reaper.ImGui_SetNextWindowPos(R.ctx, window_x, window_y, reaper.ImGui_Cond_Appearing())
    else
      local viewport = reaper.ImGui_GetMainViewport(R.ctx)
      if viewport then
        local vp_x, vp_y = reaper.ImGui_Viewport_GetPos(viewport)
        local vp_w, vp_h = reaper.ImGui_Viewport_GetSize(viewport)
        reaper.ImGui_SetNextWindowPos(R.ctx, vp_x + (vp_w - R.window_width) / 2, vp_y + (vp_h - R.window_height) / 2, reaper.ImGui_Cond_Appearing())
      end
    end
    R.is_first_display = false
  end

  -- Dynamic FPS strategy: should_update only.
  local should_update = true
  if not R.anim_active then
    local target_dt = 1.0 / IDLE_FPS
    R.idle_frame_accumulator = R.idle_frame_accumulator + R.current_frame_dt
    if R.idle_frame_accumulator < target_dt then
      should_update = false
    else
      R.idle_frame_accumulator = R.idle_frame_accumulator - target_dt
    end
  else
    R.idle_frame_accumulator = 0
  end

  reaper.ImGui_PushStyleVar(R.ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 0.0)

  local visible, open = reaper.ImGui_Begin(R.ctx, "Radial Menu", true, window_flags)
  if visible then
    draw.draw(R, should_update)
  end
  reaper.ImGui_End(R.ctx)

  reaper.ImGui_PopStyleVar(R.ctx)

  if queued_slot then
    local slot_to_exec = queued_slot
    queued_slot = nil

    -- Close UI now, but keep key intercept + Running lock until key release.
    -- This prevents the held hotkey from key-repeating and re-triggering the script.
    M.cleanup({ keep_key_intercept = true, keep_running = true })
    defer_release_key_and_running()

    if orig_trigger_slot then
      reaper.defer(function()
        pcall(orig_trigger_slot, slot_to_exec)
      end)
    end

    return
  end

  if open then
    reaper.defer(M.loop)
  end
end

function M.cleanup(opts)
  opts = opts or {}

  if not opts.keep_running then
    reaper.SetExtState("RadialMenu_Tool", "Running", "0", false)
  end
  reaper.SetExtState("RadialMenu_Tool", "WindowOpen", "0", false)

  R.is_first_display = true

  if not opts.keep_key_intercept then
    if R.key and reaper.JS_VKeys_Intercept then
      reaper.JS_VKeys_Intercept(R.key, -1)
    end
    R.key = nil
    R.script_start_time = nil
  end

  if R.ctx then
    if reaper.ImGui_DestroyContext then
      reaper.ImGui_DestroyContext(R.ctx)
    end
    R.ctx = nil
  end
end

function M.run()
  local running = reaper.GetExtState("RadialMenu_Tool", "Running")
  if running == "1" then
    return
  end

  if M.init() then
    reaper.SetExtState("RadialMenu_Tool", "WindowOpen", "1", false)
    M.loop()
  end
end

return M
