-- @description RadialMenu Tool - 轮盘绘制模块
-- @author Lee
-- @about
--   使用 ImDrawList 绘制圆形轮盘
--   负责核心视觉：扇区、中心圆、Pin按钮

local M = {}

local math_utils = require("math_utils")
local im_utils = require("im_utils")
local styles = require("gui.styles")

local hovered_sector_id = nil

-- ============================================================================
-- 颜色插值工具函数
-- ============================================================================

-- 线性插值
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- 颜色插值函数 (处理 RGBA 表)
-- 【关键修复】确保 Alpha 值不会因为插值而降低到不可见
local function lerp_color(c1, c2, t)
    -- 确保 t 在 [0, 1] 范围内
    t = math.max(0.0, math.min(1.0, t))
    local r = lerp(c1[1], c2[1], t)
    local g = lerp(c1[2], c2[2], t)
    local b = lerp(c1[3], c2[3], t)
    -- 【修复】Alpha 正常插值，但确保最小值不低于基础颜色的 80%
    -- 这确保即使插值到中间值，颜色仍然可见
    local lerped_alpha = lerp(c1[4], c2[4], t)
    local min_alpha = math.min(c1[4], c2[4]) * 0.8  -- 至少保持 80% 的最小透明度
    local a = math.max(min_alpha, lerped_alpha)
    -- 返回打包好的 U32 颜色 (复用 styles 的转换逻辑)
    return styles.correct_rgba_to_u32({r, g, b, a})
end

-- ============================================================================
-- 绘制轮盘 (主入口)
-- ============================================================================

