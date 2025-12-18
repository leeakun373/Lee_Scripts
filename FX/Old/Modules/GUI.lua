--[[
  GUI Module
  Handles all ImGui rendering
]]

local GUI = {}
local r = reaper

-- Main render function
function GUI.render(state, modules)
    local Constants = modules.Constants
    local Colors = modules.Colors
    local Themes = modules.Themes
    local DataManager = modules.DataManager
    local FXFunctions = modules.FXFunctions
    local Helpers = modules.Helpers
    
    local ctx = state.gui.ctx
    local window_state = state.gui.window_state
    
    -- Apply theme and get colors from current theme
    local current_theme = Themes.getCurrentTheme()
    local style_var_count, color_count = Themes.applyTheme(ctx, current_theme)
    
    -- Get colors from current theme
    local theme_colors = {
        BTN_FX_ON      = current_theme.BTN_FX_ON,
        BTN_FX_OFF     = current_theme.BTN_FX_OFF,
        BTN_RELOAD     = current_theme.BTN_RELOAD,
        TEXT_NORMAL    = current_theme.TEXT_NORMAL,
        TEXT_DIM       = current_theme.TEXT_DIM,
        BG_HEADER      = current_theme.BG_HEADER,
    }
    
    local active_colors = theme_colors
    
    -- Track additional style vars we push (for themes without style_vars)
    local additional_style_vars = 0
    if not current_theme.style_vars then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 6)
        additional_style_vars = 2
    end
    
    -- Set window position if saved
    if window_state.x and window_state.y then
        r.ImGui_SetNextWindowPos(ctx, window_state.x, window_state.y, r.ImGui_Cond_FirstUseEver())
    end
    
    -- Set window size
    r.ImGui_SetNextWindowSize(ctx, window_state.width, window_state.height, r.ImGui_Cond_FirstUseEver())
    
    -- Begin window (restore title bar for close button)
    local visible, open = r.ImGui_Begin(ctx, 'FX Manager', true, r.ImGui_WindowFlags_None())
    
    if visible then
        -- Push slightly larger font size for all text
        local font_size = 14
        r.ImGui_PushFont(ctx, nil, font_size)
        
        -- Tab bar area
        local avail_width, avail_height = r.ImGui_GetContentRegionAvail(ctx)
        local footer_height = 35
        local scrollable_height = avail_height - footer_height
        
        local child_flags = r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or 1
        if r.ImGui_BeginChild(ctx, "TabContentArea", 0, scrollable_height, child_flags) then
            if r.ImGui_BeginTabBar(ctx, "MainTabs") then
                -- FX Operations Tab
                if r.ImGui_BeginTabItem(ctx, " FX Operations ") then
                    GUI.renderFXOperationsTab(state, modules)
                    r.ImGui_EndTabItem(ctx)
                end
                
                -- FX Loader Tab
                if r.ImGui_BeginTabItem(ctx, " FX Loader ") then
                    GUI.renderFXLoaderTab(state, modules)
                    r.ImGui_EndTabItem(ctx)
                end
                
                r.ImGui_EndTabBar(ctx)
            end
            r.ImGui_EndChild(ctx)
        end
        
        -- Footer: Status info (similar to MarkersWorkstation)
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Status:")
        r.ImGui_SameLine(ctx)
        r.ImGui_TextWrapped(ctx, state.status_message or "就绪")
        
        -- Show selection info on the right side of status
        r.ImGui_SameLine(ctx, r.ImGui_GetContentRegionAvail(ctx) - 120)
        local track_count = r.CountSelectedTracks(0)
        local item_count = r.CountSelectedMediaItems(0)
        local info_text = string.format("(%d tracks, %d items)", track_count, item_count)
        r.ImGui_TextDisabled(ctx, info_text)
        
        -- Dialogs
        GUI.renderDialogs(state, modules)
        
        -- Pop font size
        r.ImGui_PopFont(ctx)
        
        -- Save window state
        if open then
            local wx, wy = r.ImGui_GetWindowPos(ctx)
            local ww, wh = r.ImGui_GetWindowSize(ctx)
            window_state.x = wx
            window_state.y = wy
            window_state.width = ww
            window_state.height = wh
            DataManager.saveWindowState(window_state)
        end
        
        r.ImGui_End(ctx)
    end
    
    -- Pop theme styles and colors
    Themes.popTheme(ctx, style_var_count, color_count)
    
    -- Pop additional style vars we added
    if additional_style_vars > 0 then
        r.ImGui_PopStyleVar(ctx, additional_style_vars)
    end
    
    -- Return whether to continue
    return open and state.gui.visible
