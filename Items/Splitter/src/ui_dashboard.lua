local M = {}

local script_dir = ({ reaper.get_action_context() })[2]:match("^(.*[\\/])")
local config = dofile(script_dir .. "src/splitter_config.lua")
local item_reader = dofile(script_dir .. "src/splitter_item_reader.lua")
local runner = dofile(script_dir .. "src/splitter_runner.lua")
local track_writer = dofile(script_dir .. "src/splitter_track_writer.lua")
local ROOT_DIR = script_dir:match("^(.*[\\/]Lee_Scripts[\\/])") or ""
local SHARED_WIDGETS = ROOT_DIR ~= "" and (ROOT_DIR .. "Shared/Toolbox/framework/widgets.lua") or ""
local SHARED_COLORS = ROOT_DIR ~= "" and (ROOT_DIR .. "Shared/Toolbox/framework/ui_colors.lua") or ""

local HOP_ITEMS = table.concat({ "256", "512", "1024", "2048", "" }, string.char(0))
local STATUS = {
  idle = "idle",
  running = "running",
  success = "success",
  error = "error",
}

local function ensure_imgui()
  if not reaper.ImGui_CreateContext then
    error("ReaImGui is required. Please install the ReaImGui extension via ReaPack.")
  end
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function create_imgui_adapter()
  return {
    SeparatorText = function(ctx, text)
      return reaper.ImGui_SeparatorText and reaper.ImGui_SeparatorText(ctx, text) or nil
    end,
    Separator = function(ctx)
      return reaper.ImGui_Separator(ctx)
    end,
    Text = function(ctx, text)
      return reaper.ImGui_Text(ctx, text)
    end,
    SameLine = function(ctx)
      return reaper.ImGui_SameLine(ctx)
    end,
    TextDisabled = function(ctx, text)
      return reaper.ImGui_TextDisabled(ctx, text)
    end,
    IsItemHovered = function(ctx)
      return reaper.ImGui_IsItemHovered and reaper.ImGui_IsItemHovered(ctx) or false
    end,
    BeginTooltip = function(ctx)
      return reaper.ImGui_BeginTooltip and reaper.ImGui_BeginTooltip(ctx) or nil
    end,
    PushTextWrapPos = function(ctx, wrap)
      return reaper.ImGui_PushTextWrapPos and reaper.ImGui_PushTextWrapPos(ctx, wrap) or nil
    end,
    PopTextWrapPos = function(ctx)
      return reaper.ImGui_PopTextWrapPos and reaper.ImGui_PopTextWrapPos(ctx) or nil
    end,
    EndTooltip = function(ctx)
      return reaper.ImGui_EndTooltip and reaper.ImGui_EndTooltip(ctx) or nil
    end,
    SliderDouble = function(ctx, label, v, minv, maxv, fmt)
      if reaper.ImGui_SliderDouble then
        return reaper.ImGui_SliderDouble(ctx, label, v, minv, maxv, fmt)
      end
      return false, v
    end,
    SliderFloat = function(ctx, label, v, minv, maxv, fmt)
      if reaper.ImGui_SliderFloat then
        return reaper.ImGui_SliderFloat(ctx, label, v, minv, maxv, fmt)
      end
      return false, v
    end,
    DragDouble = function(ctx, label, v, speed, minv, maxv, fmt)
      if reaper.ImGui_DragDouble then
        return reaper.ImGui_DragDouble(ctx, label, v, speed, minv, maxv, fmt)
      end
      return false, v
    end,
    DragFloat = function(ctx, label, v, speed, minv, maxv, fmt)
      if reaper.ImGui_DragFloat then
        return reaper.ImGui_DragFloat(ctx, label, v, speed, minv, maxv, fmt)
      end
      return false, v
    end,
    SliderInt = function(ctx, label, v, minv, maxv, fmt)
      return reaper.ImGui_SliderInt(ctx, label, v, minv, maxv, fmt)
    end,
    DragInt = function(ctx, label, v, speed, minv, maxv, fmt)
      if reaper.ImGui_DragInt then
        return reaper.ImGui_DragInt(ctx, label, v, speed, minv, maxv, fmt)
      end
      return false, v
    end,
  }
