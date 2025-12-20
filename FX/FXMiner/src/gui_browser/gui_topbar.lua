-- FXMiner/src/gui_browser/gui_topbar.lua
-- 顶部栏 UI：标题、搜索、模式切换、同步按钮

local Topbar = {}

-- Dependencies (will be injected)
local App, DB, Config, Engine = nil, nil, nil, nil
local state = nil
local GuiUtils = nil
local GuiList = nil

-- Draw topbar
function Topbar.draw(ctx)
  local ImGui = App.ImGui

  -- Title row + settings + close button on the right
  local title = "FXMiner"
  local x_label = "X"
  local gear_label = "⚙"
  local btn_w = 24

  if App._theme and App._theme.fonts and App._theme.fonts.heading1 then
    ImGui.PushFont(ctx, App._theme.fonts.heading1)
    ImGui.Text(ctx, title)
    ImGui.PopFont(ctx)
  else
    ImGui.Text(ctx, title)
  end

  -- Status text next to title (dimmer font)
  if state.status and state.status ~= "" then
    ImGui.SameLine(ctx)
    local col_text = type(ImGui.Col_Text) == "function" and ImGui.Col_Text() or ImGui.Col_Text
    if ImGui.PushStyleColor and col_text then
      ImGui.PushStyleColor(ctx, col_text, 0x888888FF) -- More dim
      ImGui.Text(ctx, "| " .. state.status)
      ImGui.PopStyleColor(ctx, 1)
    else
      ImGui.Text(ctx, "| " .. state.status)
    end
  end

  -- Right-side buttons: Settings + Close
  if ImGui.SameLine and ImGui.SetCursorPosX and ImGui.GetContentRegionAvail then
    local avail = ImGui.GetContentRegionAvail(ctx)
    local cur_x = ImGui.GetCursorPosX(ctx)
    local total_btn_w = btn_w * 2 + 8
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, math.max(cur_x, cur_x + avail - total_btn_w))
  else
    ImGui.SameLine(ctx)
  end

  -- Settings button (gear icon)
  if ImGui.PushStyleColor and ImGui.PopStyleColor then
    local gear_col = state.show_settings and 0x80B0FFFF or 0xA0A0A0FF
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x404040FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, gear_col)
    if ImGui.Button(ctx, gear_label .. "##settings_btn", btn_w, 0) then
      state.show_settings = not state.show_settings
    end
    ImGui.PopStyleColor(ctx, 4)
  else
    if ImGui.Button(ctx, gear_label .. "##settings_btn") then
      state.show_settings = not state.show_settings
    end
  end

  ImGui.SameLine(ctx)

  -- Close button (red X)
  if ImGui.PushStyleColor and ImGui.PopStyleColor then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x404040FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF4040FF)
    if ImGui.Button(ctx, x_label .. "##close_btn", btn_w, 0) then
      App.open = false
    end
    ImGui.PopStyleColor(ctx, 4)
  else
    if ImGui.Button(ctx, x_label .. "##close_btn") then
      App.open = false
    end
  end

  ImGui.Separator(ctx)

  -- Search row with Library mode toggle
  -- [Local] [Team] | [Search.............]

  -- Library mode buttons
  local local_active = (state.library_mode == "local")
  local team_active = (state.library_mode == "team")

  if local_active then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x4080B0FF)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x303030FF)
  end
  if ImGui.Button(ctx, "Local##lib_local", 50, 0) then
    state.library_mode = "local"
  end
  ImGui.PopStyleColor(ctx, 1)

  ImGui.SameLine(ctx)

  if team_active then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x4080B0FF)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x303030FF)
  end
  local team_enabled = Config.TEAM_PUBLISH_PATH and Config.TEAM_PUBLISH_PATH ~= ""
  if not team_enabled and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx, true) end
  if ImGui.Button(ctx, "Team##lib_team", 50, 0) then
    if team_enabled then
      state.library_mode = "team"
      -- Clear and reload team entries when switching to team mode
      state.team_entries = {}
      -- Ensure we use current TEAM_PUBLISH_PATH (clear TEAM_DB_PATH if needed)
      if Config.TEAM_DB_PATH and Config.TEAM_DB_PATH ~= "" then
        -- If TEAM_DB_PATH is set, check if it matches current TEAM_PUBLISH_PATH
        local expected_db_path = Config.path_join(Config.TEAM_PUBLISH_PATH, "server_db.json")
        if Config.TEAM_DB_PATH ~= expected_db_path then
          -- Path changed, clear TEAM_DB_PATH to force derivation from TEAM_PUBLISH_PATH
          Config.TEAM_DB_PATH = ""
        end
      end
      local team_db_path = nil
      if Config.get_team_db_path then
        team_db_path = Config.get_team_db_path()
      elseif Config.path_join and Config.TEAM_PUBLISH_PATH then
        team_db_path = Config.path_join(Config.TEAM_PUBLISH_PATH, "server_db.json")
      end
      if team_db_path and team_db_path ~= "" then
        state.team_entries = DB:get_team_entries(team_db_path) or {}
        state.team_last_sync = os.time()
      end
    end
  end
  if not team_enabled and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end
  ImGui.PopStyleColor(ctx, 1)

  ImGui.SameLine(ctx)

  -- Refresh button
  if ImGui.Button(ctx, "Refresh", 55, 0) then
    state.status = "Refreshing..."
    -- Perform full scan and prune to remove ghost files
    DB:scan_fxchains()
    DB:prune_missing_files()
    DB:load() -- Reload local DB
    if team_enabled then
      -- Clear old entries first
      state.team_entries = {}
      -- Get current team DB path (should derive from current TEAM_PUBLISH_PATH)
      local team_db_path = nil
      if Config.get_team_db_path then
        team_db_path = Config.get_team_db_path()
      elseif Config.TEAM_DB_PATH and Config.TEAM_DB_PATH ~= "" then
        team_db_path = Config.TEAM_DB_PATH
      elseif Config.path_join and Config.TEAM_PUBLISH_PATH then
        team_db_path = Config.path_join(Config.TEAM_PUBLISH_PATH, "server_db.json")
      end
      if team_db_path and team_db_path ~= "" then
        state.team_entries = DB:get_team_entries(team_db_path) or {}
      end
    end
    state.status = "Refreshed"
  end

  ImGui.SameLine(ctx, nil, 20)

  -- Folder buttons (using SmallButton to save space)
  local function open_folder(path)
    if not path or path == "" then return end
    if reaper.CF_ShellExecute then
      reaper.CF_ShellExecute(path)
    else
      local cmd = string.format('explorer "%s"', path:gsub("/", "\\"))
      os.execute(cmd)
    end
  end

  if ImGui.SmallButton(ctx, "Local Folder") then
    open_folder(Config.FXCHAINS_ROOT)
  end

  ImGui.SameLine(ctx)

  if not team_enabled and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx, true) end
  if ImGui.SmallButton(ctx, "Team Folder") then
    open_folder(Config.TEAM_PUBLISH_PATH)
  end
  if not team_enabled and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end

  ImGui.Spacing(ctx)

  -- Search input (leave space for sync buttons on the right)
  local sync_btn_width = team_enabled and 130 or 0
  ImGui.SetNextItemWidth(ctx, -sync_btn_width - 8)
  _, state.search = ImGui.InputText(ctx, "##search_input", state.search)

  -- Sync buttons on the right of search bar
  if team_enabled then
    ImGui.SameLine(ctx)

        -- Pull/Sync button (full sync or selected items)
        local sel_count = GuiList and GuiList.count_selected() or 0
        local sync_label = "↓Sync"
        local sync_tooltip = "Sync all team entries"
        
        -- Check if we're in team mode and have selected items
        local has_selected_team_items = false
        local selected_filenames = {}
        if state.library_mode == "team" and sel_count > 0 then
          -- Collect selected team item filenames
          for item_id, _ in pairs(state.selected_items) do
            if item_id:match("^team:") then
              local filename = item_id:gsub("^team:", "")
              if filename and filename ~= "" then
                table.insert(selected_filenames, filename)
                has_selected_team_items = true
              end
            end
          end
          
          if has_selected_team_items then
            sync_label = "↓Sync(" .. #selected_filenames .. ")"
            sync_tooltip = "Sync selected " .. #selected_filenames .. " item(s) from team"
          end
        end
        
        if ImGui.Button(ctx, sync_label, 60, 0) then
          if not state.sync_in_progress then
            state.sync_in_progress = true
            state.team_sync_status = has_selected_team_items and ("Syncing " .. #selected_filenames .. " item(s)...") or "Syncing..."

            local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
            if team_db_path then
              local pull_opts = {}
              if has_selected_team_items then
                pull_opts.selected_filenames = selected_filenames
              end
              
              local ok, msg, stats = DB:pull_from_team(
                Config.TEAM_PUBLISH_PATH,
                team_db_path,
                Config.TEAM_DOWNLOAD_DIR or Config.FXCHAINS_ROOT,
                pull_opts
              )

              if ok then
                state.team_entries = DB:get_team_entries(team_db_path)
                state.team_last_sync = os.time()
                state.team_sync_status = "✓ " .. tostring(msg)
                state.status = "Sync success: " .. tostring(msg)
              else
                state.team_sync_status = "✗ " .. tostring(msg)
                state.status = "Sync failed: " .. tostring(msg)
              end
            else
              state.team_sync_status = "Team path not configured"
              state.status = "Team path not configured"
            end
            state.sync_in_progress = false
          end
        end
        
        -- Show tooltip for sync button
        if sync_tooltip and ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.SetTooltip then
          ImGui.SetTooltip(ctx, sync_tooltip)
        end

        ImGui.SameLine(ctx)

    -- Push button (push selected items)
    local sel_count = 0
    for _ in pairs(state.selected_items) do sel_count = sel_count + 1 end
    local push_label = sel_count > 1 and ("↑Push(" .. sel_count .. ")") or "↑Push"

    local can_push = sel_count > 0 and state.library_mode == "local"
    if not can_push and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx, true) end

    if ImGui.Button(ctx, push_label, 65, 0) then
      if not state.sync_in_progress and sel_count > 0 then
        state.sync_in_progress = true
        state.team_sync_status = "Pushing " .. sel_count .. " item(s)..."

        local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
        
        -- Run in pcall to ensure sync_in_progress is reset
        local ok_sync, err_sync = pcall(function()
          local success_count = 0
          local fail_count = 0
          
          if not Engine then
            error("Engine module not loaded. Please check if src/fx_engine.lua exists.")
          end

          for rel, _ in pairs(state.selected_items) do
            if not rel:match("^team:") then
              local e = DB:find_entry_by_rel(rel)
              if e then
                local abs_path = DB:rel_to_abs(e.rel_path)
                if abs_path then
                  -- Copy file
                  local result, msg = Engine.publish_to_team(Config, abs_path, { force_overwrite = true })

                  if result == Engine.PUBLISH_OK then
                    -- Sync metadata with lock
                    if team_db_path then
                      local metadata = {
                        name = e.name,
                        description = e.description,
                        metadata = e.metadata,
                        plugins = e.plugins,
                      }
                      DB:push_to_team_locked(Config.TEAM_PUBLISH_PATH, team_db_path, abs_path, metadata)
                    end
                    success_count = success_count + 1
                  else
                    fail_count = fail_count + 1
                  end
                end
              end
            end
          end

          -- Refresh team entries
          if team_db_path then
            state.team_entries = DB:get_team_entries(team_db_path)
          end

          if fail_count == 0 then
            state.team_sync_status = "✓ Pushed " .. success_count .. " item(s)"
            -- Clear local selection after successful push
            state.selected_items = {}
          else
            state.team_sync_status = "Pushed " .. success_count .. ", failed " .. fail_count
          end
        end)

        if not ok_sync then
          state.team_sync_status = "✗ Error: " .. tostring(err_sync)
          state.status = "Push error: " .. tostring(err_sync)
        else
          state.status = state.team_sync_status
        end
        state.sync_in_progress = false
      end
    end

    if not can_push and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end
  end

  ImGui.Spacing(ctx)
end

-- Initialize topbar module
function Topbar.init(app_ctx, db_instance, cfg, engine, state_table, gui_utils_module, gui_list_module)
  App = app_ctx
  DB = db_instance
  Config = cfg
  Engine = engine
  state = state_table
  GuiUtils = gui_utils_module
  GuiList = gui_list_module
end

return Topbar

