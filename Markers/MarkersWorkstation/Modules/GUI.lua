--[[
  GUI Module
  Handles all ImGui rendering
]]

local GUI = {}

-- Main render function
function GUI.render(state, modules)
    local Constants = modules.Constants
    local Colors = modules.Colors
    local Themes = modules.Themes
    local DataManager = modules.DataManager
    local FunctionLoader = modules.FunctionLoader
    local LayoutManager = modules.LayoutManager
    local CustomActionsManager = modules.CustomActionsManager
    local Helpers = modules.Helpers
    
    local ctx = state.gui.ctx
    local window_state = state.gui.window_state
    
    -- Apply theme and get colors from current theme
    local current_theme = Themes.getCurrentTheme()
    local style_var_count, color_count = Themes.applyTheme(ctx, current_theme)
    
    -- Get colors from current theme (for dynamic updates)
    local theme_colors = {
        BTN_MARKER_ON  = current_theme.BTN_MARKER_ON,
        BTN_MARKER_OFF = current_theme.BTN_MARKER_OFF,
        BTN_REGION_ON  = current_theme.BTN_REGION_ON,
        BTN_REGION_OFF = current_theme.BTN_REGION_OFF,
        BTN_RELOAD     = current_theme.BTN_RELOAD,
        BTN_MANAGER    = current_theme.BTN_MANAGER,
        BTN_CUSTOM     = current_theme.BTN_CUSTOM,
        BTN_DELETE     = current_theme.BTN_DELETE,
        TEXT_NORMAL    = current_theme.TEXT_NORMAL,
        TEXT_DIM       = current_theme.TEXT_DIM,
        BG_HEADER      = current_theme.BG_HEADER,
    }
    
    -- Use theme colors (fallback to Colors for backward compatibility)
    local active_colors = theme_colors
    
    -- Track additional style vars we push (for themes without style_vars)
    local additional_style_vars = 0
    if not current_theme.style_vars then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 10, 10)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 6, 6)
        additional_style_vars = 2
    end
    
    -- Set window position if saved
    if window_state.x and window_state.y then
        reaper.ImGui_SetNextWindowPos(ctx, window_state.x, window_state.y, reaper.ImGui_Cond_FirstUseEver())
    end
    
    -- Set window size
    reaper.ImGui_SetNextWindowSize(ctx, window_state.width, window_state.height, reaper.ImGui_Cond_FirstUseEver())
    
    -- Begin window
    local visible, open = reaper.ImGui_Begin(ctx, 'Marker/Region Workstation', true, reaper.ImGui_WindowFlags_None())
    
    if visible then
        -- Push slightly larger font size for all text
        local font_size = 14  -- Slightly larger than default (13)
        reaper.ImGui_PushFont(ctx, nil, font_size)
        -- Header
        reaper.ImGui_TextColored(ctx, active_colors.TEXT_NORMAL, "Marker/Region Workstation")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format("(%d functions)", #state.marker_functions))
        
        reaper.ImGui_Separator(ctx)
        
        -- Top toolbar
        Helpers.PushBtnStyle(ctx, active_colors.BTN_RELOAD)
        if reaper.ImGui_Button(ctx, " Reload ") then
            state.marker_functions = FunctionLoader.loadFunctions(state.functions_dir or "", DataManager, active_colors)
            state.status_message = string.format("Reloaded %d function(s)", #state.marker_functions)
            state.layout_cache_dirty = true
            state.stash_cache = nil
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_SameLine(ctx)
        
        Helpers.PushBtnStyle(ctx, active_colors.BTN_MANAGER)
        if reaper.ImGui_Button(ctx, " Manager ") then
            reaper.Main_OnCommand(40326, 0)
            state.status_message = "Opened Region/Marker Manager"
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_Separator(ctx)
        
        -- Filter section
        reaper.ImGui_Text(ctx, "Filter:")
        reaper.ImGui_SameLine(ctx)
        
        local marker_btn_col = state.filter_state.show_markers and active_colors.BTN_MARKER_ON or active_colors.BTN_MARKER_OFF
        Helpers.PushBtnStyle(ctx, marker_btn_col)
        if reaper.ImGui_Button(ctx, " M ") then
            state.filter_state.show_markers = not state.filter_state.show_markers
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_SameLine(ctx)
        
        local region_btn_col = state.filter_state.show_regions and active_colors.BTN_REGION_ON or active_colors.BTN_REGION_OFF
        Helpers.PushBtnStyle(ctx, region_btn_col)
        if reaper.ImGui_Button(ctx, " R ") then
            state.filter_state.show_regions = not state.filter_state.show_regions
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_Separator(ctx)
        
        -- Tab bar
        if reaper.ImGui_BeginTabBar(ctx, "MainTabs") then
            -- Functions Tab
            if reaper.ImGui_BeginTabItem(ctx, " Functions ") then
                GUI.renderFunctionsTab(state, modules)
                reaper.ImGui_EndTabItem(ctx)
            end
            
            -- Custom Actions Tab
            if reaper.ImGui_BeginTabItem(ctx, " Custom Actions ") then
                GUI.renderCustomActionsTab(state, modules)
                reaper.ImGui_EndTabItem(ctx)
            end
            
            -- Layout Tab
            if reaper.ImGui_BeginTabItem(ctx, " Layout ") then
                GUI.renderLayoutTab(state, modules)
                reaper.ImGui_EndTabItem(ctx)
            end
            
            reaper.ImGui_EndTabBar(ctx)
        end
        
        -- Footer: Status info
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Status:")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextWrapped(ctx, state.status_message)
        
        -- Pop font size
        reaper.ImGui_PopFont(ctx)
        
        reaper.ImGui_End(ctx)
    end
    
    -- Pop theme styles and colors (this handles theme-provided style vars)
    Themes.popTheme(ctx, style_var_count, color_count)
    
    -- Pop additional style vars we added (for themes without style_vars)
    if additional_style_vars > 0 then
        reaper.ImGui_PopStyleVar(ctx, additional_style_vars)
    end
    
    -- Return whether to continue
    return open and state.gui.visible
end

-- Render Functions tab
function GUI.renderFunctionsTab(state, modules)
    local ctx = state.gui.ctx
    local Themes = modules.Themes
    local DataManager = modules.DataManager
    local FunctionLoader = modules.FunctionLoader
    local LayoutManager = modules.LayoutManager
    local Helpers = modules.Helpers
    local Constants = modules.Constants
    
    -- Get colors from current theme
    local current_theme = Themes.getCurrentTheme()
    local active_colors = {
        BTN_MARKER_ON  = current_theme.BTN_MARKER_ON,
        BTN_MARKER_OFF = current_theme.BTN_MARKER_OFF,
        BTN_REGION_ON  = current_theme.BTN_REGION_ON,
        BTN_REGION_OFF = current_theme.BTN_REGION_OFF,
        BTN_RELOAD     = current_theme.BTN_RELOAD,
        BTN_MANAGER    = current_theme.BTN_MANAGER,
        BTN_CUSTOM     = current_theme.BTN_CUSTOM,
        BTN_DELETE     = current_theme.BTN_DELETE,
        TEXT_NORMAL    = current_theme.TEXT_NORMAL,
        TEXT_DIM       = current_theme.TEXT_DIM,
        BG_HEADER      = current_theme.BG_HEADER,
    }
    
    -- Process pending swaps
    for _, swap in ipairs(state.pending_swaps) do
        local src_name = swap.src_name
        local dst_name = swap.dst_name
        if src_name and dst_name and src_name ~= dst_name then
            if LayoutManager.reorderFunctions(state.layout, src_name, dst_name) then
                DataManager.saveLayout(state.layout)
                state.status_message = string.format("Reordered: %s", src_name)
                state.layout_cache_dirty = true
            end
        end
    end
    state.pending_swaps = {}
    
    -- Build active functions list
    local all_functions = {}
    local valid_active = {}
    for _, func_name in ipairs(state.layout.active) do
        if func_name and func_name ~= "" then
            local func = FunctionLoader.getFunctionByName(func_name, state.marker_functions, state.custom_actions, active_colors)
            if func and func.name then
                table.insert(all_functions, func)
                table.insert(valid_active, func_name)
            end
        end
    end
    -- Update layout if some were invalid
    if #valid_active ~= #state.layout.active then
        state.layout.active = valid_active
        DataManager.saveLayout(state.layout)
    end
    
    -- Filter by type
    local filtered_funcs = {}
    for _, func in ipairs(all_functions) do
        local func_type = func.type or Constants.DEFAULT_TYPE
        if (func_type == "marker" and state.filter_state.show_markers) or
           (func_type == "region" and state.filter_state.show_regions) then
            table.insert(filtered_funcs, func)
        end
    end
    
    if #filtered_funcs == 0 then
        reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "No functions match current filter.")
        if #state.layout.active == 0 then
            reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Drag functions from Layout tab to add them.")
        elseif #state.marker_functions == 0 then
            reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Add .lua files to MarkerFunctions directory")
        else
            local filter_info = {}
            if not state.filter_state.show_markers then
                table.insert(filter_info, "Markers")
            end
            if not state.filter_state.show_regions then
                table.insert(filter_info, "Regions")
            end
            if #filter_info > 0 then
                reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, string.format("Tip: Click M/R buttons to show %s", table.concat(filter_info, " and ")))
            end
        end
    else
        -- Use child window for scrollable area
        local footer_height = 40
        local child_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 1
        if reaper.ImGui_BeginChild(ctx, "functions_area", 0, -footer_height, child_flags) then
            -- Calculate button layout INSIDE child window
            -- Use GetWindowContentRegionWidth to get accurate width (accounts for scrollbar)
            local avail_width = reaper.ImGui_GetWindowContentRegionWidth and reaper.ImGui_GetWindowContentRegionWidth(ctx) or reaper.ImGui_GetContentRegionAvail(ctx)
            -- If GetWindowContentRegionWidth is not available, subtract scrollbar width (typically 16-18px)
            if not reaper.ImGui_GetWindowContentRegionWidth then
                avail_width = avail_width - 18  -- Conservative estimate for scrollbar
            end
            
            local button_padding = 6
            local buttons_per_row = math.max(1, math.floor((avail_width + button_padding) / (200 + button_padding)))
            local button_width = (avail_width - (buttons_per_row - 1) * button_padding) / buttons_per_row
            local button_height = 45
            -- Drop target for entire child area
            if reaper.ImGui_BeginDragDropTarget(ctx) then
                local rv, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "FUNCTION_FROM_STASH")
                if rv and payload and payload ~= "" then
                    LayoutManager.moveToActive(state.layout, payload)
                    DataManager.saveLayout(state.layout)
                    state.layout_cache_dirty = true
                    state.stash_cache = nil
                end
                reaper.ImGui_EndDragDropTarget(ctx)
            end
            
            for i, func in ipairs(filtered_funcs) do
                local actual_idx = nil
                if func.is_custom then
                    actual_idx = "custom_" .. func.name
                else
                    for j, orig_func in ipairs(state.marker_functions) do
                        if orig_func.name == func.name then
                            actual_idx = j
                            break
                        end
                    end
                end
                
                if actual_idx then
                    reaper.ImGui_PushID(ctx, tostring(actual_idx))
                    
                    -- Apply custom color if specified
                    if func.buttonColor then
                        if type(func.buttonColor) == "table" then
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), func.buttonColor[1] or 0xFFFFFFFF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), func.buttonColor[2] or 0xFFFFFFFF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), func.buttonColor[3] or 0xFFFFFFFF)
                        end
                    end
                    
                    -- Create button
                    if reaper.ImGui_Button(ctx, func.name, button_width, button_height) then
                        local success, message = func.execute()
                        state.status_message = message or (success and "Success" or "Error")
                    end
                    
                    -- Drag source for reordering
                    if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                        reaper.ImGui_SetDragDropPayload(ctx, "FUNCTION_REORDER", func.name)
                        reaper.ImGui_Text(ctx, func.name)
                        reaper.ImGui_EndDragDropSource(ctx)
                    end
                    
                    -- Drop target for reordering
                    if reaper.ImGui_BeginDragDropTarget(ctx) then
                        local rv, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "FUNCTION_REORDER")
                        if rv and payload and payload ~= "" then
                            local src_name = payload
                            if src_name ~= func.name then
                                table.insert(state.pending_swaps, {src_name = src_name, dst_name = func.name})
                            end
                        end
                        -- Also accept from stash
                        local rv2, payload2 = reaper.ImGui_AcceptDragDropPayload(ctx, "FUNCTION_FROM_STASH")
                        if rv2 and payload2 and payload2 ~= "" then
                            local func_name_stash = payload2
                            -- Find the position of current func in active
                            local current_pos = nil
                            for j, active_name in ipairs(state.layout.active) do
                                if active_name == func.name then
                                    current_pos = j
                                    break
                                end
                            end
                            if current_pos then
                                LayoutManager.moveToActive(state.layout, func_name_stash, current_pos)
                                DataManager.saveLayout(state.layout)
                                state.layout_cache_dirty = true
                                state.stash_cache = nil
                            end
                        end
                        reaper.ImGui_EndDragDropTarget(ctx)
                    end
                    
                    -- Tooltip
                    local button_id = func.name
                    if reaper.ImGui_IsItemHovered(ctx) then
                        local current_time = reaper.time_precise()
                        if not state.tooltip_timers[button_id] then
                            state.tooltip_timers[button_id] = current_time
                        end
                        if current_time - state.tooltip_timers[button_id] >= Constants.TOOLTIP_DELAY then
                            if reaper.ImGui_BeginTooltip(ctx) then
                                reaper.ImGui_Text(ctx, Helpers.getTooltipText(func))
                                reaper.ImGui_EndTooltip(ctx)
                            end
                        end
                    else
                        state.tooltip_timers[button_id] = nil
                    end
                    
                    -- Pop colors if applied
                    if func.buttonColor and type(func.buttonColor) == "table" then
                        reaper.ImGui_PopStyleColor(ctx, 3)
                    end
                    
                    reaper.ImGui_PopID(ctx)
                end
                
                -- Same line for next button
                if i % buttons_per_row ~= 0 and i < #filtered_funcs then
                    reaper.ImGui_SameLine(ctx)
                end
            end
            reaper.ImGui_EndChild(ctx)
        end
    end
