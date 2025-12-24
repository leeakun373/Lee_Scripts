-- @description RadialMenu Tool - Runtime performance stats
-- @about
--   Perf counters and optional HUD rendering.

local M = {}

function M.accumulate_wheel(R, wheel_time)
  R.perf_wheel_time = (R.perf_wheel_time or 0.0) + (wheel_time or 0.0)
end

function M.accumulate_ui(R, ui_time)
  R.perf_ui_time = (R.perf_ui_time or 0.0) + (ui_time or 0.0)
end

function M.tick_frame(R)
  R.perf_frame_count = (R.perf_frame_count or 0) + 1
  if R.perf_frame_count >= 30 then
    local avg_wheel = (R.perf_wheel_time or 0.0) / 30.0
    local avg_ui = (R.perf_ui_time or 0.0) / 30.0
    R.perf_last_text = string.format("Wheel: %.2fms | UI: %.2fms", avg_wheel * 1000, avg_ui * 1000)

    R.perf_frame_count = 0
    R.perf_wheel_time = 0.0
    R.perf_ui_time = 0.0
  end
end

function M.draw_hud(R)
  local config = R.config
  if not (config and config.debug and config.debug.show_perf_hud) then
    return
  end

  if not R.perf_last_text or R.perf_last_text == "" then
    return
  end

  -- 【已废弃】拖拽检测：如果启用拖拽功能，拖拽时隐藏性能HUD
  -- 由于拖拽功能已默认禁用，此检测也被禁用
  local enable_drag = config.menu.enable_window_drag or false
  if enable_drag then
    local ctx = R.ctx
    if ctx and reaper.ImGui_IsMouseDragging then
      if reaper.ImGui_IsMouseDragging(ctx, 0) then
        -- 检查是否在拖拽中心手柄（通过检查鼠标是否在内圈区域）
        local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
        local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
        local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
        local center_x = win_x + win_w / 2
        local center_y = win_y + win_h / 2
        local inner_radius = config.menu.inner_radius or 50
        
        local dx = mouse_x - center_x
        local dy = mouse_y - center_y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if distance <= inner_radius then
          return  -- 正在拖拽中心，隐藏HUD
        end
      end
    end
  end

  local ctx = R.ctx
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  if not draw_list then return end

  local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
  local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)

  local text_x = win_w - 8
  local text_y = 8

  local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, R.perf_last_text)
  text_x = text_x - text_w

  local bg_color = 0x80000000
  reaper.ImGui_DrawList_AddRectFilled(draw_list,
    win_x + text_x - 4, win_y + text_y - 2,
    win_x + win_w - 4, win_y + text_y + text_h + 2,
    bg_color, 0, 0)

  local text_color = 0xFFFFFFFF
  reaper.ImGui_DrawList_AddText(draw_list, win_x + text_x, win_y + text_y, text_color, R.perf_last_text)
end

return M
