-- Shared/Toolbox/framework/dock.lua
-- DockSpace +（可选）默认布局构建。

local M = {}

local function safe_get(ImGui, key)
  local ok, val = pcall(function()
    return ImGui[key]
  end)
  if not ok then
    return nil
  end
  return val
end

function M.ensure(ctx, ImGui, id)
  -- 注意：部分 ReaImGui 版本在访问不存在的字段时会直接报错（而不是返回 nil）
  -- 所以这里必须用 pcall 探测。
  local DockSpaceOverViewport = safe_get(ImGui, "DockSpaceOverViewport")
  local GetMainViewport = safe_get(ImGui, "GetMainViewport")
  if not (DockSpaceOverViewport and GetMainViewport) then
    return nil
  end

  local vp = GetMainViewport(ctx)
  if not vp then
    return nil
  end

  -- 全局 dockspace（覆盖主 viewport），nvk 类工具常用这种方式。
  DockSpaceOverViewport(ctx, vp, 0)
  return id
end

-- 尽力而为：如果 DockBuilder 可用就做一个默认布局
function M.build_default(ctx, ImGui, dock_id)
  if not dock_id then return end
  local DockBuilderRemoveNode = safe_get(ImGui, "DockBuilderRemoveNode")
  local DockBuilderAddNode = safe_get(ImGui, "DockBuilderAddNode")
  local DockBuilderSetNodeSize = safe_get(ImGui, "DockBuilderSetNodeSize")
  local DockBuilderSplitNode = safe_get(ImGui, "DockBuilderSplitNode")
  local DockBuilderDockWindow = safe_get(ImGui, "DockBuilderDockWindow")
  local DockBuilderFinish = safe_get(ImGui, "DockBuilderFinish")
  local DockNodeFlags_DockSpace = safe_get(ImGui, "DockNodeFlags_DockSpace")
  local Dir_Right = safe_get(ImGui, "Dir_Right")
  local Dir_Down = safe_get(ImGui, "Dir_Down")
  local GetMainViewport = safe_get(ImGui, "GetMainViewport")
  local Viewport_GetSize = safe_get(ImGui, "Viewport_GetSize")

  if not (DockBuilderRemoveNode and DockBuilderAddNode and DockBuilderSetNodeSize and DockBuilderSplitNode and DockBuilderDockWindow and DockBuilderFinish and DockNodeFlags_DockSpace and Dir_Right and Dir_Down and GetMainViewport and Viewport_GetSize) then
    return
  end

  -- 仅第一次建布局（由调用者负责标记）
  DockBuilderRemoveNode(ctx, dock_id)
  DockBuilderAddNode(ctx, dock_id, DockNodeFlags_DockSpace)

  local vp = GetMainViewport(ctx)
  if vp then
    local w, h = Viewport_GetSize(vp)
    DockBuilderSetNodeSize(ctx, dock_id, w, h)
  end

  local dock_main = dock_id
  local dock_right = DockBuilderSplitNode(ctx, dock_main, Dir_Right, 0.33, nil, dock_main)
  local dock_down = DockBuilderSplitNode(ctx, dock_main, Dir_Down, 0.30, nil, dock_main)

  -- 这些窗口名由 Demo 使用；如果名字变了，布局就不会自动停靠。
  DockBuilderDockWindow(ctx, "Toolbox - UI Demo", dock_main)
  DockBuilderDockWindow(ctx, "Lee UI - Log", dock_down)
  DockBuilderDockWindow(ctx, "Lee UI - Terminal", dock_down)
  DockBuilderDockWindow(ctx, "Lee UI - Theme", dock_right)
  DockBuilderDockWindow(ctx, "Lee UI - Style", dock_right)

  DockBuilderFinish(ctx, dock_id)
end

return M
