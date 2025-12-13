-- @description RadialMenu Tool - 设置编辑器
-- @author Lee
-- @about
--   配置编辑界面
--   允许用户可视化编辑扇区和插槽

local M = {}

-- ============================================================================
-- 模块依赖
-- ============================================================================

local config_manager = require("config_manager")
local styles = require("styles")
local wheel = require("wheel")
local math_utils = require("math_utils")
local im_utils = require("im_utils")
local utils_fx = require("utils_fx")

-- ============================================================================
-- 设置界面状态
-- ============================================================================

local ctx = nil
local config = nil
local original_config = nil  -- 原始配置（用于丢弃更改）
local is_open = false
local is_modified = false
local selected_sector_index = nil  -- 当前选中的扇区索引（1-based）
local preview_config = nil  -- 缓存的预览配置（避免每次绘制都深拷贝）

-- 新增状态变量
local actions_cache = nil  -- Action 列表缓存
local actions_filtered = {}  -- 过滤后的 Action 列表
local action_search_text = ""  -- Action 搜索文本
local browser_tab = 0  -- 浏览器标签页 (0=Actions, 1=FX)
local fx_list = {}  -- FX 列表（简单实现）
local fx_search_text = ""  -- FX 搜索文本
local current_fx_filter = "All"  -- 当前 FX 过滤器 (All, VST, VST3, JS, AU, CLAP, LV2, Chain, Template)
local fx_list_clipper = nil  -- FX ListClipper 缓存
local selected_slot_index = nil  -- 当前选中的插槽索引（用于属性栏编辑）
local action_list_clipper = nil  -- ListClipper 缓存（使用 ValidatePtr 验证有效性）
local save_feedback_time = 0  -- 保存反馈时间戳（用于显示保存成功消息）
local tooltip_hover_start_time = 0  -- Tooltip 悬停开始时间
local tooltip_current_slot_id = nil  -- 当前悬停的插槽 ID
local removed_sector_stash = {}  -- 缓存被删除的扇区数据（用于恢复）

-- ============================================================================
-- Phase 4 - 初始化
-- ============================================================================

-- 初始化设置编辑器
-- @return boolean: 初始化是否成功
function M.init()
    -- 单例检查：如果设置窗口已经打开，检查上下文是否真的存在
    local settings_open = reaper.GetExtState("RadialMenu", "SettingsOpen")
    if settings_open == "1" then
        -- 如果 ExtState 是 "1"，检查上下文是否真的存在
        -- 如果 ctx 存在且有效，说明窗口确实已打开
        if ctx and reaper.ImGui_GetWindowSize then
            -- 尝试获取窗口尺寸来验证上下文是否有效
            local w, h = reaper.ImGui_GetWindowSize(ctx)
            if w and h then
                -- 窗口确实已打开
                -- -- reaper.ShowConsoleMsg("设置窗口已打开，请关闭现有窗口后再打开\n")
                return false
            end
        end
        -- 如果 ExtState 是 "1" 但上下文不存在或无效，说明窗口已关闭但 ExtState 未清除
        -- 清除 ExtState 并继续初始化
        reaper.SetExtState("RadialMenu", "SettingsOpen", "0", false)
        -- -- reaper.ShowConsoleMsg("检测到残留的 ExtState，已清除并重新初始化\n")
    end
    
    -- 检查 ReaImGui 是否可用
    if not reaper.ImGui_CreateContext then
        reaper.ShowMessageBox("错误: ReaImGui 未安装或不可用", "初始化失败", 0)
        return false
    end
    
    -- 创建 ImGui 上下文
    ctx = reaper.ImGui_CreateContext("RadialMenu_Settings", reaper.ImGui_ConfigFlags_None())
    if not ctx then
        reaper.ShowMessageBox("错误: 无法创建 ImGui 上下文", "初始化失败", 0)
        return false
    end
    
    -- 加载配置
    config = config_manager.load()
    if not config then
        reaper.ShowMessageBox("错误: 无法加载配置", "初始化失败", 0)
        return false
    end
    
    -- 深拷贝配置（用于丢弃更改）
    original_config = M.deep_copy_config(config)
    
    -- 从配置初始化样式
    styles.init_from_config(config)
    
    -- 初始化状态变量
    is_open = true
    is_modified = false
    selected_sector_index = nil
    removed_sector_stash = {}  -- 清空扇区缓存（确保每次打开编辑器时都是干净的状态）
    
    -- 初始化 Action 缓存和过滤列表
    M.load_actions()
    actions_filtered = M.filter_actions("")
    
    -- 标记设置窗口已打开
    reaper.SetExtState("RadialMenu", "SettingsOpen", "1", false)
    
    -- reaper.ShowConsoleMsg("========================================\n")
    -- reaper.ShowConsoleMsg("设置编辑器初始化成功\n")
    -- reaper.ShowConsoleMsg("  版本: 1.0.0 (Build #001)\n")
    -- reaper.ShowConsoleMsg("========================================\n")
    
    return true
end

-- ============================================================================
-- Phase 4 - 主循环
-- ============================================================================

-- 设置编辑器主循环
function M.loop()
    if not ctx or not is_open then
        M.cleanup()
        return
    end
    
    -- 绘制设置窗口
    M.draw()
    
    -- 如果窗口打开，继续 defer
    if is_open then
        reaper.defer(M.loop)
    else
        M.cleanup()
    end
end

-- ============================================================================
-- Phase 4 - 绘制主窗口
-- ============================================================================

-- 应用主题（参考Markers Modern主题风格）
function M.apply_theme()
    -- 应用样式变量（参考 Markers Modern 主题）
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 10, 10)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8, 8)  -- Markers Modern: {8, 8}
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 10, 6)  -- Markers Modern: {10, 6}
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4)  -- Markers Modern: 4
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 6)  -- Markers Modern: 6
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), 4)  -- Markers Modern: 4
    
    -- 应用颜色（参考 Markers Modern 主题 - 低饱和度，耐看）
    -- 使用 0xRRGGBBAA 格式，与 Markers 保持一致
    local WINDOW_BG = 0x18181BFF  -- Zinc-900 (#18181B)
    local POPUP_BG = 0x1D1D20F0  -- 弹窗稍亮
    local BORDER = 0x27272AFF  -- 淡淡的边框 (#27272A)
    local FRAME_BG = 0x09090BFF  -- 极黑输入框 (#09090B)
    local FRAME_BG_HOVERED = 0x18181BFF  -- 悬停稍亮
    local FRAME_BG_ACTIVE = 0x202020FF  -- 激活时稍亮
    local BUTTON = 0x27272AFF  -- 默认深灰 (#27272A)
    local BUTTON_HOVERED = 0x3F3F46FF  -- 悬停变亮 (#3F3F46)
    local BUTTON_ACTIVE = 0x18181BFF  -- 点击变深
    local TEXT = 0xE4E4E7FF  -- 锌白 (#E4E4E7)
    local TEXT_DISABLED = 0xA1A1AAFF  -- 灰字 (#A1A1AA)
    local TITLE_BG = 0x18181BFF  -- 标题栏融入背景
    local TITLE_BG_ACTIVE = 0x18181BFF  -- 激活时也不变色
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), WINDOW_BG)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), POPUP_BG)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), BORDER)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), FRAME_BG)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), FRAME_BG_HOVERED)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), FRAME_BG_ACTIVE)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), BUTTON)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), BUTTON_HOVERED)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), BUTTON_ACTIVE)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), TEXT)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextDisabled(), TEXT_DISABLED)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), TITLE_BG)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), TITLE_BG_ACTIVE)
    
    return 13, 6  -- color_count, style_var_count
