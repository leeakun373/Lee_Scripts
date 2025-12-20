-- FXMiner/src/gui_browser/gui_folders.lua
-- 【纯净版】虚拟文件夹面板 + 筛选互斥修复

local W = require("widgets")
local GuiFolders = {}
local state = nil
local App, DB, Config = nil, nil, nil
local Utils = nil

function GuiFolders.init(_state, _App, _DB, _Config, _Utils)
  state = _state
  App = _App
  DB = _DB
  Config = _Config
  Utils = _Utils
end

local function draw_folder_tree_node(ctx, folder, depth)
  local ImGui = App.ImGui
  local id = tonumber(folder.id) or 0
  local name = tostring(folder.name or "")
  if name == "" then name = (id == 0) and "Root" or ("Folder " .. id) end
  depth = tonumber(depth) or 0
  local INDENT_W = 12

  local children = DB:list_children(id)
  local has_children = false
  for _, c in ipairs(children) do
    if tonumber(c.id) ~= id then has_children = true; break end
  end

  local function begin_rename(folder_id, current_name)
    state.folder_rename_id = tonumber(folder_id) or 0
    state.folder_rename_text = tostring(current_name or "")
    state.folder_rename_init = true
  end

  -- Inline rename row
  if state.folder_rename_id == id then
    if ImGui.Indent and depth > 0 then ImGui.Indent(ctx, depth * 16) end
    if state.folder_rename_init then ImGui.SetKeyboardFocusHere(ctx, 0) end
    ImGui.SetNextItemWidth(ctx, -1)
    local flags = ImGui.InputTextFlags_AutoSelectAll or 0
    local _, newv = ImGui.InputText(ctx, "###fxminer_rename_" .. id, state.folder_rename_text, flags)
    state.folder_rename_text = newv
    if (ImGui.IsItemActive and not ImGui.IsItemActive(ctx)) and not state.folder_rename_init then
      local new_name = Utils.trim(state.folder_rename_text)
      if new_name ~= "" then
        local ok, err = DB:rename_folder(id, new_name)
        if not ok then state.status = "Rename failed: " .. tostring(err) end
      end
      state.folder_rename_id = nil
    end
    state.folder_rename_init = false
    if ImGui.Unindent and depth > 0 then ImGui.Unindent(ctx, depth * 16) end
    return
  end

  local selected = (state.selected_folder_id == id)
  state.folder_open[id] = (state.folder_open[id] == nil) and false or state.folder_open[id]

  if ImGui.Indent and depth > 0 then ImGui.Indent(ctx, depth * INDENT_W) end

  if has_children then
    local arrow = state.folder_open[id] and "▼" or "▶"
    if ImGui.SmallButton(ctx, arrow .. "###arrow_" .. id) then
      state.folder_open[id] = not state.folder_open[id]
    end
    ImGui.SameLine(ctx)
  end

  local icon = state.folder_open[id] and "📂" or "📁"
  local label = icon .. " " .. name .. "###row_" .. id
  
  -- 【修复点】点击文件夹时，清除 Library Filter
  if ImGui.Selectable(ctx, label, selected) then
    state.selected_folder_id = id
    state.library_filter = nil -- 互斥！清除 Library 筛选
  end

  local popup_id = "ctx_" .. id
  if ImGui.IsItemClicked and ImGui.IsItemClicked(ctx, 1) then ImGui.OpenPopup(ctx, popup_id) end
  if ImGui.BeginPopup(ctx, popup_id) then
    if ImGui.MenuItem(ctx, "➕ New folder below") then
      local cur = DB:get_folder(id)
      local pid = cur and tonumber(cur.parent_id) or 0
      local ok, nid = DB:create_folder("New folder", pid, { insert_after_id = id })
      if ok then 
        state.selected_folder_id = nid
        begin_rename(nid, "New folder")
      end
    end
    if ImGui.MenuItem(ctx, "➕ New subfolder") then
      local ok, nid = DB:create_folder("New folder", id)
      if ok then
        state.folder_open[id] = true
        state.selected_folder_id = nid
        begin_rename(nid, "New folder")
      end
    end
    if ImGui.Separator then ImGui.Separator(ctx) end
    if id ~= 0 and ImGui.MenuItem(ctx, "Rename") then begin_rename(id, name) end
    if id ~= 0 and ImGui.MenuItem(ctx, "🗑️ Remove folder") then
      DB:delete_folder(id)
      if state.selected_folder_id == id then state.selected_folder_id = -1 end
    end
    ImGui.EndPopup(ctx)
  end

  if id ~= 0 and ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked and ImGui.IsMouseDoubleClicked(ctx, 0) then
    begin_rename(id, name)
  end

  if ImGui.BeginDragDropTarget and ImGui.BeginDragDropTarget(ctx) then
    if ImGui.AcceptDragDropPayload then
      local ok, payload = pcall(ImGui.AcceptDragDropPayload, ctx, "FXMINER_ENTRY")
      if ok and payload and payload ~= "" then DB:set_entry_folder(tostring(payload), id) end
    end
    ImGui.EndDragDropTarget(ctx)
  end

  if ImGui.Unindent and depth > 0 then ImGui.Unindent(ctx, depth * 16) end

  if has_children and state.folder_open[id] then
    for _, c in ipairs(children) do
      if tonumber(c.id) ~= id then draw_folder_tree_node(ctx, c, depth + 1) end
    end
  end