end

-- Render Custom Actions tab
function GUI.renderCustomActionsTab(state, modules)
    local ctx = state.gui.ctx
    local Colors = modules.Colors
    local DataManager = modules.DataManager
    local CustomActionsManager = modules.CustomActionsManager
    local LayoutManager = modules.LayoutManager
    local Helpers = modules.Helpers
    local Themes = modules.Themes
    
    -- Get colors from current theme
    local current_theme = Themes.getCurrentTheme()
    local active_colors = {
        BTN_MARKER_ON  = current_theme.BTN_MARKER_ON,
        BTN_MARKER_OFF = current_theme.BTN_MARKER_OFF,
        BTN_REGION_ON  = current_theme.BTN_REGION_ON,
        BTN_REGION_OFF = current_theme.BTN_REGION_OFF,
        BTN_RELOAD     = current_theme.BTN_RELOAD,
        BTN_MANAGER    = current_theme.BTN_MANAGER,
        BTN_CUSTOM     = current_theme.BTN_CUSTOM,
        BTN_DELETE     = current_theme.BTN_DELETE,
        TEXT_NORMAL    = current_theme.TEXT_NORMAL,
        TEXT_DIM       = current_theme.TEXT_DIM,
        BG_HEADER      = current_theme.BG_HEADER,
    }
    
    local child_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 1
    if reaper.ImGui_BeginChild(ctx, "custom_actions_scroll", 0, 0, child_flags) then
        reaper.ImGui_TextColored(ctx, active_colors.TEXT_NORMAL, "Custom REAPER Actions Manager")
        reaper.ImGui_Separator(ctx)
        
        -- Add/Edit form
        reaper.ImGui_Text(ctx, "Button Name:")
        local name_buf = state.new_action.name or ""
        local name_changed, name_value = reaper.ImGui_InputText(ctx, "##name", name_buf)
        if name_changed then
            state.new_action.name = name_value
        end
        
        reaper.ImGui_Text(ctx, "Action ID:")
        local id_buf = state.new_action.action_id or ""
        local id_changed, id_value = reaper.ImGui_InputText(ctx, "##action_id", id_buf)
        if id_changed then
            state.new_action.action_id = id_value
        end
        
        reaper.ImGui_Text(ctx, "Tooltip (optional):")
        local desc_buf = state.new_action.description or ""
        local desc_changed, desc_value = reaper.ImGui_InputText(ctx, "##description", desc_buf)
        if desc_changed then
            state.new_action.description = desc_value
        end
        
        -- Type selection
        reaper.ImGui_Text(ctx, "Type:")
        reaper.ImGui_SameLine(ctx)
        local type_options = {"marker", "region"}
        local current_type_idx = 1
        if state.new_action.type == "region" then
            current_type_idx = 2
        end
        reaper.ImGui_SetNextItemWidth(ctx, 100)  -- 限制选择框宽度
        if reaper.ImGui_BeginCombo(ctx, "##type_combo", type_options[current_type_idx]) then
            if reaper.ImGui_Selectable(ctx, "marker", state.new_action.type == "marker") then
                state.new_action.type = "marker"
            end
            if reaper.ImGui_Selectable(ctx, "region", state.new_action.type == "region") then
                state.new_action.type = "region"
            end
            reaper.ImGui_EndCombo(ctx)
        end
        
        reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Tip: Enter Action ID (number) or command name. Tooltip will show on hover.")
        reaper.ImGui_Spacing(ctx)
        
        -- Add/Update button
        local btn_text = state.editing_index and " Update " or " Add "
        Helpers.PushBtnStyle(ctx, active_colors.BTN_CUSTOM)
        if reaper.ImGui_Button(ctx, btn_text) then
            if state.editing_index then
                local success, message = CustomActionsManager.updateAction(state.custom_actions, state.editing_index, state.new_action)
                if success then
                    state.editing_index = nil
                    DataManager.saveCustomActions(state.custom_actions)
                    state.new_action = {name = "", action_id = "", description = "", type = "marker"}
                    state.layout_cache_dirty = true
                    state.stash_cache = nil
                end
                state.status_message = message
            else
                local success, message = CustomActionsManager.addAction(state.custom_actions, state.new_action)
                if success then
                    -- Add to active functions automatically
                    local already_added = false
                    for _, active_name in ipairs(state.layout.active) do
                        if active_name == state.new_action.name then
                            already_added = true
                            break
                        end
                    end
                    if not already_added then
                        table.insert(state.layout.active, state.new_action.name)
                        DataManager.saveLayout(state.layout)
                    end
                    DataManager.saveCustomActions(state.custom_actions)
                    state.status_message = string.format("Added custom action: %s [%s]", state.new_action.name, (state.new_action.type or "marker"):upper())
                    state.new_action = {name = "", action_id = "", description = "", type = "marker"}
                    state.layout_cache_dirty = true
                    state.stash_cache = nil
                else
                    state.status_message = message
                end
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        if state.editing_index then
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, " Cancel ") then
                state.editing_index = nil
                state.new_action = {name = "", action_id = "", description = "", type = "marker"}
            end
        end
        
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- List of custom actions
        reaper.ImGui_Text(ctx, "Custom Actions:")
        if #state.custom_actions == 0 then
            reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "No custom actions added yet")
        else
            for i, action in ipairs(state.custom_actions) do
                reaper.ImGui_PushID(ctx, i)
                local action_type = action.type or "marker"
                local type_display = action_type == "region" and "[R]" or "[M]"
                local type_color = action_type == "region" and active_colors.BTN_REGION_ON or active_colors.BTN_MARKER_ON
                reaper.ImGui_Text(ctx, string.format("%d. %s", i, action.name))
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextColored(ctx, type_color, type_display)
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Text(ctx, string.format("(ID: %s)", action.action_id))
                if action.description and action.description ~= "" then
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, " - " .. action.description)
                end
                reaper.ImGui_SameLine(ctx)
                
                -- Edit button
                Helpers.PushBtnStyle(ctx, active_colors.BTN_CUSTOM)
                if reaper.ImGui_Button(ctx, " Edit ") then
                    state.editing_index = i
                    state.new_action.name = action.name
                    state.new_action.action_id = action.action_id
                    state.new_action.description = action.description or ""
                    state.new_action.type = action.type or "marker"
                end
                reaper.ImGui_PopStyleColor(ctx, 3)
                reaper.ImGui_SameLine(ctx)
                
                -- Delete button
                Helpers.PushBtnStyle(ctx, active_colors.BTN_DELETE)
                if reaper.ImGui_Button(ctx, " Del ") then
                    CustomActionsManager.removeFromLayout(state.layout, action.name)
                    local success, message = CustomActionsManager.deleteAction(state.custom_actions, i)
                    DataManager.saveCustomActions(state.custom_actions)
                    DataManager.saveLayout(state.layout)
                    state.status_message = message
                    state.layout_cache_dirty = true
                    state.stash_cache = nil
                end
                reaper.ImGui_PopStyleColor(ctx, 3)
                
                reaper.ImGui_PopID(ctx)
            end
        end
        
        reaper.ImGui_EndChild(ctx)
    end