end

local function load_widgets()
  if SHARED_WIDGETS ~= "" and file_exists(SHARED_WIDGETS) then
    local ok, mod = pcall(dofile, SHARED_WIDGETS)
    if ok and type(mod) == "table" then
      return mod
    end
  end
  return {
    separator_text = function(ctx, _, text)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Text(ctx, text)
      reaper.ImGui_Separator(ctx)
    end,
    slider_float = function(ctx, _, label, value, minv, maxv, fmt)
      if reaper.ImGui_SliderDouble then
        return reaper.ImGui_SliderDouble(ctx, label, value, minv, maxv, fmt)
      end
      if reaper.ImGui_SliderFloat then
        return reaper.ImGui_SliderFloat(ctx, label, value, minv, maxv, fmt)
      end
      return false, value
    end,
    slider_int = function(ctx, _, label, value, minv, maxv, fmt)
      if reaper.ImGui_SliderInt then
        return reaper.ImGui_SliderInt(ctx, label, value, minv, maxv, fmt)
      end
      if reaper.ImGui_DragInt then
        return reaper.ImGui_DragInt(ctx, label, value, 1, minv, maxv, fmt)
      end
      return false, value
    end,
  }
end

local function load_shared_colors()
  if SHARED_COLORS ~= "" and file_exists(SHARED_COLORS) then
    local ok, mod = pcall(dofile, SHARED_COLORS)
    if ok and type(mod) == "table" and type(mod.u32) == "table" then
      return mod
    end
  end
  return nil
end

local function push_theme(ctx, colors)
  if not colors or not colors.u32 then
    return 0
  end

  local count = 0
  local u = colors.u32
  local function push(col_fn, key)
    if col_fn and u[key] then
      reaper.ImGui_PushStyleColor(ctx, col_fn(), u[key])
      count = count + 1
    end
  end

  push(reaper.ImGui_Col_WindowBg, "WindowBg")
  push(reaper.ImGui_Col_TitleBg, "TitleBg")
  push(reaper.ImGui_Col_TitleBgActive, "TitleBgActive")
  push(reaper.ImGui_Col_Button, "Button")
  push(reaper.ImGui_Col_ButtonHovered, "ButtonHovered")
  push(reaper.ImGui_Col_ButtonActive, "ButtonActive")
  push(reaper.ImGui_Col_FrameBg, "FrameBg")
  push(reaper.ImGui_Col_FrameBgHovered, "FrameBgHovered")
  push(reaper.ImGui_Col_FrameBgActive, "FrameBgActive")
  push(reaper.ImGui_Col_SliderGrab, "SliderGrab")
  push(reaper.ImGui_Col_SliderGrabActive, "SliderGrabActive")
  push(reaper.ImGui_Col_Text, "Text")
  push(reaper.ImGui_Col_TextDisabled, "TextDisabled")
  return count
end

local function begin_disabled(ctx)
  if reaper.ImGui_BeginDisabled then
    reaper.ImGui_BeginDisabled(ctx)
    return true
  end
  return false
end

local function end_disabled(ctx, started)
  if started and reaper.ImGui_EndDisabled then
    reaper.ImGui_EndDisabled(ctx)
  end
end

local function cond_first_use_ever()
  if reaper.ImGui_Cond_FirstUseEver then
    return reaper.ImGui_Cond_FirstUseEver()
  end
  return 0
end

local function hop_index_from_value(value)
  for i, hop in ipairs(config.HOP_LENGTHS) do
    if hop == value then
      return i - 1
    end
  end
  return 1
end

local function apply_hop(state)
  state.settings.hop_length = config.HOP_LENGTHS[state.hop_index + 1] or config.DEFAULTS.hop_length
end

local function set_status(state, kind, text)
  state.status_kind = kind
  state.status_text = text
end

local function persist_settings(state)
  apply_hop(state)
  state.settings = config.save_settings(state.settings)
  state.hop_index = hop_index_from_value(state.settings.hop_length)
end

