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

  if R.center_drag_started then
    return
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
