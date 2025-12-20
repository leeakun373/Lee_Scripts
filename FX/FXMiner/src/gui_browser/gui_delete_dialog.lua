-- FXMiner/src/gui_browser/gui_delete_dialog.lua
-- 删除确认对话框

local GuiDeleteDialog = {}

-- Get dependencies (will be injected)
local state = nil
local App, DB, Config = nil, nil, nil
local Utils = nil
local GuiList = nil -- For count_selected

-- Initialize dependencies
function GuiDeleteDialog.init(_state, _App, _DB, _Config, _Utils, _GuiList)
  state = _state
  App = _App
  DB = _DB
  Config = _Config
  Utils = _Utils
  GuiList = _GuiList
end

-- Draw delete confirmation dialog
function GuiDeleteDialog.draw(ctx)
  local ImGui = App.ImGui
  local r = reaper

  if not state.show_delete_confirm then return end

  -- Open popup if not already open
  if ImGui.BeginPopupModal then
    local popup_flags = 0
    -- WindowFlags_AlwaysAutoResize is a constant (number), not a function
    if ImGui.WindowFlags_AlwaysAutoResize then
      popup_flags = ImGui.WindowFlags_AlwaysAutoResize
    end

    -- Set next window to center
    if ImGui.SetNextWindowPos then
      -- Use reaper API directly for viewport operations
      local r = reaper
      if r.ImGui_GetMainViewport and r.ImGui_Viewport_GetCenter then
        local viewport = r.ImGui_GetMainViewport(ctx)
        if viewport then
          local center = { r.ImGui_Viewport_GetCenter(viewport) }
          if center[1] and center[2] then
            local cond_appearing = ImGui.Cond_Appearing
            if type(cond_appearing) == "function" then
              cond_appearing = cond_appearing()
            elseif type(cond_appearing) ~= "number" then
              cond_appearing = 0x00000001
            end
            ImGui.SetNextWindowPos(ctx, center[1], center[2], cond_appearing, 0.5, 0.5)
          end
        end
      end
    end

    -- Set window size for better appearance
    if ImGui.SetNextWindowSize then
      ImGui.SetNextWindowSize(ctx, 400, 0, ImGui.Cond_Appearing or 0x00000001)
    end

    -- Apply window rounding for modern look
    if ImGui.PushStyleVar then
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding or 0x00000005, 8)
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding or 0x00000008, 24, 20)
    end

    -- Apply popup background color
    if ImGui.PushStyleColor and ImGui.PopStyleColor then
      local col_popup_bg = type(ImGui.Col_PopupBg) == "function" and ImGui.Col_PopupBg() or ImGui.Col_PopupBg
      ImGui.PushStyleColor(ctx, col_popup_bg, 0x2A2A2AFF) -- Darker background
    end

    if ImGui.BeginPopupModal(ctx, "确认删除##delete_confirm", nil, popup_flags) then
      ImGui.Spacing(ctx)
      
      -- Title text with emphasis
      if ImGui.PushStyleColor and ImGui.PopStyleColor then
        local col_text = type(ImGui.Col_Text) == "function" and ImGui.Col_Text() or ImGui.Col_Text
        ImGui.PushStyleColor(ctx, col_text, 0xFFFFFFFF) -- Bright white for title
      end
      
      if ImGui.PushFont and App._theme and App._theme.fonts and App._theme.fonts.heading1 then
        ImGui.PushFont(ctx, App._theme.fonts.heading1)
      end
      
      if state.delete_selected_items then
        local sel_count = GuiList and GuiList.count_selected() or 0
        ImGui.Text(ctx, "删除 " .. sel_count .. " 个项目")
      else
        local name = state.delete_target_name or "此项目"
        ImGui.Text(ctx, "删除 \"" .. name .. "\"")
      end
      
      if ImGui.PushFont and App._theme and App._theme.fonts and App._theme.fonts.heading1 then
        ImGui.PopFont(ctx)
      end
      
      if ImGui.PushStyleColor and ImGui.PopStyleColor then
        ImGui.PopStyleColor(ctx, 1)
      end
      
      ImGui.Spacing(ctx)
      ImGui.Spacing(ctx)
      
      -- Warning message with subtle color
      if ImGui.PushStyleColor and ImGui.PopStyleColor then
        local col_text = type(ImGui.Col_Text) == "function" and ImGui.Col_Text() or ImGui.Col_Text
        ImGui.PushStyleColor(ctx, col_text, 0xCCCCCCFF) -- Lighter gray for warning text
      end
      
      ImGui.TextWrapped(ctx, "此操作将永久删除文件并移除数据库条目。")
      ImGui.Spacing(ctx)
      ImGui.TextWrapped(ctx, "此操作无法撤销，请谨慎确认。")
      
      if ImGui.PushStyleColor and ImGui.PopStyleColor then
        ImGui.PopStyleColor(ctx, 1)
      end

      ImGui.Spacing(ctx)
      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- Button area with better spacing and alignment
      local btn_w = 100
      local btn_spacing = 12
      local btn_h = 32
      
      -- Get window width for centering
      local window_width = ImGui.GetWindowWidth and ImGui.GetWindowWidth(ctx) or 400
      local total_btn_width = btn_w * 2 + btn_spacing
      local start_x = (window_width - total_btn_width) * 0.5
      
      -- Align buttons to center
      ImGui.SetCursorPosX(ctx, start_x)

      -- Cancel button (neutral style)
      if ImGui.PushStyleColor and ImGui.PopStyleColor then
        local col_button = type(ImGui.Col_Button) == "function" and ImGui.Col_Button() or ImGui.Col_Button
        local col_button_hovered = type(ImGui.Col_ButtonHovered) == "function" and ImGui.Col_ButtonHovered() or ImGui.Col_ButtonHovered
        ImGui.PushStyleColor(ctx, col_button, 0x404040FF) -- Dark gray
        ImGui.PushStyleColor(ctx, col_button_hovered, 0x505050FF) -- Lighter gray on hover
      end
      
      if ImGui.PushStyleVar and ImGui.PopStyleVar then
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding or 0x00000006, 4) -- Rounded buttons
      end
      
      if ImGui.Button(ctx, "取消", btn_w, btn_h) then
        state.show_delete_confirm = false
        state.delete_target_rel = nil
        state.delete_target_name = nil
        state.delete_selected_items = false
        if ImGui.CloseCurrentPopup then ImGui.CloseCurrentPopup(ctx) end
      end
      
      if ImGui.PushStyleVar and ImGui.PopStyleVar then
        ImGui.PopStyleVar(ctx, 1)
      end
      
      if ImGui.PushStyleColor and ImGui.PopStyleColor then
        ImGui.PopStyleColor(ctx, 2)
      end

      ImGui.SameLine(ctx, 0, btn_spacing)

      -- Confirm button (red with gradient effect)
      if ImGui.PushStyleColor and ImGui.PopStyleColor then
        local col_button = type(ImGui.Col_Button) == "function" and ImGui.Col_Button() or ImGui.Col_Button
        local col_button_hovered = type(ImGui.Col_ButtonHovered) == "function" and ImGui.Col_ButtonHovered() or ImGui.Col_ButtonHovered
        local col_text = type(ImGui.Col_Text) == "function" and ImGui.Col_Text() or ImGui.Col_Text
        ImGui.PushStyleColor(ctx, col_button, 0xCC3333FF) -- Red button
        ImGui.PushStyleColor(ctx, col_button_hovered, 0xFF4444FF) -- Brighter red on hover
        ImGui.PushStyleColor(ctx, col_text, 0xFFFFFFFF) -- White text on red button
      end
      
      if ImGui.PushStyleVar and ImGui.PopStyleVar then
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding or 0x00000006, 4) -- Rounded buttons
      end

      if ImGui.Button(ctx, "删除", btn_w, btn_h) then
        r.Undo_BeginBlock()

        if state.delete_selected_items then
          -- Delete all selected items
          local deleted_count = 0
          local failed_count = 0
          local to_delete = {}
          for rel, _ in pairs(state.selected_items) do
            if not rel:match("^team:") then
              table.insert(to_delete, rel)
            end
          end

          for _, rel in ipairs(to_delete) do
            local e = DB:find_entry_by_rel(rel)
            local name = e and e.name or rel
            local ok, err = DB:delete_entry(rel, { delete_file = true })
            if ok then
              deleted_count = deleted_count + 1
              state.selected_items[rel] = nil
            else
              failed_count = failed_count + 1
              state.status = "删除失败: " .. tostring(name) .. " - " .. tostring(err)
            end
          end

          if deleted_count > 0 then
            state.status = "已删除 " .. deleted_count .. " 个项目"
            if failed_count > 0 then
              state.status = state.status .. "，" .. failed_count .. " 个失败"
            end
          end

          -- Clear selection if current item was deleted
          if state.selected_rel and state.selected_items[state.selected_rel] then
            state.selected_rel = nil
            Utils.set_selected_entry(nil)
          end
        else
          -- Delete single item
          local rel = state.delete_target_rel
          if rel and not rel:match("^team:") then
            local ok, err = DB:delete_entry(rel, { delete_file = true })
            if ok then
              state.status = "已删除: " .. tostring(state.delete_target_name or "")
              state.selected_items[rel] = nil
              if state.selected_rel == rel then
                state.selected_rel = nil
                Utils.set_selected_entry(nil)
              end
            else
              state.status = "删除失败: " .. tostring(err)
            end
          end
        end

        r.Undo_EndBlock("FXMiner: Delete FXChain", -1)

        state.show_delete_confirm = false
        state.delete_target_rel = nil
        state.delete_target_name = nil
        state.delete_selected_items = false
        if ImGui.CloseCurrentPopup then ImGui.CloseCurrentPopup(ctx) end
      end

      if ImGui.PushStyleVar and ImGui.PopStyleVar then
        ImGui.PopStyleVar(ctx, 1)
      end
      
      if ImGui.PushStyleColor and ImGui.PopStyleColor then
        ImGui.PopStyleColor(ctx, 3)
      end
      
      ImGui.Spacing(ctx)
      ImGui.EndPopup(ctx)
    end
    
    -- Pop style vars and colors (applied to window)
    if ImGui.PushStyleVar and ImGui.PopStyleVar then
      ImGui.PopStyleVar(ctx, 2)
    end
    
    if ImGui.PushStyleColor and ImGui.PopStyleColor then
      ImGui.PopStyleColor(ctx, 1)
    end
  end
end

return GuiDeleteDialog