local function draw_status(state)
  if state.status_kind == STATUS.error then
    reaper.ImGui_PushStyleColor(state.ctx, reaper.ImGui_Col_Text(), 0xFF4040FF)
    reaper.ImGui_TextWrapped(state.ctx, state.status_text)
    reaper.ImGui_PopStyleColor(state.ctx)
    return
  end

  reaper.ImGui_TextWrapped(state.ctx, state.status_text)
end

local function push_round_style(ctx)
  local count = 0
  if reaper.ImGui_StyleVar_WindowRounding then
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8.0)
    count = count + 1
  end
  if reaper.ImGui_StyleVar_FrameRounding then
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6.0)
    count = count + 1
  end
  if reaper.ImGui_StyleVar_GrabRounding then
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 6.0)
    count = count + 1
  end
  return count
end

local function pop_round_style(ctx, count)
  if count and count > 0 and reaper.ImGui_PopStyleVar then
    reaper.ImGui_PopStyleVar(ctx, count)
  end
end

local function begin_window_compat(ctx, title, open, flags)
  local ok4, v4, o4 = pcall(reaper.ImGui_Begin, ctx, title, open, flags)
  if ok4 and v4 ~= nil then
    return true, v4, o4, true
  end

  local ok3, v3 = pcall(reaper.ImGui_Begin, ctx, title, flags)
  if ok3 and v3 ~= nil then
    return true, v3, nil, true
  end

  local ok2, v2 = pcall(reaper.ImGui_Begin, ctx, title)
  if ok2 and v2 ~= nil then
    return true, v2, nil, true
  end

  return false, (ok4 and v4) or (ok3 and v3) or (ok2 and v2) or "ImGui_Begin failed", nil, false
end

local function check_selected_audio_item()
  return item_reader.read_selected_item({ silent = true })
end

local function start_split(state)
  if state.running then
    return
  end

  state.running = true
  set_status(state, STATUS.running, "正在处理，请稍候...")
  reaper.defer(function()
    local item_info, read_error = check_selected_audio_item()
    if not item_info then
      state.running = false
      set_status(state, STATUS.error, "执行失败: " .. tostring(read_error))
      return
    end

    persist_settings(state)

    local function on_success(result)
      local ok, write_error = xpcall(function()
        reaper.Undo_BeginBlock()
        local write_result, err = track_writer.write_stems(result, state.settings)
        if not write_result then
          error(err or "Unable to write stems.")
        end
      if state.settings.mute_source_item then
        reaper.SetMediaItemInfo_Value(result.item_info.item, "B_MUTE", 1)
        reaper.UpdateItemInProject(result.item_info.item)
      end
        reaper.Undo_EndBlock("Splitter Run (Tonal/Transient/Noise)", -1)
        reaper.UpdateArrange()
      end, debug.traceback)

      state.running = false
      if ok then
        set_status(state, STATUS.success, "处理完成！音频已导入轨道")
      else
        set_status(state, STATUS.error, "执行失败: " .. tostring(write_error))
      end
    end

    local function on_error(err)
      state.running = false
      set_status(state, STATUS.error, "执行失败: " .. tostring(err))
    end

    local run_result, run_error = runner.run(item_info, state.settings, on_success, on_error)
    if not run_result then
      state.running = false
      set_status(state, STATUS.error, "执行失败: " .. tostring(run_error))
    end
  end)
end

function M.create()
  ensure_imgui()
  local settings = config.load_settings()
  return {
    ctx = reaper.ImGui_CreateContext("Lee Splitter Dashboard"),
    ImGui = create_imgui_adapter(),
    W = load_widgets(),
    Colors = load_shared_colors(),
    open = true,
    running = false,
    settings = settings,
    hop_index = hop_index_from_value(settings.hop_length),
    status_kind = STATUS.idle,
    status_text = "等待执行",
  }
end

