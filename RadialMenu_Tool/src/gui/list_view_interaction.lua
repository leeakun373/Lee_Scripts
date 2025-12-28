-- @description RadialMenu Tool - 子菜单交互处理模块
-- @author Lee
-- @about
--   负责子菜单的交互处理：点击、拖拽反馈、坐标转换
local M = {}

-- 加载依赖
local execution = require("logic.execution")
local styles = require("gui.styles")

-- ============================================================================
-- 点击处理
-- ============================================================================
-- 处理按钮点击
-- @param slot table: 插槽数据
-- @return boolean: 是否成功处理
function M.handle_item_click(slot)
    if not slot then 
        return false 
    end
    
    -- 使用统一的执行引擎
    execution.trigger_slot(slot)
    
    -- 不再自动关闭子菜单，让用户手动关闭
    -- 用户可以通过点击扇区或 ESC 键关闭
    
    return true
end

-- ============================================================================
-- 拖拽处理
-- ============================================================================
-- 处理拖拽视觉反馈和放置检测
-- @param ctx ImGui context
-- @note 拖拽状态由主运行时统一管理，这里只负责在子菜单窗口内检测拖拽开始
function M.handle_drag_and_drop(ctx)
    -- 拖拽状态由主运行时统一管理
    -- 这里只负责在子菜单窗口内检测拖拽开始
end

-- ============================================================================
-- 拖拽反馈绘制
-- ============================================================================
-- 绘制拖拽视觉反馈 (使用 Tooltip 防止被窗口裁切)
-- @param draw_list ImDrawList*: 主窗口的绘制列表（不再使用，保留参数以兼容）
-- @param ctx ImGui context: ImGui 上下文
-- @param slot table: 正在拖拽的插槽
function M.draw_drag_feedback(draw_list, ctx, slot)
    if not slot then return end
    
    -- 设置样式以匹配我们的深色主题
    local bg_color = styles.correct_rgba_to_u32({20, 20, 22, 240})
    local border_color = styles.correct_rgba_to_u32(styles.colors.sector_active_out)
    local text_color = styles.correct_rgba_to_u32(styles.colors.text_normal)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), bg_color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), border_color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 1)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 4)
    
    -- 使用 BeginTooltip 创建一个独立悬浮窗口
    if reaper.ImGui_BeginTooltip(ctx) then
        -- 显示图标或类型前缀
        local prefix = "[?]"
        if slot.type == "action" then 
            prefix = "[Action]"
        elseif slot.type == "fx" then 
            prefix = "[FX]"
        elseif slot.type == "chain" then 
            prefix = "[Chain]" 
        elseif slot.type == "template" then 
            prefix = "[Template]" 
        end
        
        reaper.ImGui_Text(ctx, prefix .. " " .. (slot.name or "Unknown"))
        
        -- 如果是 Action，显示 ID
        if slot.type == "action" then
            local id = (slot.data and slot.data.command_id) or slot.command_id
            if id then 
                reaper.ImGui_TextDisabled(ctx, "ID: " .. tostring(id)) 
            end
        end
        
        reaper.ImGui_EndTooltip(ctx)
    end
    
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx, 3)
end

-- ============================================================================
-- 坐标转换（已弃用）
-- ============================================================================
-- 将 ImGui 坐标转换为屏幕坐标
-- @param ctx ImGui context
-- @param imgui_x number: ImGui X 坐标
-- @param imgui_y number: ImGui Y 坐标
-- @return number, number: 屏幕 X, Y 坐标
-- 
-- NOTE: This function is currently not used. Mouse release detection is handled
-- in main_runtime.lua using reaper.GetMousePosition() directly, which provides
-- the correct global screen coordinates needed for GetThingFromPoint.
function M.imgui_to_screen_coords(ctx, imgui_x, imgui_y)
    -- [DEPRECATED] This function is kept for reference but not actively used.
    -- The main_runtime.lua uses reaper.GetMousePosition() directly which is
    -- the correct approach for GetThingFromPoint.
    
    -- GetThingFromPoint requires global screen coordinates, not ImGui window-relative coordinates.
    -- reaper.GetMousePosition() returns the correct global screen coordinates.
    
    local screen_x, screen_y = reaper.GetMousePosition()
    
    if screen_x and screen_y then
        return screen_x, screen_y
    end
    
    -- Fallback: Use ImGui coordinates (may not be correct for GetThingFromPoint)
    return imgui_x, imgui_y
end

return M

