-- @description Drop Station — 将 Item 作为文件路径拖拽到外部 / 复制路径
-- @author Lee
-- @version 0.1.0
-- @about
--   悬浮工具：按 Source / Dry Clip / Wet Clip 解析本地文件路径；
--   Windows 下通过 C++ 扩展 reaper_dropstation.dll 发起系统级文件拖拽（CF_HDROP），
--   其它平台或非扩展环境请使用 Copy Path；支持用系统默认程序打开文件、在资源管理器中显示。

local r = reaper

local _, script_path = r.get_action_context()
local script_dir = script_path:match("^(.*[\\/])")

local sep = package.config:sub(1, 1)
local framework = script_dir .. ".." .. sep .. ".." .. sep .. "Shared" .. sep .. "Toolbox" .. sep .. "framework" .. sep .. "?.lua"
package.path = framework .. ";" .. package.path

local bootstrap = require("bootstrap")
local ImGui = bootstrap.ensure_imgui("0.9")
if not ImGui then
  return
end

local App = require("app").App
local W = require("widgets")
local Theme = require("ui_theme")
local AppState = require("app_state")

local Export = dofile(script_dir .. "src" .. sep .. "drop_export.lua")

local app = App.new(ImGui, {
  title = "Drop Station",
  ext_section = "Toolbox_DropStation",
})

local export_mode = tonumber(r.GetExtState("Toolbox_DropStation", "export_mode"))
if export_mode == nil or export_mode < 0 or export_mode > 2 then
  export_mode = 1
end

local last_status = ""
local last_gen_item = nil
local last_gen_mode = nil
local last_gen_path = nil
local last_resolve_err = ""
local prev_item_ptr = nil
local prev_export_mode = nil

local destroyed = false
r.atexit(function()
  if not destroyed then
    destroyed = true
    pcall(function()
      Theme.destroy(app)
      app:destroy()
    end)
  end
end)

local function save_export_mode()
  r.SetExtState("Toolbox_DropStation", "export_mode", tostring(export_mode), true)
end

local function selected_item_and_label()
  local n = r.CountSelectedMediaItems(0)
  if n == 0 then
    return nil, "No Item Selected"
  end
  local it = r.GetSelectedMediaItem(0, 0)
  if not r.ValidatePtr2(0, it, "MediaItem*") then
    return nil, "No Item Selected"
  end
  local take = r.GetActiveTake(it)
  local label = "Media Item"
  if take then
    local _, nm = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if nm and nm ~= "" then
      label = nm
    end
  end
  if n > 1 then
    label = label .. string.format("  (%d items)", n)
  end
  return it, label
end

local function resolve_export_path(item)
  if not item then
    return nil, "No item"
  end
  local first = r.GetSelectedMediaItem(0, 0)
  if not r.ValidatePtr2(0, first, "MediaItem*") then
    return nil, "No item"
  end
  return Export.resolve(first, export_mode)
end

--- 用于「用系统打开 / 在文件夹中显示」：Source 即时路径；Dry/Wet 优先已生成缓存否则现算。
local function path_for_shell_action(item)
  if not item then
    return nil, "No item"
  end
  if export_mode == 0 then
    return Export.get_source_path(item)
  end
  if last_gen_path and last_gen_item == item and last_gen_mode == export_mode then
    return last_gen_path, ""
  end
  return resolve_export_path(item)
end

local function shell_open_file(path)
  if not path or path == "" then
    return false
  end
  if r.CF_ShellExecute then
    r.CF_ShellExecute(path)
    return true
  end
  local ps = package.config:sub(1, 1)
  if ps == "\\" then
    local q = '"' .. path:gsub('"', "") .. '"'
    os.execute("cmd /c start \"\" " .. q)
    return true
  end
  os.execute("xdg-open " .. string.format("%q", path))
  return true
end

local function shell_reveal_in_folder(path)
  if not path or path == "" then
    return false
  end
  local ps = package.config:sub(1, 1)
  if ps == "\\" then
    local norm = path:gsub("/", "\\"):gsub('"', "")
    os.execute('explorer /select,"' .. norm .. '"')
    return true
  end
  local osn = (r.GetOS and r.GetOS()) or ""
  if osn:find("OSX") or osn:find("macOS") or osn == "Darwin" then
    os.execute("open -R " .. string.format("%q", path))
    return true
  end
  local dir = path:match("^(.*)[/\\][^/\\]+$") or "."
  if r.CF_ShellExecute then
    r.CF_ShellExecute(dir)
    return true
  end
  os.execute("xdg-open " .. string.format("%q", dir))
  return true
end

local function note_generation_ok(item, path)
  last_gen_path = path
  last_gen_item = item
  last_gen_mode = export_mode
  last_resolve_err = ""
end

local function display_path_block(ctx, item)
  if not item then
    return
  end
  if export_mode == 0 then
    local p, e = Export.get_source_path(item)
    if p then
      ImGui.TextDisabled(ctx, "Path:")
      ImGui.SameLine(ctx)
      ImGui.TextWrapped(ctx, p)
    elseif e and e ~= "" then
      ImGui.TextColored(ctx, 0xFF4444FF, e)
    else
      ImGui.TextDisabled(ctx, "No path")
    end
    return
  end
  if last_gen_path and last_gen_item == item and last_gen_mode == export_mode then
    ImGui.TextDisabled(ctx, "Last file:")
    ImGui.SameLine(ctx)
    ImGui.TextWrapped(ctx, last_gen_path)
  elseif last_resolve_err ~= "" then
    ImGui.TextColored(ctx, 0xFF4444FF, last_resolve_err)
  else
    ImGui.TextDisabled(ctx, "Dry / Wet：点击 [ Drag to External ] / Copy Path 时在 _DropTemp 生成 .wav；Source 非 wav 请用 Copy Path。")
  end
