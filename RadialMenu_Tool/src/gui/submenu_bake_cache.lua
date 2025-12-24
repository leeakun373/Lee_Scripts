-- @description RadialMenu Tool - 子菜单烘焙缓存系统
-- @author Lee
-- @about
--   极速缓存系统：在第一帧计算所有繁重的数据（字体宽度、布局坐标），
--   之后的每一帧只负责"无脑"画图，彻底消灭微卡顿。

local M = {}

-- 加载依赖
local styles = require("gui.styles")

-- ============================================================================
-- 全局缓存变量
-- ============================================================================

-- 用于存储"烤好"的菜单数据，画图时直接取，不用算
local CACHED_SUBMENUS = {}
local IS_BAKED = false -- 标记是否已经烘焙过

-- 最大包围盒数据（固定窗口大小）
local MAX_BOUNDS = {
    win_w = 0,
    win_h = 0,
    center_offset_x = 0,  -- 圆心在窗口内的X偏移
    center_offset_y = 0,  -- 圆心在窗口内的Y偏移
}

-- 样式配置（从配置中读取，但先定义默认值）
local bake_cfg = {
    box_w = 160,          -- 子栏宽度（会被配置覆盖）
    item_h = 30,          -- 单个选项高度（会被配置覆盖）
    bg_color = styles.correct_rgba_to_u32({45, 45, 45, 255}),   -- 背景颜色
    text_color = styles.correct_rgba_to_u32({255, 255, 255, 255}), -- 文字颜色
    margin_x = 15,        -- 距离轮盘的横向间距
}

-- ============================================================================
-- 烘焙函数（Bake Function）
-- ============================================================================