end

-- 恢复主题
function M.pop_theme(color_count, style_var_count)
    if color_count then
        reaper.ImGui_PopStyleColor(ctx, color_count)
    end
    if style_var_count then
        reaper.ImGui_PopStyleVar(ctx, style_var_count)
    end
end

-- 绘制设置编辑器主窗口
function M.draw()
    -- 应用主题
    local color_count, style_var_count = M.apply_theme()
    
    -- 设置窗口大小和位置
    reaper.ImGui_SetNextWindowSize(ctx, 1400, 800, reaper.ImGui_Cond_FirstUseEver())
    
    -- 开始窗口
    local visible, open = reaper.ImGui_Begin(ctx, "RadialMenu 设置编辑器", true, reaper.ImGui_WindowFlags_None())
    
    -- 如果窗口不可见，直接返回（不需要调用 End）
    if not visible then
        is_open = open
        M.pop_theme(color_count, style_var_count)
        return
    end
    
    -- 检查窗口是否关闭
    if not open then
        is_open = false
        reaper.ImGui_End(ctx)
        M.pop_theme(color_count, style_var_count)
        return
    end
    
    -- [REMOVED Title Text] - Window title bar already displays this information
    
    -- 绘制操作栏（现在位于顶部）
    M.draw_action_bar()
    
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- 使用表格创建 2 列布局（分割视图）
    if reaper.ImGui_BeginTable(ctx, "##MainLayout", 2, 
        reaper.ImGui_TableFlags_Resizable() | reaper.ImGui_TableFlags_BordersInnerV(), -1, -1) then
        
        -- 左侧列：预览面板
        reaper.ImGui_TableNextColumn(ctx)
        M.draw_preview_panel()
        
        -- 右侧列：编辑器面板（分为上下两部分）
        reaper.ImGui_TableNextColumn(ctx)
        M.draw_editor_panel_split()
        
        reaper.ImGui_EndTable(ctx)
    end
    
    reaper.ImGui_End(ctx)
    
    -- 恢复主题
    M.pop_theme(color_count, style_var_count)
end

-- ============================================================================
-- Phase 4 - 左侧预览面板
-- ============================================================================

-- 绘制预览面板
function M.draw_preview_panel()
    -- ============================================================
    -- 1. Compact Preview Area (Fixed Height: 220px)
    -- ============================================================
    if reaper.ImGui_BeginChild(ctx, "PreviewFrame", 0, 220, 1, reaper.ImGui_WindowFlags_None()) then
        local w, h = reaper.ImGui_GetContentRegionAvail(ctx)
        local px, py = reaper.ImGui_GetCursorScreenPos(ctx)
        local center_x = px + w / 2
        local center_y = py + h / 2
        
        -- Create a scaled-down config for visualization only
        local vis_config = M.deep_copy_config(config)
        vis_config.menu.outer_radius = 80  -- Fixed visual size
        vis_config.menu.inner_radius = 25
        
        -- Draw preview
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        M.draw_simple_preview(draw_list, ctx, center_x, center_y, vis_config, selected_sector_index)
        
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
                    if selected_sector_index ~= sector_index then
                        selected_slot_index = nil
                    end
                    selected_sector_index = sector_index
                end
            end
        end
        
        -- [NEW] 精致的"清除扇区"悬浮按钮（仅在选中扇区时显示，位于预览图右下角）
        if selected_sector_index and selected_sector_index >= 1 and selected_sector_index <= #config.sectors then
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
                local sector = config.sectors[selected_sector_index]
                if sector then
                    sector.slots = {}
                    selected_slot_index = nil
                    is_modified = true
                end
            end
            
            -- 工具提示
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_BeginTooltip(ctx)
                reaper.ImGui_Text(ctx, "清除扇区")
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
        if selected_sector_index and selected_sector_index >= 1 and selected_sector_index <= #config.sectors then
            local sector = config.sectors[selected_sector_index]
            if sector then
                reaper.ImGui_Text(ctx, "当前扇区名称:")
                reaper.ImGui_SetNextItemWidth(ctx, -1) -- Full width
                local name_buf = sector.name or ""
                local name_changed, new_name = reaper.ImGui_InputText(ctx, "##SectorName", name_buf, 256)
                if name_changed then
                    sector.name = new_name
                    is_modified = true
                end
            end
        else
            reaper.ImGui_TextDisabled(ctx, "请点击上方轮盘选择一个扇区")
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- [SECTION 2] Global Settings
        reaper.ImGui_Text(ctx, "全局设置")
        reaper.ImGui_Spacing(ctx)
        
        -- A. Sector Count (Moved to Top of Global)
        reaper.ImGui_Text(ctx, "扇区数量:")
        local sector_count = #config.sectors
        local sector_count_changed, new_count = reaper.ImGui_SliderInt(ctx, "##SectorCount", sector_count, 1, 8, "%d")
        if sector_count_changed and new_count ~= sector_count then
            M.adjust_sector_count(new_count)
            is_modified = true
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- B. Wheel Size
        reaper.ImGui_TextDisabled(ctx, "轮盘尺寸")
        
        reaper.ImGui_Text(ctx, "外半径:")
        reaper.ImGui_SameLine(ctx)
        local outer_radius = config.menu.outer_radius or 90
        local outer_radius_changed, new_outer_radius = reaper.ImGui_SliderInt(ctx, "##OuterRadius", outer_radius, 80, 300, "%d px")
        if outer_radius_changed then
            config.menu.outer_radius = new_outer_radius
            is_modified = true
        end
        
        reaper.ImGui_Text(ctx, "内半径:")
        reaper.ImGui_SameLine(ctx)
        local inner_radius = config.menu.inner_radius or 25
        local inner_radius_changed, new_inner_radius = reaper.ImGui_SliderInt(ctx, "##InnerRadius", inner_radius, 20, 100, "%d px")
        if inner_radius_changed then
            config.menu.inner_radius = new_inner_radius
            is_modified = true
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- C. Submenu Size (Stacked Vertically)
        reaper.ImGui_TextDisabled(ctx, "子菜单尺寸")
        
        reaper.ImGui_Text(ctx, "宽度:")
        reaper.ImGui_SameLine(ctx)
        local slot_w = config.menu.slot_width or 65
        local w_changed, new_w = reaper.ImGui_SliderInt(ctx, "##SlotWidth", slot_w, 60, 150, "%d px")
        if w_changed then
            config.menu.slot_width = new_w
            is_modified = true
        end
        
        reaper.ImGui_Text(ctx, "高度:")
        reaper.ImGui_SameLine(ctx)
        local slot_h = config.menu.slot_height or 25
        local h_changed, new_h = reaper.ImGui_SliderInt(ctx, "##SlotHeight", slot_h, 24, 60, "%d px")
        if h_changed then
            config.menu.slot_height = new_h
            is_modified = true
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- [SECTION 3] Interaction & Animation
        reaper.ImGui_Text(ctx, "交互与动画")
        reaper.ImGui_Spacing(ctx)
        
        -- 1. Master Animation Toggle
        local anim_enabled = config.menu.animation and config.menu.animation.enable
        if anim_enabled == nil then anim_enabled = true end
        
        local anim_changed, new_anim = reaper.ImGui_Checkbox(ctx, "启用界面动画 (Master)", anim_enabled)
        if anim_changed then
            if not config.menu.animation then config.menu.animation = {} end
            config.menu.animation.enable = new_anim
            is_modified = true
        end
        
        -- Indent animation parameters
        if anim_enabled then
            reaper.ImGui_Indent(ctx)
            
            -- Wheel Open Duration
            reaper.ImGui_Text(ctx, "开启动画时长:")
            reaper.ImGui_SameLine(ctx)
            local dur_open = config.menu.animation.duration_open or 0.06
            local dur_changed, new_dur = reaper.ImGui_SliderDouble(ctx, "##AnimDurOpen", dur_open, 0.0, 0.5, "%.2f s")
            if dur_changed then
                config.menu.animation.duration_open = new_dur
                is_modified = true
            end
            
            reaper.ImGui_Unindent(ctx)
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- 2. Sector Expansion Settings
        local expand_enabled = config.menu.enable_sector_expansion
        if expand_enabled == nil then expand_enabled = true end -- Default true
        
        local expand_changed, new_expand = reaper.ImGui_Checkbox(ctx, "启用扇区膨胀动画", expand_enabled)
        if expand_changed then
            config.menu.enable_sector_expansion = new_expand
            is_modified = true
        end
        
        if expand_enabled then
            reaper.ImGui_Indent(ctx)
            
            -- Expansion Pixels
            reaper.ImGui_Text(ctx, "膨胀幅度:")
            reaper.ImGui_SameLine(ctx)
            local exp_px = config.menu.hover_expansion_pixels or 10
            local px_changed, new_px = reaper.ImGui_SliderInt(ctx, "##ExpPixels", exp_px, 0, 30, "%d px")
            if px_changed then
                config.menu.hover_expansion_pixels = new_px
                is_modified = true
            end
            
            -- Expansion Speed (Intuitive 1-10 Scale)
            reaper.ImGui_Text(ctx, "膨胀速度:")
            reaper.ImGui_SameLine(ctx)
            local exp_spd_raw = config.menu.hover_animation_speed or 4
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
                is_modified = true
                exp_spd = new_spd  -- Update current value for label display
            end
            
            -- Helper text to explain the feel
            reaper.ImGui_SameLine(ctx)
            local speed_label = (exp_spd < 4) and "(柔和)" or ((exp_spd > 7) and "(极速)" or "(标准)")
            reaper.ImGui_TextDisabled(ctx, speed_label)
            
            reaper.ImGui_Unindent(ctx)
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- 3. Interaction
        local hover_mode = config.menu.hover_to_open or false
        local hover_changed, new_hover_mode = reaper.ImGui_Checkbox(ctx, "悬停打开子菜单", hover_mode)
        if hover_changed then
            config.menu.hover_to_open = new_hover_mode
            is_modified = true
        end
        
        reaper.ImGui_EndChild(ctx)
    end