end

local function draw_library_tree(ctx)
  local ImGui = App.ImGui
  -- [数据收集代码保持不变]
  local projects, designers, themes = {}, {}, {}
  local seen = {p={}, d={}, t={}}
  local entries = DB:entries()
  for _, e in ipairs(entries) do
    if e and e.metadata then
      local p = Utils.trim(tostring(e.metadata.Project or ""))
      if p~="" and not seen.p[p] then seen.p[p]=true; table.insert(projects, p) end
      local d = Utils.trim(tostring(e.metadata.Designer or ""))
      if d~="" and not seen.d[d] then seen.d[d]=true; table.insert(designers, d) end
      local t = Utils.trim(tostring(e.metadata.Theme or ""))
      if t~="" and not seen.t[t] then seen.t[t]=true; table.insert(themes, t) end
    end
  end
  table.sort(projects); table.sort(designers); table.sort(themes)

  -- Clear Filter Button
  if state.library_filter then
    if ImGui.Button(ctx, "❌ Clear Filter: " .. state.library_filter.value, -1, 0) then
      state.library_filter = nil
    end
    ImGui.Spacing(ctx)
  end

  local function draw_cat(name, vals, key)
    if #vals == 0 then return end
    local nid = "lib_" .. key
    state.library_open = state.library_open or {}
    local open = state.library_open[nid]
    local icon = open and "📂" or "📁"
    
    if ImGui.Selectable(ctx, icon .. " " .. name .. "###cat_" .. key, false) then
       state.library_open[nid] = not open
    end
    
    if open then
      ImGui.Indent(ctx, 16)
      for _, v in ipairs(vals) do
        local is_sel = (state.library_filter and state.library_filter.field == key and state.library_filter.value == v)
        -- 【修复点】点击 Library 节点时，不改变 folder_id，或者设为 All
        if ImGui.Selectable(ctx, "🏷️ " .. v .. "###val_" .. v, is_sel) then
          state.library_filter = { field = key, value = v }
          state.selected_folder_id = -1 -- 重置文件夹选择，确保显示全部范围
        end
      end
      ImGui.Unindent(ctx, 16)
    end
  end

  draw_cat("Projects", projects, "Project")
  ImGui.Spacing(ctx); draw_cat("Designers", designers, "Designer"); ImGui.Spacing(ctx)
  draw_cat("Themes", themes, "Theme")
end

function GuiFolders.draw(ctx)
  local ImGui = App.ImGui

  local function flat_button(label, tooltip, on_click, disabled)
    disabled = not not disabled
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)
    if disabled then ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x808080FF) end
    local clicked = ImGui.Button(ctx, label)
    if disabled then ImGui.PopStyleColor(ctx, 4); clicked = false else ImGui.PopStyleColor(ctx, 3) end
    if ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and tooltip and tooltip ~= "" then ImGui.SetTooltip(ctx, tooltip) end
    if clicked and on_click then on_click() end
    return clicked
  end

  W.separator_text(ctx, ImGui, "📁 Folders")

  -- All Button
  do
    local sel = (state.selected_folder_id == -1 and not state.library_filter)
    -- 【修复点】点击 All，清除 Library 筛选
    if ImGui.Selectable(ctx, "🔍 All", sel) then
      state.selected_folder_id = -1
      state.library_filter = nil 
    end
  end
  ImGui.Spacing(ctx)

  -- Toolbar
  local pid = (state.selected_folder_id > 0) and state.selected_folder_id or 0
  flat_button("➕", "Add folder", function()
    local ok, nid = DB:create_folder("New folder", pid)
    if ok then state.selected_folder_id = nid end
  end, false)
  ImGui.SameLine(ctx)
  flat_button("📁+", "Add parent", function()
    local ok, nid = DB:create_parent_folder(state.selected_folder_id, "New parent")
    if ok then state.selected_folder_id = nid end
  end, state.selected_folder_id <= 0)
  ImGui.SameLine(ctx)
  flat_button("🗑️", "Delete", function()
    if state.selected_folder_id > 0 then DB:delete_folder(state.selected_folder_id); state.selected_folder_id = -1 end
  end, state.selected_folder_id <= 0)
  
  ImGui.Separator(ctx)

  local root = DB:get_folder(0)
  if root then
    local top = DB:list_children(0)
    for _, f in ipairs(top) do
      if tonumber(f.id) ~= 0 then draw_folder_tree_node(ctx, f, 0) end
    end
  end

  ImGui.Spacing(ctx); ImGui.Separator(ctx); ImGui.Spacing(ctx)
  W.separator_text(ctx, ImGui, "📄 Library")
  draw_library_tree(ctx)

  ImGui.Spacing(ctx)
end

return GuiFolders
