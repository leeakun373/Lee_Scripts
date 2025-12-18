-- FXMiner/src/gui_saver.lua
-- UI for saving FX Chains with metadata and virtual folder assignment

local W = require("widgets")

local GuiSaver = {}

local App, DB, Engine, Config

local state = {
  name = "",
  -- Physical folder (on disk)
  disk_folder_list = {""},
  disk_folder_idx = 1,
  -- Virtual folder (in DB)
  virtual_folder_id = 0,
  -- Dynamic fields (from config_fields.json)
  field_inputs = {},
  -- Description
  description = "",
  -- Publish option
  publish_to_team = false,
  -- Status message
  status = "",

  -- Publish conflict modal state
  show_conflict_modal = false,
  conflict_target_path = nil,
  conflict_source_path = nil,
  conflict_filename = nil,
  conflict_metadata = nil,
}

local function trim(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Build list of physical subdirectories under FXChains root
local function build_disk_folder_list()
  local sep = Config.PATH_SEP

  local list = {""} -- root

  local function path_join(a, b)
    if not a or a == "" then return b end
    if not b or b == "" then return a end
    a = tostring(a):gsub("[\\/]+$", "")
    b = tostring(b):gsub("^[\\/]+", "")
    return a .. sep .. b
  end

  local function walk(abs_dir, rel_prefix)
    local idx = 0
    while true do
      local sub = reaper.EnumerateSubdirectories(abs_dir, idx)
      if not sub then break end
      idx = idx + 1

      if not (Config.EXCLUDED_FOLDERS and Config.EXCLUDED_FOLDERS[sub]) then
        local rel = (rel_prefix == "") and sub or (rel_prefix .. "/" .. sub)
        list[#list + 1] = rel
        walk(path_join(abs_dir, sub), rel)
      end
    end
  end

  walk(Config.FXCHAINS_ROOT, "")

  table.sort(list, function(a, b)
    if a == "" then return true end
    if b == "" then return false end
    return a:lower() < b:lower()
  end)

  return list
end

-- Build flat list of virtual folders for dropdown (synced with Browser display)
local function build_virtual_folder_list()
  local out = {}

  local function collect(parent_id, depth)
    local children = DB:list_children(parent_id)
    for _, f in ipairs(children) do
      local id = tonumber(f.id) or 0
      if id ~= 0 then -- skip Root itself, but include its children
        local indent = string.rep("  ", depth)
        out[#out + 1] = {
          id = id,
          name = f.name or ("Folder " .. id),
          label = indent .. (f.name or ("Folder " .. id)),
        }
        collect(id, depth + 1)
      end
    end
  end

  -- Add "All" as first option (id = 0, synced with Browser's "All")
  out[#out + 1] = { id = 0, name = "All", label = "All" }
  collect(0, 0)

  return out
end

function GuiSaver.init(app_ctx, db_instance, fx_engine, cfg)
  App = app_ctx
  DB = db_instance
  Engine = fx_engine
  Config = cfg

  state.name = Engine.get_selected_track_name() or "Untitled Chain"
  state.disk_folder_list = build_disk_folder_list()
  state.disk_folder_idx = 1
  state.virtual_folder_id = 0
  state.field_inputs = {}
  state.description = ""
  state.publish_to_team = false
  state.status = ""

  -- Reset conflict modal state
  state.show_conflict_modal = false
  state.conflict_target_path = nil
  state.conflict_source_path = nil
  state.conflict_filename = nil
  state.conflict_metadata = nil
end

-- Execute the publish to team action
-- Returns: success, message
local function do_publish_to_team(source_path, metadata, opts)
  opts = opts or {}
  
  -- [DEBUG] 开始：打印配置路径
  local team_path = Config.TEAM_PUBLISH_PATH
  -- 这里加了双保险：如果函数不存在，直接读变量
  local team_db_path = (Config.get_team_db_path and Config.get_team_db_path()) or Config.TEAM_DB_PATH
  
  if not team_path or team_path == "" then 
    return false, "Config Error: Path missing" 
  end
  if not team_db_path or team_db_path == "" then 
    return false, "Config Error: DB Path missing" 
  end

  -- Step 1: 物理文件复制
  local result, msg, published_path = Engine.publish_to_team(Config, source_path, opts)

  if result == Engine.PUBLISH_ERROR then
    return false, msg
  end

  if result == Engine.PUBLISH_EXISTS and not opts.force_overwrite and not opts.auto_rename then
    state.show_conflict_modal = true
    state.conflict_target_path = msg 
    state.conflict_source_path = source_path
    state.conflict_filename = Engine.get_filename(source_path)
    state.conflict_metadata = metadata
    return nil, "conflict" 
  end
  
  -- Step 2: 数据库同步 (带锁)
  local sync_ok, sync_err = DB:push_to_team_locked(
      team_path,       
      team_db_path,    
      published_path or source_path, 
      metadata         
  )

  if not sync_ok then
    return true, "File copied but DB sync failed: " .. tostring(sync_err)
  end

  return true, "Published to Team!"
end

-- Draw conflict resolution modal
local function draw_conflict_modal(ctx)
  local ImGui = App.ImGui

  if not state.show_conflict_modal then
    return
  end

  -- Open popup if not already open
  if not ImGui.IsPopupOpen(ctx, "Publish Conflict") then
    ImGui.OpenPopup(ctx, "Publish Conflict")
  end

  local popup_flags = 0
  if ImGui.WindowFlags_AlwaysAutoResize then
    popup_flags = ImGui.WindowFlags_AlwaysAutoResize()
  end

  if ImGui.BeginPopupModal(ctx, "Publish Conflict", nil, popup_flags) then
    ImGui.Text(ctx, "File already exists on team server!")
    ImGui.Spacing(ctx)

    ImGui.TextWrapped(ctx, "File: " .. tostring(state.conflict_filename or "Unknown"))
    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- Overwrite button
    if ImGui.Button(ctx, "Overwrite", 100, 0) then
      local ok, msg = do_publish_to_team(
        state.conflict_source_path,
        state.conflict_metadata,
        { force_overwrite = true }
      )
      state.show_conflict_modal = false
      state.status = ok and msg or ("Publish failed: " .. tostring(msg))
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.SameLine(ctx)

    -- Auto-Rename button
    if ImGui.Button(ctx, "Auto-Rename", 100, 0) then
      local ok, msg = do_publish_to_team(
        state.conflict_source_path,
        state.conflict_metadata,
        { auto_rename = true }
      )
      state.show_conflict_modal = false
      state.status = ok and msg or ("Publish failed: " .. tostring(msg))
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.SameLine(ctx)

    -- Cancel button
    if ImGui.Button(ctx, "Cancel", 100, 0) then
      state.show_conflict_modal = false
      state.status = "Publish cancelled"
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end
end

function GuiSaver.draw(ctx)
  local ImGui = App.ImGui

  -- Draw conflict modal if active
  draw_conflict_modal(ctx)

  -- Title
  if App._theme and App._theme.fonts and App._theme.fonts.heading1 then
    ImGui.PushFont(ctx, App._theme.fonts.heading1)
    ImGui.Text(ctx, "FXMiner - Saver")
    ImGui.PopFont(ctx)
  else
    ImGui.Text(ctx, "FXMiner - Saver")
  end

  ImGui.Separator(ctx)

  -- Name
  ImGui.Text(ctx, "Name")
  ImGui.PushItemWidth(ctx, -1)
  _, state.name = ImGui.InputText(ctx, "##saver_name", state.name)
  ImGui.PopItemWidth(ctx)

  ImGui.Spacing(ctx)

  -- Virtual Folder (Library Folder)
  W.separator_text(ctx, ImGui, "Add to Library Folder")
  ImGui.PushItemWidth(ctx, -1)

  local vf_list = build_virtual_folder_list()
  local vf_preview = "All"
  for _, vf in ipairs(vf_list) do
    if vf.id == state.virtual_folder_id then
      vf_preview = vf.label
      break
    end
  end

  if ImGui.BeginCombo(ctx, "##saver_vfolder", vf_preview) then
    for _, vf in ipairs(vf_list) do
      local selected = (vf.id == state.virtual_folder_id)
      if ImGui.Selectable(ctx, vf.label .. "##vf_" .. tostring(vf.id), selected) then
        state.virtual_folder_id = vf.id
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.PopItemWidth(ctx)

  ImGui.Spacing(ctx)

  -- Physical Folder (on disk)
  W.separator_text(ctx, ImGui, "Save to Disk Folder")
  ImGui.PushItemWidth(ctx, -1)

  local df_preview = state.disk_folder_list[state.disk_folder_idx] or ""
  if df_preview == "" then df_preview = "(FXChains root)" end

  if ImGui.BeginCombo(ctx, "##saver_dfolder", df_preview) then
    for i = 1, #state.disk_folder_list do
      local item = state.disk_folder_list[i]
      local label = item
      if label == "" then label = "(FXChains root)" end
      if ImGui.Selectable(ctx, label .. "##df_" .. tostring(i), i == state.disk_folder_idx) then
        state.disk_folder_idx = i
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.PopItemWidth(ctx)

  if ImGui.SmallButton(ctx, "Refresh folders") then
    state.disk_folder_list = build_disk_folder_list()
    state.disk_folder_idx = math.min(state.disk_folder_idx, #state.disk_folder_list)
  end

  ImGui.Spacing(ctx)

  -- Dynamic Metadata Fields (from config_fields.json)
  W.separator_text(ctx, ImGui, "Metadata")

  local fields = DB:get_fields_config()
  if type(fields) == "table" then
    for _, field in ipairs(fields) do
      local key = tostring(field.key or "")
      local label = tostring(field.label or key)
      if key ~= "" then
        -- Ensure state exists
        if state.field_inputs[key] == nil then
          state.field_inputs[key] = ""
        end

        ImGui.Text(ctx, label)
        ImGui.PushItemWidth(ctx, -1)
        local _, newv = ImGui.InputText(ctx, "##saver_field_" .. key, state.field_inputs[key])
        state.field_inputs[key] = newv
        ImGui.PopItemWidth(ctx)
      end
    end
  end

  ImGui.Spacing(ctx)

  -- Description
  W.separator_text(ctx, ImGui, "Description")
  ImGui.PushItemWidth(ctx, -1)
  _, state.description = ImGui.InputTextMultiline(ctx, "##saver_desc", state.description, 0, 60)
  ImGui.PopItemWidth(ctx)

  ImGui.Spacing(ctx)

  -- Publish option
  local can_publish = Config.TEAM_PUBLISH_PATH and Config.TEAM_PUBLISH_PATH ~= ""
  local team_path_valid = can_publish

  -- Check if team path is actually accessible
  if can_publish then
    local valid, _ = Engine.is_team_path_valid(Config)
    team_path_valid = valid
  end

  if not team_path_valid and ImGui.BeginDisabled then ImGui.BeginDisabled(ctx, true) end
  _, state.publish_to_team = ImGui.Checkbox(ctx, "Publish to Team", state.publish_to_team)
  if not team_path_valid and ImGui.EndDisabled then ImGui.EndDisabled(ctx) end

  if not can_publish then
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "(Path not set)")
  elseif not team_path_valid then
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "(Path not accessible)")
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Save button
  if ImGui.Button(ctx, "SAVE", 120, 0) then
    local disk_folder = state.disk_folder_list[state.disk_folder_idx] or ""

    -- Step 1: Save to local disk (without team publish option - we handle that separately)
    local ok, abs_path, plugins_or_err = Engine.save_chain_to_disk(Config, state.name, disk_folder, {
      publish_to_team = false, -- We'll handle team publish separately with conflict detection
    })

    if ok then
      -- Build metadata table from field inputs
      local metadata = {}
      if type(fields) == "table" then
        for _, field in ipairs(fields) do
          local key = tostring(field.key or "")
          if key ~= "" then
            metadata[key] = tostring(state.field_inputs[key] or "")
          end
        end
      end

      -- Add to local DB
      DB:add_entry(abs_path, {
        name = state.name,
        description = state.description,
        folder_id = state.virtual_folder_id,
        metadata = metadata,
        plugins = plugins_or_err or {},
      })

      -- Step 2: Handle team publish if enabled
      if state.publish_to_team and team_path_valid then
        local publish_metadata = {
          name = state.name,
          description = state.description,
          metadata = metadata,
          plugins = plugins_or_err or {},
        }

        local pub_ok, pub_msg = do_publish_to_team(abs_path, publish_metadata, {})

        if pub_ok == nil then
          -- Conflict detected - modal will be shown, don't close window yet
          state.status = "Saved locally. Resolving team conflict..."
          return
        elseif pub_ok then
          state.status = "Saved & " .. tostring(pub_msg)
        else
          state.status = "Saved locally. Team publish failed: " .. tostring(pub_msg)
        end
      else
        state.status = "Saved!"
      end

      -- Close window if no conflict modal is showing
      if not state.show_conflict_modal then
        App.open = false
      end
      return
    else
      state.status = tostring(plugins_or_err or "Save failed")
    end
  end

  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Cancel") then
    App.open = false
    return
  end

  -- Status message
  if state.status and state.status ~= "" then
    ImGui.Spacing(ctx)
    local is_error = state.status:find("failed") or state.status:find("Failed") or state.status:find("error")
    local is_success = state.status:find("Saved") or state.status:find("Published")

    local col_text = type(ImGui.Col_Text) == "function" and ImGui.Col_Text() or ImGui.Col_Text

    if is_error then
      if ImGui.PushStyleColor and ImGui.PopStyleColor and col_text then
        ImGui.PushStyleColor(ctx, col_text, 0xFF8080FF)
        ImGui.TextWrapped(ctx, state.status)
        ImGui.PopStyleColor(ctx, 1)
      else
        ImGui.TextWrapped(ctx, state.status)
      end
    elseif is_success then
      if ImGui.PushStyleColor and ImGui.PopStyleColor and col_text then
        ImGui.PushStyleColor(ctx, col_text, 0x80FF80FF)
        ImGui.TextWrapped(ctx, state.status)
        ImGui.PopStyleColor(ctx, 1)
      else
        ImGui.TextWrapped(ctx, state.status)
      end
    else
      ImGui.TextWrapped(ctx, state.status)
    end
  end
end

return GuiSaver