end

-- ============================================================================
-- Phase 4 - 右侧编辑器面板（新版本：分割视图）
-- ============================================================================

-- 绘制编辑器面板（分割为两部分：网格、浏览器）
function M.draw_editor_panel_split()
    if not selected_sector_index or selected_sector_index < 1 or selected_sector_index > #config.sectors then
        reaper.ImGui_TextDisabled(ctx, "请从左侧预览中选择一个扇区进行编辑")
        return
    end
    
    local sector = config.sectors[selected_sector_index]
    if not sector then
        return
    end
    
    -- 第一部分：子菜单网格编辑器（固定高度，从顶部开始）
    if reaper.ImGui_BeginChild(ctx, "##EditorGrid", 0, 160, 1, reaper.ImGui_WindowFlags_None()) then
        M.draw_submenu_grid(sector)
        reaper.ImGui_EndChild(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- 第二部分：属性栏（Inspector）- 在网格和浏览器之间
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- 属性栏内容
    if selected_slot_index and selected_slot_index >= 1 then
        local slot = sector.slots[selected_slot_index]
        -- [FIX] Check if slot exists AND is not an "empty" placeholder
        local is_real_slot = slot and slot.type ~= "empty"
        if is_real_slot then
            -- 选中且已填充：显示编辑界面
            reaper.ImGui_AlignTextToFramePadding(ctx)
            reaper.ImGui_Text(ctx, "标签:")
            reaper.ImGui_SameLine(ctx)
            
            local name_buf = slot.name or ""
            local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
            local btn_w = reaper.ImGui_GetFrameHeight(ctx)  -- Square button
            -- Limit input width to make it look cleaner (max 300px, or remaining space if smaller)
            local input_w = math.min(300, avail_w - btn_w)
            
            -- Design: [InputBox][×] (Tightly packed)
            -- 1. Draw Input
            reaper.ImGui_SetNextItemWidth(ctx, input_w)
            -- Push style to reduce spacing for merge effect
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 0, 0)
            
            local name_changed, new_name = reaper.ImGui_InputText(ctx, "##SlotNameEdit", name_buf, 256)
            if name_changed then
                slot.name = new_name
                is_modified = true
            end
            
            reaper.ImGui_SameLine(ctx, 0, 0)
            
            -- 2. Draw Clear Button ("×")
            -- Use a slightly different color to distinguish action
            local clear_btn_color = im_utils.color_to_u32(255, 82, 82, 200)  -- Semi-transparent red
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), clear_btn_color)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), im_utils.color_to_u32(255, 112, 112, 255))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), im_utils.color_to_u32(229, 57, 53, 255))
            
            if reaper.ImGui_Button(ctx, "×", btn_w, 0) then
                sector.slots[selected_slot_index] = { type = "empty" }
                selected_slot_index = nil
                is_modified = true
            end
            
            -- Tooltip for the button
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_BeginTooltip(ctx)
                reaper.ImGui_Text(ctx, "清除此插槽内容")
                reaper.ImGui_EndTooltip(ctx)
            end
            
            reaper.ImGui_PopStyleColor(ctx, 3)
            reaper.ImGui_PopStyleVar(ctx, 1)  -- Pop ItemSpacing
        else
            -- 选中但为空：提示拖放
            reaper.ImGui_TextDisabled(ctx, "拖放 Action/FX 以分配")
        end
    else
        -- 未选中：提示选择
        reaper.ImGui_TextDisabled(ctx, "在上方选择一个插槽进行编辑，或右键点击插槽查看选项")
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- 第三部分：资源浏览器（只包含标签和搜索栏）
    local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    if reaper.ImGui_BeginChild(ctx, "##EditorBrowser", 0, 0, 1, reaper.ImGui_WindowFlags_None()) then
        M.draw_resource_browser_simplified(sector)
        reaper.ImGui_EndChild(ctx)
    end
end


