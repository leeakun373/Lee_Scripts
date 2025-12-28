-- @description RadialMenu Tool - 列表视图模块（主入口）
-- @author Lee
-- @about
--   显示扇区的子菜单列表 (4x3 网格布局，高对比度优化版)
--   本模块作为主入口，协调各个子模块：布局、按钮、交互、缓存绘制
local M = {}

-- 加载依赖
local submenu_cache = require("gui.submenu_cache")
local submenu_bake_cache = require("gui.submenu_bake_cache")
local styles = require("gui.styles")

-- 加载子模块
local layout = require("gui.list_view_layout")
local button = require("gui.list_view_button")
local interaction = require("gui.list_view_interaction")
local cached = require("gui.list_view_cached")

-- ============================================================================
-- 状态管理
-- ============================================================================
local current_sector = nil
local dragging_slot = nil  -- 当前正在拖拽的插槽

-- 导出拖拽状态（供主运行时使用）
function M.is_dragging()
    return dragging_slot ~= nil
end

function M.get_dragging_slot()
    return dragging_slot
end

function M.get_current_sector()
    return current_sector
end

function M.reset_drag()
    dragging_slot = nil
end

-- ============================================================================
-- 主绘制函数
-- ============================================================================
-- 绘制子菜单（主入口）
-- @param ctx ImGui context
-- @param sector_data table: 扇区数据
-- @param center_x number: 轮盘中心 X 坐标
-- @param center_y number: 轮盘中心 Y 坐标
-- @param anim_scale number: 动画缩放（未使用）
-- @param config table: 配置对象
-- @return boolean: 是否悬停在子菜单上
function M.draw_submenu(ctx, sector_data, center_x, center_y, anim_scale, config)
    if not sector_data or not config then return false end

    -- 【极速缓存系统】如果已烘焙，使用快速绘制函数
    if submenu_bake_cache.is_baked() then
        -- 使用拖拽状态引用（通过表引用传递，允许子模块更新）
        local dragging_slot_ref = {dragging_slot}
        local result = cached.draw_submenu_cached(ctx, sector_data, center_x, center_y, anim_scale, config, dragging_slot_ref, M.draw_submenu)
        dragging_slot = dragging_slot_ref[1]  -- 同步回状态
        current_sector = sector_data
        return result
    end

    -- 【修复】子菜单瞬间切换，不使用任何动画
    -- anim_scale 参数保留以兼容旧调用，但完全忽略
    current_sector = sector_data
    
    -- 获取插槽数量
    local slot_count = sector_data.slots and #sector_data.slots or 0
    
    -- 获取布局尺寸
    local slot_w, slot_h, win_w, win_h, gap, padding = layout.get_layout_dims(config, slot_count)
    
    -- 1. 计算智能位置（固定位置，传入 config）
    local x, y = layout.calculate_submenu_position(ctx, sector_data, center_x, center_y, config)
    
    -- 【性能优化】尝试从缓存获取子菜单数据
    local cached_data = submenu_cache.get(sector_data.id)
    if cached_data then
        -- 使用缓存的位置和尺寸
        x = cached_data.x or x
        y = cached_data.y or y
        win_w = cached_data.win_w or win_w
        win_h = cached_data.win_h or win_h
    else
        -- 首次创建，缓存数据
        submenu_cache.set(sector_data.id, {
            x = x,
            y = y,
            win_w = win_w,
            win_h = win_h,
            slot_count = slot_count,
            slot_w = slot_w,
            slot_h = slot_h
        })
    end
    
    -- 2. 固定位置（由 calculate_submenu_position 计算或从缓存获取）
    reaper.ImGui_SetNextWindowPos(ctx, x, y, reaper.ImGui_Cond_Always())
    
    -- 3. 动态大小（从配置读取或从缓存获取）
    reaper.ImGui_SetNextWindowSize(ctx, win_w, win_h, reaper.ImGui_Cond_Always())
    
    -- 4. 【修复】瞬间显示：背景透明度直接设为 1.0（完全不透明），不使用任何动画
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 1.0)
    
    -- 3. 样式设置 (深色背景容器)
    local bg_col = styles.correct_rgba_to_u32({20, 20, 22, 240})
    local border_col = styles.correct_rgba_to_u32({0, 0, 0, 255})
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), bg_col) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), border_col)
    
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
        -- 使用 IsWindowHovered 检测窗口是否被悬停
        -- 注意：这个检测必须在 Begin 之后进行，才能正确检测到窗口状态
        is_submenu_hovered = reaper.ImGui_IsWindowHovered(ctx)
        
        -- 额外检查：验证鼠标是否真的在窗口范围内（双重保险）
        if is_submenu_hovered then
            local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
            local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
            local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
            
            -- 双重检查鼠标是否真的在窗口边界内
            if not (mouse_x >= win_x and mouse_x <= win_x + win_w and
                   mouse_y >= win_y and mouse_y <= win_y + win_h) then
                is_submenu_hovered = false
            end
        end
        
        -- 额外检查：如果窗口内有任何活动项（按钮被按下等），也认为窗口被悬停
        -- 这确保在点击按钮时，窗口仍然被认为是"悬停"状态
        if not is_submenu_hovered then
            if reaper.ImGui_IsAnyItemActive(ctx) or reaper.ImGui_IsAnyItemHovered(ctx) then
                is_submenu_hovered = true
            end
        end
        
        -- 获取动态尺寸并传递给绘制函数（传入 config）
        local slot_w, slot_h = layout.get_layout_dims(config, slot_count)
        
        -- 使用拖拽状态引用（通过表引用传递，允许子模块更新）
        local dragging_slot_ref = {dragging_slot}
        button.draw_grid_buttons(ctx, sector_data, slot_w, slot_h, slot_count, gap, padding, dragging_slot_ref)
        dragging_slot = dragging_slot_ref[1]  -- 同步回状态
        
        -- 处理拖拽视觉反馈和放置检测
        interaction.handle_drag_and_drop(ctx)
        
        reaper.ImGui_End(ctx)
    end
    
    -- 注意：不再需要 PopStyleVar 来恢复 Alpha，因为我们没有应用它
    reaper.ImGui_PopStyleVar(ctx, 4)
    reaper.ImGui_PopStyleColor(ctx, 2)
    
    return is_submenu_hovered
end

-- ============================================================================
-- 拖拽反馈绘制（委托给 interaction 模块）
-- ============================================================================
function M.draw_drag_feedback(draw_list, ctx, slot)
    interaction.draw_drag_feedback(draw_list, ctx, slot)
end

-- ============================================================================
-- 兼容性函数（已弃用）
-- ============================================================================
function M.handle_item_click(slot)
    -- 委托给 interaction 模块
    return interaction.handle_item_click(slot)
end

function M.handle_drag_and_drop(ctx)
    -- 委托给 interaction 模块
    interaction.handle_drag_and_drop(ctx)
end

function M.imgui_to_screen_coords(ctx, imgui_x, imgui_y)
    -- 委托给 interaction 模块
    return interaction.imgui_to_screen_coords(ctx, imgui_x, imgui_y)
end

return M
