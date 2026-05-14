-- Drop Station: 按模式解析/生成可拖拽的本地音频文件路径
-- mode: 0 = Source, 1 = Dry (glue), 2 = Wet (render items via master)
--
-- Wet 模式（定稿、勿改）：
--   仅使用 GetSetProjectInfo / GetSetProjectInfo_String 将渲染目标设为「选中媒体项走 Master」
--   （RENDER_SETTINGS = 64, RENDER_BOUNDSFLAG = 4）并 Main_OnCommand(42230) 静默渲染。
--   不使用 Main_OnCommand(41716) 等会污染 Arrange 的茎干轨方案。

local r = reaper

local M = {}

local function sep()
  return package.config:sub(1, 1)
end

function M.get_drop_temp_dir()
  local s = sep()
  local proj_dir = r.GetProjectPath("")
  if proj_dir and proj_dir ~= "" then
    if proj_dir:sub(-1) ~= "\\" and proj_dir:sub(-1) ~= "/" then
      proj_dir = proj_dir .. s
    end
    local dir = proj_dir .. "_DropTemp"
    r.RecursiveCreateDirectory(dir, 0)
    return dir
  end
  local tmp = os.getenv("TEMP") or os.getenv("TMP") or "."
  if tmp:sub(-1) ~= "\\" and tmp:sub(-1) ~= "/" then
    tmp = tmp .. s
  end
  local dir = tmp .. "LeeDropStation"
  r.RecursiveCreateDirectory(dir, 0)
  return dir
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function take_is_audio_pcm(take)
  if not take then
    return false, "No active take"
  end
  local src = r.GetMediaItemTake_Source(take)
  if not src then
    return false, "Take has no media source"
  end
  if (r.GetMediaSourceSampleRate(src) or 0) <= 0 then
    return false, "Not a PCM audio item (MIDI/video/reverse not supported)"
  end
  return true, ""
end

function M.get_source_path(item)
  if not r.ValidatePtr2(0, item, "MediaItem*") then
    return nil, "Invalid item"
  end
  local take = r.GetActiveTake(item)
  if not take then
    return nil, "No active take"
  end
  local src = r.GetMediaItemTake_Source(take)
  if not src then
    return nil, "Take has no media source"
  end
  local path = r.GetMediaSourceFileName(src, "")
  if not path or path == "" then
    return nil, "Source has no file path (generated/empty take?)"
  end
  if not file_exists(path) then
    return nil, "File not found: " .. path
  end
  return path, ""
end