end

-- Render FX Operations Tab
function GUI.renderFXOperationsTab(state, modules)
    local ctx = state.gui.ctx
    local Constants = modules.Constants
    local Colors = modules.Colors
    local Themes = modules.Themes
    local DataManager = modules.DataManager
    local FXFunctions = modules.FXFunctions
    local CustomActionsManager = modules.CustomActionsManager
    local LayoutManager = modules.LayoutManager
    local Helpers = modules.Helpers
    
    -- Initialize layout if empty
    if LayoutManager.initializeLayout(state.layout, state.builtin_functions, state.custom_actions) then
        DataManager.saveLayout(state.layout)
    end
    
    -- Get colors from current theme
    local current_theme = Themes.getCurrentTheme()
    local active_colors = {
        BTN_FX_ON      = current_theme.BTN_FX_ON,
        BTN_FX_OFF     = current_theme.BTN_FX_OFF,
        BTN_RELOAD     = current_theme.BTN_RELOAD,
        BTN_CUSTOM     = current_theme.BTN_CUSTOM or 0x7E57C2FF,
        BTN_DELETE     = current_theme.BTN_DELETE or 0xCC0000FF,
        TEXT_NORMAL    = current_theme.TEXT_NORMAL,
        TEXT_DIM       = current_theme.TEXT_DIM,
        BG_HEADER      = current_theme.BG_HEADER,
    }
    
    -- Helper: Get function by ID
    local function getFunctionByID(func_id)
        if not func_id then return nil end
        if func_id:match("^builtin_") then
            local func_name = func_id:match("^builtin_(.+)$")
            if func_name == "OpenAllTrackFXWindows" then
                return {name = "Open All FX Windows", description = "打开所选轨道/Item对应轨道的所有Track FX窗口并自动排列", func = FXFunctions.OpenAllTrackFXWindows, color = current_theme.BTN_VIEW or 0x0984E3FF, func_id = func_id}
            elseif func_name == "CloseAllFXWindows" then
                return {name = "Close All FX Windows", description = "关闭所有FX浮动窗口和FX Chain窗口", func = FXFunctions.CloseAllFXWindows, color = active_colors.BTN_FX_OFF, func_id = func_id}
            elseif func_name == "ToggleBypassOrActive" then
                return {name = "Toggle Bypass", description = "切换Bypass状态（Item优先，否则Track）", func = FXFunctions.ToggleBypassOrActive, color = current_theme.BTN_PROCESSING or 0xD63031FF, func_id = func_id}
            elseif func_name == "ToggleFXChainWindow" then
                return {name = "Toggle FX Chain", description = "切换FX Chain窗口（自动判断Item/Track）", func = FXFunctions.ToggleFXChainWindow, color = current_theme.BTN_VIEW or 0x0984E3FF, func_id = func_id}
            end
        elseif func_id:match("^custom_") then
            local action_name = func_id:match("^custom_(.+)$")
            for _, action in ipairs(state.custom_actions) do
                if action.name == action_name then
                    return {name = action.name, description = action.description or "", func = function() CustomActionsManager.executeAction(action) end, color = active_colors.BTN_CUSTOM, func_id = func_id, is_custom = true}
                end
            end
        end
        return nil
    end
    
    -- Build active functions list from layout
    local all_functions = {}
    for _, func_id in ipairs(state.layout.active) do
        local func = getFunctionByID(func_id)
        if func then
            table.insert(all_functions, func)
        end
    end
    
    -- Calculate button layout
    -- Get accurate width in Tab content area
    local avail_width = r.ImGui_GetContentRegionAvail(ctx)
    -- Try to get window content width if available (accounts for scrollbar)
    if r.ImGui_GetWindowContentRegionWidth then
        local window_width = r.ImGui_GetWindowContentRegionWidth(ctx)
        if window_width and window_width > 0 then
            avail_width = window_width
        end
    end
    
    local button_padding = 8
    -- Use a more flexible approach: prefer 2 columns, but adapt to available width
    local min_button_width = 140  -- Minimum width for a button
    local preferred_buttons_per_row = Constants.DEFAULT_BUTTONS_PER_ROW or 2
    -- Calculate how many buttons can fit
    local buttons_per_row = math.max(1, math.floor((avail_width + button_padding) / (min_button_width + button_padding)))
    -- But prefer at least 2 columns if space allows (need at least 280px for 2 buttons)
    if avail_width >= (min_button_width * 2 + button_padding) then
        buttons_per_row = math.max(preferred_buttons_per_row, buttons_per_row)
    end
    -- Calculate actual button width
    local button_width = (avail_width - (buttons_per_row - 1) * button_padding) / buttons_per_row
    local button_height = Constants.DEFAULT_BUTTON_HEIGHT
    
    -- Render buttons in grid
    for i, func_info in ipairs(all_functions) do
        r.ImGui_PushID(ctx, i)
        
        if (i - 1) % buttons_per_row ~= 0 then
            r.ImGui_SameLine(ctx)
        end
        
        -- Push button style
        Helpers.PushBtnStyle(ctx, func_info.color)
        
        -- Button
        if r.ImGui_Button(ctx, func_info.name, button_width, button_height) then
            func_info.func()
            state.status_message = string.format("执行: %s", func_info.name)
        end
        
        -- Tooltip with delay
        if r.ImGui_IsItemHovered(ctx) then
            local button_id = "fx_func_" .. i
            local current_time = r.time_precise()
            if not state.tooltip_timers then
                state.tooltip_timers = {}
            end
            if not state.tooltip_timers[button_id] then
                state.tooltip_timers[button_id] = current_time
            end
            if current_time - state.tooltip_timers[button_id] >= Constants.TOOLTIP_DELAY then
                if r.ImGui_BeginTooltip(ctx) then
                    r.ImGui_Text(ctx, func_info.description)
                    r.ImGui_EndTooltip(ctx)
                end
            end
        else
            -- Reset timer when not hovering
            if state.tooltip_timers then
                state.tooltip_timers["fx_func_" .. i] = nil
            end
        end
        
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_PopID(ctx)
    end
    
    -- Add separator and custom actions management
    if #all_functions > 0 then
        r.ImGui_Separator(ctx)
    end
    
    -- Custom Actions section
    r.ImGui_TextColored(ctx, active_colors.TEXT_NORMAL, "Custom Actions:")
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, " + Add ") then
        state.show_add_custom_action = true
    end
    
    -- Show custom actions list (in stash)
    if #state.layout.stash > 0 then
        r.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Stashed Actions:")
        for _, func_id in ipairs(state.layout.stash) do
            if func_id:match("^custom_") then
                local action_name = func_id:match("^custom_(.+)$")
                r.ImGui_BulletText(ctx, action_name)
            end
        end
    end
