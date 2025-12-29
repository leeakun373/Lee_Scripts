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
  last_window_w = nil,
  last_window_h = nil,
  current_active_sector_id = nil,

  -- 窗口位置控制（射手策略）
  target_gui_pos = nil,      -- 目标GUI坐标 {x, y}（首次显示时捕获的鼠标位置）

  -- 【新增】渲染抑制计数器：用于切换模式时"闭眼"几帧
  suppress_render_counter = 0,
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

  -- 初始化窗口位置相关字段
  R.target_gui_pos = nil

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
    reaper.ImGui_WindowFlags_NoMove() |
    reaper.ImGui_WindowFlags_NoResize() |
    reaper.ImGui_WindowFlags_NoSavedSettings() |
    reaper.ImGui_WindowFlags_NoFocusOnAppearing()

  -- ============================================================
  -- 【终极定位系统】统一锚点计算 (Unified Anchor System)
  -- ============================================================
  
  -- 1. 确保锚点存在 (Ensure Anchor Exists)
  -- 只有在 R.target_gui_pos 完全缺失时（首次启动），才捕获鼠标作为锚点。
  -- 之后无论怎么切换模式、刷新缓存，都永远信赖这个锚点，绝不重新捕获。
  if not R.target_gui_pos then
      local mx, my = reaper.GetMousePosition()
      if mx and my then
          local lx, ly = reaper.ImGui_PointConvertNative(R.ctx, mx, my, false)
          R.target_gui_pos = { x = lx, y = ly }
      else
          -- 极端防御：如果连鼠标都抓不到，默认为屏幕原点 (0,0) 但做好标记
          R.target_gui_pos = { x = 0, y = 0 } 
      end
  end

  -- 2. 计算当前应该显示的窗口尺寸和中心偏移 (Calculate Dimensions & Offset)
  local target_w = R.window_width
  local target_h = R.window_height
  local center_offset_x = target_w / 2
  local center_offset_y = target_h / 2
  local is_baked = submenu_bake_cache.is_baked()

  if is_baked then
      -- 如果已烘焙，使用精确的烘焙尺寸
      local max_bounds = submenu_bake_cache.get_max_bounds()
      if max_bounds.win_w > 0 then
          target_w = max_bounds.win_w
          target_h = max_bounds.win_h
          center_offset_x = max_bounds.center_offset_x
          center_offset_y = max_bounds.center_offset_y
          
          -- 同步更新状态尺寸
          R.window_width = target_w
          R.window_height = target_h
      end
  else
      -- 如果未烘焙（中间帧/幽灵帧），保持默认或上一次的尺寸
      -- 关键：必须保持尺寸稳定，防止因为尺寸突变导致的视觉跳动
  end

  -- 3. 计算最终窗口坐标 (Calculate Final Position)
  -- 算法：左上角 = 锚点 - 中心偏移量
  -- 这确保了无论窗口尺寸怎么变（target_w/h 变大变小），窗口永远围绕 target_gui_pos 中心缩放
  local final_pos_x = R.target_gui_pos.x - center_offset_x
  local final_pos_y = R.target_gui_pos.y - center_offset_y

  -- 4. 应用坐标与状态 (Apply State)
  if not is_baked and R.is_first_display then
      -- 【幽灵帧】首次启动且未烘焙：移到屏幕外
      reaper.ImGui_SetNextWindowPos(R.ctx, -10000, -10000, reaper.ImGui_Cond_Always())
  else
      -- 【正常帧】无论是中间态还是完成态，都强制锁定在计算出的中心位置
      -- 使用 Cond_Always 确保每一帧都纠正位置，彻底消除"左上角对齐"带来的偏移
      reaper.ImGui_SetNextWindowPos(R.ctx, final_pos_x, final_pos_y, reaper.ImGui_Cond_Always())
      
      -- 首次显示标记关闭
      if is_baked then
          R.is_first_display = false
      end
  end

  -- 5. 统一设置尺寸
  reaper.ImGui_SetNextWindowSize(R.ctx, target_w, target_h, reaper.ImGui_Cond_Always())
  
  -- ============================================================
  -- 【优化】帧数抑制器 (Frame Suppression Guard)
  -- 如果处于切换后的不稳定期，强制透明，直到布局稳定
  -- 注意：计数器的递减在 if visible then 块中的逻辑冻结部分执行
  -- ============================================================
  if R.suppress_render_counter > 0 then
      -- 强制隐身
      reaper.ImGui_SetNextWindowBgAlpha(R.ctx, 0.0)
  else
      -- 正常显示：设置为全透明背景（内容依然可见）
      reaper.ImGui_SetNextWindowBgAlpha(R.ctx, 0.0)
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
    -- 1. 烘焙计算 (必须执行，否则永远无法结束"未烘焙"状态)
    if not submenu_bake_cache.is_baked() then
      -- 计算相对位置进行烘焙（不依赖窗口当前实际位置，只依赖尺寸）
      -- 这里传入 0,0 即可，因为烘焙只关心相对布局
      local draw_config = R.config
      if R.management_mode and R.management_config then
        draw_config = R.management_config
      end
      local outer_radius = draw_config.menu.outer_radius or 200
      submenu_bake_cache.bake_submenus(ctx, 0, 0, outer_radius, draw_config)
    end
    
    -- 2. 【核心修复】逻辑冻结 (Logic Freeze)
    if R.suppress_render_counter > 0 then
        -- 【无感切换模式】
        -- 此时我们正在切换状态。为了防止残影和误触：
        -- 1. 绝对不要调用 draw.draw() -> 这样就不会画出任何文字/按钮
        -- 2. 绝对不要进行交互检测 -> 这样就不会触发扇区展开
        
        -- 仅递减计数器
        R.suppress_render_counter = R.suppress_render_counter - 1
        
        -- 可选：画一个看不见的全屏盖板，吞掉所有鼠标事件，防止穿透点击到 Reaper 界面
        -- reaper.ImGui_InvisibleButton(ctx, "blocker", target_w, target_h)
    else
        -- 【正常模式】
        -- 只有在画面稳定后，才开始绘制内容和响应交互
        draw.draw(R, should_update)
    end
    
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
  R.target_gui_pos = nil

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

  -- 【修改】增加到 3 帧
  R.suppress_render_counter = 3

  -- 【重要】切换模式时，立即暴力清除所有交互状态
  R.clicked_sector = nil
  R.show_submenu = false
  R.last_hover_sector_id = nil
  R.active_sector_id = nil

  -- 【重要】这里绝对不要重新捕获窗口位置！
  -- R.target_gui_pos 在脚本启动时已经确立，它是最准确的锚点。
  -- 任何试图在运行时重新获取位置的行为（如 GetWindowPos）都可能引入偏差或归零错误。

  if R.management_mode then
    R.management_config = M.generate_management_config()
    submenu_bake_cache.clear()
    submenu_cache.clear()
  else
    R.management_config = nil
    submenu_bake_cache.clear()
    submenu_cache.clear()
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
      -- 清理缓存
      submenu_bake_cache.clear()
      submenu_cache.clear()
      
      -- 【修改】增加到 3 帧
      R.suppress_render_counter = 3
      
      -- 切换预设
      local new_config = config_manager.apply_preset(preset_name)
      if new_config then
        R.config = new_config
        styles.init_from_config(R.config) -- 刷新样式
        
        -- 清除子菜单状态，避免切换后残留
        R.clicked_sector = nil
        R.show_submenu = false
        R.last_hover_sector_id = nil
        R.active_sector_id = nil

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