local function save_item_track_selection()
  local st = { items = {}, tracks = {}, master = false }
  local ic = r.CountSelectedMediaItems(0)
  for i = 0, ic - 1 do
    st.items[#st.items + 1] = r.GetSelectedMediaItem(0, i)
  end
  local tc = r.CountSelectedTracks2(0, true)
  for i = 0, tc - 1 do
    local tr = r.GetSelectedTrack2(0, i, true)
    if tr == r.GetMasterTrack(0) then
      st.master = true
    else
      st.tracks[#st.tracks + 1] = tr
    end
  end
  return st
end

local function restore_item_track_selection(st)
  r.Main_OnCommand(40289, 0)
  r.Main_OnCommand(40297, 0)
  for _, it in ipairs(st.items or {}) do
    if r.ValidatePtr2(0, it, "MediaItem*") then
      r.SetMediaItemSelected(it, true)
    end
  end
  for _, tr in ipairs(st.tracks or {}) do
    if r.ValidatePtr2(0, tr, "MediaTrack*") then
      r.SetTrackSelected(tr, true)
    end
  end
  if st.master and r.GetMasterTrack(0) then
    r.SetTrackSelected(r.GetMasterTrack(0), true)
  end
end

local function strip_take_fx(take)
  if not take or not r.TakeFX_GetCount then
    return
  end
  while r.TakeFX_GetCount(take) > 0 do
    r.TakeFX_Delete(take, 0)
  end
end

local function duplicate_item_on_track(item)
  r.SelectAllMediaItems(0, false)
  r.SetMediaItemSelected(item, true)
  r.UpdateArrange()
  r.Main_OnCommand(42398, 0)
  local track = r.GetMediaItemTrack(item)
  if not track then
    return nil
  end
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local n = r.CountTrackMediaItems(track)
  local best, best_d = nil, 1e9
  for i = 0, n - 1 do
    local it = r.GetTrackMediaItem(track, i)
    if it ~= item then
      local d = math.abs(r.GetMediaItemInfo_Value(it, "D_POSITION") - pos)
      if d < best_d then
        best_d = d
        best = it
      end
    end
  end
  return best
end

local function get_set_str(desc, val, is_set)
  return r.GetSetProjectInfo_String(0, desc, val, is_set)
end

local function get_project_string(desc)
  local a, b = get_set_str(desc, "", false)
  if type(b) == "string" then
    return b
  end
  if type(a) == "string" then
    return a
  end
  return ""
end

local function get_set_num(desc, val, is_set)
  return r.GetSetProjectInfo(0, desc, val, is_set)
end

function M.export_dry(item)
  if not r.ValidatePtr2(0, item, "MediaItem*") then
    return nil, "Invalid item"
  end
  local take = r.GetActiveTake(item)
  local ok, err = take_is_audio_pcm(take)
  if not ok then
    return nil, err
  end

  local out_dir = M.get_drop_temp_dir()
  local old_rec = get_project_string("RECORD_PATH")
  local old_idx = get_set_num("OPENCOPY_CFGIDX", 0, false)

  get_set_str("RECORD_PATH", out_dir, true)
  get_set_num("OPENCOPY_CFGIDX", 0, true)

  local sel = save_item_track_selection()
  local path_out, err_out
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local dummy = nil
  local ok_block, err_block = xpcall(function()
    local dup = duplicate_item_on_track(item)
    if not dup then
      error("Could not duplicate item (action 42398).")
    end
    local idx = r.CountTracks(0)
    r.InsertTrackAtIndex(idx, true)
    dummy = r.GetTrack(0, idx)
    if not dummy then
      error("InsertTrackAtIndex failed.")
    end
    r.SetMediaTrackInfo_Value(dummy, "B_SHOWINTCP", 0)
    r.SetMediaTrackInfo_Value(dummy, "B_SHOWINMIXER", 0)
    r.SetMediaTrackInfo_Value(dummy, "B_MUTE", 1)
    r.SetTrackSelected(dummy, false)
    r.MoveMediaItemToTrack(dup, dummy)
    strip_take_fx(r.GetActiveTake(dup))
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(dup, true)
    r.UpdateArrange()
    r.Main_OnCommand(41588, 0)
    local glued = r.GetSelectedMediaItem(0, 0)
    if not glued then
      error("Glue produced no selected item.")
    end
    local gt = r.GetActiveTake(glued)
    if not gt then
      error("Glued item has no active take.")
    end
    local src = r.GetMediaItemTake_Source(gt)
    if not src then
      error("Glued take has no source.")
    end
    path_out = r.GetMediaSourceFileName(src, "")
    if not path_out or path_out == "" or not file_exists(path_out) then
      error("Glue output file missing: " .. tostring(path_out))
    end
  end, debug.traceback)

  if dummy and r.ValidatePtr2(0, dummy, "MediaTrack*") then
    r.DeleteTrack(dummy)
  end
  restore_item_track_selection(sel)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  if ok_block then
    r.Undo_EndBlock("Drop Station: dry clip", -1)
  else
    r.Undo_EndBlock("Drop Station: dry clip (failed)", -1)
  end

  get_set_str("RECORD_PATH", old_rec or "", true)
  get_set_num("OPENCOPY_CFGIDX", old_idx, true)

  if not ok_block then
    return nil, tostring(err_block)
  end
  return path_out, err_out or ""
end

function M.export_wet(item)
  -- Wet 定稿：RENDER_SETTINGS=64 + RENDER_BOUNDSFLAG=4 + 42230（见文件头注释，禁止改为茎干轨命令）。
  if not r.ValidatePtr2(0, item, "MediaItem*") then
    return nil, "Invalid item"
  end
  local take = r.GetActiveTake(item)
  local ok, err = take_is_audio_pcm(take)
  if not ok then
    return nil, err
  end

  local out_dir = M.get_drop_temp_dir()
  local tag = string.format("ds_wet_%d_%d", math.floor(r.time_precise() * 1000), math.random(1000, 9999))

  local keys_num = {
    "RENDER_SETTINGS",
    "RENDER_BOUNDSFLAG",
    "RENDER_SRATE",
    "RENDER_CHANNELS",
    "RENDER_ADDTOPROJ",
  }
  local keys_str = {
    "RENDER_FILE",
    "RENDER_PATTERN",
    "RENDER_FORMAT",
    "RENDER_FORMAT2",
  }

  local backup_n = {}
  for _, k in ipairs(keys_num) do
    backup_n[k] = get_set_num(k, 0, false)
  end
  local backup_s = {}
  for _, k in ipairs(keys_str) do
    backup_s[k] = get_project_string(k)
  end

  local sel = save_item_track_selection()
  local path_out
  local ok_block, err_block = xpcall(function()
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(item, true)
    r.UpdateArrange()

    get_set_str("RENDER_FILE", out_dir, true)
    get_set_str("RENDER_PATTERN", tag, true)
    get_set_str("RENDER_FORMAT", "evaw", true)
    get_set_str("RENDER_FORMAT2", "", true)

    get_set_num("RENDER_SETTINGS", 64, true)
    get_set_num("RENDER_BOUNDSFLAG", 4, true)
    get_set_num("RENDER_SRATE", 0, true)
    local ch = 2
    if take then
      local src = r.GetMediaItemTake_Source(take)
      if src then
        local nc = r.GetMediaSourceNumChannels(src) or 2
        ch = (nc >= 2) and 2 or 1
      end
    end
    get_set_num("RENDER_CHANNELS", ch, true)
    local addflags = tonumber(backup_n["RENDER_ADDTOPROJ"]) or 0
    addflags = addflags & ~1
    get_set_num("RENDER_ADDTOPROJ", addflags, true)

    local ts, te = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    local ip = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local il = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    r.GetSet_LoopTimeRange2(0, true, false, ip, ip + il, false)

    r.Main_OnCommand(42230, 0)

    r.GetSet_LoopTimeRange2(0, true, false, ts, te, false)

    local s = sep()
    local candidates = {
      out_dir .. s .. tag .. ".wav",
      out_dir .. s .. tag .. ".WAV",
      out_dir .. s .. tag .. ".flac",
      out_dir .. s .. tag .. ".mp3",
    }
    for _, p in ipairs(candidates) do
      if file_exists(p) then
        path_out = p
        return
      end
    end
    error("Render finished but output file not found under: " .. out_dir)
  end, debug.traceback)

  for _, k in ipairs(keys_num) do
    get_set_num(k, backup_n[k], true)
  end
  for _, k in ipairs(keys_str) do
    get_set_str(k, backup_s[k] or "", true)
  end
  restore_item_track_selection(sel)
  r.UpdateArrange()

  if not ok_block then
    return nil, tostring(err_block)
  end
  return path_out, ""
end

function M.resolve(item, mode)
  if mode == 0 then
    return M.get_source_path(item)
  elseif mode == 1 then
    return M.export_dry(item)
  elseif mode == 2 then
    return M.export_wet(item)
  end
  return nil, "Unknown mode"
end

-- ---------------------------------------------------------------------------
-- OS 文件拖拽（Windows + reaper_dropstation.dll），与 C_Extensions/DropStation 扩展通信
-- ---------------------------------------------------------------------------

M.OS_DRAG_EXT_SECTION = "Toolbox_DropStation"
M.OS_DRAG_PATH_KEY = "Toolbox_DropStation_ExportPath"

local os_drag_gesture = { fired = false }

function M.lookup_dropstation_os_drag_command()
  if not r.NamedCommandLookup then
    return 0
  end
  local c = r.NamedCommandLookup("_Lee_StartOSDragDrop")
  if c and c ~= 0 then
    return c
  end
  c = r.NamedCommandLookup("Lee_StartOSDragDrop")
  return (c and c ~= 0) and c or 0
end

function M.os_drag_extension_ready()
  if package.config:sub(1, 1) ~= "\\" then
    return false
  end
  return M.lookup_dropstation_os_drag_command() ~= 0
end

function M.invoke_os_drag_ipc(path)
  local cmd = M.lookup_dropstation_os_drag_command()
  if cmd == 0 then
    return false, "未找到扩展动作（请编译并部署 reaper_dropstation.dll 后重启 REAPER）"
  end
  if not path or path == "" then
    return false, "路径为空"
  end
  r.SetExtState(M.OS_DRAG_EXT_SECTION, M.OS_DRAG_PATH_KEY, path, false)
  r.Main_OnCommand(cmd, 0)
  return true, ""
end

--- ReaImGui：绘制「[ Drag to External ]」并在鼠标按下/开始拖动时触发 C++ DoDragDrop。
--- opts.resolve：function() return path, err
--- opts.on_note_ok(path) / opts.on_error(msg) / opts.on_status(msg) 可选
--- opts.row_w / opts.btn_w 可选（用于与 Copy Path 并排布局）
--- 返回主按钮宽度 btn_w
function M.draw_drag_to_external(ctx, ImGui, opts)
  opts = opts or {}
  local resolve = opts.resolve
  if type(resolve) ~= "function" then
    return 0
  end
  local row_w = opts.row_w
  if (not row_w or row_w <= 0) and ImGui.GetContentRegionAvail then
    row_w = ImGui.GetContentRegionAvail(ctx)
  end
  row_w = row_w or 200
  local btn_w = opts.btn_w
  if not btn_w then
    btn_w = row_w * 0.62
    if btn_w < 140 then
      btn_w = 140
    end
  end

  local avail = M.os_drag_extension_ready()

  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xFF6A3DFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xFF8F66FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xFF551AFF)

  ImGui.Button(ctx, "[ Drag to External ]", btn_w, 36)

  local trigger = false
  if avail then
    local hovered = ImGui.IsItemHovered and ImGui.IsItemHovered(ctx)
    if hovered then
      if ImGui.IsMouseClicked and ImGui.IsMouseClicked(ctx, 0) then
        trigger = true
      elseif ImGui.IsItemActive and ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging and ImGui.IsMouseDragging(ctx, 0) then
        if not os_drag_gesture.fired then
          trigger = true
          os_drag_gesture.fired = true
        end
      end
    end
  end

  if ImGui.IsMouseDown and not ImGui.IsMouseDown(ctx, 0) then
    os_drag_gesture.fired = false
  end

  ImGui.PopStyleColor(ctx, 3)

  if not avail and ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.BeginTooltip then
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, "需要 Windows，并安装 UserPlugins\\reaper_dropstation.dll（源码见仓库 C_Extensions/DropStation）。")
    ImGui.EndTooltip(ctx)
  end

  if trigger then
    local path, err = resolve()
    if path and path ~= "" then
      local lower = path:lower()
      if not lower:match("%.wav$") then
        err = "OS 拖拽仅支持 .wav；请先 Dry/Wet 生成 wav 或使用右侧 Copy Path。"
      end
    end
    if path and path ~= "" and (not err or err == "") then
      local ok, e2 = M.invoke_os_drag_ipc(path)
      if ok then
        if opts.on_note_ok then
          opts.on_note_ok(path)
        end
        if opts.on_status then
          opts.on_status("OS drag: " .. path)
        end
      else
        if opts.on_error then
          opts.on_error(e2 or "")
        end
      end
    else
      if opts.on_error then
        opts.on_error(err or "No path")
      end
    end
  end

  return btn_w
end

return M