-- 绘制子菜单网格编辑器（3列网格，支持拖放）
function M.draw_submenu_grid(sector)
    -- 确保 slots 数组存在
    if not sector.slots then
        sector.slots = {}
    end
    
    -- 计算需要显示的插槽数量（至少9个，可扩展）
    local min_slots = 9
    local current_slot_count = #sector.slots
    local display_count = math.max(min_slots, current_slot_count)
    
    -- 3列网格布局（严格对齐）
    local cols = 3
    local spacing = 8  -- 列间距
    local btn_h = 40  -- 固定按钮高度，更好的视觉效果
    
    -- 计算按钮宽度（动态适应3列）
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local btn_w = (avail_w - (spacing * (cols - 1))) / cols
    
    -- 绘制网格（严格3列布局）
    for i = 1, display_count do
        -- 如果不是第一列，使用 SameLine
        if (i - 1) % cols ~= 0 then
            reaper.ImGui_SameLine(ctx, 0, spacing)
        end
        
        local slot = sector.slots[i]
        local slot_id = "##Slot" .. i
        
        reaper.ImGui_PushID(ctx, slot_id)
        
        -- 检查是否选中
        local is_selected = (selected_slot_index == i)
        
        -- [FIX] Check if slot exists AND is not an "empty" placeholder
        local is_real_slot = slot and slot.type ~= "empty"
        
        -- 绘制插槽
        if is_real_slot then
            -- 已填充插槽：实心按钮样式
            local full_name = slot.name or "未命名"
            local button_label = full_name
            
            -- 计算文本宽度，如果太长则截断
            local text_width, text_height = reaper.ImGui_CalcTextSize(ctx, button_label)
            local max_text_width = btn_w - 16  -- 留出边距
            
            if text_width > max_text_width then
                -- 截断文本
                local truncated = ""
                for j = 1, string.len(button_label) do
                    local test_text = string.sub(button_label, 1, j)
                    local test_w, _ = reaper.ImGui_CalcTextSize(ctx, test_text .. "...")
                    if test_w > max_text_width then
                        truncated = string.sub(button_label, 1, j - 1) .. "..."
                        break
                    end
                end
                button_label = truncated or (string.sub(button_label, 1, 8) .. "...")
            end
            
            -- 已配置的按钮：比背景明显亮一个度（更易区分）
            local filled_bg = 0x2A2A2FFF  -- 比空插槽亮
            local filled_hovered = 0x3A3A3FFF
            local filled_active = 0x4A4A4FFF
            
            -- 如果选中，进一步高亮
            if is_selected then
                filled_bg = 0x3F3F46FF
                filled_hovered = 0x4F4F56FF
                filled_active = 0x5F5F66FF
            end
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), filled_bg)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), filled_hovered)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), filled_active)
            
            if reaper.ImGui_Button(ctx, button_label, btn_w, btn_h) then
                selected_slot_index = i
            end
            
            -- [FIX 1] Simplified Context Menu (Only Clear)
            if reaper.ImGui_BeginPopupContextItem(ctx) then
                if is_real_slot then
                    if reaper.ImGui_MenuItem(ctx, "清除插槽 (Clear)") then
                        sector.slots[i] = { type = "empty" }
                        if selected_slot_index == i then selected_slot_index = nil end
                        is_modified = true
                    end
                else
                    -- Optional: Fast add for empty slots, or just nothing
                    if reaper.ImGui_MenuItem(ctx, "添加新 Action") then
                        sector.slots[i] = { type = "action", name = "新 Action", data = { command_id = 0 } }
                        selected_slot_index = i
                        is_modified = true
                    end
                end
                reaper.ImGui_EndPopup(ctx)
            end
            
            -- [FIX 2 & 3] Delayed Tooltip with Original Info
            if is_real_slot then
                if reaper.ImGui_IsItemHovered(ctx) then
                    -- Logic: If hovering a new item, reset timer.
                    if tooltip_current_slot_id ~= i then
                        tooltip_current_slot_id = i
                        tooltip_hover_start_time = reaper.time_precise()
                    end
                    
                    -- Check for 1.0s delay
                    if (reaper.time_precise() - tooltip_hover_start_time) > 1.0 then
                        if reaper.ImGui_BeginTooltip(ctx) then
                            -- Content Generation
                            if slot.type == "action" then
                                local cmd_id = slot.data and slot.data.command_id
                                -- Fetch original name from actions cache
                                local orig_name = "Unknown Action"
                                if actions_cache then
                                    for _, action in ipairs(actions_cache) do
                                        if action.command_id == cmd_id then
                                            orig_name = action.name or "Unknown Action"
                                            break
                                        end
                                    end
                                end
                                
                                -- Format: "2020: Action: Disarm action"
                                reaper.ImGui_Text(ctx, string.format("%s: Action: %s", tostring(cmd_id), orig_name))
                                
                            elseif slot.type == "fx" then
                                local fx_name = slot.data and slot.data.fx_name or "Unknown"
                                reaper.ImGui_Text(ctx, "FX: " .. fx_name)
                                
                            elseif slot.type == "chain" then
                                local path = slot.data and slot.data.path or ""
                                local filename = path:match("([^/\\]+)$") or path
                                reaper.ImGui_Text(ctx, "Chain: " .. filename)
                                
                            elseif slot.type == "template" then
                                local path = slot.data and slot.data.path or ""
                                local filename = path:match("([^/\\]+)$") or path
                                reaper.ImGui_Text(ctx, "Template: " .. filename)
                            end
                            
                            reaper.ImGui_EndTooltip(ctx)
                        end
                    end
                else
                    -- Reset if mouse leaves this specific item
                    if tooltip_current_slot_id == i then
                        tooltip_current_slot_id = nil
                    end
                end
            end
            
            -- Pop 3 个颜色（Button, ButtonHovered, ButtonActive）
            reaper.ImGui_PopStyleColor(ctx, 3)
            
            -- [NEW] 拖拽源：允许在网格内拖拽插槽进行交换
            if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                reaper.ImGui_SetDragDropPayload(ctx, "DND_GRID_SWAP", tostring(i))
                reaper.ImGui_Text(ctx, "Move: " .. (slot.name or "Empty"))
                reaper.ImGui_EndDragDropSource(ctx)
            end
        else
            -- 空插槽：更暗的背景，一眼就能看出是空的
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x141414FF)  -- 更暗
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x1E1E1EFF)  -- 悬停时稍亮
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x282828FF)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1.0)
            
            if is_selected then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2A2A2AFF)
            end
            
            if reaper.ImGui_Button(ctx, "Empty", btn_w, btn_h) then
                -- 左键点击空插槽：选中
                selected_slot_index = i
            end
            
            -- [FIX 1] Context Menu (Right Click) - Attached directly to button
            if reaper.ImGui_BeginPopupContextItem(ctx) then
                -- Empty slot options
                if reaper.ImGui_MenuItem(ctx, "添加新 Action") then
                    sector.slots[i] = { type = "action", name = "新 Action", data = { command_id = 0 } }
                    selected_slot_index = i
                    is_modified = true
                end
                reaper.ImGui_EndPopup(ctx)
            end
            
            if is_selected then
                reaper.ImGui_PopStyleColor(ctx, 1)
            end
            
            reaper.ImGui_PopStyleVar(ctx)
            reaper.ImGui_PopStyleColor(ctx, 3)
            
            -- [NEW] 拖拽源：空插槽也可以拖拽（用于交换位置）
            if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                reaper.ImGui_SetDragDropPayload(ctx, "DND_GRID_SWAP", tostring(i))
                reaper.ImGui_Text(ctx, "Move: Empty")
                reaper.ImGui_EndDragDropSource(ctx)
            end
        end
        
        -- 设置插槽为拖放目标（在按钮之后，绑定到按钮）
        -- 支持覆盖已有内容：直接设置新值，无论插槽是否已有内容
        if reaper.ImGui_BeginDragDropTarget(ctx) then
            -- [NEW] 优先处理网格内交换
            local ret_swap, payload_swap = reaper.ImGui_AcceptDragDropPayload(ctx, "DND_GRID_SWAP")
            if ret_swap and payload_swap then
                local source_idx = tonumber(payload_swap)
                local target_idx = i
                if source_idx and source_idx ~= target_idx and source_idx >= 1 and source_idx <= display_count then
                    -- SWAP
                    local temp = sector.slots[source_idx]
                    sector.slots[source_idx] = sector.slots[target_idx]
                    sector.slots[target_idx] = temp
                    
                    -- 如果选中的插槽被交换，更新选中索引
                    if selected_slot_index == source_idx then
                        selected_slot_index = target_idx
                    elseif selected_slot_index == target_idx then
                        selected_slot_index = source_idx
                    end
                    
                    is_modified = true
                end
            else
                -- 处理外部拖放（Action/FX）
                local ret, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "DND_ACTION")
                if ret then
                    -- 处理 Action 拖放（payload 格式: "command_id|name"）
                    if payload then
                        local parts = {}
                        for part in string.gmatch(payload, "[^|]+") do
                            table.insert(parts, part)
                        end
                        if #parts >= 2 then
                            local cmd_id = tonumber(parts[1]) or 0
                            local name = parts[2] or ""
                            -- 直接覆盖，无论插槽是否已有内容
                            sector.slots[i] = {
                                type = "action",
                                name = name,
                                data = {command_id = cmd_id}
                            }
                            selected_slot_index = i  -- 自动选中该插槽
                            is_modified = true
                        end
                    end
                else
                    ret, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "DND_FX")
                    if ret then
                        -- 处理 FX/Chain/Template 拖放（payload 格式: "type|id"）
                        if payload then
                            local parts = {}
                            for part in string.gmatch(payload, "[^|]+") do
                                table.insert(parts, part)
                            end
                            
                            if #parts >= 2 then
                                local payload_type = parts[1]  -- fx, chain, template
                                local payload_id = parts[2]    -- original_name, path, etc.
                                
                                -- 根据类型创建不同的插槽数据
                                if payload_type == "chain" then
                                    sector.slots[i] = {
                                        type = "chain",
                                        name = payload_id:match("([^/\\]+)%.RfxChain$") or payload_id,
                                        data = {path = payload_id}
                                    }
                                elseif payload_type == "template" then
                                    sector.slots[i] = {
                                        type = "template",
                                        name = payload_id:match("([^/\\]+)%.RTrackTemplate$") or payload_id,
                                        data = {path = payload_id}
                                    }
                                else
                                    -- 默认 FX
                                    sector.slots[i] = {
                                        type = "fx",
                                        name = payload_id:gsub("^[^:]+: ", ""),  -- 移除前缀
                                        data = {fx_name = payload_id}
                                    }
                                end
                                
                                selected_slot_index = i  -- 自动选中该插槽
                                is_modified = true
                            else
                                -- 兼容旧格式（只有 fx_name）
                                sector.slots[i] = {
                                    type = "fx",
                                    name = payload,
                                    data = {fx_name = payload}
                                }
                                selected_slot_index = i
                                is_modified = true
                            end
                        end
                    end
                end
            end
            reaper.ImGui_EndDragDropTarget(ctx)
        end
        
        reaper.ImGui_PopID(ctx)
    end
    
    -- 添加 "+" 按钮（扩展插槽）
    if (display_count % cols) ~= 0 then
        reaper.ImGui_SameLine(ctx, 0, spacing)
    end
    
    if reaper.ImGui_Button(ctx, "+", btn_w, btn_h) then
        -- 添加新插槽
        table.insert(sector.slots, {
            type = "action",
            name = "新插槽",
            data = {command_id = 0}
        })
        is_modified = true
    end
