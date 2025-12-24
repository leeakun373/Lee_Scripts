-- @description RadialMenu Tool - Runtime drawing composition
-- @about
--   Draw wheel/submenu/center handle composition.
--
--   This module contains the heavy UI drawing logic that previously lived in
--   `main_runtime.lua`, to reduce the controller's size and make maintenance
--   easier.

local M = {}

local config_manager = require("config_manager")
local wheel = require("gui.wheel")
local list_view = require("gui.list_view")
local styles = require("gui.styles")
local math_utils = require("math_utils")
local execution = require("logic.execution")
local anim = require("runtime.anim")
local perf = require("runtime.perf")
local submenu_bake_cache = require("gui.submenu_bake_cache")

function M.on_sector_click(R, sector)
  if not sector then return end

  -- Drag lock
  if list_view.is_dragging() then
    return
  end

  -- 【修复点击逻辑冲突】悬浮模式下点击已展开扇区时保持展开状态
  if R.show_submenu and R.clicked_sector and R.clicked_sector.id == sector.id then
    -- 如果子菜单已展开且是同一扇区 → 保持展开，不执行动作
    -- 这样避免了"关闭→重开"的闪烁问题
    return
  end

  -- 【修复】瞬间切换：点击时立即显示/隐藏子栏，不使用任何动画
  if R.clicked_sector and R.clicked_sector.id == sector.id then
    -- 瞬间隐藏：直接设为 false，alpha = 0.0
    R.show_submenu = false
    R.clicked_sector = nil
  else
    -- 瞬间显示：直接设为 true，alpha = 1.0
    R.clicked_sector = sector
    R.show_submenu = true
  end
end

function M.handle_sector_click(R, center_x, center_y, inner_radius, outer_radius, is_submenu_hovered, draw_config)
  -- Drag lock: completely block sector click logic.
  if list_view.is_dragging() then
    return
  end

  -- If hovering submenu window, let it handle clicks.
  if is_submenu_hovered then
    return
  end

  local ctx = R.ctx
  -- 【修复】使用 GetMousePosition() 获取屏幕坐标，然后转换为窗口坐标
  -- 这样才能检测到窗口外的鼠标位置（包括右键点击）
  local screen_mouse_x, screen_mouse_y = reaper.GetMousePosition()
  local mouse_x, mouse_y = reaper.ImGui_PointConvertNative(ctx, screen_mouse_x, screen_mouse_y)
  local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
  local relative_x = mouse_x - win_x
  local relative_y = mouse_y - win_y
  local w, h = reaper.ImGui_GetWindowSize(ctx)

  local distance = math_utils.distance(relative_x, relative_y, w / 2, h / 2)

  if distance > inner_radius and distance <= outer_radius then
    -- 【修复】同时支持左键和右键点击扇区
    if reaper.ImGui_IsMouseClicked(ctx, 0) or reaper.ImGui_IsMouseClicked(ctx, 1) then
      R.last_interact_time = reaper.time_precise()
      -- 【重构】使用计算好的 active_sector_id（在 draw 函数开头已计算）
      -- 注意：这里需要重新计算一次，因为点击时鼠标位置可能已变化
      -- 【修复】使用 GetMousePosition() 获取屏幕坐标，然后转换为窗口坐标
      local click_screen_x, click_screen_y = reaper.GetMousePosition()
      local click_mouse_x, click_mouse_y = reaper.ImGui_PointConvertNative(ctx, click_screen_x, click_screen_y)
      local click_dx = click_mouse_x - center_x
      local click_dy = click_mouse_y - center_y
      local click_dist_sq = click_dx * click_dx + click_dy * click_dy
      local click_inner_radius_sq = inner_radius * inner_radius
      
      local hovered_id = nil
      -- 【实现 Sexan 效果】只要超过内圈，就根据角度判断扇区，不管距离多远
      -- 点击时仍然限制在内外圈之间，但悬停时允许无限外延
      if click_dist_sq > click_inner_radius_sq and click_dist_sq <= (outer_radius * outer_radius) and draw_config and draw_config.sectors then
        local click_angle = math.atan(click_dy, click_dx)
        if click_angle < 0 then click_angle = click_angle + 2 * math.pi end
        
        local num_sectors = #draw_config.sectors
        local step = (2 * math.pi) / num_sectors
        local start_offset = -math.pi / 2
        
        for i = 1, num_sectors do
          local ang_min = start_offset + (i - 1) * step
          local ang_max = start_offset + i * step
          if math_utils.angle_in_range(click_angle, ang_min, ang_max) then
            hovered_id = draw_config.sectors[i].id
            break
          end
        end
      end
      
      if hovered_id then
        -- 管理模式下的点击处理
        if R.management_mode and R.management_config then
          local sector = config_manager.get_sector_by_id(R.management_config, hovered_id)
          if sector then
            local controller = require("runtime.controller")
            controller.handle_management_click(sector.id)
          end
        else
          -- 正常模式下的点击处理
          local sector = config_manager.get_sector_by_id(R.config, hovered_id)
          if sector then
            M.on_sector_click(R, sector)
          end
        end
      end
    end
  elseif distance > outer_radius then
    if reaper.ImGui_IsMouseClicked(ctx, 0) then
      R.last_interact_time = reaper.time_precise()
      if R.show_submenu and not is_submenu_hovered and not list_view.is_dragging() then
        R.show_submenu = false
        R.clicked_sector = nil
      end
    end
  end
