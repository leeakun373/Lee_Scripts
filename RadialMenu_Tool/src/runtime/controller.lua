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
local submenu_cache = require("gui.submenu_cache")
local submenu_bake_cache = require("gui.submenu_bake_cache")

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
  is_dragging_window = false,

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

  -- management mode
  management_mode = false,
  management_config = nil,

  -- 如影随形窗口系统
  last_window_x = nil,
  last_window_y = nil,
  last_window_w = nil,
  last_window_h = nil,
  current_active_sector_id = nil,
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

  -- ============================================================
  -- 【固定窗口大小系统】使用预计算的最大包围盒
  -- ============================================================
  -- 获取最大包围盒数据（固定窗口大小）
  local max_bounds = submenu_bake_cache.get_max_bounds()
  local win_w = max_bounds.win_w
  local win_h = max_bounds.win_h
  
  -- 如果还没有烘焙，使用默认大小
  if win_w == 0 or win_h == 0 then
    local draw_config = R.config
    if R.management_mode and R.management_config then
      draw_config = R.management_config
    end
    local outer_radius = draw_config.menu.outer_radius or 200
    win_w = outer_radius * 2 + 40
    win_h = outer_radius * 2 + 40
  end

  -- 只在第一帧设置窗口位置（以鼠标为中心，减去圆心偏移量）
  if R.is_first_display then
    local native_x, native_y = reaper.GetMousePosition()
    if native_x and native_y then
      -- 【关键修复】ImGui_SetNextWindowPos 需要屏幕坐标，不是窗口坐标
      -- 如果还没有烘焙，使用窗口中心作为默认偏移量
      local center_offset_x = max_bounds.center_offset_x
      local center_offset_y = max_bounds.center_offset_y
      
      -- 如果还没有烘焙（偏移量为0），使用窗口中心作为默认偏移量
      if center_offset_x == 0 or center_offset_y == 0 then
        center_offset_x = win_w / 2
        center_offset_y = win_h / 2
      end
      
      -- 设置位置，确保圆心正好在鼠标位置（使用屏幕坐标）
      local win_x = native_x - center_offset_x
      local win_y = native_y - center_offset_y
      
      -- 确保窗口不会超出视口
      local viewport = reaper.ImGui_GetMainViewport(R.ctx)
      if viewport then
        local vp_x, vp_y = reaper.ImGui_Viewport_GetPos(viewport)
        local vp_w, vp_h = reaper.ImGui_Viewport_GetSize(viewport)
        
        if win_x < vp_x then win_x = vp_x end
        if win_y < vp_y then win_y = vp_y end
        if win_x + win_w > vp_x + vp_w then win_x = vp_x + vp_w - win_w end
        if win_y + win_h > vp_y + vp_h then win_y = vp_y + vp_h - win_h end
      end
      
      reaper.ImGui_SetNextWindowPos(R.ctx, win_x, win_y, reaper.ImGui_Cond_Appearing())
      R.last_window_x = win_x
      R.last_window_y = win_y
    else
      local viewport = reaper.ImGui_GetMainViewport(R.ctx)
      if viewport then
        local vp_x, vp_y = reaper.ImGui_Viewport_GetPos(viewport)
        local vp_w, vp_h = reaper.ImGui_Viewport_GetSize(viewport)
        local win_x = vp_x + (vp_w - win_w) / 2
        local win_y = vp_y + (vp_h - win_h) / 2
        reaper.ImGui_SetNextWindowPos(R.ctx, win_x, win_y, reaper.ImGui_Cond_Appearing())
        R.last_window_x = win_x
        R.last_window_y = win_y
      end
    end
    R.is_first_display = false
  end

  -- 设置固定窗口大小（不再每帧变化）
  reaper.ImGui_SetNextWindowSize(R.ctx, win_w, win_h, reaper.ImGui_Cond_Always())
  reaper.ImGui_SetNextWindowBgAlpha(R.ctx, 0.0)
  
  -- 保存窗口大小（用于后续使用）
  R.last_window_w = win_w
  R.last_window_h = win_h

  -- 第一帧显示逻辑已移到上面的智能窗口边界计算中
  if R.is_first_display then
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

  -- Save context to local variable in case it gets destroyed during draw
  local ctx = R.ctx
  if not ctx then return end

  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 0.0)

  local visible, open = reaper.ImGui_Begin(ctx, "Radial Menu", true, window_flags)
  if visible then
    -- 【极速缓存系统】第一帧烘焙所有繁重数据
    -- 必须在 ImGui_Begin 之后调用，因为 CalcTextSize 需要上下文
    if not submenu_bake_cache.is_baked() then
      local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
      local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
      local center_x = win_x + win_w / 2
      local center_y = win_y + win_h / 2
      local draw_config = R.config
      if R.management_mode and R.management_config then
        draw_config = R.management_config
      end
      local outer_radius = draw_config.menu.outer_radius or 200
      submenu_bake_cache.bake_submenus(ctx, center_x, center_y, outer_radius, draw_config)
      
      -- 【关键修复】烘焙完成后，使用计算好的最大包围盒更新窗口大小和位置
      local new_max_bounds = submenu_bake_cache.get_max_bounds()
      if new_max_bounds.win_w > 0 and new_max_bounds.win_h > 0 then
        -- 更新窗口大小
        reaper.ImGui_SetNextWindowSize(ctx, new_max_bounds.win_w, new_max_bounds.win_h, reaper.ImGui_Cond_Always())
        R.last_window_w = new_max_bounds.win_w
        R.last_window_h = new_max_bounds.win_h
        
        -- 【关键修复】重新调整窗口位置，确保圆心在鼠标位置
        -- 因为窗口大小可能改变了，需要重新计算位置
        local native_x, native_y = reaper.GetMousePosition()
        if native_x and native_y then
          local new_win_x = native_x - new_max_bounds.center_offset_x
          local new_win_y = native_y - new_max_bounds.center_offset_y
          
          -- 确保窗口不会超出视口
          local viewport = reaper.ImGui_GetMainViewport(ctx)
          if viewport then
            local vp_x, vp_y = reaper.ImGui_Viewport_GetPos(viewport)
            local vp_w, vp_h = reaper.ImGui_Viewport_GetSize(viewport)
            
            if new_win_x < vp_x then new_win_x = vp_x end
            if new_win_y < vp_y then new_win_y = vp_y end
            if new_win_x + new_max_bounds.win_w > vp_x + vp_w then new_win_x = vp_x + vp_w - new_max_bounds.win_w end
            if new_win_y + new_max_bounds.win_h > vp_y + vp_h then new_win_y = vp_y + vp_h - new_max_bounds.win_h end
          end
          
          reaper.ImGui_SetNextWindowPos(ctx, new_win_x, new_win_y, reaper.ImGui_Cond_Always())
          R.last_window_x = new_win_x
          R.last_window_y = new_win_y
        end
      end
    end
    
    draw.draw(R, should_update)
  end
  
  -- Always call ImGui_End if Begin was called, using saved context
  -- This ensures proper pairing even if R.ctx was set to nil during draw
  if visible then
    reaper.ImGui_End(ctx)
  end
  
  -- Always pop style var to match the push, using saved context
  -- This ensures proper pairing even if R.ctx was set to nil during draw
  reaper.ImGui_PopStyleVar(ctx)

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

  -- 【性能优化】清理子菜单缓存池
  if submenu_cache and submenu_cache.clear then
    submenu_cache.clear()
  end

  if R.ctx then
    if reaper.ImGui_DestroyContext then
      reaper.ImGui_DestroyContext(R.ctx)
    end
    R.ctx = nil
  end
