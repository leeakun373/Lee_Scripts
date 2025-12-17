-- Shared/Toolbox/framework/bootstrap.lua
-- 最小 ReaImGui 引导模块：检查依赖 + 加载 imgui。

local M = {}
local r = reaper

function M.ensure_imgui(required_version)
  required_version = required_version or "0.9"

  if not r or not r.APIExists then
    return nil, "reaper API not available"
  end

  if not r.APIExists("ImGui_GetBuiltinPath") then
    local msg = [[
未检测到 ReaImGui（或版本过旧）。

请通过 ReaPack 安装/更新：
ReaTeam Extensions -> "ReaImGui: ReaScript binding for Dear ImGui"
安装完成后重启 REAPER。]]
    r.ShowMessageBox(msg, "Toolbox", 0)

    if r.ReaPack_BrowsePackages and r.ReaPack_GetRepositoryInfo and r.ReaPack_GetRepositoryInfo("ReaTeam Extensions") then
      r.ReaPack_BrowsePackages('^"ReaImGui: ReaScript binding for Dear ImGui"$ ^"ReaTeam Extensions"$')
    end

    return nil, "ReaImGui missing"
  end

  if not ImGui then
    package.path = r.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
    ImGui = require("imgui")(required_version)
  end

  return ImGui
end

return M
