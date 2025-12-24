-- @description RadialMenu Tool - 样式定义模块
-- @author Lee
-- @about
--   定义 UI 样式、颜色、字体
--   提供统一的视觉效果

local M = {}

-- 加载 ImGui 工具
local im_utils = require("im_utils")

-- ============================================================================
-- Phase 2 - 颜色定义
-- ============================================================================

-- ============================================================================
-- 硬编码颜色常量 
-- 所有颜色值都是硬编码的，完全忽略配置文件中的颜色设置
-- 配置文件中的颜色数据将被忽略，确保视觉一致性
-- ============================================================================
M.colors = {
    -- 兼容旧版本
    background = {63, 60, 64, 0},  -- #3f3c40 完全透明背景
    text = {224, 224, 224, 255},  -- 灰白色文本 (#E0E0E0) [向后兼容]
    text_normal = {180, 180, 180, 255},  -- 新版本文本颜色
    text_disabled = {128, 128, 128, 200},
    text_shadow = {0, 0, 0, 200},  -- 更新为更深的阴影
    -- 边框颜色：比扇区颜色更深的半透明（用于创建"间隙"效果）
    border = {15, 15, 15, 150},  -- 深灰色半透明边框（比扇区深）
    hover = {255, 255, 255, 120},
    active = {255, 255, 255, 150},
    -- Mantrika 风格：渐变扇区颜色（高保真版本）
    -- 默认状态渐变
    sector_bg_in = {30, 32, 35, 230},  -- 深灰 (近圆心)
    sector_bg_out = {45, 48, 55, 230},  -- 稍亮 (远圆心)
    -- 向后兼容的旧版本颜色
    sector_default = {35, 38, 45, 240},  -- 冷深灰色，蓝调 (Alpha 240)
    -- 激活状态渐变
    sector_active_in = {40, 60, 80, 255},  -- 冷蓝 (近圆心)
    sector_active_out = {60, 100, 140, 255},  -- 冷蓝高亮 (远圆心)
    -- 向后兼容
    sector_hover = {60, 100, 140, 255},  -- 专业蓝灰色高亮 (Alpha 255)
    -- 高亮边缘 (Rim Light)
    sector_rim_light = {255, 255, 255, 30},  -- 边缘高光
    accent_color = {0, 120, 215, 200},  -- 专业蓝色（仅用于图标/文本，不用于边框）
    center_circle = {50, 50, 50, 200},  -- 深色中心圆
    -- 全局背景遮罩
    backdrop_dim = {0, 0, 0, 100},  -- 屏幕背景遮罩
    -- 子菜单背景
    glass_background = {25, 25, 28, 255},  -- 冷深色背景（蓝调）
    glass_border = {0, 0, 0, 255},  -- 纯黑色边框（关键：用于创建"间隙"效果）
    submenu_bg = {25, 26, 28, 245},  -- 新版本子菜单背景
    submenu_border = {60, 100, 140, 80},  -- 蓝色边框
    -- ImGui 主题颜色
    window_bg = {63, 60, 64, 255},  -- #3f3c40 深灰色
    frame_bg = {16, 16, 16, 255},  -- #101010 几乎黑色
    button = {51, 51, 51, 255},  -- #333333 微妙
    -- Pin 按钮颜色（高保真版本）
    pin_active = {255, 190, 40, 255},  -- 金色（更暖的金色）
    pin_inactive = {80, 80, 80, 180},  -- 铁灰
    pin_shadow = {0, 0, 0, 150},  -- 阴影
    pin_glow = {255, 215, 0, 128},  -- 金色发光（向后兼容）
    -- 文本颜色
    text_active = {255, 255, 255, 255},  -- 激活时文本颜色
    text_hover = {255, 255, 255, 255},  -- 悬停时文本颜色
}

-- ============================================================================
-- Phase 2 - 尺寸定义
-- ============================================================================

-- 尺寸常量（从配置加载）
M.sizes = {
    wheel_outer_radius = 200,
    wheel_inner_radius = 50,
    sector_border_width = 2,
    text_radius_ratio = 0.65,  -- 文本距离中心的半径比例
    submenu_width = 250,
    submenu_item_height = 30,
    -- 高保真版本尺寸
    wheel_radius_min = 35,  -- 稍微增大内圆，留出呼吸感
    wheel_radius_max = 130,
    gap_size = 3.0,  -- 加粗切割线，增强硬朗感
    pin_size = 6.0,  -- Pin 按钮大小（增大）
    -- 向后兼容
    wheel_radius_min_old = 30,
    wheel_radius_max_old = 120,
}

-- ============================================================================
-- Phase 2 - 间距定义
-- ============================================================================

M.spacing = {
    item_spacing_x = 8,
    item_spacing_y = 4,
    window_padding_x = 10,
    window_padding_y = 10,
    frame_padding_x = 4,
    frame_padding_y = 3,
}

-- ============================================================================
-- Phase 2 - 字体定义
-- ============================================================================

M.fonts = {
    small = 12,
    normal = 14,
    large = 16,
    title = 18,
    icon = 20,  -- 图标字体大小
}

-- ============================================================================
-- 修复颜色显示问题的核心函数
-- ============================================================================

-- ReaImGui (Windows/Little Endian) 需要 0xAABBGGRR 格式
-- [关键] 正确的颜色打包顺序：R G B A (修正后的顺序)
local function correct_rgba_to_u32(t)
    if not t then return 0 end
    
    local r = math.floor(t[1] or 0)
    local g = math.floor(t[2] or 0)
    local b = math.floor(t[3] or 0)
    local a = math.floor(t[4] or 255)
    
    -- ★★★ 修正后的代码 ★★★
    -- 之前的代码 (a << 24) 把 Alpha 放在最高位，导致系统把最高位解释为红色
    -- 所以 {30, 32, 35, 230} 被显示为：红色=230（鲜红），透明度=30（非常透明）
    -- 现在把 R 放在最高位，A 放在最低位，修正颜色显示
    return (r << 24) | (g << 16) | (b << 8) | a
end

-- 导出为模块函数，供其他模块使用
M.correct_rgba_to_u32 = correct_rgba_to_u32

-- ============================================================================
-- Phase 2 - 从配置初始化样式
-- ============================================================================

-- 从配置文件初始化样式
-- config: 配置表
-- [重要] 强制使用硬编码的 Mantrika 风格，禁止配置文件覆盖颜色
function M.init_from_config(config)
    if not config then return end
    
    -- [修改点] 注释掉颜色覆盖部分
    -- 防止 config.json 文件里的旧颜色覆盖我们写好的 Mantrika 风格
    -- 所有颜色必须使用代码中硬编码的值，确保视觉一致性
    -- if config.colors then
    --     for key, value in pairs(config.colors) do
    --         if M.colors[key] then
    --             M.colors[key] = value
    --         end
    --     end
    -- end
    
    -- 下面的尺寸设置可以保留，方便调节大小
    if config.menu then
        if config.menu.outer_radius then
            M.sizes.wheel_outer_radius = config.menu.outer_radius
        end
        if config.menu.inner_radius then
            M.sizes.wheel_inner_radius = config.menu.inner_radius
        end
        if config.menu.sector_border_width then
            M.sizes.sector_border_width = config.menu.sector_border_width
        end
    end
end

-- ============================================================================
-- Phase 2 - 应用主题
-- ============================================================================

-- 将样式应用到 ImGui 上下文（专业深色模式）
-- 使用修正的颜色打包函数确保颜色正确显示
function M.apply_theme(ctx)
    -- 应用窗口样式（使用修正的颜色打包函数）
    local window_bg_color = correct_rgba_to_u32(M.colors.window_bg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), window_bg_color)
    
    local text_color = correct_rgba_to_u32(M.colors.text_normal or M.colors.text)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color)
    
    local border_color = correct_rgba_to_u32(M.colors.border)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), border_color)
    
    local frame_bg_color = correct_rgba_to_u32(M.colors.frame_bg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), frame_bg_color)
    
    local button_color = correct_rgba_to_u32(M.colors.button)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), button_color)
    
    -- 应用间距
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 
        M.spacing.item_spacing_x, M.spacing.item_spacing_y)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 
        M.spacing.window_padding_x, M.spacing.window_padding_y)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 
        M.spacing.frame_padding_x, M.spacing.frame_padding_y)
    
    -- 返回推送的数量（用于后续 pop）
    return 5, 3  -- color_count, var_count
