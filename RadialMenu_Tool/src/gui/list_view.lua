-- @description RadialMenu Tool - 列表视图模块
-- @author Lee
-- @about
--   显示扇区的子菜单列表 (3x3 网格布局，高对比度优化版)

local M = {}

-- 加载依赖
local actions = require("actions")
local styles = require("styles")
local math_utils = require("math_utils")
local execution = require("execution")

-- ============================================================================
-- 配置常量 (3x3 紧凑布局)
-- ============================================================================
local GRID_COLS = 3
local GRID_ROWS = 3
local TOTAL_SLOTS = 9 
local GAP = 4           

-- 计算总尺寸
local WINDOW_PADDING = 10

-- 动态获取布局尺寸（从配置中读取）
local function get_layout_dims(config)
    -- Fallback if config is nil (should not happen, but safe)
    if not config or not config.menu then return 80, 32, 0, 0, 4, 10 end
    
    local w = config.menu.slot_width or 80
    local h = config.menu.slot_height or 32
    local gap = GAP
    local padding = WINDOW_PADDING
    local cols = GRID_COLS
    local rows = GRID_ROWS
    
    local total_w = (w * cols) + (gap * (cols - 1)) + (padding * 2)
    local total_h = (h * rows) + (gap * (rows - 1)) + (padding * 2)
    
    return w, h, total_w, total_h, gap, padding
end

-- 列表视图状态
local current_sector = nil
local dragging_slot = nil  -- 当前正在拖拽的插槽
local drag_start_pos = nil  -- 拖拽开始位置（用于判断是否真的在拖拽）

-- 导出拖拽状态（供主运行时使用）
function M.is_dragging()
    return dragging_slot ~= nil
end

function M.get_dragging_slot()
    return dragging_slot
end

-- ============================================================================
-- Phase 3 - 绘制子菜单 (主入口)
-- ============================================================================

function M.draw_submenu(ctx, sector_data, center_x, center_y, anim_scale, config)
    if not sector_data or not config then return false end  -- Return false if no sector data or config
    
    anim_scale = anim_scale or 1.0
    current_sector = sector_data
    
    -- [REVERTED] 移除 Pop 动画。使用固定大小和位置。
    -- 我们仍然使用 anim_scale 仅用于透明度（Alpha），这是稳定的。
    
    -- 获取动态尺寸（传递 config）
    local slot_w, slot_h, win_w, win_h = get_layout_dims(config)
    
    -- 1. 计算智能位置（固定位置，传递 config）
    local x, y = M.calculate_submenu_position(ctx, sector_data, center_x, center_y, config)
    
    -- 2. 固定位置（由 calculate_submenu_position 计算）
    reaper.ImGui_SetNextWindowPos(ctx, x, y, reaper.ImGui_Cond_Always())
    
    -- 3. 动态大小（从配置读取）
    reaper.ImGui_SetNextWindowSize(ctx, win_w, win_h, reaper.ImGui_Cond_Always())
    
    -- 4. 保留透明度淡入（微妙且安全）
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0.95 * anim_scale)
    
    -- 3. 样式设置 (深色背景容器)
    
    -- 背景色：深色磨砂背景
    local bg_col = styles.correct_rgba_to_u32({20, 20, 22, 240})
    -- 面板边框：纯黑
    local border_col = styles.correct_rgba_to_u32({0, 0, 0, 255})
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), bg_col) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), border_col)
    
    -- 获取动态尺寸（用于样式，传递 config）
    local _, _, _, _, gap, padding = get_layout_dims(config)
    
    -- 布局样式
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), padding, padding)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), gap, gap)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 1)

    -- Flag to track if submenu is hovered
    local is_submenu_hovered = false

    -- 注意：不应用 Alpha 样式变量，因为它可能影响按钮交互
    -- 只使用背景透明度（SetNextWindowBgAlpha）来实现淡入效果
    -- 这样可以保持按钮的交互性不受影响

    if reaper.ImGui_Begin(ctx, "##Submenu_" .. sector_data.id, true, reaper.ImGui_WindowFlags_NoDecoration() | reaper.ImGui_WindowFlags_NoMove()) then
        -- [FIX] Check if this window is hovered (including items inside it)
        -- Try to use ChildWindows flag if available (includes child windows in hover detection)
        if reaper.ImGui_HoveredFlags_ChildWindows then
            is_submenu_hovered = reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_ChildWindows())
        else
            -- Fallback: check without flags if the API doesn't support it
            is_submenu_hovered = reaper.ImGui_IsWindowHovered(ctx)
            
            -- Additional check: verify mouse is within window bounds
            if is_submenu_hovered then
                local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
                local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
                local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
                
                -- Double-check mouse is actually in window bounds
                if not (mouse_x >= win_x and mouse_x <= win_x + win_w and
                       mouse_y >= win_y and mouse_y <= win_y + win_h) then
                    is_submenu_hovered = false
                end
            end
        end
        
        -- 获取动态尺寸并传递给绘制函数（传递 config）
        local slot_w, slot_h = get_layout_dims(config)
        M.draw_grid_buttons(ctx, sector_data, slot_w, slot_h)
        
        -- 处理拖拽视觉反馈和放置检测
        M.handle_drag_and_drop(ctx)
        
        reaper.ImGui_End(ctx)
    end
    
    -- 注意：不再需要 PopStyleVar 来恢复 Alpha，因为我们没有应用它
    reaper.ImGui_PopStyleVar(ctx, 4)
    reaper.ImGui_PopStyleColor(ctx, 2)
    
    return is_submenu_hovered