end

local function draw()
  local ctx = app.ctx

  W.separator_text(ctx, ImGui, "Drop Station")

  local item, label = selected_item_and_label()

  ImGui.TextDisabled(ctx, "Selection:")
  ImGui.SameLine(ctx)
  ImGui.Text(ctx, label)

  local mode_labels = "Source\0Dry Clip\0Wet Clip\0"
  local _, new_mode = ImGui.Combo(ctx, "Mode", export_mode, mode_labels)
  if new_mode ~= export_mode then
    export_mode = new_mode
    save_export_mode()
  end
  ImGui.SameLine(ctx)
  W.help_marker(ctx, ImGui, "Source: 原始文件路径。\nDry: 隐藏轨上复制并 Glue（已尽量移除 Take FX），输出到工程 _DropTemp。\nWet: 定稿方案 — RENDER_SETTINGS=64（选中 Item 走 Master）+ 42230 静默渲染，不写茎干轨。\n「用系统打开 / 在文件夹中显示」与 Copy 使用相同路径解析规则。")

  ImGui.Spacing(ctx)

  display_path_block(ctx, item)

  ImGui.Spacing(ctx)

  local row_w = ImGui.GetContentRegionAvail(ctx)
  local btn_w = Export.draw_drag_to_external(ctx, ImGui, {
    row_w = row_w,
    resolve = function()
      return resolve_export_path(item)
    end,
    on_note_ok = function(p)
      note_generation_ok(item, p)
    end,
    on_error = function(msg)
      last_resolve_err = msg
      last_status = msg
    end,
    on_status = function(msg)
      last_status = msg
    end,
  })

  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Copy Path", math.max(80, row_w - btn_w - 8), 36) then
    local p, e = resolve_export_path(item)
    if p and ImGui.SetClipboardText then
      ImGui.SetClipboardText(ctx, p)
      last_status = "Copied: " .. p
      note_generation_ok(item, p)
    else
      last_resolve_err = e or "Copy failed"
      last_status = last_resolve_err
    end
  end

  ImGui.Spacing(ctx)
  local row2 = ImGui.GetContentRegionAvail(ctx)
  local half = (row2 - 8) / 2
  if half < 100 then
    half = 100
  end
  if ImGui.Button(ctx, "用系统打开", half, 28) then
    local p, e = path_for_shell_action(item)
    if p then
      if shell_open_file(p) then
        last_status = "Opened: " .. p
        if export_mode ~= 0 then
          note_generation_ok(item, p)
        end
      else
        last_resolve_err = "Could not launch file"
        last_status = last_resolve_err
      end
    else
      last_resolve_err = e or "No path to open"
      last_status = last_resolve_err
    end
  end
  if ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.BeginTooltip then
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, "使用系统默认程序打开当前路径（优先 SWS CF_ShellExecute）。")
    ImGui.EndTooltip(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "在文件夹中显示", half, 28) then
    local p, e = path_for_shell_action(item)
    if p then
      if shell_reveal_in_folder(p) then
        last_status = "Reveal: " .. p
        if export_mode ~= 0 then
          note_generation_ok(item, p)
        end
      else
        last_resolve_err = "Reveal not supported on this OS"
        last_status = last_resolve_err
      end
    else
      last_resolve_err = e or "No path to reveal"
      last_status = last_resolve_err
    end
  end
  if ImGui.IsItemHovered and ImGui.IsItemHovered(ctx) and ImGui.BeginTooltip then
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, "Windows: explorer /select；macOS: open -R；Linux: 打开所在文件夹。")
    ImGui.EndTooltip(ctx)
  end

  if last_status ~= "" then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, last_status)
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  if ImGui.Button(ctx, "Close", -1, 22) then
    app.open = false
  end

  if item ~= prev_item_ptr or export_mode ~= prev_export_mode then
    last_gen_path = nil
    last_gen_item = nil
    last_gen_mode = nil
    last_resolve_err = ""
    last_status = ""
  end
  prev_item_ptr = item
  prev_export_mode = export_mode
end

local function loop()
  Theme.begin(app)

  local sw = 400 * (app.state.scale or 1)
  local sh = 248 * (app.state.scale or 1)
  if ImGui.SetNextWindowSize then
    local cond_always = 1
    if ImGui.Cond_Always then
      if type(ImGui.Cond_Always) == "function" then
        cond_always = ImGui.Cond_Always()
      else
        cond_always = ImGui.Cond_Always
      end
    end
    ImGui.SetNextWindowSize(app.ctx, sw, sh, cond_always)
  end

  local visible, open
  if app.open == false then
    visible, open = false, false
  else
    visible, open = app:begin_window()
    if visible then
      draw()
    end
    app:end_window()
    if app.open == false then
      open = false
    end
  end

  Theme.end_(app)

  if open then
    AppState.tick(app, app.state.low_cpu and 2.0 or 0.2)
    r.defer(loop)
  else
    if not destroyed then
      destroyed = true
      Theme.destroy(app)
      app:destroy()
    end
  end
end

r.defer(loop)
