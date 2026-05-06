-- @description Lee SonicCompass Spot - Focus Search (整合版：唯一对外脚本)
-- @version 0.4.0
-- @author Lee / SonicCompass
-- @about
--   一个脚本完成三件事，无感知反复触发：
--     1. 自动启动 Spot Listener（带心跳防双开）
--     2. 弹 SC 主题风格的 ReaImGui 输入框（缺 ReaImGui 时自动回退原生输入框）
--     3. POST /api/reaper/focus-search 把 SC 拉到前台并预填搜索
--
--   行为：
--     - 重复按快捷键不会弹"ReaScript task control"对话框（auto-terminate）
--     - 不再向 REAPER Console 写任何启动消息
--     - 输入回车 = 发送；Esc / 关闭按钮 = 取消（listener 仍保留）
--
--   依赖：
--     - SWS 扩展（CF_ShellExecute，必需）
--     - SonicCompass_Mosaic 包内的 http_client.lua
--     - 可选：ReaImGui（如缺失则自动用 GetUserInputs 兜底）

-- ══════════════════════════════════════════════════════
-- 步骤 0：抑制 ReaScript task control 对话框
-- ══════════════════════════════════════════════════════
-- 1 = 重新调用本脚本时自动终止旧实例 + 跳过任务控制对话框
-- 注：REAPER < 6 没有这个 API，pcall 容错
pcall(function()
  if reaper.set_action_options then
    reaper.set_action_options(1)
  end
end)

-- ─── 自助查找当前脚本目录 ───
local function script_dir()
  local src = debug.getinfo(1, "S").source
  return src:match("^@(.+[\\/])")
end

local this_dir = script_dir()
package.path = this_dir .. "?.lua;" .. package.path

local cfg = require("spot_config")

-- ══════════════════════════════════════════════════════
-- 步骤 1：硬性依赖检查 — SWS 扩展
-- ══════════════════════════════════════════════════════
if not reaper.CF_ShellExecute then
  reaper.ShowMessageBox(
    "未检测到 SWS 扩展（CF_ShellExecute 不可用）。\n\n" ..
    "SonicCompass Spot 依赖 SWS 来执行无窗口的 HTTP 请求。\n" ..
    "请前往 https://www.sws-extension.org 下载并安装 SWS 后重启 REAPER。",
    "SonicCompass Spot — 缺少依赖",
    0
  )
  return
end

-- ══════════════════════════════════════════════════════
-- 步骤 2：加载共享 http_client（来自 SonicCompass_Mosaic 包）
-- ══════════════════════════════════════════════════════
local mosaic_dir = reaper.GetResourcePath()
                     .. "/Scripts/Lee_Scripts/SonicCompass_Mosaic/"
package.path = mosaic_dir .. "?.lua;" .. package.path

local ok_http, http_client = pcall(require, "http_client")
if not ok_http then
  reaper.ShowMessageBox(
    "未找到 http_client.lua。\n\n" ..
    "请确保已安装 SonicCompass_Mosaic 脚本包（提供共享 HTTP 客户端）。\n\n" ..
    "预期路径：\n" .. mosaic_dir .. "http_client.lua",
    "SonicCompass Spot — 缺少依赖",
    0
  )
  return
end

-- ══════════════════════════════════════════════════════
-- 步骤 3：自启 Listener（静默 — 心跳防双开）
-- ══════════════════════════════════════════════════════
-- listener.start() 内部检查心跳：旧的存活则直接 return，否则注册 defer 主循环
local listener = require("spot_listener")
listener.start()  -- 不再 ShowConsoleMsg

-- ══════════════════════════════════════════════════════
-- 步骤 4：发 POST 的辅助
-- ══════════════════════════════════════════════════════
local function send_focus(query)
  -- 收集 context：当前 REAPER 项目目录
  local proj_path = ""
  do
    local ok_p, p = pcall(reaper.GetProjectPath, "")
    if ok_p and type(p) == "string" then proj_path = p end
  end

  local payload = {
    protocol_version = cfg.PROTOCOL_VERSION,
    query            = query or "",
    bring_to_front   = true,
    project_path     = proj_path,
  }

  http_client.post_json(cfg.SC_BASE_URL .. cfg.FOCUS_PATH, payload,
    function(ok, resp)
      if ok then return end
      local msg = tostring(resp or "Unknown error")
      reaper.ShowMessageBox(
        "无法连接到 SonicCompass。\n\n" ..
        "请确认：\n" ..
        "  1. SonicCompass 已启动；\n" ..
        "  2. 端口为 " .. tostring(cfg.SC_PORT) .. "；\n" ..
        "  3. 防火墙未阻断本机 127.0.0.1。\n\n" ..
        "详细信息：\n" .. msg,
        "SonicCompass Spot — 连接失败",
        0
      )
    end)
end

-- ══════════════════════════════════════════════════════
-- 步骤 5：弹 SC 主题风格输入框（ReaImGui 优先）
-- ══════════════════════════════════════════════════════
local spot_dialog = require("spot_dialog")
spot_dialog.show({
  title       = "SonicCompass — Spot 搜索",
  placeholder = "输入关键词，回车 = 发送 / Esc = 取消",
  on_submit   = function(query) send_focus(query) end,
  on_cancel   = function() end,  -- 取消时仅退出，listener 已启动不动
})