end

-- ============================================================================
-- 绘制按钮网格
-- ============================================================================

function M.draw_grid_buttons(ctx, sector_data, slot_w, slot_h)
    for i = 1, TOTAL_SLOTS do
        local slot = sector_data.slots and sector_data.slots[i] or nil
        
        if (i - 1) % GRID_COLS ~= 0 then
            reaper.ImGui_SameLine(ctx)
        end
        
        M.draw_single_button(ctx, slot, i, slot_w, slot_h)
    end
end

function M.draw_single_button(ctx, slot, index, w, h)
    -- [FIX] Determine if this is a REAL configured slot
    local is_configured = slot and slot.type ~= "empty"
    
    local label = is_configured and slot.name or ""
    
    -- ============================================================
    -- 颜色优化区域 (High Contrast)
    -- ============================================================
    
    local col_normal, col_hover, col_active, col_border
    local text_color = styles.correct_rgba_to_u32(styles.colors.text_normal)
    
    -- [FIX] Use is_configured instead of checking slot directly
    if is_configured then
        -- [有功能的按钮]
        -- 稍微亮一点的灰色，使其从黑色背景中凸显出来
        col_normal = styles.correct_rgba_to_u32({60, 62, 66, 255}) 
        -- 悬停高亮色 (使用配置的蓝色)
        col_hover  = styles.correct_rgba_to_u32(styles.colors.sector_active_out)
        -- 点击高亮色
        col_active = styles.correct_rgba_to_u32(styles.colors.sector_active_in)
        -- 边框色 (亮灰色描边，增强轮廓)
        col_border = styles.correct_rgba_to_u32({85, 85, 90, 100})
    else
        -- [空插槽]
        -- 更暗的背景，表示"空"
        col_normal = styles.correct_rgba_to_u32({30, 30, 32, 100}) 
        -- 悬停时稍微亮一点
        col_hover  = styles.correct_rgba_to_u32({50, 50, 55, 150})
        col_active = styles.correct_rgba_to_u32({60, 60, 65, 150})
        -- 边框色 (暗淡的描边，仅用于显示网格位置)
        col_border = styles.correct_rgba_to_u32({60, 60, 60, 60})
        -- 文字变暗
        text_color = styles.correct_rgba_to_u32(styles.colors.text_disabled)
    end

    -- 应用颜色
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col_normal)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_hover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_active)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_border)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color)
    
    -- 应用样式 (增加 BorderSize 以显示描边)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1) -- 关键：开启按钮描边
    
    -- [FIX] Update Click Logic to use is_configured
    -- 先绘制按钮，这样 IsItemActive 和 IsMouseDragging 才能正确工作
    if reaper.ImGui_Button(ctx, label .. "##Slot" .. index, w, h) then
        if is_configured and not dragging_slot then
            M.handle_item_click(slot)
        end
    end
    
    -- [FIX] Update Drag Logic to use is_configured
    -- 拖拽检测必须在按钮绘制之后，因为 IsItemActive 需要按钮状态
    if is_configured and reaper.ImGui_IsItemActive(ctx) and reaper.ImGui_IsMouseDragging(ctx, 0) then
        -- 检查是否真的在拖拽（移动距离超过阈值）
        local mouse_delta_x, mouse_delta_y = reaper.ImGui_GetMouseDelta(ctx, 0)
        local drag_distance = math.sqrt(mouse_delta_x * mouse_delta_x + mouse_delta_y * mouse_delta_y)
        
        if drag_distance > 5 then  -- 5 像素阈值，避免误触发
            if not dragging_slot or dragging_slot ~= slot then
                -- 静默模式：不输出日志
                dragging_slot = slot
                local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
                drag_start_pos = {x = mouse_x, y = mouse_y}
            end
        end
    end
    
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx, 5)
    
    -- [FIX] Update Tooltip Logic to use is_configured
    if is_configured and reaper.ImGui_IsItemHovered(ctx) and not dragging_slot then
        local tooltip = slot.description
        if not tooltip or tooltip == "" then tooltip = slot.name end
        if tooltip and tooltip ~= "" then
            reaper.ImGui_BeginTooltip(ctx)
            reaper.ImGui_Text(ctx, tooltip)
            reaper.ImGui_EndTooltip(ctx)
        end
    end