-- 绘制完整的轮盘菜单
-- @param ctx: ImGui 上下文
-- @param config: 配置对象
-- @param active_sector_id: 当前激活的扇区 ID (子菜单打开时高亮，可选)
-- @param is_pinned: 是否处于 Pin 住状态 (可选)
-- @param anim_scale: 动画缩放因子 (0.0 到 1.0，默认 1.0)
-- @param sector_anim_states: 扇区扩展动画状态表 (可选)
function M.draw_wheel(ctx, config, active_sector_id, is_pinned, anim_scale, sector_anim_states)
    anim_scale = anim_scale or 1.0
    sector_anim_states = sector_anim_states or {}
    if not ctx or not config or not config.sectors then return end
    
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    if not draw_list then return end
    
    local window_w, window_h = reaper.ImGui_GetWindowSize(ctx)
    if not window_w or not window_h or window_w <= 0 or window_h <= 0 then return end
    
    local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
    
    -- 计算轮盘中心点 (屏幕坐标)
    local center_x = window_x + window_w / 2
    local center_y = window_y + window_h / 2
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
    
    -- 应用动画透明度
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), anim_scale)
    
    -- 1. 获取悬停扇区
    local hovered_sector = M.get_hovered_sector(mouse_x, mouse_y, center_x, center_y, config)
    hovered_sector_id = hovered_sector and hovered_sector.id or nil
    
    -- 应用动画缩放到基础半径
    local inner_radius = config.menu.inner_radius * anim_scale
    local base_outer_radius = config.menu.outer_radius * anim_scale
    
    -- 2. 绘制所有扇区（每个扇区可能有不同的扩展半径）
    -- 检查动画是否启用
    local expansion_enabled = (config.menu.enable_sector_expansion ~= false)
    
    for i, sector in ipairs(config.sectors) do
        local is_hovered = (hovered_sector_id == sector.id)
        -- 只要 active_id 匹配，就强制高亮 (视觉连接)
        local is_active = (active_sector_id and tonumber(active_sector_id) == tonumber(sector.id))
        
        -- [ANIMATION] 获取此扇区的扩展进度
        local expansion_progress = sector_anim_states[sector.id] or 0.0
        
        -- 【关键修复】如果动画关闭，根据悬停/激活状态强制设置进度
        if not expansion_enabled then
            -- 动画关闭时，如果悬停或激活，强制显示高亮状态
            if is_hovered or is_active then
                expansion_progress = 1.0
            else
                expansion_progress = 0.0
            end
        end
        
        -- 【修复1+2】计算膨胀像素数，并限制最大幅度为 10px
        -- 1. 确定目标膨胀值（默认 0）
        local target_expand_pixels = 0.0
        
        if expansion_enabled and (is_hovered or is_active) then
            -- 只有在【开启开关】且【鼠标悬停或激活】时才计算膨胀
            local strength = config.menu.hover_expansion_pixels or 4
            -- 【修复2：最大幅度不超过 10px】
            target_expand_pixels = math.min(strength, 10)
        else
            -- 【修复1：关闭功能时强制为 0，清除残留状态】
            target_expand_pixels = 0.0
        end
        
        -- 2. 应用动画进度（平滑过渡）
        local expansion_pixels = target_expand_pixels * expansion_progress
        
        -- 计算此扇区的动态外半径
        local current_sector_outer = base_outer_radius + expansion_pixels
        
        M.draw_sector(draw_list, ctx, center_x, center_y, sector, i, #config.sectors, is_hovered, is_active, config, inner_radius, current_sector_outer, expansion_progress)
    end
    
    -- 3. 绘制中心圆 (甜甜圈效果)
    if config.menu then
        M.draw_center_circle(draw_list, ctx, center_x, center_y, config, inner_radius)
    end
    
    -- 4. 绘制中心 Pin 按钮
    if config.menu then
        M.draw_pin_button(draw_list, center_x, center_y, config, is_pinned or false)
    end
    
    -- 恢复透明度
    reaper.ImGui_PopStyleVar(ctx)
end

-- ============================================================================
-- 绘制组件
-- ============================================================================

-- 绘制 Pin 按钮 (高保真版本)
function M.draw_pin_button(draw_list, center_x, center_y, config, is_pinned)
    local size = styles.sizes.pin_size or 6  -- 菱形大小 (半径)
    
    -- 使用修正的颜色打包函数（修复 Windows 颜色显示问题）
    local color = is_pinned and 
        styles.correct_rgba_to_u32(styles.colors.pin_active) or 
        styles.correct_rgba_to_u32(styles.colors.pin_inactive)
    local shadow_color = styles.correct_rgba_to_u32(styles.colors.pin_shadow)
    
    -- 绘制阴影
    reaper.ImGui_DrawList_AddQuadFilled(draw_list, 
        center_x, center_y - size + 2,
        center_x + size + 2, center_y + 2,
        center_x, center_y + size + 4,
        center_x - size + 2, center_y + 2,
        shadow_color)
    
    -- 绘制菱形本体
    reaper.ImGui_DrawList_AddQuadFilled(draw_list, 
        center_x, center_y - size,     -- 上
        center_x + size, center_y,     -- 右
        center_x, center_y + size,     -- 下
        center_x - size, center_y,     -- 左
        color)
        
    -- Pin 住时的光晕
    if is_pinned then
        local glow_color = 0xFFD70060  -- 金色光晕（使用十六进制，兼容性更好）
        reaper.ImGui_DrawList_AddQuad(draw_list, 
            center_x, center_y - size - 3,
            center_x + size + 3, center_y,
            center_x, center_y + size + 3,
            center_x - size - 3, center_y,
            glow_color, 2.0)
    end
end

-- 绘制单个扇区 (高保真版本，支持渐变)
function M.draw_sector(draw_list, ctx, center_x, center_y, sector, index, total_sectors, is_hovered, is_active, config, inner_radius, outer_radius, expansion_progress)
    expansion_progress = expansion_progress or 0.0
    local rotation_offset = -math.pi / 2
    local start_angle, end_angle = math_utils.get_sector_angles(index, total_sectors, rotation_offset)
    
    -- 使用传入的动画缩放后的半径，如果没有传入则使用配置值
    inner_radius = inner_radius or config.menu.inner_radius
    outer_radius = outer_radius or config.menu.outer_radius
    
    -- 几何间隙 (Gap) - 使用固定的基准半径，避免边缘抖动
    local base_outer_radius = config.menu.outer_radius  -- 使用固定的配置值
    local gap_radians = (styles.sizes.gap_size or 3.0) / base_outer_radius
    local draw_start = start_angle + gap_radians
    local draw_end = end_angle - gap_radians
    
    -- 颜色平滑插值：使用 expansion_progress 进行线性插值
    -- expansion_progress 是 0.0 (Idle) 到 1.0 (Hovered) 的动画值
    local col_in = lerp_color(styles.colors.sector_bg_in, styles.colors.sector_active_in, expansion_progress)
    local col_out = lerp_color(styles.colors.sector_bg_out, styles.colors.sector_active_out, expansion_progress)
    
    -- 绘制扇形（使用插值后的颜色）
    M.draw_sector_arc_gradient(draw_list, center_x, center_y, inner_radius, outer_radius, 
                                draw_start, draw_end, col_in, col_out, expansion_progress)
    
    -- 如果激活，添加边缘高光（根据 expansion_progress 调整透明度）
    if expansion_progress > 0.0 then
        M.draw_sector_rim_light(draw_list, center_x, center_y, outer_radius, draw_start, draw_end, expansion_progress)
    end
    
    -- 绘制纯黑切割线（最后绘制以确保锋利）
    M.draw_sector_border_line(draw_list, center_x, center_y, inner_radius, outer_radius, 
                              draw_start, draw_end, styles.sizes.gap_size or 3.0)
    
    -- 绘制文本（使用扇环几何中心，确保文字永远在正中央）
    local text_radius = (inner_radius + outer_radius) / 2
    local should_highlight = expansion_progress > 0.5
    M.draw_sector_text(draw_list, ctx, center_x, center_y, text_radius, start_angle, end_angle, sector, should_highlight)
end

-- 绘制扇形（使用 Path API 优化，单次绘制）
function M.draw_sector_arc_gradient(draw_list, center_x, center_y, inner_radius, outer_radius, start_angle, end_angle, col_in, col_out, expansion_progress)
    expansion_progress = expansion_progress or 0.0
    -- [PERF] 动态 segments：根据半径计算分段数
    local avg_radius = (inner_radius + outer_radius) / 2
    local outer_segments = 32  -- 外弧分段数
    local inner_segments = 24  -- 内弧分段数
    
    -- 根据半径调整分段数
    if avg_radius < 50 then
        outer_segments = 16
        inner_segments = 12
    elseif avg_radius < 100 then
        outer_segments = 24
        inner_segments = 18
    end
    
    -- 计算角度跨度
    local angle_span = end_angle - start_angle
    if angle_span < 0 then angle_span = angle_span + 2 * math.pi end
    
    -- 根据角度跨度调整分段数
    local angle_ratio = angle_span / (2 * math.pi)
    outer_segments = math.max(12, math.floor(outer_segments * angle_ratio))
    inner_segments = math.max(12, math.floor(inner_segments * angle_ratio))
    
    -- 使用外圆颜色（更亮的颜色，视觉上更突出）
    -- 由于 col_in 和 col_out 已经在 draw_sector 中进行了插值，这里直接使用 col_out
    local fill_color = col_out
    
    -- 使用 Path API 进行单次绘制
    reaper.ImGui_DrawList_PathClear(draw_list)
    
    -- 绘制外弧（从 StartAngle 到 EndAngle）
    reaper.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, outer_radius, start_angle, end_angle, outer_segments)
    
    -- 绘制内弧（从 EndAngle 到 StartAngle，角度反向以闭合路径）
    reaper.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, inner_radius, end_angle, start_angle, inner_segments)
    
    -- 填充封闭路径
    reaper.ImGui_DrawList_PathFillConvex(draw_list, fill_color)
