-- @description RadialMenu Tool - 列表视图模块
-- @author Lee
-- @about
--   显示扇区的子菜单列表 (3x3 网格布局，高对比度优化版)

local M = {}

-- 加载依赖
local actions = require("logic.actions")
local styles = require("gui.styles")
local math_utils = require("math_utils")
local execution = require("logic.execution")
local submenu_cache = require("gui.submenu_cache")
local submenu_bake_cache = require("gui.submenu_bake_cache")

-- ============================================================================
-- 配置常量 (3x3 紧凑布局)
-- ============================================================================
local GRID_COLS = 3
local GRID_ROWS = 3
-- [REMOVED] local TOTAL_SLOTS = 9 (删除这行常量)

-- 默认值（当配置中没有指定时使用）
local DEFAULT_GAP = 3
local DEFAULT_WINDOW_PADDING = 4

-- 动态获取布局尺寸（从配置中读取）
local function get_layout_dims(config, slot_count)
    -- Fallback if config is nil (should not happen, but safe)
    if not config or not config.menu then return 80, 32, 0, 0, DEFAULT_GAP, DEFAULT_WINDOW_PADDING end
    
    local w = config.menu.slot_width or 80
    local h = config.menu.slot_height or 32
    -- 【新增】从配置读取按钮间距和窗口内边距
    local gap = config.menu.submenu_gap or DEFAULT_GAP
    local padding = config.menu.submenu_padding or DEFAULT_WINDOW_PADDING
    local cols = GRID_COLS
    
    -- 【修改】子菜单尺寸使用独立参数，不依赖按钮参数计算
    -- 如果配置中有独立的子菜单尺寸，使用它；否则根据按钮参数计算
    local total_w = config.menu.submenu_width
    local total_h = config.menu.submenu_height
    
    if not total_w or not total_h then
        -- 如果没有独立的子菜单尺寸，根据按钮参数计算（向后兼容）
        local count = math.max(9, slot_count or 9) -- 至少显示 3x3，如果更多则扩展
        local rows = math.ceil(count / cols)
        total_w = (w * cols) + (gap * (cols - 1)) + (padding * 2)
        total_h = (h * rows) + (gap * (rows - 1)) + (padding * 2)
    end
    
    return w, h, total_w, total_h, gap, padding
end

-- 列表视图状态
local current_sector = nil
local dragging_slot = nil  -- 当前正在拖拽的插槽

-- 预计算的按钮颜色（性能优化）
local button_colors = {
    configured = {
        normal = nil,
        hover = nil,
        active = nil,
        border = nil,
        text = nil
    },
    empty = {
        normal = nil,
        hover = nil,
        active = nil,
        border = nil,
        text = nil
    }
}

-- 初始化预计算颜色（在模块加载时执行一次）
local function init_precomputed_colors()
    -- 有功能的按钮颜色
    button_colors.configured.normal = styles.correct_rgba_to_u32({60, 62, 66, 255})
    button_colors.configured.hover = styles.correct_rgba_to_u32(styles.colors.sector_active_out)
    button_colors.configured.active = styles.correct_rgba_to_u32(styles.colors.sector_active_in)
    button_colors.configured.border = styles.correct_rgba_to_u32({85, 85, 90, 100})
    button_colors.configured.text = styles.correct_rgba_to_u32(styles.colors.text_normal)
    
    -- 空插槽颜色
    button_colors.empty.normal = styles.correct_rgba_to_u32({30, 30, 32, 100})
    button_colors.empty.hover = styles.correct_rgba_to_u32({50, 50, 55, 150})
    button_colors.empty.active = styles.correct_rgba_to_u32({60, 60, 65, 150})
    button_colors.empty.border = styles.correct_rgba_to_u32({60, 60, 60, 60})
    button_colors.empty.text = styles.correct_rgba_to_u32(styles.colors.text_disabled)
end

-- 初始化颜色
init_precomputed_colors()

-- 导出拖拽状态（供主运行时使用）
function M.is_dragging()
    return dragging_slot ~= nil
end

function M.get_dragging_slot()
    return dragging_slot
end

-- ============================================================================
-- 【极速缓存绘制】使用烘焙缓存直接绘制（无计算，只画图）
-- ============================================================================