end

-- ============================================================================
-- 智能位置计算
-- ============================================================================

function M.calculate_submenu_position(ctx, sector_data, center_x, center_y, config)
    local math_utils = require("math_utils")
    
    local outer_radius = config.menu.outer_radius or 200
    local total_sectors = #config.sectors
    local angle = math_utils.get_sector_center_angle(sector_data.id, total_sectors, -math.pi / 2)
    
    -- 获取动态尺寸（传递 config）
    local _, _, win_w, win_h = get_layout_dims(config)
    
    -- 增加 overlap
    local overlap_offset = 12 
    local anchor_dist = outer_radius - overlap_offset
    
    local anchor_x_rel, anchor_y_rel = math_utils.polar_to_cartesian(angle, anchor_dist)
    local anchor_x = center_x + anchor_x_rel
    local anchor_y = center_y + anchor_y_rel
    
    local final_x = anchor_x
    local final_y = anchor_y - (win_h / 2)
    
    local is_right_side = math.cos(angle) >= 0
    
    if is_right_side then
        final_x = anchor_x + 5 
    else
        final_x = anchor_x - win_w - 5
    end
    
    return final_x, final_y
end

-- ============================================================================
-- 交互逻辑
-- ============================================================================

function M.handle_item_click(slot)
    if not slot then 
        -- 静默模式：不输出日志
        return false 
    end
    
    -- 静默模式：不输出日志
    
    -- 使用统一的执行引擎
    execution.trigger_slot(slot)
    
    -- 不再自动关闭子菜单，让用户手动关闭
    -- 用户可以通过点击扇区或 ESC 键关闭
    
    return true
end

function M.get_current_sector()
    return current_sector
end

-- ============================================================================
-- 拖拽和放置处理
-- ============================================================================

-- 处理拖拽视觉反馈和放置检测
-- 注意：鼠标释放检测现在在主运行时中处理，因为鼠标可能移出子菜单窗口
function M.handle_drag_and_drop(ctx)
    -- 拖拽状态由主运行时统一管理
    -- 这里只负责在子菜单窗口内检测拖拽开始
end

-- 重置拖拽状态（由主运行时调用）
function M.reset_drag()
    dragging_slot = nil
    drag_start_pos = nil
end

-- 绘制拖拽视觉反馈 (使用 Tooltip 防止被窗口裁切)
-- @param draw_list ImDrawList*: 主窗口的绘制列表（不再使用，保留参数以兼容）
-- @param ctx ImGui context: ImGui 上下文
-- @param slot table: 正在拖拽的插槽
function M.draw_drag_feedback(draw_list, ctx, slot)
    if not slot then return end
    
    -- Tooltip 默认会自动跟随鼠标，但我们可以强制位置以确保不遮挡视线
    -- 注意：BeginTooltip 自动处理位置，通常不需要 SetNextWindowPos，除非你想自定义偏移
    -- 这里我们依赖 ImGui 的默认行为，它通常很聪明
    
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