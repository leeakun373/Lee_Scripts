-- @description RadialMenu Tool - 预览面板模块
-- @author Lee
-- @about
--   左侧预览面板：轮盘预览和全局设置

local M = {}

-- ============================================================================
-- 模块依赖
-- ============================================================================

local math_utils = require("math_utils")
local im_utils = require("im_utils")
local styles = require("gui.styles")
local i18n = require("utils.i18n")

-- ============================================================================
-- 模块状态变量
-- ============================================================================

-- [PERF] 预览配置缓存，避免每帧 deep_copy
local vis_cache = nil
local vis_cache_key = nil

-- ============================================================================
-- 辅助函数
-- ============================================================================

-- 深拷贝配置表
local function deep_copy_config(src)
    if type(src) ~= "table" then
        return src
    end
    
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = deep_copy_config(v)
    end
    
    return dst
end

-- ============================================================================
-- 绘制函数
-- ============================================================================

-- 简化的预览绘制（避免 wheel.draw_wheel 的交互检测导致卡死）
-- 使用与 wheel.lua 相同的间隙逻辑
local function draw_simple_preview(draw_list, ctx, center_x, center_y, preview_config, selected_index)
    if not preview_config or not preview_config.sectors then
        return
    end
    
    local inner_radius = preview_config.menu.inner_radius
    local outer_radius = preview_config.menu.outer_radius
    local total_sectors = #preview_config.sectors
    -- 保持与 wheel.lua 一致的间隙逻辑
    local gap_radians = (styles.sizes.gap_size or 3.0) / outer_radius
    
    -- 1. 绘制所有扇区
    for i, sector in ipairs(preview_config.sectors) do
        local is_selected = (selected_index == i)
        
        -- 获取扇区角度
        local rotation_offset = -math.pi / 2
        local start_angle, end_angle = math_utils.get_sector_angles(i, total_sectors, rotation_offset)
        
        -- 应用间隙
        local draw_start = start_angle + gap_radians
        local draw_end = end_angle - gap_radians
        
        -- 获取颜色 (强制使用 styles 中的深色主题逻辑)
        local color = styles.get_sector_color_u32(sector, is_selected, preview_config)
        
        -- 绘制扇形
        local base_segments = 64
        local angle_span = draw_end - draw_start
        if angle_span < 0 then angle_span = angle_span + 2 * math.pi end
        local sector_segments = math.max(16, math.floor(base_segments * angle_span / (2 * math.pi)))
        
        -- Add overlap to cover seams between quads (same as wheel.lua)
        local overlap_radians = 1.0 * math.pi / 180  -- Same overlap as wheel.lua
        
        for j = 0, sector_segments - 1 do
            -- Add overlap to hide seams between segments
            local a1 = draw_start + angle_span * (j / sector_segments) - (j > 0 and overlap_radians or 0)
            local a2 = draw_start + angle_span * ((j + 1) / sector_segments) + (j < sector_segments - 1 and overlap_radians or 0)
            
            local x1_inner, y1_inner = math_utils.polar_to_cartesian(a1, inner_radius)
            local x1_outer, y1_outer = math_utils.polar_to_cartesian(a1, outer_radius)
            local x2_inner, y2_inner = math_utils.polar_to_cartesian(a2, inner_radius)
            local x2_outer, y2_outer = math_utils.polar_to_cartesian(a2, outer_radius)
            
            reaper.ImGui_DrawList_AddQuadFilled(draw_list,
                center_x + x1_inner, center_y + y1_inner,
                center_x + x1_outer, center_y + y1_outer,
                center_x + x2_outer, center_y + y2_outer,
                center_x + x2_inner, center_y + y2_inner,
                color)
        end
        
        -- 绘制扇区边缘高光 (模拟 wheel.lua 效果)
        if is_selected then
             local rim_color = styles.correct_rgba_to_u32(styles.colors.sector_rim_light)
             for j = 0, 31 do -- 简化段数
                local a1 = draw_start + angle_span * (j / 32)
                local a2 = draw_start + angle_span * ((j + 1) / 32)
                local x1, y1 = math_utils.polar_to_cartesian(a1, outer_radius - 1)
                local x2, y2 = math_utils.polar_to_cartesian(a2, outer_radius - 1)
                reaper.ImGui_DrawList_AddLine(draw_list, center_x + x1, center_y + y1, center_x + x2, center_y + y2, rim_color, 2.0)
            end
        end
        -- 绘制文本（支持多行，几何居中）
        local text_radius = (inner_radius + outer_radius) / 2
        local center_angle = (start_angle + end_angle) / 2
        local tx, ty = math_utils.polar_to_cartesian(center_angle, text_radius)
        
        local name_text = sector.name or ""
        
        -- 分割文本为多行（支持 \n）
        local lines = {}
        if name_text then
            for line in (name_text:gsub("\\n", "\n") .. "\n"):gmatch("(.-)\n") do
                table.insert(lines, line)
            end
        end
        
        local text_color = is_selected and styles.correct_rgba_to_u32(styles.colors.text_active) or styles.correct_rgba_to_u32(styles.colors.text_normal)
        local shadow_color = styles.correct_rgba_to_u32(styles.colors.text_shadow)
        
        -- 计算尺寸布局
        local line_height = reaper.ImGui_GetTextLineHeight(ctx)
        local total_height = #lines * line_height
        
        local cursor_x = center_x + tx
        local cursor_y = center_y + ty - (total_height / 2)
        
        -- 绘制多行文本
        for _, line in ipairs(lines) do
            if line ~= "" then
                local text_w = reaper.ImGui_CalcTextSize(ctx, line)
                local text_x = cursor_x - (text_w / 2)
                
                reaper.ImGui_DrawList_AddText(draw_list, text_x + 1, cursor_y + 1, shadow_color, line)
                reaper.ImGui_DrawList_AddText(draw_list, text_x, cursor_y, text_color, line)
            end
            cursor_y = cursor_y + line_height
        end
    end
    
    -- 2. 绘制中心圆 (甜甜圈效果 - 关键修正部分)
    local center_outer = inner_radius
    local center_inner = center_outer - 6
    local dark_grey = styles.correct_rgba_to_u32({63, 60, 64, 255})
    local inner_grey = styles.correct_rgba_to_u32({50, 47, 51, 255})
    
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, center_outer, dark_grey, 0)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, center_inner, inner_grey, 0)
    
    -- 3. 绘制中心 Pin 菱形 (关键修正部分)
    local pin_size = styles.sizes.pin_size or 6
    local pin_color = styles.correct_rgba_to_u32(styles.colors.pin_inactive) -- 预览默认为未 Pin 状态
    local pin_shadow = styles.correct_rgba_to_u32(styles.colors.pin_shadow)
    
    -- 阴影
    reaper.ImGui_DrawList_AddQuadFilled(draw_list, 
        center_x, center_y - pin_size + 2,
        center_x + pin_size + 2, center_y + 2,
        center_x, center_y + pin_size + 4,
        center_x - pin_size + 2, center_y + 2,
        pin_shadow)
    -- 本体
    reaper.ImGui_DrawList_AddQuadFilled(draw_list, 
        center_x, center_y - pin_size,
        center_x + pin_size, center_y,
        center_x, center_y + pin_size,
        center_x - pin_size, center_y,
        pin_color)