end

-- Render FX Loader Tab
function GUI.renderFXLoaderTab(state, modules)
    local ctx = state.gui.ctx
    local Constants = modules.Constants
    local Themes = modules.Themes
    local DataManager = modules.DataManager
    local FXLoader = modules.FXLoader
    local Helpers = modules.Helpers
    
    -- Get colors from current theme
    local current_theme = Themes.getCurrentTheme()
    local active_colors = {
        BTN_FX_ON      = current_theme.BTN_FX_ON,
        BTN_FX_HOVER   = current_theme.BTN_FX_HOVER,
        BTN_FX_ACTIVE  = current_theme.BTN_FX_ACTIVE,
        BTN_FX_BORDER  = current_theme.BTN_FX_BORDER,
        BTN_FX_OFF     = current_theme.BTN_FX_OFF,
        BTN_RELOAD     = current_theme.BTN_RELOAD,
        BTN_CUSTOM     = current_theme.BTN_CUSTOM or 0x6C5CE7FF,
        BTN_DELETE     = current_theme.BTN_DELETE or 0xD63031FF,
        TEXT_NORMAL    = current_theme.TEXT_NORMAL,
        TEXT_DIM       = current_theme.TEXT_DIM,
        BG_HEADER      = current_theme.BG_HEADER,
    }
    
    -- ===== TOP TOOLBAR (编辑态) =====
    -- 缩小设置按钮，放在顶部一行
    r.ImGui_BeginGroup(ctx)
    
    -- Add FX button (small)
    if r.ImGui_Button(ctx, "+") then
        state.show_add_fx_dialog = true
    end
    if r.ImGui_IsItemHovered(ctx) then
        if r.ImGui_BeginTooltip(ctx) then
            r.ImGui_Text(ctx, "Add FX")
            r.ImGui_EndTooltip(ctx)
        end
    end
    
    r.ImGui_SameLine(ctx)
    
    -- Buttons per row control (arrows)
    r.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Cols:")
    r.ImGui_SameLine(ctx)
    
    local buttons_per_row = state.buttons_per_row or 2
    if r.ImGui_ArrowButton(ctx, "##row_minus", 0) then  -- Left arrow
        state.buttons_per_row = math.max(1, buttons_per_row - 1)
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, tostring(buttons_per_row))
    r.ImGui_SameLine(ctx)
    if r.ImGui_ArrowButton(ctx, "##row_plus", 1) then  -- Right arrow
        state.buttons_per_row = math.min(10, buttons_per_row + 1)
    end
    
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, active_colors.TEXT_DIM, string.format("(%d)", #state.fx_buttons))
    
    r.ImGui_SameLine(ctx, r.ImGui_GetContentRegionAvail(ctx) - 120)
    
    -- Preset buttons (small)
    if r.ImGui_Button(ctx, "Save") then
        state.show_save_preset_dialog = true
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Load") then
        state.show_load_preset_dialog = true
    end
    
    r.ImGui_EndGroup(ctx)
    
    r.ImGui_Separator(ctx)  -- 分割线：编辑区 vs 工作区
    
    -- ===== CORE BUTTON AREA (工作态 - 打击垫风格) =====
    if #state.fx_buttons == 0 then
        r.ImGui_Spacing(ctx)
        r.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "No FX buttons. Click '+' to add one.")
        r.ImGui_Spacing(ctx)
    else
        local avail_width = r.ImGui_GetContentRegionAvail(ctx)
        local button_spacing = 8  -- 增加间距，防止误触
        local buttons_per_row = state.buttons_per_row or 2
        local button_width = (avail_width - (buttons_per_row - 1) * button_spacing) / buttons_per_row
        local button_height = 50  -- 更大的按钮高度，像打击垫
        
        -- 应用FX按钮样式（Hero buttons）
        Helpers.PushFXButtonStyle(ctx, current_theme)
        
        -- 增加字体大小（通过PushFont）
        local original_font_size = 14
        r.ImGui_PushFont(ctx, nil, 15)  -- 稍微大一点的字体
        
        for i, fx_info in ipairs(state.fx_buttons) do
            r.ImGui_PushID(ctx, "fx_btn_" .. i)
            
            if (i - 1) % buttons_per_row ~= 0 then
                r.ImGui_SameLine(ctx, 0, button_spacing)
            end
            
            -- Hero Button (打击垫风格)
            local display_name = fx_info.display_name or fx_info.fx_name
            if r.ImGui_Button(ctx, display_name, button_width, button_height) then
                local success, msg = FXLoader.insertFX(fx_info.fx_name, fx_info.fx_guid)
                state.status_message = msg or (success and "已插入FX" or "插入失败")
            end
            
            -- Right-click context menu
            if r.ImGui_BeginPopupContextItem(ctx) then
                if r.ImGui_MenuItem(ctx, "Edit") then
                    state.editing_fx_index = i
                    state.edit_fx_name = fx_info.fx_name
                    state.edit_fx_display_name = fx_info.display_name or fx_info.fx_name
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                if r.ImGui_MenuItem(ctx, "Delete") then
                    local success, msg = FXLoader.deleteFXButton(state.fx_buttons, i)
                    if success then
                        DataManager.saveFXButtons(state.fx_buttons)
                        state.status_message = msg
                    end
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                r.ImGui_EndPopup(ctx)
            end
            
            r.ImGui_PopID(ctx)
        end
        
        -- Pop font
        r.ImGui_PopFont(ctx)
        
        -- Pop FX button style
        Helpers.PopFXButtonStyle(ctx)
    end
