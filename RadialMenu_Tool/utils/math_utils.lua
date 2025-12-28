-- @description RadialMenu Tool - 数学工具模块
-- @author Lee
-- @about
--   几何计算和数学辅助函数
--   用于轮盘菜单的角度、距离计算

local M = {}

-- ============================================================================
-- Phase 2 - 鼠标位置分析
-- ============================================================================

-- 计算鼠标相对于中心点的角度和距离
-- 角度：0 在右侧，顺时针增加，范围 [0, 2π)
function M.get_mouse_angle_and_distance(mouse_x, mouse_y, center_x, center_y)
    local dx = mouse_x - center_x
    local dy = mouse_y - center_y
    
    -- 计算距离
    local distance = math.sqrt(dx * dx + dy * dy)
    
    -- 计算角度（atan2 返回 [-π, π]）
    local angle = math.atan(dy, dx)
    
    -- 归一化角度到 [0, 2π)
    if angle < 0 then
        angle = angle + 2 * math.pi
    end
    
    return angle, distance
end

-- ============================================================================
-- Phase 2 - 扇区判定
-- ============================================================================

-- 判断点是否在扇区内
-- 重要：先检查距离，再检查角度（避免中心死区的抖动问题）
function M.is_point_in_sector(angle, distance, sector_start, sector_end, inner_radius, outer_radius)
    -- 首先检查距离是否在圆环范围内
    if distance < inner_radius or distance > outer_radius then
        return false
    end
    
    -- 归一化角度
    angle = M.normalize_angle(angle)
    sector_start = M.normalize_angle(sector_start)
    sector_end = M.normalize_angle(sector_end)
    
    -- 检查角度是否在扇区范围内
    if sector_start <= sector_end then
        -- 普通情况：扇区不跨越 0 度
        return angle >= sector_start and angle <= sector_end
    else
        -- 特殊情况：扇区跨越 0 度
        return angle >= sector_start or angle <= sector_end
    end
end

-- ============================================================================
-- Phase 2 - 角度工具
-- ============================================================================

-- 将角度归一化到 [0, 2π) 范围
function M.normalize_angle(angle)
    while angle < 0 do
        angle = angle + 2 * math.pi
    end
    while angle >= 2 * math.pi do
        angle = angle - 2 * math.pi
    end
    return angle
end

-- Sexan 的核心算法：判断当前角度是否在 [lower, upper] 范围内
-- 处理了 0/360 度跨越的边界情况，非常稳定
-- 魔法数字 0.005 是为了防止浮点数精度误差导致的边缘闪烁
function M.angle_in_range(angle, lower, upper)
    local pi = math.pi
    local two_pi = 2 * pi
    
    -- 【第三阶段修复】单扇区特殊处理：当范围跨度接近 2π 时，直接返回 true
    -- 这解决了单扇区死锁问题（当 total_sectors == 1 时）
    local range_span = (upper - lower) % two_pi
    if range_span >= two_pi - 0.01 then  -- 允许小的浮点误差
        return true  -- 单扇区覆盖整个圆，任何角度都应该匹配
    end
    
    return (angle - lower + 0.005) % two_pi <= (upper - 0.005 - lower) % two_pi
end

-- 角度转弧度
function M.deg_to_rad(degrees)
    return degrees * math.pi / 180
end

-- 弧度转角度
function M.rad_to_deg(radians)
    return radians * 180 / math.pi
end

-- ============================================================================
-- Phase 2 - 极坐标转换
-- ============================================================================

-- 极坐标转笛卡尔坐标
function M.polar_to_cartesian(angle, radius)
    local x = radius * math.cos(angle)
    local y = radius * math.sin(angle)
    return x, y
end

-- 笛卡尔坐标转极坐标
function M.cartesian_to_polar(x, y)
    local radius = math.sqrt(x * x + y * y)
    local angle = math.atan(y, x)
    
    -- 归一化角度
    if angle < 0 then
        angle = angle + 2 * math.pi
    end
    
    return angle, radius
end

-- ============================================================================
-- Phase 2 - 距离计算
-- ============================================================================