local function draw_controls(state)
  local changed
  reaper.ImGui_Text(state.ctx, "Lee Splitter Dashboard")
  if reaper.ImGui_TextDisabled then
    reaper.ImGui_TextDisabled(state.ctx, "Tonal / Transient / Noise")
  end
  reaper.ImGui_Separator(state.ctx)
  state.W.separator_text(state.ctx, state.ImGui, "Splitter Parameters")

  changed, state.settings.margin = state.W.slider_float(
    state.ctx, state.ImGui,
    "Margin",
    state.settings.margin,
    1.0,
    10.0,
    "%.1f"
  )

  changed, state.settings.wiener_iters = state.W.slider_int(
    state.ctx, state.ImGui,
    "Wiener",
    state.settings.wiener_iters,
    0,
    10,
    "%d"
  )

  state.W.separator_text(state.ctx, state.ImGui, "Track Output")
  local is_new = state.settings.track_mode == config.TRACK_MODES.new_tracks
  if reaper.ImGui_RadioButton(state.ctx, "New Tracks", is_new) then
    state.settings.track_mode = config.TRACK_MODES.new_tracks
  end
  reaper.ImGui_SameLine(state.ctx)
  local is_reuse = state.settings.track_mode == config.TRACK_MODES.reuse_tracks
  if reaper.ImGui_RadioButton(state.ctx, "Reuse Existing Empty Tracks First", is_reuse) then
    state.settings.track_mode = config.TRACK_MODES.reuse_tracks
  end

  changed, state.settings.mute_source_item = reaper.ImGui_Checkbox(
    state.ctx,
    "Mute Source Item After Split",
    state.settings.mute_source_item
  )

  changed, state.hop_index = reaper.ImGui_Combo(
    state.ctx,
    "Hop Length",
    state.hop_index,
    HOP_ITEMS
  )
  if changed then
    apply_hop(state)
  end
end

function M.frame(state)
  if not state or not state.ctx then
    return false
  end

  if reaper.ImGui_SetNextWindowSize then
    reaper.ImGui_SetNextWindowSize(state.ctx, 420, 330, cond_first_use_ever())
  end

  if reaper.ImGui_SetNextWindowDockID then
    reaper.ImGui_SetNextWindowDockID(state.ctx, 0)
  end

  local style_vars = push_round_style(state.ctx)
  local pushed_colors = push_theme(state.ctx, state.Colors)

  local window_flags = 0
  if reaper.ImGui_WindowFlags_NoTitleBar then
    window_flags = window_flags | reaper.ImGui_WindowFlags_NoTitleBar()
  end
  if reaper.ImGui_WindowFlags_NoCollapse then
    window_flags = window_flags | reaper.ImGui_WindowFlags_NoCollapse()
  end
  if reaper.ImGui_WindowFlags_NoScrollbar then
    window_flags = window_flags | reaper.ImGui_WindowFlags_NoScrollbar()
  end
  if reaper.ImGui_WindowFlags_NoDocking then
    window_flags = window_flags | reaper.ImGui_WindowFlags_NoDocking()
  end

  local begin_ok, visible, p_open, began = begin_window_compat(
    state.ctx,
    "Lee Splitter Dashboard",
    state.open,
    window_flags
  )
  if not begin_ok then
    if pushed_colors > 0 then
      reaper.ImGui_PopStyleColor(state.ctx, pushed_colors)
    end
    pop_round_style(state.ctx, style_vars)
    error(visible)
  end

  if type(p_open) == "boolean" then
    state.open = p_open
  end

  if visible then
    draw_controls(state)
    reaper.ImGui_Separator(state.ctx)

    if state.running then
      local disabled_started = begin_disabled(state.ctx)
      reaper.ImGui_Button(state.ctx, "Start Splitting", 160, 0)
      end_disabled(state.ctx, disabled_started)
    else
      if reaper.ImGui_Button(state.ctx, "Start Splitting", 160, 0) then
        start_split(state)
      end
    end

    reaper.ImGui_Separator(state.ctx)
    draw_status(state)
    reaper.ImGui_Separator(state.ctx)
    if reaper.ImGui_Button(state.ctx, "Exit", 120, 0) then
      state.open = false
    end
  end

  if began then
    reaper.ImGui_End(state.ctx)
  end

  if pushed_colors > 0 then
    reaper.ImGui_PopStyleColor(state.ctx, pushed_colors)
  end
  pop_round_style(state.ctx, style_vars)

  return state.open
end

function M.destroy(state)
  if state and state.ctx and reaper.ImGui_DestroyContext then
    reaper.ImGui_DestroyContext(state.ctx)
    state.ctx = nil
  end
end

return M
