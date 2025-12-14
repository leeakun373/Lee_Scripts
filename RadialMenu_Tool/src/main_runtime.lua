-- @description RadialMenu Tool - 主运行时
-- @author Lee
-- @about
--   轮盘菜单的主循环
--   优化：解决遮挡问题，优化拖拽手感

local M = {}

-- 加载依赖模块
local config_manager = require("config_manager")
local wheel = require("wheel")
local list_view = require("list_view")
local styles = require("styles")
local math_utils = require("math_utils")
local execution = require("execution")

-- 运行时状态
local ctx = nil
local config = nil
local is_open = false
local window_width = 500
local window_height = 500
local clicked_sector = nil
local show_submenu = false
local is_pinned = false
-- 拖拽跟踪（用于区分点击和拖拽）
local center_drag_started = false

-- 窗口定位辅助
local is_first_display = true

-- 长按模式相关变量
local SCRIPT_START_TIME = nil
local KEY = nil
local KEY_START_STATE = nil

-- 配置热重载跟踪
local last_config_update_time = nil

-- 动画状态变量
local anim_open_start_time = 0
local anim_submenu_start_time = 0
local last_submenu_state = false
local last_active_sector_id = nil
-- 扇区扩展动画状态（每个扇区ID对应一个0.0-1.0的进度值）
local sector_anim_states = {}

-- [Context Tracking] 记录最后一次有效的 Context
-- 用于解决 ImGui 抢走焦点导致 GetCursorContext 返回不准确的问题
local last_valid_context = -1

-- ============================================================================
-- Phase 2 - 初始化
-- ============================================================================

function M.init()
    -- Force clear "Running" state on startup to fix "Script not opening" issues
    reaper.SetExtState("RadialMenu_Tool", "Running", "0", false)
    
    local ext_state = reaper.GetExtState("RadialMenu_Tool", "Running")
    if ext_state == "1" then return false end
    
    reaper.SetExtState("RadialMenu_Tool", "Running", "1", false)
    
    reaper.atexit(function()
        reaper.SetExtState("RadialMenu_Tool", "Running", "0", false)
        -- 释放按键拦截
        if KEY and reaper.JS_VKeys_Intercept then
            reaper.JS_VKeys_Intercept(KEY, -1)
        end
        if ctx and reaper.ImGui_DestroyContext then
            reaper.ImGui_DestroyContext(ctx)
        end
    end)
    
    if not reaper.ImGui_CreateContext then
        reaper.ShowMessageBox("错误: ReaImGui 未安装", "初始化失败", 0)
        return false
    end
    
    -- 检查 JS_VKeys API 是否可用（用于按键检测）
    if not reaper.JS_VKeys_GetState then
        reaper.ShowMessageBox("错误: JS_ReaScriptAPI 扩展未安装\n\n请安装 JS_ReaScriptAPI 扩展以支持长按模式", "初始化失败", 0)
        return false
    end
    
    ctx = reaper.ImGui_CreateContext("RadialMenu_Wheel", reaper.ImGui_ConfigFlags_None())
    config = config_manager.load()
    styles.init_from_config(config)
    
    -- 静默模式：不打开控制台，不输出启动消息
    
    -- 窗口大小与轮盘一致，只留少量边距（子菜单作为独立窗口显示）
    local diameter = config.menu.outer_radius * 2 + 20  -- 只留 10 像素边距（每边）
    window_width = diameter
    window_height = diameter
    
    -- 记录脚本启动时间
    SCRIPT_START_TIME = reaper.time_precise()
    
    -- 初始化动画开始时间
    anim_open_start_time = reaper.time_precise()
    anim_submenu_start_time = 0
    last_submenu_state = false
    
    -- 初始化启动时默认展开的扇区
    if config.menu.start_sectors then
        for _, sector_id in ipairs(config.menu.start_sectors) do
            sector_anim_states[sector_id] = 1.0  -- 直接设置为完全展开状态
        end
    end
    
    -- 检测并拦截触发按键（参考 Sexan_Pie3000 的实现）
    local key_state = reaper.JS_VKeys_GetState(SCRIPT_START_TIME - 1)
    local down_state = reaper.JS_VKeys_GetDown(SCRIPT_START_TIME)
    for i = 1, 255 do
        if key_state:byte(i) ~= 0 or down_state:byte(i) ~= 0 then
            if reaper.JS_VKeys_Intercept then
                reaper.JS_VKeys_Intercept(i, 1)  -- 拦截按键
            end
            KEY = i
            break
        end
    end
    
    if not KEY then
        reaper.ShowMessageBox("错误: 无法检测到触发按键", "初始化失败", 0)
        return false
    end
    
    -- 不再需要 gfx 窗口，使用 ImGui 原生按键检测
    is_open = true
    return true