end

-- Render Layout tab
function GUI.renderLayoutTab(state, modules)
    local ctx = state.gui.ctx
    local Themes = modules.Themes
    local DataManager = modules.DataManager
    local FunctionLoader = modules.FunctionLoader
    local LayoutManager = modules.LayoutManager
    local Helpers = modules.Helpers
    
    -- Get colors from current theme
    local current_theme = Themes.getCurrentTheme()
    local active_colors = {
        BTN_MARKER_ON  = current_theme.BTN_MARKER_ON,
        BTN_MARKER_OFF = current_theme.BTN_MARKER_OFF,
        BTN_REGION_ON  = current_theme.BTN_REGION_ON,
        BTN_REGION_OFF = current_theme.BTN_REGION_OFF,
        BTN_RELOAD     = current_theme.BTN_RELOAD,
        BTN_MANAGER    = current_theme.BTN_MANAGER,
        BTN_CUSTOM     = current_theme.BTN_CUSTOM,
        BTN_DELETE     = current_theme.BTN_DELETE,
        TEXT_NORMAL    = current_theme.TEXT_NORMAL,
        TEXT_DIM       = current_theme.TEXT_DIM,
        BG_HEADER      = current_theme.BG_HEADER,
    }
    
    reaper.ImGui_TextColored(ctx, active_colors.TEXT_NORMAL, "Layout Manager")
    reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Use Functions tab for drag-drop reordering")
    reaper.ImGui_Separator(ctx)
    
    -- Layout Presets Section
    reaper.ImGui_Text(ctx, "Layout Presets:")
    reaper.ImGui_SameLine(ctx)
    
    -- Preset dropdown/combo
    local preset_names = {}
    for name, _ in pairs(state.layout_presets) do
        table.insert(preset_names, name)
    end
    table.sort(preset_names)
    
    local preview_value = state.current_preset_name
    if preview_value == "" then
        preview_value = "(None)"
    end
    
    -- Calculate available width for combo (leave space for buttons)
    -- Use a smaller, fixed maximum width to ensure input box is visible
    local combo_width = 150  -- Fixed compact width for preset combo
    
    reaper.ImGui_SetNextItemWidth(ctx, combo_width)
    if reaper.ImGui_BeginCombo(ctx, "##preset_combo", preview_value) then
        if reaper.ImGui_Selectable(ctx, "(None)", state.current_preset_name == "") then
            state.current_preset_name = ""
        end
        for _, name in ipairs(preset_names) do
            if reaper.ImGui_Selectable(ctx, name, state.current_preset_name == name) then
                local new_layout = LayoutManager.applyLayoutPreset(state.layout_presets, name)
                if new_layout then
                    state.layout = new_layout
                    DataManager.saveLayout(state.layout)
                    state.current_preset_name = name
                    state.layout_cache_dirty = true
                    state.stash_cache = nil
                end
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end
    
    reaper.ImGui_SameLine(ctx)
    -- Save as preset button
    Helpers.PushBtnStyle(ctx, active_colors.BTN_CUSTOM)
    if reaper.ImGui_Button(ctx, " Save As ") then
        if state.new_preset_name and state.new_preset_name ~= "" then
            if LayoutManager.saveCurrentLayoutAsPreset(state.layout, state.layout_presets, state.new_preset_name) then
                DataManager.saveLayoutPresets(state.layout_presets)
                state.current_preset_name = state.new_preset_name
                state.new_preset_name = ""
                state.status_message = "Saved layout as preset: " .. state.current_preset_name
            end
        else
            state.status_message = "Please enter a preset name"
        end
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    
    -- Delete preset button (on same line if preset is selected)
    if state.current_preset_name and state.current_preset_name ~= "" then
        reaper.ImGui_SameLine(ctx)
        Helpers.PushBtnStyle(ctx, active_colors.BTN_DELETE)
        if reaper.ImGui_Button(ctx, " Delete ") then
            if LayoutManager.deleteLayoutPreset(state.layout_presets, state.current_preset_name) then
                DataManager.saveLayoutPresets(state.layout_presets)
                if state.current_preset_name == state.current_preset_name then
                    state.current_preset_name = ""
                end
                state.status_message = "Deleted preset: " .. state.current_preset_name
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
    end
    
    reaper.ImGui_Text(ctx, "Preset Name:")
    reaper.ImGui_SameLine(ctx)
    local name_buf = state.new_preset_name or ""
    local name_changed, name_value = reaper.ImGui_InputText(ctx, "##new_preset_name", name_buf)
    if name_changed then
        state.new_preset_name = name_value
    end
    
    reaper.ImGui_Separator(ctx)
    
    -- Active Functions Section
    reaper.ImGui_Text(ctx, "Active Functions (in UI):")
    reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Use Functions tab for drag-drop reordering")
    local child_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 1
    if reaper.ImGui_BeginChild(ctx, "active_functions", 0, 200, child_flags) then
        -- Cleanup layout only when cache is dirty (not every frame)
        if state.layout_cache_dirty then
            LayoutManager.cleanupLayout(state.layout, function(func_name)
                return FunctionLoader.getFunctionByName(func_name, state.marker_functions, state.custom_actions, active_colors)
            end)
            DataManager.saveLayout(state.layout)
            state.layout_cache_dirty = false
        end
        
        -- Build function cache once (avoid repeated lookups)
        local func_cache = {}
        for idx, func_name in ipairs(state.layout.active) do
            if func_name and func_name ~= "" then
                local func = FunctionLoader.getFunctionByName(func_name, state.marker_functions, state.custom_actions, active_colors)
                if func and func.name then
                    func_cache[idx] = {func = func, name = func_name}
                end
            end
        end
        
        -- Render cached functions (no nested loops)
        for display_idx = 1, #state.layout.active do
            local cached = func_cache[display_idx]
            if cached then
                local func = cached.func
                local func_name = cached.name
                reaper.ImGui_PushID(ctx, "active_" .. display_idx)
                reaper.ImGui_Text(ctx, string.format("%d. %s", display_idx, func.name))
                reaper.ImGui_SameLine(ctx)
                Helpers.PushBtnStyle(ctx, active_colors.BTN_DELETE)
                if reaper.ImGui_Button(ctx, " To Stash ") then
                    if LayoutManager.moveToStash(state.layout, func_name) then
                        DataManager.saveLayout(state.layout)
                        state.status_message = "Moved " .. func.name .. " to stash"
                        -- Mark cache as dirty (will be rebuilt next frame)
                        state.layout_cache_dirty = true
                    end
                end
                reaper.ImGui_PopStyleColor(ctx, 3)
                reaper.ImGui_PopID(ctx)
            end
        end
        reaper.ImGui_EndChild(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- Stash Section
    reaper.ImGui_Text(ctx, "Stash (Available Functions):")
    reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Use 'To UI' button to add functions back")
    if reaper.ImGui_BeginChild(ctx, "stash_functions", 0, 0, child_flags) then
        -- Cache available functions (only recalculate when needed)
        if not state.stash_cache or state.layout_cache_dirty then
            -- Build active set for fast lookup (O(1) instead of O(n))
            local active_set = {}
            for _, name in ipairs(state.layout.active) do
                active_set[name] = true
            end
            
            -- Build available list
            local available = {}
            -- Add builtin functions
            for _, func in ipairs(state.marker_functions) do
                if func and func.name and not active_set[func.name] then
                    local func_copy = {}
                    for k, v in pairs(func) do
                        func_copy[k] = v
                    end
                    func_copy.func_name = func.name
                    table.insert(available, func_copy)
                end
            end
            -- Add custom actions
            for _, action in ipairs(state.custom_actions) do
                if action and action.name and action.action_id and not active_set[action.name] then
                    local action_id = tonumber(action.action_id)
                    if not action_id then
                        action_id = reaper.NamedCommandLookup(action.action_id)
                    end
                    if action_id and action_id > 0 then
                        local action_type = action.type or "marker"
                        local btn_color = active_colors.BTN_MARKER_ON
                        if action_type == "region" then
                            btn_color = active_colors.BTN_REGION_ON
                        end
                        table.insert(available, {
                            name = action.name,
                            description = action.description or "",
                            type = action_type,
                            execute = function()
                                reaper.Main_OnCommand(action_id, 0)
                                return true, "Executed: " .. action.name
                            end,
                            buttonColor = {btn_color, btn_color + 0x11111100, btn_color - 0x11111100},
                            is_custom = true,
                            func_name = action.name
                        })
                    end
                end
            end
            state.stash_cache = available
            state.layout_cache_dirty = false
        end
        
        local available = state.stash_cache
        if #available == 0 then
            reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "All functions are in UI")
        else
            for i, func in ipairs(available) do
                reaper.ImGui_PushID(ctx, "stash_" .. i)
                reaper.ImGui_Text(ctx, func.name)
                if func.is_custom then
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_TextColored(ctx, active_colors.BTN_CUSTOM, "[Custom]")
                end
                reaper.ImGui_SameLine(ctx)
                Helpers.PushBtnStyle(ctx, active_colors.BTN_CUSTOM)
                if reaper.ImGui_Button(ctx, " To UI ") then
                    local func_name = func.func_name or func.name
                    if func_name then
                        if LayoutManager.moveToActive(state.layout, func_name) then
                            DataManager.saveLayout(state.layout)
                            state.status_message = "Moved " .. func.name .. " to UI"
                            -- Mark cache as dirty
                            state.layout_cache_dirty = true
                            state.stash_cache = nil  -- Invalidate cache
                        end
                    end
                end
                reaper.ImGui_PopStyleColor(ctx, 3)
                reaper.ImGui_PopID(ctx)
            end
        end
        reaper.ImGui_EndChild(ctx)
    end
end

return GUI