end

-- ============================================================================
-- Management Mode Functions
-- ============================================================================

function M.generate_management_config()
  local presets = config_manager.get_preset_list()
  local current_preset = config_manager.get_current_preset_name()

  local sectors = {}

  -- 1. Setup 扇区：纯文字
  table.insert(sectors, {
    id = "sys_setup",
    name = "Setup",
    color = {200, 50, 50, 255}, -- 红色高亮
    slots = {} -- 空槽位，仅作为按钮
  })

  -- 2. 预设扇区：纯文字
  for i, name in ipairs(presets) do
    local is_current = (name == current_preset)
    -- 当前选中的预设用方括号标识，或仅依靠颜色区分
    local display_name = name
    if is_current then 
      display_name = "[ " .. name .. " ]"
    end
    
    table.insert(sectors, {
      id = "preset:" .. name,
      name = display_name,
      -- 当前预设用绿色，其他用灰色
      color = is_current and {50, 200, 100, 255} or {100, 100, 100, 255},
      slots = {}
    })
  end

  -- 构造虚拟 Config 对象，保留原有的 menu 几何设置
  return {
    menu = R.config.menu, -- 复用半径设置
    sectors = sectors,
    colors = R.config.colors -- 复用全局颜色
  }
end

function M.toggle_management_mode()
  R.management_mode = not R.management_mode
  R.clicked_sector = nil -- 清除子菜单状态
  R.show_submenu = false

  if R.management_mode then
    R.management_config = M.generate_management_config()
  else
    R.management_config = nil
  end