end

-- ============================================================================
-- Phase 2 - 按键检测函数
-- ============================================================================

-- 检测按键是否仍然被按住
local function KeyHeld()
    if not KEY or not SCRIPT_START_TIME then return false end
    if not reaper.JS_VKeys_GetState then return false end
    local key_state = reaper.JS_VKeys_GetState(SCRIPT_START_TIME - 1)
    return key_state:byte(KEY) == 1
end

-- 跟踪快捷键状态，如果松开则关闭窗口（除非已 Pin 住）
local function TrackShortcutKey()
    if not KeyHeld() then
        -- 按键已松开，但如果已 Pin 住，则不关闭窗口
        if not is_pinned then
            M.cleanup()
            return false
        end
        -- 如果已 Pin 住，继续运行
    end
    return true
end

-- ============================================================================
-- Phase 2 - 主循环
-- ============================================================================

function M.loop()
    if not ctx then return end
    
    -- [核心] 配置热重载检测
    local current_update_time = reaper.GetExtState("RadialMenu", "ConfigUpdated")
    if current_update_time and current_update_time ~= "" then
        if last_config_update_time == nil then
            -- 首次运行，初始化时间戳
            last_config_update_time = current_update_time
        elseif last_config_update_time ~= current_update_time then
            -- 配置已更新，重新加载
            config = config_manager.load()
            if config then
                styles.init_from_config(config)
                -- 更新窗口尺寸（如果配置中的尺寸改变了）
                local diameter = config.menu.outer_radius * 2 + 20
                window_width = diameter
                window_height = diameter
            end
            last_config_update_time = current_update_time
        end
    end
    
    -- [核心] 长按模式：检测按键是否仍然被按住
    if not TrackShortcutKey() then
        return
    end
    
    -- ESC 键关闭窗口（使用 ImGui 原生检测，除非已 Pin 住）
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then 
        if not is_pinned then
            M.cleanup()
            return
        end
        -- [核心] 拖拽逻辑锁：如果正在拖拽，ESC 键不关闭子菜单
        if not list_view.is_dragging() then
            -- 如果已 Pin 住，ESC 键不关闭窗口，只关闭子菜单
            show_submenu = false
            clicked_sector = nil
        end
    end
    
    -- [Context Tracking] 持续更新 Context
    -- 只有当 Context 明确为 Tracks (0) 或 Items (1) 或 Envelopes (2) 时才更新
    -- 忽略 -1 (无效/无焦点) 或其他值
    local current_context = reaper.GetCursorContext()
    if current_context >= 0 and current_context <= 2 then
        last_valid_context = current_context
    end
    
    -- 将 last_valid_context 传递给 execution 模块 (如果模块支持)
    if execution.set_last_valid_context then
        execution.set_last_valid_context(last_valid_context)
    end
    
    -- ============================================================
    -- 1. 智能窗口标志 (Smart Window Flags)
    -- ============================================================
    local window_flags = 
        reaper.ImGui_WindowFlags_NoDecoration() |
        reaper.ImGui_WindowFlags_NoSavedSettings() |
        reaper.ImGui_WindowFlags_NoFocusOnAppearing()
    
    -- [核心优化] 动态计算是否穿透
    -- 默认情况下，我们希望窗口能接收输入。
    -- 但是，如果我们在 Draw 阶段发现鼠标悬停在空白处，我们会在下一帧加上 NoMouseInputs
    -- (由于 ImGui 是即时模式，完全的逐帧透传比较复杂，这里采用"大框套小框"的策略更稳妥)
    -- 实际上，对于大窗口遮挡问题，最好的办法是不移动窗口，而是只移动"绘图内容"。
    -- 但为了简化代码，我们保持移动窗口，但使用 HitTest 逻辑。

    -- 设置窗口背景完全透明
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 0.0)
    reaper.ImGui_SetNextWindowSize(ctx, window_width, window_height, reaper.ImGui_Cond_Always())
    
    if is_first_display then
        -- [FIX] Get Native Mouse Position
        local native_x, native_y = reaper.GetMousePosition()
        
        if native_x and native_y then
            -- [FIX] Convert Native (OS) coordinates to ImGui coordinates
            -- false means: convert FROM native TO imgui
            local mouse_x, mouse_y = reaper.ImGui_PointConvertNative(ctx, native_x, native_y, false)
            
            local window_x = mouse_x - window_width / 2
            local window_y = mouse_y - window_height / 2
            
            -- 获取视口信息，确保窗口在屏幕范围内
            local viewport = reaper.ImGui_GetMainViewport(ctx)
            if viewport then
                local vp_x, vp_y = reaper.ImGui_Viewport_GetPos(viewport)
                local vp_w, vp_h = reaper.ImGui_Viewport_GetSize(viewport)
                
                -- 确保窗口不超出屏幕边界
                if window_x < vp_x then
                    window_x = vp_x
                end
                if window_x + window_width > vp_x + vp_w then
                    window_x = vp_x + vp_w - window_width
                end
                if window_y < vp_y then
                    window_y = vp_y
                end
                if window_y + window_height > vp_y + vp_h then
                    window_y = vp_y + vp_h - window_height
                end
            end
            
            reaper.ImGui_SetNextWindowPos(ctx, window_x, window_y, reaper.ImGui_Cond_Appearing())
        else
            -- 如果无法获取鼠标位置，则使用居中逻辑作为后备
            local viewport = reaper.ImGui_GetMainViewport(ctx)
            if viewport then
                local vp_x, vp_y = reaper.ImGui_Viewport_GetPos(viewport)
                local vp_w, vp_h = reaper.ImGui_Viewport_GetSize(viewport)
                reaper.ImGui_SetNextWindowPos(ctx, vp_x + (vp_w - window_width)/2, vp_y + (vp_h - window_height)/2, reaper.ImGui_Cond_Appearing())
            end
        end
        is_first_display = false
    end
    
    -- 强制去除窗口边框（在 Begin 之前设置）
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 0.0)
    
    local visible, open = reaper.ImGui_Begin(ctx, "Radial Menu", true, window_flags)
    
    if visible then
        M.draw()
        
        -- [关键] 检查鼠标是否在交互区域内
        -- 如果鼠标不在任何可交互元素上，通过 reaper.JS 或 API 让点击穿透 (ReaImGui 较难直接实现完美穿透)
        -- 替代方案：让窗口本身 NoBackground 且 NoDecoration，Reaper 通常会处理好透明区域的点击。
        -- 如果你发现还是挡住了，说明 ReaImGui 的窗口捕获了所有点击。
        
        reaper.ImGui_End(ctx)
    end
    
    -- 恢复窗口边框样式（在 End 之后配对 PopStyleVar）
    reaper.ImGui_PopStyleVar(ctx)
    
    if open then
        reaper.defer(M.loop)
    end
