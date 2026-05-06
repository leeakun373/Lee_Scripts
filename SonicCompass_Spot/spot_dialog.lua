--[[
  SonicCompass Spot — 输入对话框

  基于用户的 Lee_Scripts/Shared/Toolbox 框架（与 SonicCompass Mosaic 同套），
  自动获得 Toolbox 风格 + 用户级主题/字体/缩放。

  外部接口：
    spot_dialog.show {
      title       = "...",
      placeholder = "...",
      on_submit   = function(query) ... end,
      on_cancel   = function() ... end,
    }

  失败兜底：Toolbox / ReaImGui 任意一项缺失时，自动改用 reaper.GetUserInputs。
]]

local M = {}

-- ── 尝试加载 Toolbox 框架 ──────────────────────────────
-- 与 mosaic_panel.lua 完全一致的引导路径。
local function try_load_toolbox()
  local r = reaper
  local toolbox_root = r.GetResourcePath() .. "/Scripts/Lee_Scripts/Shared/Toolbox/"
  package.path = toolbox_root .. "framework/?.lua;" .. package.path

  local ok_bs, bootstrap = pcall(require, "bootstrap")
  if not ok_bs then return nil end

  -- ensure_imgui 内部已处理"未装 ReaImGui"的情况（弹 MessageBox），
  -- 缺失时返回 nil，我们再回退到 GetUserInputs。
  local ImGui = bootstrap.ensure_imgui("0.9")
  if not ImGui then return nil end

  local ok_app, app_mod = pcall(require, "app")
  if not ok_app then return nil end

  local ok_theme, Theme = pcall(require, "ui_theme")
  if not ok_theme then return nil end

  return { ImGui = ImGui, App = app_mod.App, Theme = Theme }
end


-- ── 入口 ──────────────────────────────────────────────
function M.show(opts)
  opts = opts or {}
  local title       = opts.title       or "SonicCompass — Spot 搜索"
  local placeholder = opts.placeholder or "输入关键词，回车 = 发送 / Esc = 取消"
  local on_submit   = opts.on_submit   or function() end
  local on_cancel   = opts.on_cancel   or function() end

  -- ── 没有 Toolbox/ReaImGui 时回退到原生输入框 ──
  local tb = try_load_toolbox()
  if not tb then
    local ok, q = reaper.GetUserInputs(title, 1,
      "关键词,extrawidth=300", "")
    if ok then on_submit(q or "") else on_cancel() end
    return false
  end

  local ImGui = tb.ImGui
  local App   = tb.App
  local Theme = tb.Theme

  -- 创建 App 容器（Toolbox 会自动绑定 state/log/terminal 配置）
  local app = App.new(ImGui, {
    title       = "SonicCompass Spot",          -- 内部窗口名（NoTitleBar 不显示）
    ext_section = "SonicCompass_Spot_Dialog",   -- ExtState 隔离
  })

  -- 让窗口尽量保持在最前（如果 ImGui 版本支持）
  if app.state then
    app.state.always_on_top = true
  end

  local ctx = app.ctx

  local query        = ""
  local first_frame  = true
  local closed       = false
  local destroyed    = false

  local function destroy()
    if destroyed then return end
    destroyed = true
    pcall(function()
      Theme.destroy(app)
      app:destroy()
    end)
  end

  local function finish(submit_value)
    if closed then return end
    closed = true
    if submit_value ~= nil then
      pcall(on_submit, submit_value)
    else
      pcall(on_cancel)
    end
    -- 让窗口在下一帧自然退出
    app.open = false
  end

  -- REAPER 关闭时清理
  reaper.atexit(destroy)

  -- ── 单帧绘制 ──
  local function draw()
    -- 顶栏（NoTitleBar 用一行文本+分割线代替）
    ImGui.Text(ctx, title)
    ImGui.Separator(ctx)

    -- 输入框：首帧自动取焦点
    if first_frame then
      ImGui.SetKeyboardFocusHere(ctx)
    end
    ImGui.SetNextItemWidth(ctx, -1)

    local enter_pressed
    enter_pressed, query = ImGui.InputTextWithHint(
      ctx, "##query", placeholder, query,
      ImGui.InputTextFlags_EnterReturnsTrue)

    ImGui.Spacing(ctx)

    -- 主操作按钮
    local sent = ImGui.Button(ctx, "Send to SonicCompass", 240, 28)
    ImGui.SameLine(ctx)
    local canceled = ImGui.Button(ctx, "Cancel", 100, 28)

    -- Esc 也算取消
    local esc_pressed = false
    if ImGui.IsKeyPressed and ImGui.Key_Escape then
      esc_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false)
    end

    if sent or enter_pressed then
      finish(query or "")
    elseif canceled or esc_pressed then
      finish(nil)
    end
  end

  -- ── 主循环（与 mosaic_panel 完全相同的 begin/end + defer 结构）──
  local function loop()
    if destroyed then return end

    Theme.begin(app)

    -- 首帧定位 + 尺寸
    if first_frame then
      ImGui.SetNextWindowSize(ctx, 460, 130, ImGui.Cond_Always)
      local mx, my = reaper.GetMousePosition()
      ImGui.SetNextWindowPos(ctx, mx - 230, my - 65, ImGui.Cond_Always)
    end

    local visible, open
    if app.open == false then
      visible, open = false, false
    else
      visible, open = app:begin_window()
      if visible then draw() end
      app:end_window()
      if app.open == false then open = false end
    end

    Theme.end_(app)

    if first_frame then
      first_frame = false
    end

    if open and not closed then
      reaper.defer(loop)
    else
      -- 用户关了窗口（X 按钮 / Esc / 选了 Cancel）
      if not closed then finish(nil) end
      destroy()
    end
  end

  reaper.defer(loop)
  return true
end

return M