end

-- Main UI draw function (previously M.draw in main_runtime)
function M.draw(R, should_update)
  local ctx = R.ctx
  if not ctx or not R.config then return end

  should_update = (should_update ~= false)

  -- 根据管理模式选择配置源
  local draw_config = R.config
  if R.management_mode and R.management_config then
    draw_config = R.management_config
  end

  local ui_start_time = reaper.time_precise()

  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 0, 0)

  -- 【固定窗口系统】使用圆心偏移量计算稳定的绘制中心
  local submenu_bake_cache = require("gui.submenu_bake_cache")
  local max_bounds = submenu_bake_cache.get_max_bounds()
  
  local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
  local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
  
  -- 圆心在窗口内的位置（这是稳定的绘制中心）
  local center_x, center_y
  if max_bounds and max_bounds.center_offset_x > 0 and max_bounds.center_offset_y > 0 then
    center_x = win_x + max_bounds.center_offset_x
    center_y = win_y + max_bounds.center_offset_y
  else
    -- 如果还没有烘焙，使用窗口中心（向后兼容）
    center_x = win_x + win_w / 2
    center_y = win_y + win_h / 2
  end

  local inner_radius = draw_config.menu.inner_radius or 50
  local outer_radius = draw_config.menu.outer_radius or 200

  -- ============================================================
  -- 【核心重构】先算后画：纯数学判定 Active Sector
  -- ============================================================
  -- 1. 【输入层】获取鼠标数据（只获取，不画图）
  -- 【关键修复】使用 GetMousePosition() 获取屏幕坐标，然后转换为窗口坐标
  -- 这样才能检测到窗口外的鼠标位置，实现"无限外延"效果（参考 Sexan 的实现）
  local screen_mouse_x, screen_mouse_y = reaper.GetMousePosition()
  -- 将屏幕坐标转换为窗口坐标（参考 Sexan 第 651 行）
  local mouse_x, mouse_y = reaper.ImGui_PointConvertNative(ctx, screen_mouse_x, screen_mouse_y)
  local dx = mouse_x - center_x
  local dy = mouse_y - center_y
  local dist_sq = dx * dx + dy * dy  -- 用平方距离，省去开根号，性能更好
  
  -- 计算鼠标角度 (0 到 2PI)
  local mouse_angle = math.atan(dy, dx)
  if mouse_angle < 0 then 
    mouse_angle = mouse_angle + 2 * math.pi 
  end

  -- 2. 【逻辑层】纯数学计算 Active Sector（不依赖任何 UI）
  -- 【实现 Sexan 效果】只要超过内圈，就根据角度判断扇区，不管距离多远
  -- 这样鼠标在轮盘外也能根据方向判断扇区
  local active_sector = nil
  local active_sector_id = nil
  local inner_radius_sq = inner_radius * inner_radius
  
  -- 只有出了内圈才开始算（实现 Sexan 的"无限外延"且"中间有死区"）
  -- 不检查外圈上限，这样鼠标在轮盘外也能根据方向判断扇区
  if dist_sq > inner_radius_sq and draw_config.sectors then
    local num_sectors = #draw_config.sectors
    local step = (2 * math.pi) / num_sectors
    local start_offset = -math.pi / 2  -- 从上方（-90度）开始分布
    
    -- 遍历所有扇区，看鼠标角度落在哪一个里面
    for i = 1, num_sectors do
      local ang_min = start_offset + (i - 1) * step
      local ang_max = start_offset + i * step
      
      -- 【关键点】用数学判断，而不是 UI 碰撞
      -- 只判断角度，不判断距离上限，实现"无限外延"效果
      -- 【修复】确保只匹配一个扇区，找到后立即退出
      if math_utils.angle_in_range(mouse_angle, ang_min, ang_max) then
        active_sector = draw_config.sectors[i]
        active_sector_id = active_sector.id
        break  -- 【关键】找到了就立即退出，确保只有一个扇区被激活
      end
    end
  end
  
  -- 到这里，active_sector 已经是绝对准确的了，而且是在画图之前就确定了！

  -- ============================================================
  -- Animations (wheel open + anim_active policy)
  -- ============================================================
  local now = reaper.time_precise()
  local anim_scale = anim.calc_wheel_open_scale(draw_config, R.anim_open_start_time, now)
  anim.update_anim_active_policy(R, should_update, anim_scale, now)

  -- ============================================================
  -- Submenu: no animation (instant switch)
  -- ============================================================
  local is_dragging = list_view.is_dragging()
  -- 【修复】sub_scale 不再使用，子栏瞬间显示/隐藏
  if is_dragging then
    R.show_submenu = true
  end

  -- ============================================================
  -- Sector expansion animation state（使用新的 active_sector_id）
  -- ============================================================
  -- 更新动画状态，使用计算好的 active_sector_id
  if active_sector_id ~= R.last_hover_sector_id then
    R.anim_active = true
    R.last_hover_sector_id = active_sector_id
  end
  
  -- 更新扇区扩展动画（传入计算好的 active_sector_id）
  anim.update_sector_expansion_with_active(R, draw_config, should_update, active_sector_id)

  -- ============================================================
  -- 1) Submenu draw (below wheel) - Instant switch
  -- ============================================================
  if is_dragging and R.clicked_sector then
    R.show_submenu = true
  end

  local is_submenu_hovered = false
  -- 【修复】子栏瞬间切换：如果 show_submenu 为 true，立即显示（alpha = 1.0）
  -- 如果为 false，不绘制（相当于 alpha = 0.0）
  if R.show_submenu and R.clicked_sector then
    -- 直接绘制，不使用任何动画参数
    is_submenu_hovered = list_view.draw_submenu(ctx, R.clicked_sector, center_x, center_y, 1.0, draw_config)
  end
  
  -- 存储当前激活的扇区ID（用于计算窗口边界）
  R.current_active_sector_id = active_sector_id
  if R.show_submenu and R.clicked_sector then
    R.current_active_sector_id = R.clicked_sector.id
  end

  -- ============================================================
  -- 3) 【绘制层】根据算好的 active_sector_id 画图
  -- ============================================================
  local wheel_start_time = reaper.time_precise()
  -- 子菜单激活时优先使用 clicked_sector，否则使用计算好的 active_sector_id
  local active_id = (R.show_submenu and R.clicked_sector) and R.clicked_sector.id or active_sector_id
  wheel.draw_wheel(ctx, draw_config, active_id, R.is_pinned, anim_scale, R.sector_anim_states, active_sector_id)
  local wheel_time = reaper.time_precise() - wheel_start_time
  perf.accumulate_wheel(R, wheel_time)

  -- ============================================================
  -- 3) Center Pin button (InvisibleButton for click detection only)
  -- ============================================================
  -- 【修复】取消窗口拖拽功能，只保留点击检测
  -- 设置光标位置到圆心按钮的左上角
  reaper.ImGui_SetCursorPos(ctx, (win_w / 2) - inner_radius, (win_h / 2) - inner_radius)
  
  -- 画一个隐形按钮覆盖住内圈（仅用于点击检测，不用于拖拽）
  reaper.ImGui_InvisibleButton(ctx, "##PinButton", inner_radius * 2, inner_radius * 2)

  -- ============================================================
  -- 【已完全禁用】窗口拖拽逻辑 - 取消拖拽扇区移动轮盘的功能
  -- ============================================================
  -- 窗口拖拽功能已完全禁用，确保拖拽扇区时不会移动轮盘
  -- ============================================================

  -- 右键点击检测（用于管理模式）
  if reaper.ImGui_IsItemClicked(ctx, 1) then -- 1 = Right Button
    local controller = require("runtime.controller")
    controller.toggle_management_mode()
  end

  -- 左键点击检测：切换 Pin 状态或退出管理模式
  -- 【修复】移除拖拽检测，只检测点击（避免拖拽扇区时触发）
  if reaper.ImGui_IsItemDeactivated(ctx) then
    -- 在管理模式下，左键点击中心退出管理模式
    if R.management_mode then
      local controller = require("runtime.controller")
      controller.toggle_management_mode()
    else
      R.is_pinned = not R.is_pinned
    end
  end

  -- 【已禁用】鼠标悬停时的光标变化（因为已取消拖拽功能）
  -- if reaper.ImGui_IsItemHovered(ctx) then
  --   if reaper.ImGui_MouseCursor_ResizeAll then
  --     reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeAll())
  --   end
  -- end

  -- ============================================================
  -- 4) Hover-to-open (skip in management mode) - Instant switch
  -- ============================================================
  -- 【重构】使用计算好的 active_sector_id，不再调用 wheel.get_hovered_sector_id()
  if not is_dragging and not R.management_mode then
    if draw_config.menu.hover_to_open and active_sector_id then
      -- 【修复】扇区切换时立即切换子栏，不保留淡出状态
      if not R.clicked_sector or R.clicked_sector.id ~= active_sector_id then
        if active_sector then
          -- 立即切换：直接设置新扇区，立即显示子栏（alpha = 1.0）
          R.clicked_sector = active_sector
          R.show_submenu = true
          -- 不保留任何淡出状态，直接切换
        end
      end
    end
  end

  -- ============================================================
  -- 5) Auto-hide submenu (skip in management mode) - Instant hide
  -- ============================================================
  -- 【重构】使用计算好的 active_sector_id
  if R.show_submenu and R.clicked_sector and not is_dragging and draw_config.menu.hover_to_open and not R.management_mode then
    local is_hovering_any_sector = (active_sector_id ~= nil)
    -- 【修复】瞬间隐藏：如果鼠标移开，立即隐藏子栏（alpha = 0.0），不保留淡出状态
    if not is_hovering_any_sector and not is_submenu_hovered then
      R.show_submenu = false
      R.clicked_sector = nil
      -- 立即清除状态，不保留任何淡出动画
    end
  end

  -- ============================================================
  -- 6) Sector click hit-test
  -- ============================================================
  M.handle_sector_click(R, center_x, center_y, inner_radius, outer_radius, is_submenu_hovered, draw_config)

  -- ============================================================
  -- 7) Drag feedback + drop
  -- ============================================================
  if list_view.is_dragging() then
    local dragging_slot = list_view.get_dragging_slot()
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    if draw_list and dragging_slot then
      list_view.draw_drag_feedback(draw_list, ctx, dragging_slot)
    end

    if not reaper.ImGui_IsMouseDown(ctx, 0) then
      local screen_x, screen_y = reaper.GetMousePosition()
      if screen_x and screen_y and dragging_slot then
        execution.handle_drop(dragging_slot, screen_x, screen_y)
      end
      list_view.reset_drag()
    end
  end

  reaper.ImGui_PopStyleVar(ctx)

  -- ============================================================
  -- Perf stats / HUD
  -- ============================================================
  local ui_time = reaper.time_precise() - ui_start_time
  perf.accumulate_ui(R, ui_time)
  perf.tick_frame(R)
  perf.draw_hud(R)
end

return M