end

-- ============================================================================
-- Phase 2 - 绘制界面 & 交互
-- ============================================================================

function M.draw()
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 0, 0)
    
    local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
    local center_x = win_x + win_w / 2
    local center_y = win_y + win_h / 2
    
    local inner_radius = config.menu.inner_radius or 50
    local outer_radius = config.menu.outer_radius or 200
    
    -- ============================================================
    -- 动画计算：轮盘展开动画
    -- ============================================================
    local now = reaper.time_precise()
    local anim_scale = 1.0
    
    if config.menu.animation and config.menu.animation.enable then
        local open_dur = config.menu.animation.duration_open or 0.06
        local t_open = math.max(0, math.min(1, (now - anim_open_start_time) / open_dur))
        anim_scale = math_utils.ease_out_cubic(t_open)
    end
    
    -- ============================================================
    -- 动画计算：子菜单弹出动画
    -- ============================================================
    -- [核心] 拖拽逻辑锁：检测是否正在拖拽
    local is_dragging = list_view.is_dragging()
    
    -- [FIX] 触发动画：如果菜单刚打开 OR 如果切换到不同的扇区
    local current_sector_id = clicked_sector and clicked_sector.id or nil
    
    -- 检查条件：
    -- 1. 菜单之前没打开，现在打开了
    -- 2. 菜单之前打开了，但扇区ID改变了（切换扇区）
    if show_submenu and (not last_submenu_state or current_sector_id ~= last_active_sector_id) then
        anim_submenu_start_time = now
    end
    
    last_submenu_state = show_submenu
    last_active_sector_id = current_sector_id
    
    local sub_scale = 1.0
    if show_submenu and config.menu.animation and config.menu.animation.enable then
        local sub_dur = config.menu.animation.duration_submenu or 1.0  -- [TESTING] 持续1秒以便观察动画效果
        local t_sub = math.max(0, math.min(1, (now - anim_submenu_start_time) / sub_dur))
        sub_scale = math_utils.ease_out_cubic(t_sub)
    elseif not show_submenu then
        sub_scale = 0.0
    end
    
    -- [CRITICAL FIX] 拖拽稳定性锁
    -- 如果用户正在拖拽项目，强制完整缩放并保持打开状态，防止闪烁/故障
    if is_dragging then
        sub_scale = 1.0  -- 强制完整缩放
        show_submenu = true  -- 防止自动关闭逻辑
        
        -- 同时确保 clicked_sector 在拖拽期间不会切换
        -- （这个逻辑通常在悬停部分处理，但在这里确保也很重要）
    end
    
    -- ============================================================
    -- [ANIMATION] 计算扇区扩展动画状态
    -- ============================================================
    -- Check toggle first
    local expansion_enabled = (config.menu.enable_sector_expansion ~= false) -- Default true
    
    -- 计算当前悬停的扇区ID（需要在绘制前获取，只计算一次）
    local current_hover_id = nil
    if expansion_enabled and config.sectors then
        local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
        local center_x = win_x + win_w / 2
        local center_y = win_y + win_h / 2
        
        local math_utils = require("math_utils")
        local angle, distance = math_utils.get_mouse_angle_and_distance(mouse_x, mouse_y, center_x, center_y)
        -- 注意：悬停检测使用原始半径，不受轮盘展开动画影响
        local inner_radius = config.menu.inner_radius
        local outer_radius = config.menu.outer_radius
        
        if distance >= inner_radius and distance <= outer_radius then
            local sector_index = math_utils.angle_to_sector_index(angle, #config.sectors, -math.pi / 2)
            if sector_index >= 1 and sector_index <= #config.sectors then
                current_hover_id = config.sectors[sector_index].id
            end
        end
    end
    
    if config.sectors then
        for _, sector in ipairs(config.sectors) do
            local id = sector.id
            local current_val = sector_anim_states[id] or 0.0
            
            -- Calculate Target
            local target_val = 0.0
            
            if expansion_enabled then
                local is_active_submenu = (show_submenu and clicked_sector and clicked_sector.id == id)
                -- Target is 1.0 if hovered or active, otherwise 0.0
                if (id == current_hover_id) or is_active_submenu then
                    target_val = 1.0
                end
            end
            
            -- [CHANGED] Convert 1-10 integer scale to 0.05-0.50 Lerp factor
            -- Handle backward compatibility: old format was float (0.0-1.0), new format is int (1-10)
            local speed_level_raw = config.menu.hover_animation_speed or 4
            local speed_level
            if type(speed_level_raw) == "number" then
                if speed_level_raw < 1 then
                    -- Old format: convert 0.0-1.0 to 1-10 scale, then to lerp factor
                    speed_level = math.max(1, math.min(10, math.floor((speed_level_raw / 0.05) + 0.5)))
                else
                    -- New format: already 1-10
                    speed_level = math.max(1, math.min(10, math.floor(speed_level_raw + 0.5)))
                end
            else
                speed_level = 4  -- Default fallback
            end
            -- Formula: Level * 0.05. (Level 1=0.05, Level 10=0.50)
            local expansion_speed = speed_level * 0.05
            
            -- Apply Lerp
            if math.abs(current_val - target_val) > 0.001 then
                sector_anim_states[id] = current_val + (target_val - current_val) * expansion_speed
            else
                sector_anim_states[id] = target_val
            end
        end
    end
    
    -- ============================================================
    -- 1. 绘制子菜单（先绘制，使其在轮盘下层）
    -- ============================================================
    -- [核心] 拖拽逻辑锁：如果正在拖拽，强制保持子菜单打开
    if is_dragging and clicked_sector then
        show_submenu = true
    end
    
    -- 子菜单悬停状态（用于防止自动关闭）
    local is_submenu_hovered = false
    
    if show_submenu and clicked_sector then
        -- list_view.draw_submenu 内部使用了 SetNextWindowPos + Begin
        -- 这意味着子菜单是一个独立的 ImGui 窗口
        -- [FIX] Pass 'config' to draw_submenu to avoid file I/O
        is_submenu_hovered = list_view.draw_submenu(ctx, clicked_sector, center_x, center_y, sub_scale, config)
    end
    
    -- ============================================================
    -- 2. 绘制轮盘 (上层，遮挡子菜单)
    -- ============================================================
    local active_id = (show_submenu and clicked_sector) and clicked_sector.id or nil
    wheel.draw_wheel(ctx, config, active_id, is_pinned, anim_scale, sector_anim_states)
    
    -- ============================================================
    -- 3. 优化拖拽手感：InvisibleButton 覆盖中心
    -- ============================================================
    -- 我们在窗口正中心放置一个看不见的按钮，大小等于 inner_radius
    -- 这样可以利用 ImGui 原生的拖拽逻辑，不仅手感好，而且不消耗性能
    
    reaper.ImGui_SetCursorPos(ctx, (win_w / 2) - inner_radius, (win_h / 2) - inner_radius)
    
    -- 创建一个隐形按钮作为"拖拽手柄"
    -- 只有按住这个区域，才会被 ImGui 视为"在窗口内有效点击"
    reaper.ImGui_InvisibleButton(ctx, "##DragHandle", inner_radius * 2, inner_radius * 2)
    
    -- 拖拽逻辑 (优化版)
    -- 利用 IsItemActive (按下并保持) 来驱动移动
    if reaper.ImGui_IsItemActive(ctx) and reaper.ImGui_IsMouseDragging(ctx, 0) then
        center_drag_started = true
        local dx, dy = reaper.ImGui_GetMouseDelta(ctx, 0)
        local new_x = win_x + dx
        local new_y = win_y + dy
        
        -- 获取视口信息，确保拖动时窗口不超出屏幕边界
        local viewport = reaper.ImGui_GetMainViewport(ctx)
        if viewport then
            local vp_x, vp_y = reaper.ImGui_Viewport_GetPos(viewport)
            local vp_w, vp_h = reaper.ImGui_Viewport_GetSize(viewport)
            
            -- 确保窗口不超出屏幕边界
            if new_x < vp_x then
                new_x = vp_x
            end
            if new_x + win_w > vp_x + vp_w then
                new_x = vp_x + vp_w - win_w
            end
            if new_y < vp_y then
                new_y = vp_y
            end
            if new_y + win_h > vp_y + vp_h then
                new_y = vp_y + vp_h - win_h
            end
        end
        
        reaper.ImGui_SetWindowPos(ctx, new_x, new_y)
        
        -- 注意：ReaImGui 可能没有 ResetMouseDragDelta 函数，如果报错可以注释掉
        if reaper.ImGui_ResetMouseDragDelta then
            reaper.ImGui_ResetMouseDragDelta(ctx, 0)
        end
    end
    
    -- 点击切换 Pin（仅在未发生拖拽时）
    -- 检测鼠标释放：如果点击了中心区域且没有拖拽，则切换 Pin 状态
    if reaper.ImGui_IsItemDeactivated(ctx) and not center_drag_started then
        -- 鼠标释放且没有发生拖拽，切换 Pin 状态
        is_pinned = not is_pinned
    end
    
    -- 重置拖拽状态（如果鼠标已释放）
    if not reaper.ImGui_IsItemActive(ctx) then
        center_drag_started = false
    end
    
    -- 设置鼠标指针 (悬停在中心时显示移动图标)
    if reaper.ImGui_IsItemHovered(ctx) then
        -- 检查是否有 ResizeAll 光标常量，如果没有则使用默认
        if reaper.ImGui_MouseCursor_ResizeAll then
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeAll())
        end
    end

    -- ============================================================
    -- 4. 悬停打开子菜单逻辑 (Hover to Open)
    -- ============================================================
    -- [核心] 拖拽逻辑锁：如果正在拖拽，完全禁止悬停切换扇区
    if not is_dragging then
        -- [New Hover Logic]
        local hovered_id = wheel.get_hovered_sector_id()
        
        -- [FIX] Added check: `and not is_dragging`
        -- Prevents switching sectors while the user is dragging an item
        if config.menu.hover_to_open and hovered_id then
            -- Only trigger if we are hovering a NEW sector (prevent flickering/toggling)
            if not clicked_sector or clicked_sector.id ~= hovered_id then
                local sector = config_manager.get_sector_by_id(config, hovered_id)
                if sector then
                    clicked_sector = sector
                    show_submenu = true
                end
            end
        end
    end

    -- ============================================================
    -- 5. 子菜单自动消失逻辑优化
    -- ============================================================
    -- [核心修复] 检查鼠标是否在扇区或子菜单范围内
    -- 如果鼠标既不在扇区，也不在子菜单范围内，则关闭子菜单
    -- [防闪烁优化] 只有当鼠标确实离开所有扇区和子菜单时，才关闭子菜单
    if show_submenu and clicked_sector and not is_dragging and config.menu.hover_to_open then
        local hovered_id = wheel.get_hovered_sector_id()
        local is_hovering_current_sector = (hovered_id == clicked_sector.id)
        local is_hovering_any_sector = (hovered_id ~= nil)
        
        -- [防闪烁] 如果鼠标在任何扇区上，不关闭子菜单（即使不是当前扇区）
        -- 这样可以避免在扇区间快速移动时出现闪烁
        -- 只有当鼠标既不在任何扇区，也不在子菜单范围内时，才关闭子菜单
        if not is_hovering_any_sector and not is_submenu_hovered then
            show_submenu = false
            clicked_sector = nil
        end
    end
    
    -- ============================================================
    -- 6. 扇区点击逻辑 (Hit Test)
    -- ============================================================
    -- 我们需要手动检测扇区点击，因为扇区是画出来的，不是真实的 Button
    -- 传递悬停状态，防止点击子菜单时关闭它
    M.handle_sector_click(center_x, center_y, inner_radius, outer_radius, is_submenu_hovered)
    
    -- ============================================================
    -- 7. 绘制拖拽视觉反馈和处理放置（在主窗口上）
    -- ============================================================
    -- [关键逻辑] 使用 Lua 状态 list_view.is_dragging() 作为唯一真理
    if list_view.is_dragging() then
        local dragging_slot = list_view.get_dragging_slot()
        
        -- 1. 绘制跟随鼠标的视觉反馈 (即便鼠标移出了 ImGui 窗口也能看到)
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        if draw_list and dragging_slot then
            list_view.draw_drag_feedback(draw_list, ctx, dragging_slot)
        end
        
        -- 2. 检测鼠标释放 (Drop Detection)
        -- 在主窗口中检测，因为鼠标可能移出子菜单窗口
        if not reaper.ImGui_IsMouseDown(ctx, 0) then
            -- 鼠标左键松开了，且之前处于拖拽状态 -> 触发放置
            
            -- 获取全局屏幕坐标 (用于 reaper.GetThingFromPoint)
            local screen_x, screen_y = reaper.GetMousePosition()
            
            if screen_x and screen_y and dragging_slot then
                -- 调用执行模块处理放置 (判断是放到 Track, Item 还是 Empty Area)
                execution.handle_drop(dragging_slot, screen_x, screen_y)
            end
            
            -- 立即重置拖拽状态
            list_view.reset_drag()
        end
    end
    
    reaper.ImGui_PopStyleVar(ctx)