end

-- 绘制预览面板
-- @param ctx ImGui context
-- @param config table: 配置对象
-- @param state table: 状态对象（包含 selected_sector_index, is_modified 等）
-- @param callbacks table: 回调函数（adjust_sector_count, on_sector_selected, on_clear_sector）
function M.draw(ctx, config, state, callbacks)
    -- ============================================================
    -- 1. Compact Preview Area (Fixed Height: 220px)
    -- ============================================================
    if reaper.ImGui_BeginChild(ctx, "PreviewFrame", 0, 220, 1, reaper.ImGui_WindowFlags_None()) then
        local w, h = reaper.ImGui_GetContentRegionAvail(ctx)
        local px, py = reaper.ImGui_GetCursorScreenPos(ctx)
        local center_x = px + w / 2
        local center_y = py + h / 2
        
        -- [PERF] 生成轻量 key 用于缓存失效检测
        -- NOTE:
        -- - 这里必须使用 config.sectors（不是 config.menu.sectors），否则增加/减少扇区不会触发缓存刷新。
        -- - 同时加入一个很便宜的 sectors signature，让扇区名称/颜色变更也能刷新预览文本/颜色。
        local sectors = config.sectors or {}
        local sectors_sig = 0
        for i, s in ipairs(sectors) do
            -- id / name length
            sectors_sig = sectors_sig + (tonumber(s.id) or i) * 17
            local n = s.name or ""
            sectors_sig = sectors_sig + #tostring(n) * 31
            -- color components
            if type(s.color) == "table" then
                for _, c in ipairs(s.color) do
                    sectors_sig = sectors_sig + (tonumber(c) or 0)
                end
            end
        end
        local menu = config.menu or {}
        local key = tostring(config.version or '') .. '|' ..
                   tostring(#sectors) .. '|' ..
                   tostring(menu.inner_radius or '') .. '|' ..
                   tostring(menu.outer_radius or '') .. '|' ..
                   tostring(sectors_sig)
        
        -- [PERF] 只有当 key 变化时才重新 deep_copy
        if key ~= vis_cache_key then
            vis_cache = deep_copy_config(config)
            vis_cache.menu.outer_radius = 80  -- Fixed visual size
            vis_cache.menu.inner_radius = 25
            vis_cache_key = key
        end
        
        -- Create a scaled-down config for visualization only (使用缓存)
        local vis_config = vis_cache or config
        
        -- Draw preview
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        draw_simple_preview(draw_list, ctx, center_x, center_y, vis_config, state.selected_sector_index)
        
        -- 检测预览区域的鼠标点击，选择扇区
        if reaper.ImGui_IsWindowHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 0) then
            local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
            local relative_x = mouse_x - center_x
            local relative_y = mouse_y - center_y
            local distance = math_utils.distance(relative_x, relative_y, 0, 0)
            local inner_radius = vis_config.menu.inner_radius
            local outer_radius = vis_config.menu.outer_radius
            
            -- 如果点击在轮盘区域内（排除中心圆）
            if distance > inner_radius and distance <= outer_radius then
                -- 使用 math_utils 计算角度
                local angle, _ = math_utils.cartesian_to_polar(relative_x, relative_y)
                local rotation_offset = -math.pi / 2
                local sector_index = math_utils.angle_to_sector_index(angle, #config.sectors, rotation_offset)
                
                if sector_index >= 1 and sector_index <= #config.sectors then
                    -- 切换扇区时清除选中的插槽
                    if state.selected_sector_index ~= sector_index then
                        state.selected_slot_index = nil
                    end
                    state.selected_sector_index = sector_index
                    if callbacks and callbacks.on_sector_selected then
                        callbacks.on_sector_selected(sector_index)
                    end
                end
            end
        end
        
        -- [NEW] 精致的"清除扇区"悬浮按钮（仅在选中扇区时显示，位于预览图右下角）
        if state.selected_sector_index and state.selected_sector_index >= 1 and state.selected_sector_index <= #config.sectors then
            local btn_size = 24  -- 小按钮尺寸
            local btn_padding = 8  -- 距离边缘的间距
            local btn_x = px + w - btn_size - btn_padding
            local btn_y = py + h - btn_size - btn_padding
            
            -- 设置按钮位置
            reaper.ImGui_SetCursorScreenPos(ctx, btn_x, btn_y)
            
            -- 精致的按钮样式（半透明，悬停时变亮）
            local btn_bg = im_utils.color_to_u32(255, 82, 82, 180)  -- 半透明红色
            local btn_hovered = im_utils.color_to_u32(255, 112, 112, 220)
            local btn_active = im_utils.color_to_u32(229, 57, 53, 255)
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), btn_bg)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), btn_hovered)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), btn_active)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4)
            
            if reaper.ImGui_Button(ctx, "×", btn_size, btn_size) then
                local sector = config.sectors[state.selected_sector_index]
                if sector then
                    sector.slots = {}
                    state.selected_slot_index = nil
                    state.is_modified = true
                    if callbacks and callbacks.on_clear_sector then
                        callbacks.on_clear_sector(state.selected_sector_index)
                    end
                end
            end
            
            -- 工具提示
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_BeginTooltip(ctx)
                reaper.ImGui_Text(ctx, i18n.t("clear_sector"))
                reaper.ImGui_EndTooltip(ctx)
            end
            
            reaper.ImGui_PopStyleVar(ctx)
            reaper.ImGui_PopStyleColor(ctx, 3)
        end
        
        reaper.ImGui_EndChild(ctx)
    end
    
    -- ============================================================
    -- 2. Scrollable Settings Area
    -- ============================================================
    if reaper.ImGui_BeginChild(ctx, "LeftSettingsRegion", 0, 0, 1, reaper.ImGui_WindowFlags_None()) then
        reaper.ImGui_Spacing(ctx)
        
        -- [SECTION 1] Sector Name (Top Priority)
        if state.selected_sector_index and state.selected_sector_index >= 1 and state.selected_sector_index <= #config.sectors then
            local sector = config.sectors[state.selected_sector_index]
            if sector then
                reaper.ImGui_Text(ctx, i18n.t("current_sector_name"))
                reaper.ImGui_SetNextItemWidth(ctx, -1) -- Full width
                local name_buf = sector.name or ""
                local name_changed, new_name = reaper.ImGui_InputText(ctx, "##SectorName", name_buf, 256)
                if name_changed then
                    sector.name = new_name
                    state.is_modified = true
                end
            end
        else
            reaper.ImGui_TextDisabled(ctx, i18n.t("please_select_sector"))
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- [SECTION 2] Global Settings
        reaper.ImGui_Text(ctx, i18n.t("global_settings"))
        reaper.ImGui_Spacing(ctx)
        
        -- A. Sector Count (Moved to Top of Global)
        reaper.ImGui_Text(ctx, i18n.t("sector_count"))
        local sector_count = #config.sectors
        local sector_count_changed, new_count = reaper.ImGui_SliderInt(ctx, "##SectorCount", sector_count, 1, 8, "%d")
        if sector_count_changed and new_count ~= sector_count then
            if callbacks and callbacks.adjust_sector_count then
                callbacks.adjust_sector_count(new_count)
            end
            state.is_modified = true
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- B. Wheel Size
        reaper.ImGui_TextDisabled(ctx, i18n.t("wheel_size"))
        
        reaper.ImGui_Text(ctx, i18n.t("outer_radius"))
        local outer_radius = config.menu.outer_radius or 90
        local outer_radius_changed, new_outer_radius = reaper.ImGui_SliderInt(ctx, "##OuterRadius", outer_radius, 80, 300, "%d px")
        if outer_radius_changed then
            config.menu.outer_radius = new_outer_radius
            state.is_modified = true
        end
        
        reaper.ImGui_Text(ctx, i18n.t("inner_radius"))
        local inner_radius = config.menu.inner_radius or 25
        local inner_radius_changed, new_inner_radius = reaper.ImGui_SliderInt(ctx, "##InnerRadius", inner_radius, 20, 100, "%d px")
        if inner_radius_changed then
            config.menu.inner_radius = new_inner_radius
            state.is_modified = true
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- C. Submenu Size (Stacked Vertically)
        reaper.ImGui_TextDisabled(ctx, i18n.t("submenu_size"))
        
        reaper.ImGui_Text(ctx, i18n.t("width"))
        local slot_w = config.menu.slot_width or 65
        local w_changed, new_w = reaper.ImGui_SliderInt(ctx, "##SlotWidth", slot_w, 60, 150, "%d px")
        if w_changed then
            config.menu.slot_width = new_w
            state.is_modified = true
        end
        
        reaper.ImGui_Text(ctx, i18n.t("height"))
        local slot_h = config.menu.slot_height or 25
        local h_changed, new_h = reaper.ImGui_SliderInt(ctx, "##SlotHeight", slot_h, 24, 60, "%d px")
        if h_changed then
            config.menu.slot_height = new_h
            state.is_modified = true
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- [SECTION 3] Interaction & Animation
        reaper.ImGui_Text(ctx, i18n.t("interaction_animation"))
        reaper.ImGui_Spacing(ctx)
        
        -- 1. Master Animation Toggle
        local anim_enabled = config.menu.animation and config.menu.animation.enable
        if anim_enabled == nil then anim_enabled = true end
        
        local anim_changed, new_anim = reaper.ImGui_Checkbox(ctx, i18n.t("enable_ui_animation"), anim_enabled)
        if anim_changed then
            if not config.menu.animation then config.menu.animation = {} end
            config.menu.animation.enable = new_anim
            state.is_modified = true
        end
        
        -- Indent animation parameters
        if anim_enabled then
            reaper.ImGui_Indent(ctx)
            
            -- Wheel Open Duration
            reaper.ImGui_Text(ctx, i18n.t("open_animation_duration"))
            local dur_open = config.menu.animation.duration_open or 0.06
            local dur_changed, new_dur = reaper.ImGui_SliderDouble(ctx, "##AnimDurOpen", dur_open, 0.0, 0.5, "%.2f s")
            if dur_changed then
                config.menu.animation.duration_open = new_dur
                state.is_modified = true
            end
            
            reaper.ImGui_Unindent(ctx)
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- 2. Sector Expansion Settings
        local expand_enabled = config.menu.enable_sector_expansion
        if expand_enabled == nil then expand_enabled = true end -- Default true
        
        local expand_changed, new_expand = reaper.ImGui_Checkbox(ctx, i18n.t("enable_sector_expansion"), expand_enabled)
        if expand_changed then
            config.menu.enable_sector_expansion = new_expand
            state.is_modified = true
        end
        
        if expand_enabled then
            reaper.ImGui_Indent(ctx)
            
            -- Expansion Pixels
            reaper.ImGui_Text(ctx, i18n.t("expansion_amount") .. ":")
            local exp_px = config.menu.hover_expansion_pixels or 4
            -- 【修复】限制滑块上限为 10px，与渲染逻辑保持一致
            exp_px = math.min(exp_px, 10)  -- 确保当前值不超过上限
            local px_changed, new_px = reaper.ImGui_SliderInt(ctx, "##ExpPixels", exp_px, 0, 10, "%d px")
            if px_changed then
                -- 【修复】保存时也限制最大值，确保不超过 10px
                config.menu.hover_expansion_pixels = math.min(new_px, 10)
                state.is_modified = true
            end
            
            -- Expansion Speed (Intuitive 1-10 Scale)
            reaper.ImGui_Text(ctx, i18n.t("expansion_speed") .. ":")
            local exp_spd_raw = config.menu.hover_animation_speed or 8
            -- Convert to integer: handle old float values (0.0-1.0) or new int values (1-10)
            local exp_spd
            if type(exp_spd_raw) == "number" then
                if exp_spd_raw < 1 then
                    -- Old format: convert 0.0-1.0 to 1-10 scale
                    -- Formula: (value / 0.05) rounded, clamped to 1-10
                    exp_spd = math.max(1, math.min(10, math.floor((exp_spd_raw / 0.05) + 0.5)))
                else
                    -- New format: already 1-10, just ensure it's an integer
                    exp_spd = math.max(1, math.min(10, math.floor(exp_spd_raw + 0.5)))
                end
            else
                exp_spd = 4  -- Default fallback
            end
            -- SliderInt: 1 (Slow) to 10 (Fast)
            local spd_changed, new_spd = reaper.ImGui_SliderInt(ctx, "##ExpSpeed", exp_spd, 1, 10, "%d")
            if spd_changed then
                config.menu.hover_animation_speed = new_spd
                state.is_modified = true
            end
            
            reaper.ImGui_Unindent(ctx)
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- 3. Interaction
        local hover_mode = config.menu.hover_to_open or false
        local hover_changed, new_hover_mode = reaper.ImGui_Checkbox(ctx, i18n.t("hover_to_open"), hover_mode)
        if hover_changed then
            config.menu.hover_to_open = new_hover_mode
            state.is_modified = true
        end
        
        reaper.ImGui_EndChild(ctx)
    end
end

return M