end

-- 恢复之前的样式设置
function M.pop_theme(ctx, color_count, var_count)
    if color_count then
        reaper.ImGui_PopStyleColor(ctx, color_count)
    end
    if var_count then
        reaper.ImGui_PopStyleVar(ctx, var_count)
    end
end

-- ============================================================================
-- Phase 2 - 预定义主题
-- ============================================================================

-- 深色主题（默认）
function M.get_dark_theme()
    return {
        background = {30, 30, 30, 240},
        text = {255, 255, 255, 255},
        text_disabled = {128, 128, 128, 255},
        border = {100, 100, 100, 200},
        hover = {255, 200, 100, 200},
        center_circle = {50, 50, 50, 255},
    }
end

-- 浅色主题
function M.get_light_theme()
    return {
        background = {240, 240, 240, 240},
        text = {30, 30, 30, 255},
        text_disabled = {128, 128, 128, 255},
        border = {180, 180, 180, 200},
        hover = {100, 150, 255, 200},
        center_circle = {220, 220, 220, 255},
    }
end

-- ============================================================================
-- Phase 2 - 辅助函数
-- ============================================================================

-- RGBA 转 U32 辅助函数（已废弃，使用 correct_rgba_to_u32 替代）
-- local function rgba(r, g, b, a)
--     a = a or 255
--     return (r << 24) | (g << 16) | (b << 8) | a
-- end