function M.draw_submenu_cached(ctx, sector_data, center_x, center_y, anim_scale, config)
    if not sector_data or not config then return false end
    
    -- 1. 直接读内存，0 耗时
    local cached_data = submenu_bake_cache.get_cached(sector_data.id)
    if not cached_data then
        -- 如果缓存不存在，回退到原始绘制方法
        return M.draw_submenu(ctx, sector_data, center_x, center_y, anim_scale, config)
    end
    
    current_sector = sector_data
    
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    if not draw_list then return false end
    
    local bake_cfg = submenu_bake_cache.get_config()
    local max_bounds = submenu_bake_cache.get_max_bounds()
    
    -- 获取窗口内的圆心位置（这是稳定的绘制中心）
    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
    local cx = win_x + max_bounds.center_offset_x
    local cy = win_y + max_bounds.center_offset_y
    
    -- 将相对坐标转换为绝对坐标
    local bg_rect_rel = cached_data.bg_rect_rel
    local bg_rect = {
        cx + bg_rect_rel[1],
        cy + bg_rect_rel[2],
        cx + bg_rect_rel[3],
        cy + bg_rect_rel[4]
    }
    
    local is_submenu_hovered = false
    
    -- 2. 直接画背景，不用算坐标
    reaper.ImGui_DrawList_AddRectFilled(draw_list, 
        bg_rect[1], bg_rect[2], bg_rect[3], bg_rect[4], 
        bake_cfg.bg_color, 8.0)
    
    -- 3. 绘制边框
    local border_color = styles.correct_rgba_to_u32({0, 0, 0, 255})
    reaper.ImGui_DrawList_AddRect(draw_list,
        bg_rect[1], bg_rect[2], bg_rect[3], bg_rect[4],
        border_color, 8.0, 0, 1.0)
    
    -- 4. 遍历画选项
    local mx, my = reaper.ImGui_GetMousePos(ctx)
    
    -- 先创建所有按钮（用于状态检测），然后再绘制
    local button_states = {}  -- 存储每个按钮的状态
    
    for i, item in ipairs(cached_data.items) do
        -- 将相对坐标转换为绝对坐标
        local rect_rel = item.rect_rel
        local rect = {
            cx + rect_rel[1],
            cy + rect_rel[2],
            cx + rect_rel[3],
            cy + rect_rel[4]
        }
        
        -- 使用 InvisibleButton 进行点击检测（先创建，用于状态检测）
        local rel_x = rect[1] - win_x
        local rel_y = rect[2] - win_y
        reaper.ImGui_SetCursorPos(ctx, rel_x, rel_y)
        local button_id = "##BakedSlot_" .. sector_data.id .. "_" .. (item.grid_pos[1] * cached_data.cols + item.grid_pos[2] + 1)
        reaper.ImGui_InvisibleButton(ctx, button_id, rect[3] - rect[1], rect[4] - rect[2])
        
        -- 检测按钮状态
        local is_hover = reaper.ImGui_IsItemHovered(ctx)
        local is_active = reaper.ImGui_IsItemActive(ctx)
        
        if is_hover then
            is_submenu_hovered = true
        end
        
        -- 存储按钮状态
        button_states[i] = {
            rect = rect,
            is_hover = is_hover,
            is_active = is_active,
            item = item
        }
    end
    
    -- 现在绘制所有按钮（使用检测到的状态）
    for i, state in ipairs(button_states) do
        local item = state.item
        local rect = state.rect
        local is_hover = state.is_hover
        local is_active = state.is_active
        
        local text_pos_rel = item.text_pos_rel
        local text_pos = {
            cx + text_pos_rel[1],
            cy + text_pos_rel[2]
        }
        
        -- 判断是否为已配置的插槽
        local is_configured = item.slot and item.slot.type ~= "empty"
        
        -- 【修复】使用与原来相同的按钮颜色系统
        local col_normal, col_hover, col_active, col_border, text_color
        if is_configured then
            col_normal = button_colors.configured.normal
            col_hover = button_colors.configured.hover
            col_active = button_colors.configured.active
            col_border = button_colors.configured.border
            text_color = button_colors.configured.text
        else
            col_normal = button_colors.empty.normal
            col_hover = button_colors.empty.hover
            col_active = button_colors.empty.active
            col_border = button_colors.empty.border
            text_color = button_colors.empty.text
        end
        
        -- 绘制按钮背景（根据状态选择颜色）
        local bg_color = col_normal
        if is_active then
            bg_color = col_active
        elseif is_hover then
            bg_color = col_hover
        end
        
        -- 绘制按钮背景（圆角矩形）
        reaper.ImGui_DrawList_AddRectFilled(draw_list, 
            rect[1], rect[2], rect[3], rect[4], 
            bg_color, 4.0)
        
        -- 绘制按钮边框（圆角矩形）
        reaper.ImGui_DrawList_AddRect(draw_list,
            rect[1], rect[2], rect[3], rect[4],
            col_border, 4.0, 0, 1.0)
        
        -- 【修复】绘制文字，使用裁剪区域防止溢出
        if item.text and item.text ~= "" then
            -- 使用裁剪区域确保文字不会溢出按钮
            reaper.ImGui_DrawList_PushClipRect(draw_list, rect[1], rect[2], rect[3], rect[4], true)
            reaper.ImGui_DrawList_AddText(draw_list, 
                text_pos[1], text_pos[2], text_color, item.text)
            reaper.ImGui_DrawList_PopClipRect(draw_list)
        end
        
        -- 点击处理
        if is_configured then
            -- 重新设置光标位置以访问按钮状态
            local rel_x = rect[1] - win_x
            local rel_y = rect[2] - win_y
            reaper.ImGui_SetCursorPos(ctx, rel_x, rel_y)
            local button_id = "##BakedSlot_" .. sector_data.id .. "_" .. (item.grid_pos[1] * cached_data.cols + item.grid_pos[2] + 1)
            reaper.ImGui_InvisibleButton(ctx, button_id, rect[3] - rect[1], rect[4] - rect[2])
            
            if reaper.ImGui_IsItemActive(ctx) then
                -- 检查是否正在拖拽
                local is_dragging = reaper.ImGui_IsMouseDragging(ctx, 0)
                if not is_dragging then
                    local mouse_delta_x, mouse_delta_y = reaper.ImGui_GetMouseDelta(ctx, 0)
                    local drag_distance = math.sqrt(mouse_delta_x * mouse_delta_x + mouse_delta_y * mouse_delta_y)
                    if drag_distance > 3 then
                        is_dragging = true
                    end
                end
                
                if is_dragging then
                    if not dragging_slot or dragging_slot ~= item.slot then
                        dragging_slot = item.slot
                    end
                end
            end
            
            if reaper.ImGui_IsItemClicked(ctx, 0) and not dragging_slot then
                -- 这是一个纯点击 (Action)
                M.handle_item_click(item.slot)
            end
            
            -- Tooltip
            if reaper.ImGui_IsItemHovered(ctx) and not dragging_slot then
                local tooltip = item.slot.name
                if tooltip and tooltip ~= "" then
                    reaper.ImGui_BeginTooltip(ctx)
                    reaper.ImGui_Text(ctx, tooltip)
                    reaper.ImGui_EndTooltip(ctx)
                end
            end
        end
    end
    
    return is_submenu_hovered