end

function M.open_setup_script()
  -- 计算 Setup 脚本的绝对路径
  -- 从当前文件 (controller.lua) 的位置推导根目录
  local source_path = debug.getinfo(1, "S").source
  source_path = source_path:match("@?(.*)")
  -- 去掉文件名，得到 src/runtime/ 目录路径
  local runtime_dir = source_path:match("(.*[\\/])")
  -- 去掉 src/runtime/ 部分，得到根目录（使用匹配方式更可靠）
  local root_path
  if runtime_dir:match("[\\/]src[\\/]runtime[\\/]$") then
    root_path = runtime_dir:match("(.*)[\\/]src[\\/]runtime[\\/]$")
  elseif runtime_dir:match("[\\/]src[\\/]$") then
    root_path = runtime_dir:match("(.*)[\\/]src[\\/]$")
  else
    -- fallback: 假设从 runtime 往上两级
    root_path = runtime_dir:match("(.*[\\/])[^\\/]+[\\/]$")
    if root_path then
      root_path = root_path:match("(.*[\\/])[^\\/]+[\\/]$")
    end
  end
  if not root_path then
    reaper.MB("无法确定脚本根目录路径", "错误", 0)
    return
  end
  -- 确保路径以分隔符结尾
  local sep = runtime_dir:match("([\\/])") or "/"
  if not root_path:match("[\\/]$") then
    root_path = root_path .. sep
  end
  local setup_path = root_path .. "Lee_RadialMenu_Setup.lua"

  -- 使用 AddRemoveReaScript 自动注册并获取 Command ID
  -- 如果脚本已在 Action List，返回现有 ID；如果没有，自动注册并返回新 ID
  local command_id = reaper.AddRemoveReaScript(true, 0, setup_path, true)

  if command_id and command_id > 0 then
    reaper.Main_OnCommand(command_id, 0)
    -- 启动 Setup 后，关闭当前的轮盘，避免绘图冲突
    M.cleanup()
  else
    reaper.MB("无法自动启动设置脚本，请手动在 Action List 中运行 Lee_RadialMenu_Setup.lua", "错误", 0)
  end
end

function M.handle_management_click(sector_id)
  if sector_id == "sys_setup" then
    -- 打开设置脚本
    M.open_setup_script()

  elseif sector_id:match("^preset:") then
    local preset_name = sector_id:match("^preset:(.+)")
    if preset_name then
      -- 切换预设
      local new_config = config_manager.apply_preset(preset_name)
      if new_config then
        R.config = new_config
        styles.init_from_config(R.config) -- 刷新样式

        -- 视觉反馈：退出管理模式并重置动画状态
        R.management_mode = false
        R.management_config = nil

        -- 重置动画状态让用户感觉到刷新
        R.anim_open_start_time = reaper.time_precise()
      end
    end
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