end

-- 绘制资源浏览器（简化版：固定头部，防止搜索栏滚动）
function M.draw_resource_browser_simplified(sector)
    -- 标签栏（直接绘制在父窗口中，不滚动）
    if reaper.ImGui_BeginTabBar(ctx, "##ResourceTabs", reaper.ImGui_TabBarFlags_None()) then
        -- Actions 标签页
        if reaper.ImGui_BeginTabItem(ctx, "Actions") then
            browser_tab = 0
            reaper.ImGui_EndTabItem(ctx)
        end
        
        -- FX 标签页
        if reaper.ImGui_BeginTabItem(ctx, "FX") then
            browser_tab = 1
            reaper.ImGui_EndTabItem(ctx)
        end
        
        reaper.ImGui_EndTabBar(ctx)
    end
    
    -- 绘制标签页内容（搜索栏和列表在各自的函数中处理）
    if browser_tab == 0 then
        -- Actions 标签页内容
        M.draw_action_browser()
    else
        -- FX 标签页内容
        M.draw_fx_browser()
    end
end

-- 绘制资源浏览器（标签页：Actions / FX，属性栏合并到标签栏）
function M.draw_resource_browser_with_properties(sector)
    -- 标签栏
    if reaper.ImGui_BeginTabBar(ctx, "##ResourceTabs", reaper.ImGui_TabBarFlags_None()) then
        -- Actions 标签页
        if reaper.ImGui_BeginTabItem(ctx, "Actions") then
            browser_tab = 0
            reaper.ImGui_EndTabItem(ctx)
        end
        
        -- FX 标签页
        if reaper.ImGui_BeginTabItem(ctx, "FX") then
            browser_tab = 1
            reaper.ImGui_EndTabItem(ctx)
        end
        
        reaper.ImGui_EndTabBar(ctx)
    end
    
    -- 在同一行右侧绘制属性编辑器（在标签栏之后）
    reaper.ImGui_SameLine(ctx, 0, 8)
    
    -- 修复垂直对齐（关键：确保与标签栏对齐）
    reaper.ImGui_AlignTextToFramePadding(ctx)
    
    -- 计算可用宽度和组件尺寸
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local clear_btn_w = 50
    local label_text = "名称:"
    local label_w, label_h = reaper.ImGui_CalcTextSize(ctx, label_text)
    local spacing_total = 20  -- 总间距（标签、输入框、按钮之间的间距）
    local input_w = math.max(100, avail_w - label_w - clear_btn_w - spacing_total)  -- 确保最小宽度
    
    -- 检查是否有选中的插槽
    if selected_slot_index and selected_slot_index >= 1 then
        local slot = sector.slots[selected_slot_index]
        
        if slot then
            -- 选中且已填充：显示编辑界面
            reaper.ImGui_Text(ctx, label_text)
            reaper.ImGui_SameLine(ctx)
            
            local name_buf = slot.name or ""
            reaper.ImGui_SetNextItemWidth(ctx, input_w)
            local name_changed, new_name = reaper.ImGui_InputText(ctx, "##SlotNameEdit", name_buf, 256)
            if name_changed then
                slot.name = new_name
                is_modified = true
            end
            
            reaper.ImGui_SameLine(ctx, 0, 4)
            if reaper.ImGui_Button(ctx, "清除", clear_btn_w, 0) then
                sector.slots[selected_slot_index] = nil
                selected_slot_index = nil
                is_modified = true
            end
        else
            -- 选中但为空：提示拖放
            reaper.ImGui_TextDisabled(ctx, "拖放 Action/FX 以分配")
        end
    else
        -- 未选中：提示选择
        reaper.ImGui_TextDisabled(ctx, "选择插槽以编辑")
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- 绘制标签页内容
    if browser_tab == 0 then
        -- Actions 标签页内容
        M.draw_action_browser()
    else
        -- FX 标签页内容
        M.draw_fx_browser()
    end
end

