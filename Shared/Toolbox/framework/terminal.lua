-- Shared/Toolbox/framework/terminal.lua
-- 轻量“终端”：输入 Lua 表达式/语句并执行（带最小沙箱）。

local M = {}
local Log = require("log")

function M.new()
  return {
    input = "",
    history = {},
    hist_idx = 0,
  }
end

local function make_env(app)
  -- 给终端一些可用对象；不要暴露危险的 os/io。
  return {
    reaper = reaper,
    app = app,
    ImGui = app and app.ImGui,
    print = function(...)
      local t = {}
      for i = 1, select('#', ...) do
        t[#t+1] = tostring(select(i, ...))
      end
      if app and app.log then
        Log.info(app.log, table.concat(t, "\t"))
      end
    end,
    math = math,
    string = string,
    table = table,
    tonumber = tonumber,
    tostring = tostring,
    ipairs = ipairs,
    pairs = pairs,
    type = type,
    select = select,
  }
end

local function run(app, code)
  local env = make_env(app)

  -- 先尝试表达式
  local chunk = load("return " .. code, "Toolbox_Terminal", "t", env)
  if not chunk then
    chunk = load(code, "Toolbox_Terminal", "t", env)
  end
  if not chunk then
    return false, "compile error"
  end

  local ok, res = pcall(chunk)
  if not ok then
    return false, res
  end
  return true, res
end

function M.draw(ctx, ImGui, app)
  local term = app.terminal
  if not term then return end

  ImGui.Text(ctx, "Terminal (Lua)")
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, "(提示：输入 1+1 或 reaper.GetCursorPosition())")

  ImGui.PushItemWidth(ctx, -80)
  local changed
  changed, term.input = ImGui.InputText(ctx, "##term_input", term.input or "", ImGui.InputTextFlags_EnterReturnsTrue)
  ImGui.PopItemWidth(ctx)

  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Run") or changed then
    local code = (term.input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if code ~= "" then
      term.history[#term.history+1] = code
      term.input = ""
      local ok, res = run(app, code)
      if ok then
        if res ~= nil then
          require("log").info(app.log, "> " .. code .. "  =>  " .. tostring(res))
        else
          require("log").info(app.log, "> " .. code)
        end
      else
        require("log").error(app.log, "> " .. code .. "  !!  " .. tostring(res))
      end
    end
  end
end

return M
