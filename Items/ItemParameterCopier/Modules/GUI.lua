--[[
  GUI Module
  Handles all ImGui rendering
]]

local GUI = {}

-- Main render function
function GUI.render(state, modules)
    local Constants = modules.Constants
    local Themes = modules.Themes
    local DataManager = modules.DataManager
    local ParameterManager = modules.ParameterManager
    local Helpers = modules.Helpers
    
    local ctx = state.gui.ctx
    local window_state = state.gui.window_state
    
    -- Apply theme and get colors from current theme
    local current_theme = Themes.getCurrentTheme()
    local style_var_count, color_count = Themes.applyTheme(ctx, current_theme)
    
    -- Get colors from current theme
    local theme_colors = {
        BTN_COPY     = current_theme.BTN_COPY or current_theme.BTN_CUSTOM,
        BTN_PASTE    = current_theme.BTN_PASTE or current_theme.BTN_CUSTOM,
        TEXT_NORMAL  = current_theme.TEXT_NORMAL,
        TEXT_DIM     = current_theme.TEXT_DIM,
        BG_HEADER    = current_theme.BG_HEADER,
    }
    
    local active_colors = theme_colors
    
    -- Track additional style vars we push (for themes without style_vars)
    local additional_style_vars = 0
    if not current_theme.style_vars then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 12, 12)
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
    local visible, open = reaper.ImGui_Begin(ctx, 'Item Parameter Copier', true, reaper.ImGui_WindowFlags_None())
    
    if visible then
        -- Push slightly larger font size for all text
        local font_size = 14
        reaper.ImGui_PushFont(ctx, nil, font_size)
        
        -- Header
        reaper.ImGui_TextColored(ctx, active_colors.TEXT_NORMAL, "Item Parameter Copier")
        reaper.ImGui_Separator(ctx)
        
        -- Check if we have copied data
        local has_copied_data = state.copied_data ~= nil
        
        -- Parameter Selection Area (scrollable)
        local avail_width, avail_height = reaper.ImGui_GetContentRegionAvail(ctx)
        local footer_height = 120
        local scrollable_height = avail_height - footer_height
        
        local child_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 1
        if reaper.ImGui_BeginChild(ctx, "ParamSelectionArea", 0, scrollable_height, child_flags) then
            GUI.renderParameterSelection(ctx, state, modules, active_colors)
            reaper.ImGui_EndChild(ctx)
        end
        
        reaper.ImGui_Separator(ctx)
        
        -- Status and Action Buttons
        reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "Status:")
        reaper.ImGui_SameLine(ctx)
        if has_copied_data then
            reaper.ImGui_TextColored(ctx, active_colors.TEXT_NORMAL, "已复制参数")
        else
            reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, "未复制参数")
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- Action buttons
        local button_width = (avail_width - 10) / 2
        
        -- Copy button
        Helpers.PushBtnStyle(ctx, active_colors.BTN_COPY)
        if reaper.ImGui_Button(ctx, "Copy from Selected", button_width, 35) then
            local sel_count = reaper.CountSelectedMediaItems(0)
            if sel_count > 0 then
                local first_item = reaper.GetSelectedMediaItem(0, 0)
                if first_item then
                    local selected_params = ParameterManager.getSelectedParams(Constants, state.param_checkboxes)
                    local copied_data = ParameterManager.copyItemParameters(first_item, selected_params)
                    if copied_data then
                        state.copied_data = copied_data
                        state.selected_params = selected_params
                        DataManager.saveCopiedData(copied_data, selected_params)
                        state.status_message = "已复制参数"
                    else
                        state.status_message = "复制失败：Item 没有有效的 Take"
                    end
                end
            else
                state.status_message = "请先选中一个 Item"
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_SameLine(ctx)
        
        -- Paste button
        Helpers.PushBtnStyle(ctx, active_colors.BTN_PASTE)
        local paste_enabled = has_copied_data
        if not paste_enabled then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.5)
        end
        if reaper.ImGui_Button(ctx, "Paste to Selected", button_width, 35) and paste_enabled then
            local sel_count = reaper.CountSelectedMediaItems(0)
            if sel_count > 0 then
                -- Verify we have valid data to paste
                if not state.selected_params then
                    state.status_message = "错误：没有可粘贴的参数"
                else
                    reaper.Undo_BeginBlock()
                    reaper.PreventUIRefresh(1)
                    
                    local pasted_count = 0
                    for i = 0, sel_count - 1 do
                        local item = reaper.GetSelectedMediaItem(0, i)
                        if item then
                            if ParameterManager.pasteItemParameters(item, state.copied_data, state.selected_params) then
                                pasted_count = pasted_count + 1
                            end
                        end
                    end
                    
                    -- Force update all items and arrange view
                    reaper.PreventUIRefresh(-1)
                    reaper.UpdateArrange()
                    reaper.UpdateTimeline()
                    reaper.Undo_EndBlock("Paste Item Parameters", -1)
                    
                    state.status_message = string.format("已粘贴到 %d 个 Item", pasted_count)
                end
            else
                state.status_message = "请先选中目标 Item"
            end
        end
        if not paste_enabled then
            reaper.ImGui_PopStyleVar(ctx, 1)
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        -- Status message
        if state.status_message then
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_TextColored(ctx, active_colors.TEXT_DIM, state.status_message)
        end
        
        -- Pop font size
        reaper.ImGui_PopFont(ctx)
        
        reaper.ImGui_End(ctx)
    end
    
    -- Pop theme styles and colors
    Themes.popTheme(ctx, style_var_count, color_count)
    
    -- Pop additional style vars we added
    if additional_style_vars > 0 then
        reaper.ImGui_PopStyleVar(ctx, additional_style_vars)
    end
    
    -- Update window state
    if visible then
        local wx, wy = reaper.ImGui_GetWindowPos(ctx)
        local ww, wh = reaper.ImGui_GetWindowSize(ctx)
        window_state.x = wx
        window_state.y = wy
        window_state.width = ww
        window_state.height = wh
    end
    
    -- Return whether to continue
    return open and state.gui.visible