-- 绘制资源浏览器（标签页：Actions / FX）（保留用于兼容）
function M.draw_resource_browser()
    -- 标签页
    if reaper.ImGui_BeginTabBar(ctx, "##ResourceTabs", reaper.ImGui_TabBarFlags_None()) then
        -- Actions 标签页
        if reaper.ImGui_BeginTabItem(ctx, "Actions") then
            browser_tab = 0
            M.draw_action_browser()
            reaper.ImGui_EndTabItem(ctx)
        end
        
        -- FX 标签页
        if reaper.ImGui_BeginTabItem(ctx, "FX") then
            browser_tab = 1
            M.draw_fx_browser()
            reaper.ImGui_EndTabItem(ctx)
        end
        
        reaper.ImGui_EndTabBar(ctx)
    end
end

-- 绘制 Action 浏览器（高性能，使用 ListClipper，固定头部）
function M.draw_action_browser()
    -- 搜索框（在 Child 外面，不滚动）
    local search_changed, new_search = reaper.ImGui_InputText(ctx, "##ActionSearch", action_search_text, 256)
    if search_changed then
        action_search_text = new_search
        -- 重新过滤
        actions_filtered = M.filter_actions(action_search_text)
    elseif #actions_filtered == 0 then
        -- 初始化过滤列表
        actions_filtered = M.filter_actions(action_search_text)
    end
    
    -- 列表区域（可滚动）
    local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    if reaper.ImGui_BeginChild(ctx, "ActionList", 0, 0, 1, reaper.ImGui_WindowFlags_None()) then
        -- 使用 ListClipper 进行高性能渲染
        -- 使用 ValidatePtr 验证 ListClipper 是否有效，避免频繁创建
        if not reaper.ImGui_ValidatePtr(action_list_clipper, 'ImGui_ListClipper*') then
            action_list_clipper = reaper.ImGui_CreateListClipper(ctx)
        end
        
        if action_list_clipper then
            reaper.ImGui_ListClipper_Begin(action_list_clipper, #actions_filtered)
            while reaper.ImGui_ListClipper_Step(action_list_clipper) do
                local display_start, display_end = reaper.ImGui_ListClipper_GetDisplayRange(action_list_clipper)
                
                for i = display_start, display_end - 1 do
                    if i + 1 <= #actions_filtered then
                        local action = actions_filtered[i + 1]
                        local item_label = string.format("%d: %s", action.command_id, action.name or "")
                        
                        -- 先渲染 Selectable
                        if reaper.ImGui_Selectable(ctx, item_label, false, reaper.ImGui_SelectableFlags_None(), 0, 0) then
                            -- 点击选择（可选功能）
                        end
                        
                        -- 然后在 Selectable 之后设置为拖放源
                        if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                            local payload_data = string.format("%d|%s", action.command_id, action.name or "")
                            reaper.ImGui_SetDragDropPayload(ctx, "DND_ACTION", payload_data)
                            reaper.ImGui_Text(ctx, item_label)
                            reaper.ImGui_EndDragDropSource(ctx)
                        end
                    end
                end
            end
            reaper.ImGui_ListClipper_End(action_list_clipper)
        end
        
        reaper.ImGui_EndChild(ctx)
    end
end

-- 绘制 FX 浏览器（分类版本，固定头部）
function M.draw_fx_browser()
    -- 定义过滤器按钮
    local filters = {"All", "VST", "VST3", "JS", "AU", "CLAP", "LV2", "Chain", "Template"}
    
    -- 绘制过滤器按钮（水平排列，在 Child 外面）
    for _, filter in ipairs(filters) do
        local is_selected = (current_fx_filter == filter)
        if is_selected then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x3F3F46FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x4F4F56FF)
        end
        
        if reaper.ImGui_Button(ctx, filter, 0, 0) then
            current_fx_filter = filter
        end
        
        if is_selected then
            reaper.ImGui_PopStyleColor(ctx, 2)
        end
        
        reaper.ImGui_SameLine(ctx, 0, 4)
    end
    
    -- 搜索框（紧跟在过滤器按钮后，同一行）
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local search_w = math.max(150, avail_w - 8)  -- 至少 150 像素宽
    reaper.ImGui_SetNextItemWidth(ctx, search_w)
    local search_changed, new_search = reaper.ImGui_InputText(ctx, "##FXSearch", fx_search_text, 256)
    if search_changed then
        fx_search_text = new_search
    end
    
    -- 准备显示列表（根据过滤器）
    local display_list = {}
    
    if current_fx_filter == "Template" then
        display_list = utils_fx.get_track_templates()
    elseif current_fx_filter == "Chain" then
        display_list = utils_fx.get_fx_chains()
    else
        -- 标准 FX，按类型过滤
        local all_fx = utils_fx.get_all_fx()
        for _, fx in ipairs(all_fx) do
            if current_fx_filter == "All" or fx.type == current_fx_filter then
                table.insert(display_list, fx)
            end
        end
    end
    
    -- 应用搜索过滤
    if fx_search_text and fx_search_text ~= "" then
        local filtered = {}
        local lower_search = string.lower(fx_search_text)
        for _, item in ipairs(display_list) do
            local name = item.name or ""
            if string.find(string.lower(name), lower_search, 1, true) then
                table.insert(filtered, item)
            end
        end
        display_list = filtered
    end
    
    -- 列表区域（可滚动）
    if reaper.ImGui_BeginChild(ctx, "FXList", 0, 0, 1, reaper.ImGui_WindowFlags_None()) then
        -- 使用 ListClipper 进行高性能渲染
        if not reaper.ImGui_ValidatePtr(fx_list_clipper, 'ImGui_ListClipper*') then
            fx_list_clipper = reaper.ImGui_CreateListClipper(ctx)
        end
        
        if fx_list_clipper then
            reaper.ImGui_ListClipper_Begin(fx_list_clipper, #display_list)
            while reaper.ImGui_ListClipper_Step(fx_list_clipper) do
                local display_start, display_end = reaper.ImGui_ListClipper_GetDisplayRange(fx_list_clipper)
                
                for i = display_start, display_end - 1 do
                    if i + 1 <= #display_list then
                        local item = display_list[i + 1]
                        local item_label = item.name or "未命名"
                        
                        -- 添加类型标签（如果有）
                        if item.type and item.type ~= "Other" then
                            item_label = string.format("[%s] %s", item.type, item_label)
                        end
                        
                        -- 渲染 Selectable
                        if reaper.ImGui_Selectable(ctx, item_label, false, reaper.ImGui_SelectableFlags_None(), 0, 0) then
                            -- 点击选择（可选功能）
                        end
                        
                        -- 设置为拖放源
                        if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                            -- 根据类型设置不同的 payload
                            local payload_type = "fx"
                            local payload_id = item.original_name or item.name
                            
                            if current_fx_filter == "Chain" or item.type == "Chain" then
                                payload_type = "chain"
                                payload_id = item.path or item.name
                            elseif current_fx_filter == "Template" or item.type == "TrackTemplate" then
                                payload_type = "template"
                                payload_id = item.path or item.name
                            end
                            
                            -- Payload 格式: "type|id"
                            local payload_data = string.format("%s|%s", payload_type, payload_id)
                            reaper.ImGui_SetDragDropPayload(ctx, "DND_FX", payload_data)
                            reaper.ImGui_Text(ctx, item_label)
                            reaper.ImGui_EndDragDropSource(ctx)
                        end
                    end
                end
            end
            reaper.ImGui_ListClipper_End(fx_list_clipper)
        end
        
        -- 如果列表为空，显示提示
        if #display_list == 0 then
            reaper.ImGui_TextDisabled(ctx, string.format("未找到匹配的 %s", current_fx_filter))
        end
        
        reaper.ImGui_EndChild(ctx)
    end
end


-- ============================================================================
-- Phase 4 - 插槽编辑
-- ============================================================================

-- 绘制单个插槽的编辑器
-- @param slot table: 插槽数据（可能为 nil）
-- @param index number: 插槽索引
-- @param sector table: 所属扇区
function M.draw_slot_editor(slot, index, sector)
    local header_text = string.format("插槽 %d", index)
    
    if not slot then
        reaper.ImGui_TextDisabled(ctx, header_text .. " (空)")
        return
    end
    
    reaper.ImGui_Text(ctx, header_text)
    reaper.ImGui_SameLine(ctx)
    
    -- 删除按钮
    if reaper.ImGui_Button(ctx, "删除##Slot" .. index, 0, 0) then
        sector.slots[index] = nil
        is_modified = true
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- 标签输入
    reaper.ImGui_Text(ctx, "  标签:")
    reaper.ImGui_SameLine(ctx)
    local name_buf = slot.name or ""
    local name_changed, new_name = reaper.ImGui_InputText(ctx, "##SlotName" .. index, name_buf, 256)
    if name_changed then
        slot.name = new_name
        is_modified = true
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- 类型下拉框
    reaper.ImGui_Text(ctx, "  类型:")
    reaper.ImGui_SameLine(ctx)
    local type_options = {"action", "fx", "script"}
    local current_type = slot.type or "action"
    local current_type_display = current_type
    
    -- 使用 BeginCombo/EndCombo
    if reaper.ImGui_BeginCombo(ctx, "##SlotType" .. index, current_type_display, reaper.ImGui_ComboFlags_None()) then
        for i, opt in ipairs(type_options) do
            local is_selected = (opt == current_type)
            if reaper.ImGui_Selectable(ctx, opt, is_selected, reaper.ImGui_SelectableFlags_None(), 0, 0) then
                slot.type = opt
                -- 重置 data 字段
                if slot.type == "action" then
                    slot.data = {command_id = 0}
                elseif slot.type == "fx" then
                    slot.data = {fx_name = ""}
                elseif slot.type == "script" then
                    slot.data = {script_path = ""}
                end
                is_modified = true
            end
            if is_selected then
                reaper.ImGui_SetItemDefaultFocus(ctx)
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- 根据类型显示不同的输入字段
    if slot.type == "action" then
        reaper.ImGui_Text(ctx, "  Command ID:")
        reaper.ImGui_SameLine(ctx)
        local cmd_id = slot.data and slot.data.command_id or 0
        local cmd_id_changed, new_cmd_id = reaper.ImGui_InputInt(ctx, "##SlotValue" .. index, cmd_id, 1, 100)
        if cmd_id_changed then
            if not slot.data then slot.data = {} end
            slot.data.command_id = new_cmd_id
            is_modified = true
        end
        
    elseif slot.type == "fx" then
        reaper.ImGui_Text(ctx, "  FX 名称:")
        reaper.ImGui_SameLine(ctx)
        local fx_name = slot.data and slot.data.fx_name or ""
        local fx_name_changed, new_fx_name = reaper.ImGui_InputText(ctx, "##SlotValue" .. index, fx_name, 256)
        if fx_name_changed then
            if not slot.data then slot.data = {} end
            slot.data.fx_name = new_fx_name
            is_modified = true
        end
        
    elseif slot.type == "script" then
        reaper.ImGui_Text(ctx, "  脚本路径:")
        reaper.ImGui_SameLine(ctx)
        local script_path = slot.data and slot.data.script_path or ""
        local script_path_changed, new_script_path = reaper.ImGui_InputText(ctx, "##SlotValue" .. index, script_path, 512)
        if script_path_changed then
            if not slot.data then slot.data = {} end
            slot.data.script_path = new_script_path
            is_modified = true
        end
    end
    
    -- 描述输入
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "  描述:")
    reaper.ImGui_SameLine(ctx)
    local desc_buf = slot.description or ""
    local desc_changed, new_desc = reaper.ImGui_InputText(ctx, "##SlotDesc" .. index, desc_buf, 256)
    if desc_changed then
        slot.description = new_desc
        is_modified = true
    end