end

-- ============================================================================
-- 输入处理逻辑
-- ============================================================================

function M.handle_sector_click(center_x, center_y, inner_radius, outer_radius, is_submenu_hovered)
    -- [核心] 拖拽逻辑锁：如果正在拖拽，完全禁止所有扇区点击逻辑
    local is_dragging = list_view.is_dragging()
    if is_dragging then
        -- 拖拽时强制保持子菜单打开状态，禁止任何切换
        return
    end
    
    -- [关键修复] 如果鼠标悬停在子菜单上，不处理任何点击（让子菜单自己处理）
    -- 这确保点击子菜单内的按钮不会触发扇区点击逻辑
    if is_submenu_hovered then
        return
    end
    
    -- 获取鼠标位置
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
    local relative_x = mouse_x - win_x
    local relative_y = mouse_y - win_y
    local w, h = reaper.ImGui_GetWindowSize(ctx)
    
    -- 计算距离
    local distance = math_utils.distance(relative_x, relative_y, w/2, h/2)
    
    -- 只有在扇区环带内，且没有正在拖拽中心时，才检测点击
    if distance > inner_radius and distance <= outer_radius then
        
        -- 只有点击左键时触发
        if reaper.ImGui_IsMouseClicked(ctx, 0) then
             local hovered_id = wheel.get_hovered_sector_id()
             if hovered_id then
                 local sector = config_manager.get_sector_by_id(config, hovered_id)
                 if sector then
                     M.on_sector_click(sector)
                 end
             end
        end
        
    elseif distance > outer_radius then
        -- [核心] 解决大框遮挡问题：
        -- 如果鼠标在轮盘外部，点击时我们希望穿透下去。
        -- [FIX] Only close if clicked AND NOT hovering the submenu AND NOT dragging
        -- 注意：子菜单是独立窗口，ImGui 会自动处理子菜单内的点击，不会传播到这里
        if reaper.ImGui_IsMouseClicked(ctx, 0) then
            if show_submenu and not is_submenu_hovered and not is_dragging then
                -- 点击了外部且没有悬停在子菜单上，关闭子菜单
                show_submenu = false
                clicked_sector = nil
            end
        end
    end
