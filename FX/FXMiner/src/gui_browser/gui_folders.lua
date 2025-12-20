-- FXMiner/src/gui_browser/gui_folders.lua
-- 虚拟文件夹面板的绘制和交互逻辑

local W = require("widgets")

local GuiFolders = {}

-- Get dependencies (will be injected)
local state = nil
local App, DB, Config = nil, nil, nil
local Utils = nil

-- Initialize dependencies
function GuiFolders.init(_state, _App, _DB, _Config, _Utils)
  state = _state
  App = _App
  DB = _DB
  Config = _Config
  Utils = _Utils
end

-- Draw a single folder tree node
local function draw_folder_tree_node(ctx, folder, depth)
  local ImGui = App.ImGui

  local id = tonumber(folder.id) or 0
  local name = tostring(folder.name or "")
  if name == "" then name = (id == 0) and "Root" or ("Folder " .. id) end

  depth = tonumber(depth) or 0
  local INDENT_W = 12
  local ARROW_W = 16

  local children = DB:list_children(id)
  local has_children = false
  for _, c in ipairs(children) do
    if tonumber(c.id) ~= id then
      has_children = true
      break
    end
  end

  local function begin_rename(folder_id, current_name)
    state.folder_rename_id = tonumber(folder_id) or 0
    state.folder_rename_text = tostring(current_name or "")
    state.folder_rename_init = true
  end

  -- Inline rename row
  if state.folder_rename_id == id then
    if ImGui.Indent and ImGui.Unindent and depth > 0 then
      ImGui.Indent(ctx, depth * 16)
    end
    if state.folder_rename_init and ImGui.SetKeyboardFocusHere then
      ImGui.SetKeyboardFocusHere(ctx, 0)
    end
    if ImGui.SetNextItemWidth then
      ImGui.SetNextItemWidth(ctx, -1)
    end
    local flags = ImGui.InputTextFlags_AutoSelectAll or 0
    local _, newv = ImGui.InputText(ctx, "###fxminer_rename_folder_" .. tostring(id), state.folder_rename_text, flags)
    state.folder_rename_text = newv
    -- commit on focus lost
    if (ImGui.IsItemActive and not ImGui.IsItemActive(ctx)) and not state.folder_rename_init then
      local new_name = Utils.trim(state.folder_rename_text)
      if new_name ~= "" then
        local ok, err = DB:rename_folder(id, new_name)
        if not ok then
          state.status = "Rename failed: " .. tostring(err)
        end
      end
      state.folder_rename_id = nil
      state.folder_rename_text = ""
    end
    state.folder_rename_init = false
    if ImGui.Indent and ImGui.Unindent and depth > 0 then
      ImGui.Unindent(ctx, depth * 16)
    end
    return
  end

  -- Folder row (fully manual, avoids TreePop issues across ReaImGui versions)
  local selected = (state.selected_folder_id == id)
  state.folder_open[id] = (state.folder_open[id] == nil) and false or state.folder_open[id]

  if ImGui.Indent and ImGui.Unindent and depth > 0 then
    ImGui.Indent(ctx, depth * INDENT_W)
  end

  -- Arrow toggle for parents (only if has children)
  if has_children then
    local arrow = state.folder_open[id] and "▼" or "▶"
    if ImGui.SmallButton(ctx, arrow .. "###fxminer_folder_arrow_" .. tostring(id)) then
      state.folder_open[id] = not state.folder_open[id]
    end
    ImGui.SameLine(ctx)
  end
  -- No dummy for leaf: keeps leaf aligned with All

  local label = name .. "###fxminer_folder_row_" .. tostring(id)
  if ImGui.Selectable(ctx, label, selected) then
    state.selected_folder_id = id
  end

  -- Right-click context menu (OpenPopup + BeginPopup is most stable)
  local popup_id = "fxminer_folder_menu_" .. tostring(id)
  if ImGui.IsItemClicked and ImGui.IsItemClicked(ctx, 1) and ImGui.OpenPopup then
    ImGui.OpenPopup(ctx, popup_id)
  end
  if ImGui.BeginPopup and ImGui.EndPopup and ImGui.BeginPopup(ctx, popup_id) then
    if ImGui.MenuItem(ctx, "New folder below") then
      local cur = DB:get_folder(id)
      local pid = cur and tonumber(cur.parent_id) or 0
      local ok, new_id_or_err = DB:create_folder("New folder", pid, { insert_after_id = id })
      if ok then
        state.selected_folder_id = new_id_or_err
        begin_rename(new_id_or_err, "New folder")
      else
        state.status = "Create failed: " .. tostring(new_id_or_err)
      end
    end
    if ImGui.MenuItem(ctx, "New subfolder") then
      local ok, new_id_or_err = DB:create_folder("New folder", id, { insert_after_id = nil })
      if ok then
        state.folder_open[id] = true
        state.selected_folder_id = new_id_or_err
        begin_rename(new_id_or_err, "New folder")
      else
        state.status = "Create failed: " .. tostring(new_id_or_err)
      end
    end
    if id ~= 0 and ImGui.MenuItem(ctx, "New parent folder") then
      local ok, new_id_or_err = DB:create_parent_folder(id, "New parent folder")
      if ok then
        state.selected_folder_id = new_id_or_err
        begin_rename(new_id_or_err, "New parent folder")
      else
        state.status = "Create parent failed: " .. tostring(new_id_or_err)
      end
    end
    if ImGui.Separator then ImGui.Separator(ctx) end
    if id ~= 0 and ImGui.MenuItem(ctx, "Rename") then
      begin_rename(id, name)
    end
    if ImGui.Separator then ImGui.Separator(ctx) end
    if id ~= 0 and ImGui.MenuItem(ctx, "Remove folder") then
      local ok, err = DB:delete_folder(id)
      if not ok then
        state.status = "Remove failed: " .. tostring(err)
      else
        if state.selected_folder_id == id then
          state.selected_folder_id = -1
        end
        state.folder_open[id] = nil
        if state.folder_rename_id == id then
          state.folder_rename_id = nil
          state.folder_rename_text = ""
          state.folder_rename_init = false
        end
      end
    end
    ImGui.EndPopup(ctx)
  end

  -- Double-click rename
  if id ~= 0 and ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked and ImGui.IsMouseDoubleClicked(ctx, 0) then
    begin_rename(id, name)
  end

  -- Drop target: move entry into this folder
  if ImGui.BeginDragDropTarget and ImGui.BeginDragDropTarget(ctx) then
    if ImGui.AcceptDragDropPayload then
      local ok, payload = pcall(ImGui.AcceptDragDropPayload, ctx, "FXMINER_ENTRY")
      if ok and payload and payload ~= "" then
        DB:set_entry_folder(tostring(payload), id)
      end
    end
    ImGui.EndDragDropTarget(ctx)
  end

  if ImGui.Indent and ImGui.Unindent and depth > 0 then
    ImGui.Unindent(ctx, depth * 16)
  end

  -- Children
  if has_children and state.folder_open[id] == true then
    for _, c in ipairs(children) do
      if tonumber(c.id) ~= id then
        draw_folder_tree_node(ctx, c, depth + 1)
      end
    end
  end