end

-- ============================================================================
-- Phase 3 - 绘制子菜单 (主入口)
-- ============================================================================

function M.draw_submenu(ctx, sector_data, center_x, center_y, anim_scale, config)
    if not sector_data or not config then return false end  -- Return false if no sector data or config

    -- 【极速缓存系统】如果已烘焙，使用快速绘制函数
    if submenu_bake_cache.is_baked() then
        return M.draw_submenu_cached(ctx, sector_data, center_x, center_y, anim_scale, config)
    end

    -- 【修复】子菜单瞬间切换，不使用任何动画
    -- anim_scale 参数保留以兼容旧调用，但完全忽略
    current_sector = sector_data
    
    -- 获取插槽数量
    local slot_count = sector_data.slots and #sector_data.slots or 0
    
    -- 传递 slot_count 给 get_layout_dims
    local slot_w, slot_h, win_w, win_h = get_layout_dims(config, slot_count)
    
    -- 1. 计算智能位置（固定位置，传递 config）
    local x, y = M.calculate_submenu_position(ctx, sector_data, center_x, center_y, config)
    
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
    
    -- 背景色：深色磨砂背景
    local bg_col = styles.correct_rgba_to_u32({20, 20, 22, 240})
    -- 面板边框：纯黑
    local border_col = styles.correct_rgba_to_u32({0, 0, 0, 255})
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), bg_col) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), border_col)
    
    -- 获取动态尺寸（用于样式，传递 config）
    local _, _, _, _, gap, padding = get_layout_dims(config, slot_count)
    
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
        
        -- 获取动态尺寸并传递给绘制函数（传递 config）
        local slot_w, slot_h = get_layout_dims(config, slot_count)
        M.draw_grid_buttons(ctx, sector_data, slot_w, slot_h, slot_count)
        
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

function M.draw_grid_buttons(ctx, sector_data, slot_w, slot_h, slot_count)
    -- 虚拟化渲染：如果项目数超过9个，只渲染可见项
    local enable_virtualization = (slot_count > 9)
    
    if enable_virtualization then
        -- 虚拟化模式：只渲染可见区域的按钮
        M.draw_virtualized_grid(ctx, sector_data, slot_w, slot_h, slot_count)
    else
        -- 普通模式：渲染所有按钮（至少9个）
        local render_count = math.max(9, slot_count)
        
        for i = 1, render_count do
            local slot = sector_data.slots and sector_data.slots[i] or nil
            
            if (i - 1) % GRID_COLS ~= 0 then
                reaper.ImGui_SameLine(ctx)
            end
            
            M.draw_single_button(ctx, slot, i, slot_w, slot_h)
        end
    end