-- 烘焙所有扇区的子菜单数据
-- @param ctx: ImGui 上下文（用于 CalcTextSize）
-- @param center_x: 圆心 X 坐标（用于计算相对位置，实际不使用）
-- @param center_y: 圆心 Y 坐标（用于计算相对位置，实际不使用）
-- @param outer_radius: 轮盘外半径
-- @param config: 配置对象
function M.bake_submenus(ctx, center_x, center_y, outer_radius, config)
    if not ctx or not config or not config.sectors then return end
    
    -- 从配置中读取样式参数（与 list_view.lua 中的 get_layout_dims 保持一致）
    local slot_w = config.menu and config.menu.slot_width or 80
    local slot_h = config.menu and config.menu.slot_height or 32
    -- 【新增】从配置读取按钮间距和窗口内边距
    local gap = config.menu and config.menu.submenu_gap or 3
    local padding = config.menu and config.menu.submenu_padding or 4
    local cols = 3  -- 与 list_view.lua 中的 GRID_COLS 常量一致
    
    -- 更新 bake_cfg
    bake_cfg.box_w = (slot_w * cols) + (gap * (cols - 1)) + (padding * 2)
    bake_cfg.item_h = slot_h + gap
    
    -- 从配置中读取颜色（使用正确的颜色转换函数）
    if config.colors then
        if config.colors.background then
            bake_cfg.bg_color = styles.correct_rgba_to_u32(config.colors.background)
        end
        if config.colors.text then
            bake_cfg.text_color = styles.correct_rgba_to_u32(config.colors.text)
        end
    end
    
    local math_utils = require("math_utils")
    local total_sectors = #config.sectors
    
    -- 清空旧缓存
    CACHED_SUBMENUS = {}
    
    -- ============================================================
    -- 【预计算最大包围盒】计算所有潜在子菜单展开状态的最大包围盒
    -- ============================================================
    -- 初始包围盒至少要包含中间的圆形菜单（相对于圆心）
    local padding = 20  -- 边缘留白
    local min_x = -outer_radius - padding
    local min_y = -outer_radius - padding
    local max_x = outer_radius + padding
    local max_y = outer_radius + padding
    
    -- 遍历所有扇区，计算它们子列表的理论位置
    for _, sector in ipairs(config.sectors) do
        if sector.slots and #sector.slots > 0 then
            -- 计算该扇区对应的角度（中间角度）
            local angle = math_utils.get_sector_center_angle(sector.id, total_sectors, -math.pi / 2)
            
            -- 计算子菜单出现的"锚点"位置（圆周上的点，相对于圆心）
            local overlap_offset = 12
            local anchor_dist = outer_radius - overlap_offset
            local anchor_x_rel, anchor_y_rel = math_utils.polar_to_cartesian(angle, anchor_dist)
            
            -- 计算该扇区子菜单的实际尺寸
            -- 【修改】子菜单尺寸使用独立参数，不依赖按钮参数计算
            local menu_w = config.menu.submenu_width
            local menu_h = config.menu.submenu_height
            
            if not menu_w or not menu_h then
                -- 如果没有独立的子菜单尺寸，根据按钮参数计算（向后兼容）
                local slot_count = #sector.slots
                local rows = math.ceil(slot_count / cols)
                menu_h = (slot_h * rows) + (gap * (rows - 1)) + (padding * 2)
                menu_w = (slot_w * cols) + (gap * (cols - 1)) + (padding * 2)
            end
            
            -- 根据角度判断子菜单是向左还是向右延伸
            local is_right_side = math.cos(angle) >= 0
            
            -- 计算子菜单的四个角（相对于圆心）
            local submenu_left, submenu_right, submenu_top, submenu_bottom
            
            if is_right_side then
                -- 右侧：子菜单向右延伸
                submenu_left = anchor_x_rel + 5
                submenu_right = anchor_x_rel + 5 + menu_w
            else
                -- 左侧：子菜单向左延伸
                submenu_left = anchor_x_rel - menu_w - 5
                submenu_right = anchor_x_rel - 5
            end
            
            -- 子菜单垂直居中于锚点
            submenu_top = anchor_y_rel - (menu_h / 2)
            submenu_bottom = anchor_y_rel + (menu_h / 2)
            
            -- 更新全局的 min/max
            if submenu_left < min_x then min_x = submenu_left end
            if submenu_right > max_x then max_x = submenu_right end
            if submenu_top < min_y then min_y = submenu_top end
            if submenu_bottom > max_y then max_y = submenu_bottom end
        end
    end
    
    -- 加上额外的 Padding 防止边缘被切
    min_x = min_x - padding
    min_y = min_y - padding
    max_x = max_x + padding
    max_y = max_y + padding
    
    -- 计算最终窗口尺寸
    MAX_BOUNDS.win_w = max_x - min_x
    MAX_BOUNDS.win_h = max_y - min_y
    
    -- 计算圆心在窗口内的相对坐标（这是关键，防止绘图跑偏）
    MAX_BOUNDS.center_offset_x = -min_x
    MAX_BOUNDS.center_offset_y = -min_y
    
    -- ============================================================
    -- 遍历所有扇区，烘焙每个扇区的子菜单数据（使用相对坐标）
    -- ============================================================
    for _, sector in ipairs(config.sectors) do
        if sector.slots and #sector.slots > 0 then
            local sector_id = sector.id
            local items = sector.slots
            
            -- 计算子菜单尺寸
            -- 【修改】子菜单尺寸使用独立参数，不依赖按钮参数计算
            local menu_w = config.menu.submenu_width
            local menu_h = config.menu.submenu_height
            
            if not menu_w or not menu_h then
                -- 如果没有独立的子菜单尺寸，根据按钮参数计算（向后兼容）
                local slot_count = #items
                local rows = math.ceil(slot_count / cols)
                menu_h = (slot_h * rows) + (gap * (rows - 1)) + (padding * 2)
                menu_w = (slot_w * cols) + (gap * (cols - 1)) + (padding * 2)
            end
            local y_centered = center_y - (menu_h / 2)
            
            -- 计算扇区角度和位置（相对于圆心）
            local angle = math_utils.get_sector_center_angle(sector_id, total_sectors, -math.pi / 2)
            local overlap_offset = 12
            local anchor_dist = outer_radius - overlap_offset
            local anchor_x_rel, anchor_y_rel = math_utils.polar_to_cartesian(angle, anchor_dist)
            
            -- 判断左右侧
            local is_right_side = math.cos(angle) >= 0
            local sx_rel, sy_rel  -- 相对于圆心的坐标
            if is_right_side then
                sx_rel = anchor_x_rel + 5
            else
                sx_rel = anchor_x_rel - menu_w - 5
            end
            sy_rel = anchor_y_rel - (menu_h / 2)
            
            -- 【核心】提前算好所有东西！（使用相对坐标）
            local cached_sector = {
                -- 背景框坐标（相对于圆心）
                bg_rect_rel = { sx_rel, sy_rel, sx_rel + menu_w, sy_rel + menu_h },
                -- 窗口尺寸（用于参考）
                window_size = { menu_w, menu_h },
                -- 选项列表
                items = {},
                -- 布局参数
                slot_w = slot_w,
                slot_h = slot_h,
                gap = gap,
                padding = padding,
                cols = cols,
                rows = rows
            }
            
            -- 遍历所有插槽，计算每个插槽的位置和文字坐标
            for i, slot in ipairs(items) do
                local row = math.floor((i - 1) / cols)
                local col = (i - 1) % cols
                
                -- 计算按钮位置（网格布局，相对于圆心）
                -- 【修复】确保按钮不超出子栏边界
                local item_x_rel = sx_rel + padding + col * (slot_w + gap)
                local item_y_rel = sy_rel + padding + row * (slot_h + gap)
                
                -- 【修复】验证并修正按钮位置，确保不超出子栏边界
                -- 计算按钮的右边界和底边界
                local item_right = item_x_rel + slot_w
                local item_bottom = item_y_rel + slot_h
                -- 子栏的实际边界（减去 padding，因为按钮应该在 padding 内部）
                local menu_right = sx_rel + menu_w - padding
                local menu_bottom = sy_rel + menu_h - padding
                
                -- 如果按钮超出边界，调整位置（防止溢出）
                if item_right > menu_right then
                    item_x_rel = menu_right - slot_w
                end
                if item_bottom > menu_bottom then
                    item_y_rel = menu_bottom - slot_h
                end
                
                -- 提前计算文字宽度，为了居中（最耗时的操作之一，现在只做一次）
                local text = slot.name or ""
                local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, text)
                
                -- 计算文字居中位置（相对于圆心）
                local text_x_rel = item_x_rel + (slot_w - text_w) / 2
                local text_y_rel = item_y_rel + (slot_h - text_h) / 2
                
                -- 存储计算好的数据（使用相对坐标）
                table.insert(cached_sector.items, {
                    slot = slot,
                    text = text,
                    -- 按钮矩形坐标（相对于圆心）
                    rect_rel = { item_x_rel, item_y_rel, item_x_rel + slot_w, item_y_rel + slot_h },
                    -- 文字位置（已居中，相对于圆心）
                    text_pos_rel = { text_x_rel, text_y_rel },
                    -- 文字尺寸
                    text_size = { text_w, text_h },
                    -- 网格位置
                    grid_pos = { row, col }
                })
            end
            
            -- 存入全局缓存
            CACHED_SUBMENUS[sector_id] = cached_sector
        end
    end
    
    IS_BAKED = true
end

-- ============================================================================
-- 获取缓存数据
-- ============================================================================

-- 获取指定扇区的缓存数据
-- @param sector_id: 扇区ID
-- @return: 缓存的扇区数据，如果不存在则返回nil
function M.get_cached(sector_id)
    return CACHED_SUBMENUS[sector_id]
end

-- 检查是否已烘焙
function M.is_baked()
    return IS_BAKED
end

-- 清除缓存（用于配置重新加载时）
function M.clear()
    CACHED_SUBMENUS = {}
    IS_BAKED = false
end

-- 获取样式配置
function M.get_config()
    return bake_cfg
end

-- 获取所有缓存的子菜单数据（用于计算窗口边界）
function M.get_all_cached()
    return CACHED_SUBMENUS
end

-- 获取最大包围盒数据（固定窗口大小）
function M.get_max_bounds()
    return MAX_BOUNDS
end

-- 清除缓存（用于配置重新加载时）
function M.clear()
    CACHED_SUBMENUS = {}
    IS_BAKED = false
    MAX_BOUNDS = {
        win_w = 0,
        win_h = 0,
        center_offset_x = 0,
        center_offset_y = 0,
    }
end

return M