end

-- Draw the folders panel
function GuiFolders.draw(ctx)
  local ImGui = App.ImGui

  W.separator_text(ctx, ImGui, "Folders")

  -- Toolbar: create default name then inline-rename
  local function begin_rename(folder_id, current_name)
    state.folder_rename_id = tonumber(folder_id) or 0
    state.folder_rename_text = tostring(current_name or "")
    state.folder_rename_init = true
  end

  local function flat_button(label, tooltip, on_click, disabled)
    disabled = not not disabled
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)
    if disabled and ImGui.Col_TextDisabled then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x808080FF)
    end
    if state.icon_font and ImGui.PushFont and ImGui.PopFont then
      ImGui.PushFont(ctx, state.icon_font)
    end
    local clicked = ImGui.Button(ctx, label)
    if state.icon_font and ImGui.PushFont and ImGui.PopFont then
      ImGui.PopFont(ctx)
    end
    if disabled then clicked = false end
    if ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and tooltip and tooltip ~= "" and ImGui.SetTooltip then
      ImGui.SetTooltip(ctx, tooltip)
    end
    if disabled and ImGui.Col_TextDisabled then
      ImGui.PopStyleColor(ctx, 1)
    end
    ImGui.PopStyleColor(ctx, 3)
    if clicked and on_click then on_click() end
    return clicked
  end

  local parent_id_for_create = tonumber(state.selected_folder_id) or -1
  local insert_after_id = nil
  if parent_id_for_create > 0 then
    local cur = DB:get_folder(parent_id_for_create)
    insert_after_id = parent_id_for_create
    parent_id_for_create = cur and tonumber(cur.parent_id) or 0
  else
    parent_id_for_create = 0 -- All -> Root container
  end

  flat_button(state.icon_plus or "+", "Add folder", function()
    local ok, new_id_or_err = DB:create_folder("New folder", parent_id_for_create, { insert_after_id = insert_after_id })
    if ok then
      state.selected_folder_id = new_id_or_err
      begin_rename(new_id_or_err, "New folder")
    else
      state.status = "Create failed: " .. tostring(new_id_or_err)
    end
  end, false)
  ImGui.SameLine(ctx)
  flat_button((state.icon_folder_add and state.icon_folder_add ~= "" and state.icon_folder_add) or "Parent+", "Add parent folder", function()
    local ok, new_id_or_err = DB:create_parent_folder(state.selected_folder_id, "New parent folder")
    if ok then
      state.selected_folder_id = new_id_or_err
      begin_rename(new_id_or_err, "New parent folder")
    else
      state.status = "Create parent failed: " .. tostring(new_id_or_err)
    end
  end, state.selected_folder_id <= 0)
  ImGui.SameLine(ctx)
  flat_button((state.icon_delete and state.icon_delete ~= "" and state.icon_delete) or "Del", "Delete folder", function()
    local id = tonumber(state.selected_folder_id) or -1
    if id > 0 then
      local ok, err = DB:delete_folder(id)
      if not ok then
        state.status = "Remove failed: " .. tostring(err)
      else
        state.selected_folder_id = -1
        state.folder_open[id] = nil
        if state.folder_rename_id == id then
          state.folder_rename_id = nil
          state.folder_rename_text = ""
          state.folder_rename_init = false
        end
      end
    end
  end, state.selected_folder_id <= 0)
  ImGui.Separator(ctx)

  -- "All" (top entry) - no arrow, no tree
  do
    local sel = (state.selected_folder_id == -1)
    local label = "All"
    if ImGui.Selectable(ctx, label .. "###fxminer_folder_all", sel) then
      state.selected_folder_id = -1
    end
  end

  -- Hide internal Root container; render its children as top-level list
  local root = DB:get_folder(0)
  if not root then
    ImGui.TextDisabled(ctx, "folders_db not loaded")
  else
    local top = DB:list_children(0)
    for _, f in ipairs(top) do
      if tonumber(f.id) ~= 0 then
        draw_folder_tree_node(ctx, f, 0)
      end
    end
  end

  ImGui.Spacing(ctx)
end

return GuiFolders