end

-- ============================================================================
-- Phase 4 - 底部操作栏
-- ============================================================================

-- 绘制底部操作栏（稳定布局）
function M.draw_action_bar()
    -- 左侧：按钮组（紧密排列）
    local save_btn_color = im_utils.color_to_u32(66, 165, 245, 200)  -- #42A5F5
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), save_btn_color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), im_utils.color_to_u32(100, 181, 246, 255))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), im_utils.color_to_u32(30, 136, 229, 255))
    if reaper.ImGui_Button(ctx, "保存", 0, 0) then
        if M.save_config() then
            save_feedback_time = os.time()
            -- [REMOVED] MessageBox - replaced with green text feedback
        end
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    
    reaper.ImGui_SameLine(ctx, 0, 4)
    
    -- 丢弃按钮
    if reaper.ImGui_Button(ctx, "丢弃", 0, 0) then
        M.discard_changes()
    end
    
    reaper.ImGui_SameLine(ctx, 0, 4)
    
    -- 重置按钮（使用警告颜色）
    local reset_btn_color = im_utils.color_to_u32(255, 82, 82, 200)  -- #FF5252
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reset_btn_color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), im_utils.color_to_u32(255, 112, 112, 255))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), im_utils.color_to_u32(229, 57, 53, 255))
    if reaper.ImGui_Button(ctx, "重置", 0, 0) then
        M.reset_to_default()
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    
    -- 状态文本（绝对定位，不影响按钮布局）
    local current_time = os.time()
    local status_text = ""
    local status_color = 0
    
    if current_time - save_feedback_time < 2 then
        status_text = "✔ 配置已保存"
        status_color = 0x4CAF50FF  -- Green
    elseif is_modified then
        status_text = "* 有未保存的更改"
        status_color = 0xFFC800FF  -- Yellow
    end
    
    if status_text ~= "" then
        local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, status_text)
        local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
        -- Align to right with 20px padding
        reaper.ImGui_SameLine(ctx)  -- Keep on same line technically to share height
        reaper.ImGui_SetCursorPosX(ctx, win_w - text_w - 20)
        reaper.ImGui_TextColored(ctx, status_color, status_text)
    end
end

-- ============================================================================
-- Phase 4 - 配置操作
-- ============================================================================

-- 保存配置到文件
-- @return boolean: 是否保存成功
function M.save_config()
    -- [FIX] Preserve slot positions by filling gaps with "empty" placeholders
    for _, sector in ipairs(config.sectors) do
        if sector.slots then
            local fixed_slots = {}
            local max_index = config.menu.max_slots_per_sector or 9
            
            for i = 1, max_index do
                if sector.slots[i] and sector.slots[i].type ~= "empty" then
                    table.insert(fixed_slots, sector.slots[i])
                else
                    -- Insert placeholder to keep the array index alignment in JSON
                    table.insert(fixed_slots, { type = "empty" })
                end
            end
            sector.slots = fixed_slots
        end
    end
    
    -- 保存配置（config_manager.save() 内部会发出更新信号）
    local success = config_manager.save(config)
    if success then
        is_modified = false
        original_config = M.deep_copy_config(config)
        save_feedback_time = os.time() -- Trigger green feedback
        return true
    else
        -- Keep error message for actual failures
        reaper.ShowMessageBox("配置保存失败", "错误", 0)
        return false
    end
end