-- RGBA 转 U32（覆盖 im_utils，确保全局颜色正确）
-- [关键] 修正颜色打包顺序为 R G B A (修正后的顺序)
function M.rgba_to_u32(r, g, b, a)
    r = math.floor(r or 0)
    g = math.floor(g or 0)
    b = math.floor(b or 0)
    a = math.floor(a or 255)
    
    -- ★★★ 修正后的代码 ★★★
    -- 把 R 放在最高位，A 放在最低位，修正颜色显示
    return (r << 24) | (g << 16) | (b << 8) | a
end

-- U32 转 RGBA（包装 im_utils）
function M.u32_to_rgba(color)
    return im_utils.u32_to_color(color)
end

-- 获取扇区颜色（U32 格式）- 强制使用统一的 Mantrika 风格
-- sector: 扇区数据（忽略 sector.color，强制使用统一风格）
-- is_hovered: 是否悬停
-- config: 配置（已忽略，仅用于向后兼容）
-- [重要] 此函数强制使用硬编码的 Mantrika 风格颜色，忽略配置文件中的颜色设置
-- [关键] 使用正确的颜色打包函数，修复 Windows 下的颜色显示问题
function M.get_sector_color_u32(sector, is_hovered, config)
    -- 1. 定义我们想要的基础颜色 (从 M.colors 读取)
    local color_table
    
    if is_hovered then
        -- 悬停状态：使用 sector_active_out (冷蓝)
        color_table = M.colors.sector_active_out
    else
        -- 默认状态：使用 sector_bg_in (深灰，近圆心)
        -- 使用 sector_bg_in 增加渐变层次，确保灰色正常显示
        color_table = M.colors.sector_bg_in
    end
    
    -- 2. 强制使用修正后的转换函数，避开 im_utils 可能存在的 BUG
    -- 使用 correct_rgba_to_u32 确保正确的 A B G R 打包顺序
    return correct_rgba_to_u32(color_table)
end

-- 获取文本颜色（U32 格式）- 使用修正的颜色打包函数
function M.get_text_color_u32()
    return correct_rgba_to_u32(M.colors.text_normal or M.colors.text)
end