end

-- Render dialogs (Add FX, Edit FX, Save/Load Preset, etc.)
function GUI.renderDialogs(state, modules)
    local ctx = state.gui.ctx
    local DataManager = modules.DataManager
    local FXLoader = modules.FXLoader
    local CustomActionsManager = modules.CustomActionsManager
    local LayoutManager = modules.LayoutManager
    local Themes = modules.Themes
    
    local current_theme = Themes.getCurrentTheme()
    local active_colors = {
        TEXT_NORMAL = current_theme.TEXT_NORMAL,
        TEXT_DIM = current_theme.TEXT_DIM,
    }
    
    -- Add Custom Action Dialog
    if state.show_add_custom_action then
        r.ImGui_OpenPopup(ctx, "Add Custom Action")
        state.show_add_custom_action = false
        state.new_action_name = ""
        state.new_action_id = ""
        state.new_action_description = ""
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Add Custom Action", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        r.ImGui_Text(ctx, "Action Name:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 300)
        local changed, new_name = r.ImGui_InputText(ctx, "##action_name", state.new_action_name or "")
        if changed then
            state.new_action_name = new_name
        end
        
        r.ImGui_Text(ctx, "Action ID (number or command ID):")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 300)
        local changed2, new_id = r.ImGui_InputText(ctx, "##action_id", state.new_action_id or "")
        if changed2 then
            state.new_action_id = new_id
        end
        
        r.ImGui_Text(ctx, "Description (optional):")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 300)
        local changed3, new_desc = r.ImGui_InputText(ctx, "##action_desc", state.new_action_description or "")
        if changed3 then
            state.new_action_description = new_desc
        end
        
        r.ImGui_Separator(ctx)
        
        if r.ImGui_Button(ctx, "OK") then
            if state.new_action_name and state.new_action_name ~= "" and state.new_action_id and state.new_action_id ~= "" then
                local success, msg = CustomActionsManager.addAction(state.custom_actions, {
                    name = state.new_action_name,
                    action_id = state.new_action_id,
                    description = state.new_action_description or ""
                })
                if success then
                    DataManager.saveCustomActions(state.custom_actions)
                    -- Add to layout
                    local func_id = "custom_" .. state.new_action_name
                    LayoutManager.moveToActive(state.layout, func_id)
                    DataManager.saveLayout(state.layout)
                    state.status_message = msg
                    state.new_action_name = ""
                    state.new_action_id = ""
                    state.new_action_description = ""
                    r.ImGui_CloseCurrentPopup(ctx)
                else
                    state.status_message = msg
                end
            else
                state.status_message = "请填写名称和Action ID"
            end
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel") then
            state.new_action_name = ""
            state.new_action_id = ""
            state.new_action_description = ""
            r.ImGui_CloseCurrentPopup(ctx)
        end
        
        r.ImGui_EndPopup(ctx)
    end
    
    -- Add FX Dialog
    if state.show_add_fx_dialog then
        r.ImGui_OpenPopup(ctx, "Add FX")
        state.show_add_fx_dialog = false
        state.new_fx_name = ""
        state.new_fx_display_name = ""
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Add FX", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        r.ImGui_Text(ctx, "FX Name:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 300)
        local changed, new_name = r.ImGui_InputText(ctx, "##fx_name", state.new_fx_name or "")
        if changed then
            state.new_fx_name = new_name
        end
        
        r.ImGui_Text(ctx, "Display Name (optional):")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 300)
        local changed2, new_display = r.ImGui_InputText(ctx, "##fx_display", state.new_fx_display_name or "")
        if changed2 then
            state.new_fx_display_name = new_display
        end
        
        r.ImGui_Separator(ctx)
        
        if r.ImGui_Button(ctx, "From Browser") then
            -- Open FX browser
            r.Main_OnCommand(40271, 0)  -- FX: Show/hide FX browser
            -- Try to get last added FX from selected track/item
            state.status_message = "FX浏览器已打开。请：1) 在浏览器中选择FX并双击添加到轨道/媒体项，2) 然后点击'Get Last FX'按钮获取名称"
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Get Last FX") then
            -- Try to get the last FX from selected track/item
            local fx_name = FXLoader.getLastAddedFXFromSelection()
            if fx_name and fx_name ~= "" then
                state.new_fx_name = fx_name
                state.new_fx_display_name = fx_name
                state.status_message = "已获取FX名称: " .. fx_name
            else
                state.status_message = "未找到最近添加的FX。请确保已选择轨道/媒体项并添加了FX"
            end
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "OK") then
            if state.new_fx_name and state.new_fx_name ~= "" then
                local success, msg = FXLoader.addFXButton(state.fx_buttons, {
                    fx_name = state.new_fx_name,
                    display_name = state.new_fx_display_name or state.new_fx_name
                })
                if success then
                    DataManager.saveFXButtons(state.fx_buttons)
                    state.status_message = msg
                    state.new_fx_name = ""
                    state.new_fx_display_name = ""
                    r.ImGui_CloseCurrentPopup(ctx)
                else
                    state.status_message = msg
                end
            end
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel") then
            state.new_fx_name = ""
            state.new_fx_display_name = ""
            r.ImGui_CloseCurrentPopup(ctx)
        end
        
        r.ImGui_EndPopup(ctx)
    end
    
    -- Edit FX Dialog
    if state.editing_fx_index and state.editing_fx_index > 0 and state.editing_fx_index <= #state.fx_buttons then
        if not state.edit_dialog_open then
            r.ImGui_OpenPopup(ctx, "Edit FX")
            state.edit_dialog_open = true
        end
        
        if r.ImGui_BeginPopupModal(ctx, "Edit FX", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_Text(ctx, "FX Name:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 300)
            local changed, new_name = r.ImGui_InputText(ctx, "##edit_fx_name", state.edit_fx_name or "")
            if changed then
                state.edit_fx_name = new_name
            end
            
            r.ImGui_Text(ctx, "Display Name:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 300)
            local changed2, new_display = r.ImGui_InputText(ctx, "##edit_fx_display", state.edit_fx_display_name or "")
            if changed2 then
                state.edit_fx_display_name = new_display
            end
            
            r.ImGui_Separator(ctx)
            
            if r.ImGui_Button(ctx, "OK") then
                if state.edit_fx_name and state.edit_fx_name ~= "" then
                    local success, msg = FXLoader.updateFXButton(state.fx_buttons, state.editing_fx_index, {
                        fx_name = state.edit_fx_name,
                        display_name = state.edit_fx_display_name or state.edit_fx_name
                    })
                    if success then
                        DataManager.saveFXButtons(state.fx_buttons)
                        state.status_message = msg
                        state.editing_fx_index = nil
                        state.edit_fx_name = ""
                        state.edit_fx_display_name = ""
                        state.edit_dialog_open = false
                        r.ImGui_CloseCurrentPopup(ctx)
                    else
                        state.status_message = msg
                    end
                end
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Cancel") then
                state.editing_fx_index = nil
                state.edit_fx_name = ""
                state.edit_fx_display_name = ""
                state.edit_dialog_open = false
                r.ImGui_CloseCurrentPopup(ctx)
            end
            
            r.ImGui_EndPopup(ctx)
        end
    end
    
    -- Save Preset Dialog
    if state.show_save_preset_dialog then
        r.ImGui_OpenPopup(ctx, "Save Preset")
        state.show_save_preset_dialog = false
        state.new_preset_name = ""
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Save Preset", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        r.ImGui_Text(ctx, "Preset Name:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 300)
        local changed, new_name = r.ImGui_InputText(ctx, "##preset_name", state.new_preset_name or "")
        if changed then
            state.new_preset_name = new_name
        end
        
        r.ImGui_Separator(ctx)
        
        if r.ImGui_Button(ctx, "OK") then
            if state.new_preset_name and state.new_preset_name ~= "" then
                local preset = FXLoader.saveAsFXPreset(state.fx_buttons, state.buttons_per_row, state.new_preset_name)
                if preset then
                    state.fx_presets[state.new_preset_name] = preset
                    DataManager.saveFXPresets(state.fx_presets)
                    state.status_message = "预设已保存: " .. state.new_preset_name
                    state.new_preset_name = ""
                    r.ImGui_CloseCurrentPopup(ctx)
                end
            end
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel") then
            state.new_preset_name = ""
            r.ImGui_CloseCurrentPopup(ctx)
        end
        
        r.ImGui_EndPopup(ctx)
    end
    
    -- Load Preset Dialog
    if state.show_load_preset_dialog then
        r.ImGui_OpenPopup(ctx, "Load Preset")
        state.show_load_preset_dialog = false
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Load Preset", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        local preset_names = {}
        for name, _ in pairs(state.fx_presets) do
            table.insert(preset_names, name)
        end
        table.sort(preset_names)
        
        if #preset_names == 0 then
            r.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "No presets available")
        else
            for _, preset_name in ipairs(preset_names) do
                if r.ImGui_Selectable(ctx, preset_name) then
                    local preset = state.fx_presets[preset_name]
                    if preset then
                        local success, msg = FXLoader.applyFXPreset(preset, state.fx_buttons)
                        if success then
                            state.buttons_per_row = preset.buttons_per_row or 2
                            DataManager.saveFXButtons(state.fx_buttons)
                            state.status_message = "已加载预设: " .. preset_name
                            r.ImGui_CloseCurrentPopup(ctx)
                        else
                            state.status_message = msg
                        end
                    end
                end
            end
        end
        
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, "Cancel") then
            r.ImGui_CloseCurrentPopup(ctx)
        end
        
        r.ImGui_EndPopup(ctx)
    end
end

return GUI