-- 丢弃更改，重新加载配置
function M.discard_changes()
    if is_modified then
        local result = reaper.ShowMessageBox(
            "确定要丢弃所有未保存的更改吗？",
            "确认",
            4  -- 4 = Yes/No
        )
        if result == 6 then  -- 6 = Yes
            config = M.deep_copy_config(original_config)
            is_modified = false
            selected_sector_index = nil
            -- reaper.ShowConsoleMsg("已丢弃更改\n")
        end
    end
end

-- 重置为默认配置
function M.reset_to_default()
    local result = reaper.ShowMessageBox(
        "确定要重置为默认配置吗？这将丢失所有自定义设置。",
        "确认",
        4  -- 4 = Yes/No
    )
    if result == 6 then  -- 6 = Yes
        config = config_manager.get_default()
        original_config = M.deep_copy_config(config)
        is_modified = true
        selected_sector_index = nil
        selected_slot_index = nil
        styles.init_from_config(config)
        -- reaper.ShowConsoleMsg("已重置为默认配置\n")
    end
end

-- 调整扇区数量（带数据保留功能）
function M.adjust_sector_count(new_count)
    local current_count = #config.sectors
    
    if new_count == current_count then return end
    
    if new_count < current_count then
        -- [减少扇区]：先备份，再删除
        for i = current_count, new_count + 1, -1 do
            -- 备份到缓存（深拷贝以确保数据安全）
            removed_sector_stash[i] = M.deep_copy_config(config.sectors[i])
            table.remove(config.sectors, i)
        end
        -- 如果当前选中的扇区被删除了，取消选择
        if selected_sector_index and selected_sector_index > new_count then
            selected_sector_index = nil
            selected_slot_index = nil
        end
        
    elseif new_count > current_count then
        -- [增加扇区]：优先从缓存恢复
        for i = current_count + 1, new_count do
            if removed_sector_stash[i] then
                -- 1. 尝试从缓存恢复
                local restored_sector = M.deep_copy_config(removed_sector_stash[i])
                -- 确保 ID 正确（防止乱序）
                restored_sector.id = i
                table.insert(config.sectors, restored_sector)
            else
                -- 2. 缓存里没有，创建新的默认扇区
                table.insert(config.sectors, {
                    id = i,
                    name = "扇区 " .. i,
                    color = {26, 26, 26, 180},  -- Default dark gray
                    slots = {}
                })
            end
        end
    end
    
    -- 更新 ID（双重保险）
    for i, sector in ipairs(config.sectors) do
        sector.id = i
    end
end

-- ============================================================================
-- Phase 4 - 清理
-- ============================================================================

-- 清理资源
function M.cleanup()
    if is_modified then
        local result = reaper.ShowMessageBox(
            "有未保存的更改，确定要关闭吗？",
            "确认",
            4  -- 4 = Yes/No
        )
        if result ~= 6 then  -- 6 = Yes. If user clicked "No" or closed dialog
            is_open = true  -- 保持打开
            reaper.defer(M.loop)  -- [FIX] CRITICAL: Restart the loop immediately!
            return
        end
    end
    
    -- 清除设置窗口打开标记
    reaper.SetExtState("RadialMenu", "SettingsOpen", "0", false)
    
    if ctx then
        if reaper.ImGui_DestroyContext then
            reaper.ImGui_DestroyContext(ctx)
        end
        ctx = nil
    end
    
    config = nil
    original_config = nil
    is_open = false
    is_modified = false
    selected_sector_index = nil
    selected_slot_index = nil  -- 清理选中的插槽索引
    action_list_clipper = nil  -- 清理 ListClipper 缓存
    fx_list_clipper = nil  -- 清理 FX ListClipper 缓存
    tooltip_hover_start_time = 0  -- 重置 Tooltip 状态
    tooltip_current_slot_id = nil  -- 重置 Tooltip 状态
    
    -- reaper.ShowConsoleMsg("设置编辑器已关闭\n")
end

-- ============================================================================
-- Phase 4 - 启动
-- ============================================================================

-- 显示设置编辑器窗口
function M.show()
    if M.init() then
        M.loop()
    else
        -- reaper.ShowConsoleMsg("设置编辑器启动失败\n")
    end
end

-- ============================================================================
-- Action 数据管理
-- ============================================================================

-- 加载所有 Reaper Actions（缓存）
-- @return table: Action 列表，每个元素包含 {command_id, name}
function M.load_actions()
    if actions_cache then
        return actions_cache
    end
    
    actions_cache = {}
    local i = 0
    
    -- 使用 CF_EnumerateActions 枚举所有 Actions
    while true do
        local command_id, name = reaper.CF_EnumerateActions(0, i, '')
        if not command_id or command_id <= 0 then
            break
        end
        table.insert(actions_cache, {
            command_id = command_id,
            name = name or ""
        })
        i = i + 1
    end
    
    -- 按名称排序
    table.sort(actions_cache, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    
    return actions_cache
end

-- 过滤 Actions
-- @param search_text string: 搜索文本
-- @return table: 过滤后的 Action 列表
function M.filter_actions(search_text)
    if not actions_cache then
        M.load_actions()
    end
    
    if not search_text or search_text == "" then
        return actions_cache
    end
    
    local filtered = {}
    
    -- Split search text into tokens (by space)
    local tokens = {}
    for token in string.gmatch(string.lower(search_text), "%S+") do
        table.insert(tokens, token)
    end
    
    for _, action in ipairs(actions_cache) do
        local name_lower = string.lower(action.name or "")
        local id_str = tostring(action.command_id)
        
        local match_all = true
        for _, token in ipairs(tokens) do
            -- Check if token exists in Name OR Command ID
            local found_in_name = string.find(name_lower, token, 1, true)
            local found_in_id = string.find(id_str, token, 1, true)
            
            if not (found_in_name or found_in_id) then
                match_all = false
                break
            end
        end
        
        if match_all then
            table.insert(filtered, action)
        end
    end
    
    return filtered
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

-- 简化的预览绘制（避免 wheel.draw_wheel 的交互检测导致卡死）
-- 使用与 wheel.lua 相同的间隙逻辑
function M.draw_simple_preview(draw_list, ctx, center_x, center_y, preview_config, selected_index)
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
        -- 绘制文本
        local text_radius = outer_radius * (styles.sizes.text_radius_ratio or 0.65)
        local center_angle = (start_angle + end_angle) / 2
        local tx, ty = math_utils.polar_to_cartesian(center_angle, text_radius)
        local display_text = (sector.name or "")
        
        local text_color = is_selected and styles.correct_rgba_to_u32(styles.colors.text_active) or styles.correct_rgba_to_u32(styles.colors.text_normal)
        local shadow_color = styles.correct_rgba_to_u32(styles.colors.text_shadow)
        
        local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, display_text)
        local text_x = center_x + tx - text_w / 2
        local text_y = center_y + ty - text_h / 2
        
        -- 绘制阴影和文本
        reaper.ImGui_DrawList_AddText(draw_list, text_x + 1, text_y + 1, shadow_color, display_text)
        reaper.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, display_text)
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

-- 深拷贝配置表
function M.deep_copy_config(src)
    if type(src) ~= "table" then
        return src
    end
    
    local dst = {}
    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = M.deep_copy_config(value)
        else
            dst[key] = value
        end
    end
    
    -- 处理数组部分
    if #src > 0 then
        for i = 1, #src do
            if type(src[i]) == "table" then
                dst[i] = M.deep_copy_config(src[i])
            else
                dst[i] = src[i]
            end
        end
    end
    
    return dst
end

return M
