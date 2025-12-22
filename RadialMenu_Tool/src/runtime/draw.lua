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

function M.on_sector_click(R, sector)
  if not sector then return end

  -- Drag lock
  if list_view.is_dragging() then
    return
  end

  if R.clicked_sector and R.clicked_sector.id == sector.id then
    R.show_submenu = false
    R.clicked_sector = nil
  else
    R.clicked_sector = sector
    R.show_submenu = true
  end
end

function M.handle_sector_click(R, center_x, center_y, inner_radius, outer_radius, is_submenu_hovered)
  -- Drag lock: completely block sector click logic.
  if list_view.is_dragging() then
    return
  end

  -- If hovering submenu window, let it handle clicks.
  if is_submenu_hovered then
    return
  end

  local ctx = R.ctx
  local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
  local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
  local relative_x = mouse_x - win_x
  local relative_y = mouse_y - win_y
  local w, h = reaper.ImGui_GetWindowSize(ctx)

  local distance = math_utils.distance(relative_x, relative_y, w / 2, h / 2)

  if distance > inner_radius and distance <= outer_radius then
    if reaper.ImGui_IsMouseClicked(ctx, 0) then
      R.last_interact_time = reaper.time_precise()
      local hovered_id = wheel.get_hovered_sector_id()
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

  local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
  local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
  local center_x = win_x + win_w / 2
  local center_y = win_y + win_h / 2

  local inner_radius = draw_config.menu.inner_radius or 50
  local outer_radius = draw_config.menu.outer_radius or 200

  -- ============================================================
  -- Animations (wheel open + anim_active policy)
  -- ============================================================
  local now = reaper.time_precise()
  local anim_scale = anim.calc_wheel_open_scale(draw_config, R.anim_open_start_time, now)
  anim.update_anim_active_policy(R, should_update, anim_scale, now)

  -- ============================================================
  -- Submenu: no animation
  -- ============================================================
  local is_dragging = list_view.is_dragging()
  local sub_scale = 1.0
  if is_dragging then
    R.show_submenu = true
  end

  -- ============================================================
  -- Sector expansion animation state
  -- ============================================================
  anim.update_sector_expansion(R, draw_config, should_update, center_x, center_y)

  -- ============================================================
  -- 1) Submenu draw (below wheel)
  -- ============================================================
  if is_dragging and R.clicked_sector then
    R.show_submenu = true
  end

  local is_submenu_hovered = false
  if R.show_submenu and R.clicked_sector then
    is_submenu_hovered = list_view.draw_submenu(ctx, R.clicked_sector, center_x, center_y, sub_scale, draw_config)
  end

  -- ============================================================
  -- 2) Wheel draw
  -- ============================================================
  local wheel_start_time = reaper.time_precise()
  local active_id = (R.show_submenu and R.clicked_sector) and R.clicked_sector.id or nil
  wheel.draw_wheel(ctx, draw_config, active_id, R.is_pinned, anim_scale, R.sector_anim_states)
  local wheel_time = reaper.time_precise() - wheel_start_time
  perf.accumulate_wheel(R, wheel_time)

  -- ============================================================
  -- 3) Center drag handle (InvisibleButton)
  -- ============================================================
  reaper.ImGui_SetCursorPos(ctx, (win_w / 2) - inner_radius, (win_h / 2) - inner_radius)
  reaper.ImGui_InvisibleButton(ctx, "##DragHandle", inner_radius * 2, inner_radius * 2)

  -- Right-click detection for management mode
  if reaper.ImGui_IsItemClicked(ctx, 1) then -- 1 = Right Button
    local controller = require("runtime.controller")
    controller.toggle_management_mode()
  end

  if reaper.ImGui_IsItemActive(ctx) and reaper.ImGui_IsMouseDragging(ctx, 0) then
    R.center_drag_started = true

    local dx, dy = reaper.ImGui_GetMouseDelta(ctx, 0)
    if reaper.ImGui_ResetMouseDragDelta then
      reaper.ImGui_ResetMouseDragDelta(ctx, 0)
    end

    if math.abs(dx) > 0.001 or math.abs(dy) > 0.001 then
      local new_x = win_x + dx
      local new_y = win_y + dy

      local viewport = reaper.ImGui_GetMainViewport(ctx)
      if viewport then
        local vp_x, vp_y = reaper.ImGui_Viewport_GetPos(viewport)
        local vp_w, vp_h = reaper.ImGui_Viewport_GetSize(viewport)

        if new_x < vp_x then
          new_x = vp_x
        elseif new_x + win_w > vp_x + vp_w then
          new_x = vp_x + vp_w - win_w
        end

        if new_y < vp_y then
          new_y = vp_y
        elseif new_y + win_h > vp_y + vp_h then
          new_y = vp_y + vp_h - win_h
        end
      end

      reaper.ImGui_SetWindowPos(ctx, new_x, new_y)
    end
  end

  if reaper.ImGui_IsItemDeactivated(ctx) and not R.center_drag_started then
    -- 在管理模式下，左键点击中心退出管理模式
    if R.management_mode then
      local controller = require("runtime.controller")
      controller.toggle_management_mode()
    else
      R.is_pinned = not R.is_pinned
    end
  end

  if not reaper.ImGui_IsItemActive(ctx) then
    R.center_drag_started = false
  end

  if reaper.ImGui_IsItemHovered(ctx) then
    if reaper.ImGui_MouseCursor_ResizeAll then
      reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeAll())
    end
  end

  -- ============================================================
  -- 4) Hover-to-open (skip in management mode)
  -- ============================================================
  if not is_dragging and not R.management_mode then
    local hovered_id = wheel.get_hovered_sector_id()
    if draw_config.menu.hover_to_open and hovered_id then
      if not R.clicked_sector or R.clicked_sector.id ~= hovered_id then
        local sector = config_manager.get_sector_by_id(draw_config, hovered_id)
        if sector then
          R.clicked_sector = sector
          R.show_submenu = true
        end
      end
    end
  end

  -- ============================================================
  -- 5) Auto-hide submenu (skip in management mode)
  -- ============================================================
  if R.show_submenu and R.clicked_sector and not is_dragging and draw_config.menu.hover_to_open and not R.management_mode then
    local hovered_id = wheel.get_hovered_sector_id()
    local is_hovering_any_sector = (hovered_id ~= nil)
    if not is_hovering_any_sector and not is_submenu_hovered then
      R.show_submenu = false
      R.clicked_sector = nil
    end
  end

  -- ============================================================
  -- 6) Sector click hit-test
  -- ============================================================
  M.handle_sector_click(R, center_x, center_y, inner_radius, outer_radius, is_submenu_hovered)

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