-- 计算两点之间的距离
function M.distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- 计算两点之间的距离平方（避免开方，提高性能）
function M.distance_squared(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return dx * dx + dy * dy
end

-- ============================================================================
-- Phase 2 - 数值工具
-- ============================================================================

-- 限制数值在指定范围内
function M.clamp(value, min_val, max_val)
    return math.max(min_val, math.min(max_val, value))
end

-- 线性插值
function M.lerp(a, b, t)
    return a + (b - a) * t
end

-- 将值从一个范围映射到另一个范围
function M.map(value, in_min, in_max, out_min, out_max)
    local normalized = (value - in_min) / (in_max - in_min)
    return out_min + normalized * (out_max - out_min)
end

-- ============================================================================
-- Phase 2 - 圆形碰撞检测
-- ============================================================================

-- 判断点是否在圆内
function M.is_point_in_circle(px, py, cx, cy, radius)
    local distance_sq = M.distance_squared(px, py, cx, cy)
    return distance_sq <= radius * radius
end

-- 判断点是否在圆环内
-- 重要：这是避免中心死区抖动的关键函数
function M.is_point_in_ring(px, py, cx, cy, inner_radius, outer_radius)
    local distance = M.distance(px, py, cx, cy)
    return distance >= inner_radius and distance <= outer_radius
end

-- ============================================================================
-- Phase 2 - 扇区计算辅助
-- ============================================================================

-- 根据角度和扇区总数计算扇区索引
-- 返回 1-based 索引
function M.angle_to_sector_index(angle, num_sectors, rotation_offset)
    rotation_offset = rotation_offset or 0
    
    -- 应用旋转偏移
    angle = M.normalize_angle(angle - rotation_offset)
    
    -- 计算每个扇区的角度
    local angle_per_sector = (2 * math.pi) / num_sectors
    
    -- 计算扇区索引
    local index = math.floor(angle / angle_per_sector) + 1
    
    -- 确保索引在有效范围内
    if index > num_sectors then
        index = 1
    end
    
    return index
end

-- 计算扇区的起始和结束角度
-- 返回两个值：start_angle, end_angle（弧度）
-- sector_index: 1-based 索引
function M.get_sector_angles(sector_index, num_sectors, rotation_offset)
    rotation_offset = rotation_offset or -math.pi / 2  -- 默认从顶部开始（-90度）
    
    -- 【第三阶段修复】单扇区特殊处理：确保覆盖完整的 2π 范围
    if num_sectors == 1 then
        -- 单扇区时，起始角度为 -π/2，结束角度为 3π/2，覆盖完整的 2π 范围
        return rotation_offset, rotation_offset + 2 * math.pi
    end
    
    local angle_per_sector = (2 * math.pi) / num_sectors
    
    local start_angle = (sector_index - 1) * angle_per_sector + rotation_offset
    local end_angle = sector_index * angle_per_sector + rotation_offset
    
    return start_angle, end_angle
end

-- 计算扇区的中心角度
-- 用于放置文本或图标
function M.get_sector_center_angle(sector_index, num_sectors, rotation_offset)
    local start_angle, end_angle = M.get_sector_angles(sector_index, num_sectors, rotation_offset)
    return (start_angle + end_angle) / 2
end

-- ============================================================================
-- Phase 2 - 颜色混合工具（用于悬停效果）
-- ============================================================================

-- 混合两个 RGBA 颜色
-- color1, color2: {r, g, b, a} 表格，值范围 0-255
-- t: 混合因子，0 = 完全是 color1，1 = 完全是 color2
function M.blend_colors(color1, color2, t)
    t = M.clamp(t, 0, 1)
    
    return {
        M.lerp(color1[1], color2[1], t),
        M.lerp(color1[2], color2[2], t),
        M.lerp(color1[3], color2[3], t),
        M.lerp(color1[4] or 255, color2[4] or 255, t)
    }
end

-- 调整颜色亮度
-- color: {r, g, b, a} 表格
-- brightness: 亮度因子，1.0 = 原始，> 1.0 = 变亮，< 1.0 = 变暗
function M.adjust_brightness(color, brightness)
    return {
        M.clamp(color[1] * brightness, 0, 255),
        M.clamp(color[2] * brightness, 0, 255),
        M.clamp(color[3] * brightness, 0, 255),
        color[4] or 255
    }
end

-- ============================================================================
-- Phase 4 - 缓动函数 (Easing Functions)
-- ============================================================================

-- 缓动函数：Ease Out Cubic (快速开始，缓慢结束)
-- t: 当前时间进度 (0.0 到 1.0)
-- 返回: 缓动后的进度值 (0.0 到 1.0)
function M.ease_out_cubic(t)
    t = M.clamp(t, 0, 1)
    return 1 - (1 - t) ^ 3
end

-- 缓动函数：Ease Out Quart (四次方，比 Cubic 更激进)
-- t: 当前时间进度 (0.0 到 1.0)
-- 返回: 缓动后的进度值 (0.0 到 1.0)
function M.ease_out_quart(t)
    t = M.clamp(t, 0, 1)
    return 1 - (1 - t) ^ 4
end

-- 缓动函数：Back Out (回弹效果，会稍微超过目标值然后回弹)
-- t: 当前时间进度 (0.0 到 1.0)
-- overshoot: 回弹幅度 (默认 1.70158，标准值)
-- 返回: 缓动后的进度值 (可能超过 1.0，需要 clamp)
function M.ease_out_back(t, overshoot)
    overshoot = overshoot or 1.70158
    t = M.clamp(t, 0, 1)
    local c1 = overshoot + 1
    local c3 = c1 + 1
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

return M
