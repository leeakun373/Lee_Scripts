-- Shared/Toolbox/framework/log.lua
-- 简单日志：支持 UI 查看/复制/清空。

local M = {}

M.levels = {
  INFO = "INFO",
  WARN = "WARN",
  ERROR = "ERROR",
}

local function now()
  return reaper.time_precise()
end

function M.new(max_items)
  return {
    max = max_items or 500,
    items = {},
    filter = "",
    auto_scroll = true,
  }
end

local function push(log, level, msg)
  local t = type(msg) == "string" and msg or tostring(msg)
  log.items[#log.items + 1] = {ts = now(), level = level, msg = t}
  if #log.items > log.max then
    table.remove(log.items, 1)
  end
end

function M.info(log, msg) push(log, M.levels.INFO, msg) end
function M.warn(log, msg) push(log, M.levels.WARN, msg) end
function M.error(log, msg) push(log, M.levels.ERROR, msg) end

function M.clear(log)
  log.items = {}
end

function M.draw(ctx, ImGui, log)
  if not log then return end

  ImGui.PushItemWidth(ctx, -160)
  local changed
  changed, log.filter = ImGui.InputText(ctx, "Filter", log.filter or "")
  ImGui.PopItemWidth(ctx)

  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Copy") then
    local out = {}
    for _, it in ipairs(log.items) do
      out[#out+1] = string.format("[%s] %.3f %s", it.level, it.ts, it.msg)
    end
    ImGui.SetClipboardText(ctx, table.concat(out, "\n"))
  end

  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Clear") then
    M.clear(log)
  end

  ImGui.SameLine(ctx)
  _, log.auto_scroll = ImGui.Checkbox(ctx, "Auto", log.auto_scroll ~= false)

  local flags = ImGui.ChildFlags_Border and ImGui.ChildFlags_Border or 0
  local h = 200
  if ImGui.BeginChild(ctx, "##log", -1, h, flags) then
    local f = (log.filter or ""):lower()
    for _, it in ipairs(log.items) do
      local line = string.format("[%s] %s", it.level, it.msg)
      if f == "" or line:lower():find(f, 1, true) then
        if it.level == M.levels.ERROR then
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF4040FF)
          ImGui.TextWrapped(ctx, line)
          ImGui.PopStyleColor(ctx)
        elseif it.level == M.levels.WARN then
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFA000FF)
          ImGui.TextWrapped(ctx, line)
          ImGui.PopStyleColor(ctx)
        else
          ImGui.TextWrapped(ctx, line)
        end
      end
    end
    if log.auto_scroll and ImGui.GetScrollY(ctx) >= ImGui.GetScrollMaxY(ctx) - 2 then
      ImGui.SetScrollHereY(ctx, 1)
    end
    ImGui.EndChild(ctx)
  end
end

return M
