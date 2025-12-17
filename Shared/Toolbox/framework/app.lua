-- Shared/Toolbox/framework/app.lua
-- App 容器：管理 Context、窗口 flags、focus 状态；配置/日志等由 app_state 挂载。

local M = {}
local r = reaper
local AppState = require("app_state")

local App = {}
App.__index = App

function App.new(ImGui, opts)
  opts = opts or {}

  local self = setmetatable({}, App)
  self.ImGui = ImGui
  self.title = opts.title or "Toolbox UI"
  self.ext_section = opts.ext_section or "Toolbox_UI"

  self.ctx = ImGui.CreateContext(self.title, ImGui.ConfigFlags_DockingEnable)
  self.open = true
  self.visible = true
  self.focused = false
  AppState.attach(self)
  return self
end

function App:get_window_flags()
  local ImGui = self.ImGui

  -- 默认尽量贴近 nvk：无标题栏、无滚动条、自动布局更紧凑
  local flags = ImGui.WindowFlags_NoTitleBar
    | ImGui.WindowFlags_NoCollapse
    | ImGui.WindowFlags_NoScrollbar

  -- 置顶（某些版本/平台可能不支持，属于“尽力而为”）
  if self.state.always_on_top and ImGui.WindowFlags_TopMost then
    flags = flags | ImGui.WindowFlags_TopMost
  end

  return flags
end

function App:begin_window()
  local ImGui = self.ImGui

  -- 简单用 scale 缩放初始窗口大小（你也可以把 scale 应用到字体和 spacing）
  ImGui.SetNextWindowSize(self.ctx, 520 * self.state.scale, 420 * self.state.scale, ImGui.Cond_FirstUseEver)
  -- 注意：把 self.open 作为第三参数传入，这样我们可以用自定义按钮关闭窗口
  self.visible, self.open = ImGui.Begin(self.ctx, self.title, self.open, self:get_window_flags())

  if ImGui.IsWindowFocused and ImGui.FocusedFlags_AnyWindow then
    self.focused = ImGui.IsWindowFocused(self.ctx, ImGui.FocusedFlags_AnyWindow)
  end

  return self.visible, self.open
end

function App:end_window()
  self.ImGui.End(self.ctx)

  if self.state.show_demo_window and self.ImGui.ShowDemoWindow then
    self.ImGui.ShowDemoWindow(self.ctx, true)
  end
end

function App:destroy()
  -- 保存配置（ExtState）
  pcall(function()
    AppState.save(self)
  end)

  if self.ctx then
    -- 兼容性：部分 ReaImGui 版本没有暴露 DestroyContext
    pcall(function()
      local destroy = self.ImGui and self.ImGui.DestroyContext
      if destroy then
        destroy(self.ctx)
      end
    end)
    self.ctx = nil
  end
end

M.App = App
return M