end

-- 虚拟化渲染函数
-- 注意：由于ImGui子菜单窗口不支持滚动，当前实现渲染所有项目
-- 但保留了虚拟化框架，以便未来添加滚动支持时使用
function M.draw_virtualized_grid(ctx, sector_data, slot_w, slot_h, slot_count)
    -- 【当前实现】由于窗口不支持滚动，渲染所有项目
    -- 【未来改进】如果添加滚动容器，可以只渲染可见区域
    
    -- 计算总行数
    local total_rows = math.ceil(slot_count / GRID_COLS)
    
    -- 渲染所有项目（当前实现）
    for i = 1, slot_count do
        local slot = sector_data.slots and sector_data.slots[i] or nil
        
        if (i - 1) % GRID_COLS ~= 0 then
            reaper.ImGui_SameLine(ctx)
        end
        
        M.draw_single_button(ctx, slot, i, slot_w, slot_h)
    end
    
    -- 【未来改进点】如果添加滚动支持，可以在这里实现：
    -- 1. 使用 ImGui_BeginChild 创建可滚动区域
    -- 2. 计算可见范围（基于滚动位置）
    -- 3. 只渲染可见项
    -- 4. 使用占位元素撑开总高度
end

function M.draw_single_button(ctx, slot, index, w, h)
    -- [FIX] Determine if this is a REAL configured slot
    local is_configured = slot and slot.type ~= "empty"
    
    local label = is_configured and slot.name or ""
    
    -- ============================================================
    -- 颜色优化区域 (使用预计算颜色，避免重复计算)
    -- ============================================================
    
    local col_normal, col_hover, col_active, col_border, text_color
    
    -- [性能优化] 使用预计算的颜色值
    if is_configured then
        col_normal = button_colors.configured.normal
        col_hover = button_colors.configured.hover
        col_active = button_colors.configured.active
        col_border = button_colors.configured.border
        text_color = button_colors.configured.text
    else
        col_normal = button_colors.empty.normal
        col_hover = button_colors.empty.hover
        col_active = button_colors.empty.active
        col_border = button_colors.empty.border
        text_color = button_colors.empty.text
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
    local button_clicked = false
    if is_configured then
        button_clicked = reaper.ImGui_Button(ctx, label .. "##Slot" .. index, w, h)
    else
        -- 空插槽也绘制按钮（用于占位）
        reaper.ImGui_Button(ctx, label .. "##Slot" .. index, w, h)
    end
    
    -- [FIX] Update Drag Logic to use is_configured
    -- 拖拽检测必须在按钮绘制之后，因为 IsItemActive 需要按钮状态
    -- 关键：先检测拖拽，再处理点击，确保拖拽状态在点击检测时已经设置
    if is_configured and reaper.ImGui_IsItemActive(ctx) then
        -- 检查鼠标是否正在拖拽（使用 IsMouseDragging 或检查鼠标移动距离）
        local is_dragging = reaper.ImGui_IsMouseDragging(ctx, 0)
        if not is_dragging then
            -- 如果 IsMouseDragging 返回 false，检查鼠标移动距离
            local mouse_delta_x, mouse_delta_y = reaper.ImGui_GetMouseDelta(ctx, 0)
            local drag_distance = math.sqrt(mouse_delta_x * mouse_delta_x + mouse_delta_y * mouse_delta_y)
            if drag_distance > 3 then  -- 降低阈值，更早检测到拖拽
                is_dragging = true
            end
        end
        
        if is_dragging then
            -- 检查是否真的在拖拽（移动距离超过阈值）
            local mouse_delta_x, mouse_delta_y = reaper.ImGui_GetMouseDelta(ctx, 0)
            local drag_distance = math.sqrt(mouse_delta_x * mouse_delta_x + mouse_delta_y * mouse_delta_y)
            
            if drag_distance > 3 then  -- 降低阈值到 3 像素，更早检测到拖拽
                if not dragging_slot or dragging_slot ~= slot then
                    dragging_slot = slot
                end
            end
        end
    end
    
    -- [关键修改] 点击逻辑优化
    -- 只有在【没有正在拖拽】的情况下才触发点击
    -- ImGui_Button 返回 true 表示点击释放了，但这可能是在拖拽结束时触发
    -- 所以必须严格检查 dragging_slot 是否为 nil
    if button_clicked and is_configured and not dragging_slot then
        -- 这是一个纯点击 (Action)
        M.handle_item_click(slot)
    end
    
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx, 5)
    
    -- [FIX] Update Tooltip Logic to use is_configured
    if is_configured and reaper.ImGui_IsItemHovered(ctx) and not dragging_slot then
        local tooltip = slot.name
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