end

-- 当扇区被点击时调用
function M.on_sector_click(sector)
    if not sector then return end
    
    -- [核心] 拖拽逻辑锁：如果正在拖拽，禁止切换扇区
    if list_view.is_dragging() then
        return
    end
    
    if clicked_sector and clicked_sector.id == sector.id then
        show_submenu = false
        clicked_sector = nil
    else
        clicked_sector = sector
        show_submenu = true
    end
end

-- ============================================================================
-- 清理与启动
-- ============================================================================

function M.cleanup()
    reaper.SetExtState("RadialMenu_Tool", "Running", "0", false)
    reaper.SetExtState("RadialMenu_Tool", "WindowOpen", "0", false)
    is_first_display = true
    
    -- 释放按键拦截
    if KEY and reaper.JS_VKeys_Intercept then
        reaper.JS_VKeys_Intercept(KEY, -1)
    end
    KEY = nil
    SCRIPT_START_TIME = nil
    
    -- 不再需要 gfx.quit，因为已经移除了 gfx.init
    if ctx then
        if reaper.ImGui_DestroyContext then reaper.ImGui_DestroyContext(ctx) end
        ctx = nil
    end
end

function M.run()
    -- 长按模式：不再使用 toggle 逻辑
    -- 每次运行都直接初始化并显示窗口
    -- 窗口会在按键松开时自动关闭（在 TrackShortcutKey 中处理）
    
    local running = reaper.GetExtState("RadialMenu_Tool", "Running")
    if running == "1" then
        -- 如果已有实例在运行，不重复启动
        return
    end
    
    if M.init() then
        reaper.SetExtState("RadialMenu_Tool", "WindowOpen", "1", false)
        M.loop()
    end
end

return M
