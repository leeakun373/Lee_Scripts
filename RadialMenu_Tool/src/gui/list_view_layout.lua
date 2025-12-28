-- @description RadialMenu Tool - 子菜单布局计算模块
-- @author Lee
-- @about
--   负责子菜单的布局计算：尺寸计算、位置计算
local M = {}

-- ============================================================================
-- 配置常量 (4x3 紧凑布局)
-- ============================================================================
M.GRID_COLS = 4
M.GRID_ROWS = 3
M.DEFAULT_GAP = 3
M.DEFAULT_WINDOW_PADDING = 4

-- ============================================================================
-- 布局尺寸计算
-- ============================================================================
-- 动态获取布局尺寸（从配置读取参数）
-- @param config table: 配置对象
-- @param slot_count number: 插槽数量
-- @return number, number, number, number, number, number: w, h, total_w, total_h, gap, padding
function M.get_layout_dims(config, slot_count)
    -- 从配置读取按钮尺寸，如果没有则使用默认值
    local w = (config and config.menu and config.menu.slot_width) or 60   -- 按钮宽度
    local h = (config and config.menu and config.menu.slot_height) or 25   -- 按钮高度
    local gap = (config and config.menu and config.menu.submenu_gap) or M.DEFAULT_GAP
    local padding = (config and config.menu and config.menu.submenu_padding) or M.DEFAULT_WINDOW_PADDING
    local cols = M.GRID_COLS
    
    -- 计算子菜单尺寸
    local count = math.max(12, slot_count or 12) -- 至少显示 4x3，如果更多则扩展
    local rows = math.ceil(count / cols)
    local total_w = (w * cols) + (gap * (cols - 1)) + (padding * 2)
    local total_h = (h * rows) + (gap * (rows - 1)) + (padding * 2)
    
    return w, h, total_w, total_h, gap, padding
end

-- ============================================================================
-- 智能位置计算
-- ============================================================================
-- 计算子菜单的智能位置（根据扇区角度和轮盘位置）
-- @param ctx ImGui context
-- @param sector_data table: 扇区数据
-- @param center_x number: 轮盘中心 X 坐标
-- @param center_y number: 轮盘中心 Y 坐标
-- @param config table: 配置对象
-- @return number, number: x, y 坐标
function M.calculate_submenu_position(ctx, sector_data, center_x, center_y, config)
    local math_utils = require("math_utils")
    
    local outer_radius = config.menu.outer_radius or 200
    local total_sectors = #config.sectors
    local angle = math_utils.get_sector_center_angle(sector_data.id, total_sectors, -math.pi / 2)
    
    -- 获取动态尺寸
    local _, _, win_w, win_h = M.get_layout_dims(config)
    
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

return M