end

-- 绘制边缘高光
function M.draw_sector_rim_light(draw_list, center_x, center_y, outer_radius, start_angle, end_angle, expansion_progress)
    expansion_progress = expansion_progress or 1.0
    -- 根据 expansion_progress 调整高光透明度
    local base_rim_color = styles.colors.sector_rim_light
    local rim_color_rgba = {
        base_rim_color[1],
        base_rim_color[2],
        base_rim_color[3],
        math.floor(base_rim_color[4] * expansion_progress)
    }
    local rim_color = styles.correct_rgba_to_u32(rim_color_rgba)
    local segments = 32
    local angle_span = end_angle - start_angle
    if angle_span < 0 then angle_span = angle_span + 2 * math.pi end
    
    for i = 0, segments - 1 do
        local a1 = start_angle + angle_span * (i / segments)
        local a2 = start_angle + angle_span * ((i + 1) / segments)
        
        local x1, y1 = math_utils.polar_to_cartesian(a1, outer_radius - 1)
        local x2, y2 = math_utils.polar_to_cartesian(a2, outer_radius - 1)
        
        reaper.ImGui_DrawList_AddLine(draw_list,
            center_x + x1, center_y + y1,
            center_x + x2, center_y + y2,
            rim_color, 2.0)
    end
end

-- 绘制扇区边框线（纯黑切割线）
function M.draw_sector_border_line(draw_list, center_x, center_y, inner_radius, outer_radius, start_angle, end_angle, gap_size)
    local border_color = styles.correct_rgba_to_u32(styles.colors.border)
    local segments = 32
    local angle_span = end_angle - start_angle
    if angle_span < 0 then angle_span = angle_span + 2 * math.pi end
    
    -- 绘制内弧
    for i = 0, segments - 1 do
        local a1 = start_angle + angle_span * (i / segments)
        local a2 = start_angle + angle_span * ((i + 1) / segments)
        
        local x1, y1 = math_utils.polar_to_cartesian(a1, inner_radius)
        local x2, y2 = math_utils.polar_to_cartesian(a2, inner_radius)
        
        reaper.ImGui_DrawList_AddLine(draw_list,
            center_x + x1, center_y + y1,
            center_x + x2, center_y + y2,
            border_color, gap_size)
    end
    
    -- 绘制外弧
    for i = 0, segments - 1 do
        local a1 = start_angle + angle_span * (i / segments)
        local a2 = start_angle + angle_span * ((i + 1) / segments)
        
        local x1, y1 = math_utils.polar_to_cartesian(a1, outer_radius)
        local x2, y2 = math_utils.polar_to_cartesian(a2, outer_radius)
        
        reaper.ImGui_DrawList_AddLine(draw_list,
            center_x + x1, center_y + y1,
            center_x + x2, center_y + y2,
            border_color, gap_size)
    end