end

-- Render parameter selection checkboxes
function GUI.renderParameterSelection(ctx, state, modules, active_colors)
    local Constants = modules.Constants
    
    -- Select All / Deselect All buttons
    local all_selected = true
    local any_selected = false
    
    -- Check all checkboxes state
    for _, param in ipairs(Constants.TAKE_PARAMS) do
        local key = "take_" .. param.key
        if state.param_checkboxes[key] then
            any_selected = true
        else
            all_selected = false
        end
    end
    
    for _, param in ipairs(Constants.ITEM_PARAMS) do
        local key = "item_" .. param.key
        if state.param_checkboxes[key] then
            any_selected = true
        else
            all_selected = false
        end
    end
    
    for _, env in ipairs(Constants.ENVELOPES) do
        local key = "env_" .. env.name
        if state.param_checkboxes[key] then
            any_selected = true
        else
            all_selected = false
        end
    end
    
    -- Select All / Deselect All buttons
    if all_selected then
        if reaper.ImGui_Button(ctx, "Deselect All", -1, 25) then
            -- Deselect all
            for _, param in ipairs(Constants.TAKE_PARAMS) do
                state.param_checkboxes["take_" .. param.key] = false
            end
            for _, param in ipairs(Constants.ITEM_PARAMS) do
                state.param_checkboxes["item_" .. param.key] = false
            end
            for _, env in ipairs(Constants.ENVELOPES) do
                state.param_checkboxes["env_" .. env.name] = false
            end
        end
    else
        if reaper.ImGui_Button(ctx, "Select All", -1, 25) then
            -- Select all
            for _, param in ipairs(Constants.TAKE_PARAMS) do
                state.param_checkboxes["take_" .. param.key] = true
            end
            for _, param in ipairs(Constants.ITEM_PARAMS) do
                state.param_checkboxes["item_" .. param.key] = true
            end
            for _, env in ipairs(Constants.ENVELOPES) do
                state.param_checkboxes["env_" .. env.name] = true
            end
        end
    end
    
    reaper.ImGui_Separator(ctx)
    
    -- Take Parameters section
    reaper.ImGui_TextColored(ctx, active_colors.TEXT_NORMAL, Constants.PARAM_GROUPS.TAKE)
    reaper.ImGui_Separator(ctx)
    
    for _, param in ipairs(Constants.TAKE_PARAMS) do
        local key = "take_" .. param.key
        local label = param.name .. " (" .. param.desc .. ")"
        local checked = state.param_checkboxes[key] or false
        local changed, new_value = reaper.ImGui_Checkbox(ctx, label .. "##" .. key, checked)
        if changed then
            state.param_checkboxes[key] = new_value
        end
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- Item Parameters section
    reaper.ImGui_TextColored(ctx, active_colors.TEXT_NORMAL, Constants.PARAM_GROUPS.ITEM)
    reaper.ImGui_Separator(ctx)
    
    for _, param in ipairs(Constants.ITEM_PARAMS) do
        local key = "item_" .. param.key
        local label = param.name .. " (" .. param.desc .. ")"
        local checked = state.param_checkboxes[key] or false
        local changed, new_value = reaper.ImGui_Checkbox(ctx, label .. "##" .. key, checked)
        if changed then
            state.param_checkboxes[key] = new_value
        end
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- Envelopes section
    reaper.ImGui_TextColored(ctx, active_colors.TEXT_NORMAL, Constants.PARAM_GROUPS.ENVELOPES)
    reaper.ImGui_Separator(ctx)
    
    for _, env in ipairs(Constants.ENVELOPES) do
        local key = "env_" .. env.name
        local label = env.name .. " (" .. env.desc .. ")"
        local checked = state.param_checkboxes[key] or false
        local changed, new_value = reaper.ImGui_Checkbox(ctx, label .. "##" .. key, checked)
        if changed then
            state.param_checkboxes[key] = new_value
        end
    end
end

return GUI