-- 获取文本阴影颜色（U32 格式）- 使用修正的颜色打包函数
function M.get_text_shadow_color_u32()
    return correct_rgba_to_u32(M.colors.text_shadow)
end

-- 获取边框颜色（U32 格式）- 使用修正的颜色打包函数
function M.get_border_color_u32()
    return correct_rgba_to_u32(M.colors.border)
end

-- 获取中心圆颜色（U32 格式）- 玻璃质感，使用修正的颜色打包函数
function M.get_center_circle_color_u32()
    return correct_rgba_to_u32(M.colors.center_circle)
end

-- 获取玻璃背景颜色（U32 格式）- 用于子菜单，使用修正的颜色打包函数
function M.get_glass_background_u32()
    return correct_rgba_to_u32(M.colors.glass_background)
end

-- 获取玻璃边框颜色（U32 格式）- 使用修正的颜色打包函数
function M.get_glass_border_u32()
    return correct_rgba_to_u32(M.colors.glass_border)
end

-- ============================================================================
-- 预计算颜色表（性能优化）
-- ============================================================================

-- 预计算的扇区颜色表（避免运行时计算）
local precomputed_sector_colors = {
    -- 默认状态（expansion_progress = 0.0）
    default_in = nil,
    default_out = nil,
    -- 激活状态（expansion_progress = 1.0）
    active_in = nil,
    active_out = nil,
    -- 中间状态（expansion_progress = 0.5，用于平滑过渡）
    mid_in = nil,
    mid_out = nil
}

-- 初始化预计算颜色
local function init_precomputed_sector_colors()
    -- 线性插值函数
    local function lerp(a, b, t)
        return a + (b - a) * t
    end
    
    -- 颜色插值
    local function lerp_color(c1, c2, t)
        t = math.max(0.0, math.min(1.0, t))
        local r = lerp(c1[1], c2[1], t)
        local g = lerp(c1[2], c2[2], t)
        local b = lerp(c1[3], c2[3], t)
        local a = lerp(c1[4], c2[4], t)
        return correct_rgba_to_u32({r, g, b, a})
    end
    
    -- 预计算不同状态的颜色
    precomputed_sector_colors.default_in = correct_rgba_to_u32(M.colors.sector_bg_in)
    precomputed_sector_colors.default_out = correct_rgba_to_u32(M.colors.sector_bg_out)
    precomputed_sector_colors.active_in = correct_rgba_to_u32(M.colors.sector_active_in)
    precomputed_sector_colors.active_out = correct_rgba_to_u32(M.colors.sector_active_out)
    precomputed_sector_colors.mid_in = lerp_color(M.colors.sector_bg_in, M.colors.sector_active_in, 0.5)
    precomputed_sector_colors.mid_out = lerp_color(M.colors.sector_bg_out, M.colors.sector_active_out, 0.5)
end

-- 初始化预计算颜色
init_precomputed_sector_colors()

-- 获取预计算的扇区颜色（根据expansion_progress）
-- @param expansion_progress: 0.0 (默认) 到 1.0 (激活)
-- @return: col_in, col_out (U32格式)
function M.get_precomputed_sector_colors(expansion_progress)
    expansion_progress = expansion_progress or 0.0
    expansion_progress = math.max(0.0, math.min(1.0, expansion_progress))
    
    -- 使用预计算的颜色，避免运行时插值计算
    -- 对于中间值，使用预计算的中间颜色作为近似（性能优化）
    if expansion_progress <= 0.0 then
        return precomputed_sector_colors.default_in, precomputed_sector_colors.default_out
    elseif expansion_progress >= 1.0 then
        return precomputed_sector_colors.active_in, precomputed_sector_colors.active_out
    elseif expansion_progress <= 0.5 then
        -- 0.0 到 0.5 之间：使用中间颜色作为近似
        return precomputed_sector_colors.mid_in, precomputed_sector_colors.mid_out
    else
        -- 0.5 到 1.0 之间：更接近激活状态，使用激活颜色
        return precomputed_sector_colors.active_in, precomputed_sector_colors.active_out
    end
end

return M