end

-- 绘制中心圆 (无边框甜甜圈)
function M.draw_center_circle(draw_list, ctx, center_x, center_y, config, anim_inner_radius)
    local outer_radius = anim_inner_radius or config.menu.inner_radius
    local inner_radius = outer_radius - 6
    -- 使用修正的颜色打包函数
    local dark_grey = styles.correct_rgba_to_u32({63, 60, 64, 255})
    local inner_grey = styles.correct_rgba_to_u32({50, 47, 51, 255})
    
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, outer_radius, dark_grey, 0)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, inner_radius, inner_grey, 0)
end

-- 绘制扇形弧 (向后兼容，使用单色)
function M.draw_sector_arc(draw_list, center_x, center_y, inner_radius, outer_radius, start_angle, end_angle, color)
    local base_segments = 64
    local angle_span = end_angle - start_angle
    if angle_span < 0 then angle_span = angle_span + 2 * math.pi end
    local sector_segments = math.max(16, math.floor(base_segments * angle_span / (2 * math.pi)))
    
    for i = 0, sector_segments - 1 do
        local a1 = start_angle + angle_span * (i / sector_segments)
        local a2 = start_angle + angle_span * ((i + 1) / sector_segments)
        
        local x1_in, y1_in = math_utils.polar_to_cartesian(a1, inner_radius)
        local x1_out, y1_out = math_utils.polar_to_cartesian(a1, outer_radius)
        local x2_in, y2_in = math_utils.polar_to_cartesian(a2, inner_radius)
        local x2_out, y2_out = math_utils.polar_to_cartesian(a2, outer_radius)
        
        reaper.ImGui_DrawList_AddQuadFilled(draw_list,
            center_x + x1_in, center_y + y1_in,
            center_x + x1_out, center_y + y1_out,
            center_x + x2_out, center_y + y2_out,
            center_x + x2_in, center_y + y2_in,
            color)
    end
end

-- ============================================================================
-- 纯文本绘制优化 (无 Icon，几何居中)
-- ============================================================================

local config_manager = require("config_manager")

-- 绘制扇区文本
function M.draw_sector_text(draw_list, ctx, center_x, center_y, text_radius, start_angle, end_angle, sector, is_active)
    local center_angle = (start_angle + end_angle) / 2
    local tx, ty = math_utils.polar_to_cartesian(center_angle, text_radius)
    
    -- 使用缓存的文本行（性能优化）
    local lines = sector.cached_lines
    -- 向后兼容：如果缓存不存在，实时分割
    if not lines then
        if sector.name then
            lines = config_manager.split_text_into_lines(sector.name)
            -- 缓存结果以便下次使用
            sector.cached_lines = lines
        else
            lines = {}
        end
    end
    
    -- 颜色配置
    local text_color = is_active and 
        styles.correct_rgba_to_u32(styles.colors.text_active) or 
        styles.correct_rgba_to_u32(styles.colors.text_normal)
    local shadow_color = styles.correct_rgba_to_u32(styles.colors.text_shadow)
    
    -- 计算总高度以进行垂直居中
    local line_height = reaper.ImGui_GetTextLineHeight(ctx)
    local total_height = #lines * line_height
    
    -- 计算起始坐标
    local cursor_x = center_x + tx
    local cursor_y = center_y + ty - (total_height / 2)
    
    -- 绘制每一行
    for _, line in ipairs(lines) do
        if line ~= "" then
            local text_w = reaper.ImGui_CalcTextSize(ctx, line)
            local text_x = cursor_x - (text_w / 2)
            
            -- 阴影
            reaper.ImGui_DrawList_AddText(draw_list, text_x + 1, cursor_y + 1, shadow_color, line)
            -- 本体
            reaper.ImGui_DrawList_AddText(draw_list, text_x, cursor_y, text_color, line)
        end
        cursor_y = cursor_y + line_height
    end
end

-- ============================================================================
-- 悬停检测
-- ============================================================================

-- 根据鼠标位置判断悬停在哪个扇区
function M.get_hovered_sector(mouse_x, mouse_y, center_x, center_y, config)
    local angle, distance = math_utils.get_mouse_angle_and_distance(mouse_x, mouse_y, center_x, center_y)
    
    local inner_radius = config.menu.inner_radius
    local outer_radius = config.menu.outer_radius
    
    if distance < inner_radius or distance > outer_radius then return nil end
    
    local sector_index = math_utils.angle_to_sector_index(angle, #config.sectors, -math.pi / 2)
    
    if sector_index >= 1 and sector_index <= #config.sectors then
        return config.sectors[sector_index]
    end
    
    return nil
end

-- 获取当前悬停的扇区 ID
function M.get_hovered_sector_id()
    return hovered_sector_id
end

return M
