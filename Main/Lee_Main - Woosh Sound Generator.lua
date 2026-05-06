-- @description Lee Main - Woosh Sound Generator
-- @version 0.3
-- @author Lee
-- @about
--   Sony Woosh API 文本生成音频，自动插入到 REAPER 时间线。
--   - Model: Woosh-DFlow / Woosh-Flow（默认参数随模型）
--   - Sampler: 仅 Flow 生效（dopri5/dopri8/bosh3/adaptive_heun）
--   - 插入模式：默认 / 保持光标 / 新建轨道
--   - 批量生成 + 跟随顶部 Random Seed 复选框
--   - 一键启动本地 start_server.bat
--   - 使用 Lee_Scripts/Shared/Toolbox 框架（主题/Log/Dock）

-- ══════════════════════════════════════════════
-- Toolbox 引导
-- ══════════════════════════════════════════════

local r = reaper

local function script_dir()
  local src = debug.getinfo(1, "S").source
  return src:match("^@(.+[\\/])")
end

local script_root = script_dir() or ""
local sep = package.config:sub(1, 1)

-- 当前脚本位于 Lee_Scripts/Main/，Toolbox 在 Lee_Scripts/Shared/Toolbox/framework
package.path = script_root .. ".." .. sep .. "Shared" .. sep .. "Toolbox" .. sep .. "framework" .. sep .. "?.lua;" .. package.path

local bootstrap = require("bootstrap")
local ImGui = bootstrap.ensure_imgui("0.9")
if not ImGui then return end

if not r.CF_ShellExecute then
  r.ShowMessageBox("需要 SWS Extension（CF_ShellExecute）。\n请安装：https://www.sws-extension.org",
                   "缺少依赖", 0)
  return
end

local App      = require("app").App
local W        = require("widgets")
local Theme    = require("ui_theme")
local AppState = require("app_state")
local Dock     = require("dock")
local Editors  = require("editors")
local Log      = require("log")
local Terminal = require("terminal")

-- ══════════════════════════════════════════════
-- 业务配置
-- ══════════════════════════════════════════════

local API_HOST   = "127.0.0.1"
local API_PORT   = 8000
local API_URL    = string.format("http://%s:%d/generate", API_HOST, API_PORT)
local PING_URL   = string.format("http://%s:%d/ping",     API_HOST, API_PORT)
local SERVER_BAT = [[E:\Audio_Projects\Tools\SonyWhoosh\Woosh_Playground\start_server.bat]]

local MODELS = { "Woosh-DFlow", "Woosh-Flow" }
local MODEL_DEFAULTS = {
  ["Woosh-DFlow"] = { cfg = 4.5, num_steps = 4, steps_locked = false, sampler_active = false,
                      note = "Distilled, fast (~4 steps). Sampler=Euler (fixed)." },
  ["Woosh-Flow"]  = { cfg = 4.5, num_steps = 0, steps_locked = true,  sampler_active = true,
                      note = "Adaptive ODE. Steps auto by tolerance. Sampler choice matters." },
}
local ODE_METHODS = { "dopri5", "dopri8", "bosh3", "adaptive_heun" }
local INSERT_MODES = {
  { id = "default",   label = "Insert at cursor (cursor moves)" },
  { id = "stay",      label = "Insert at cursor, keep cursor" },
  { id = "new_track", label = "New track below, keep cursor" },
}

-- ══════════════════════════════════════════════
-- 工具函数
-- ══════════════════════════════════════════════

local TMP_DIR = script_root .. "tmp"
r.RecursiveCreateDirectory(TMP_DIR, 0)

local function resolve_save_dir()
  local _, proj_path = r.EnumProjects(-1, "")
  local proj_dir = proj_path and proj_path ~= "" and proj_path:match("(.+)[/\\]") or nil
  if proj_dir then
    local sub = proj_dir .. sep .. "Woosh"
    r.RecursiveCreateDirectory(sub, 0)
    return sub
  end
  local fb = script_root .. "generated"
  r.RecursiveCreateDirectory(fb, 0)
  return fb
end

local function make_id()
  local t = math.floor(r.time_precise() * 1000000)
  return string.format("%x%04x", t, math.random(0, 0xFFFF))
end

local function write_file(path, content)
  local f = io.open(path, "wb"); if not f then return false end
  f:write(content); f:close(); return true
end
local function read_file(path)
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function file_exists(path)
  local f = io.open(path, "rb"); if f then f:close(); return true end; return false
end
local function file_size(path)
  local f = io.open(path, "rb"); if not f then return 0 end
  local sz = f:seek("end") or 0; f:close(); return sz
end
local function remove_files(...)
  for _, p in ipairs({...}) do pcall(os.remove, p) end
end
local function win_path(p) return (p:gsub("/", "\\")) end

local function json_escape(s)
  return s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
end
local function json_value(v)
  local t = type(v)
  if t == "string"  then return '"' .. json_escape(v) .. '"' end
  if t == "number"  then return tostring(v) end
  if t == "boolean" then return v and "true" or "false" end
  if t == "table"   then
    local parts = {}
    for k, vv in pairs(v) do parts[#parts + 1] = '"' .. k .. '":' .. json_value(vv) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local function launch_curl_silent(curl_args, flag_path, vbs_path)
  local cmd_line = 'curl ' .. curl_args
                .. ' & echo 1 > ""' .. win_path(flag_path) .. '""'
  local vbs = 'On Error Resume Next\n'
            .. 'Set s = WScript.CreateObject("WScript.Shell")\n'
            .. 's.Run "cmd /C ' .. cmd_line .. '", 0, True\n'
  if not write_file(vbs_path, vbs) then return false end
  r.CF_ShellExecute(win_path(vbs_path))
  return true
end

-- ══════════════════════════════════════════════
-- App + 业务状态
-- ══════════════════════════════════════════════

local app = App.new(ImGui, {
  title = "Lee Main - Woosh Sound Generator",
  ext_section = "Lee_Woosh_Generator",
})

local function apply_model_defaults(state, model)
  local d = MODEL_DEFAULTS[model]; if not d then return end
  state.cfg            = d.cfg
  state.num_steps      = d.num_steps
  state.steps_locked   = d.steps_locked
  state.sampler_active = d.sampler_active
end

local function biz()
  if app._biz then return app._biz end
  app._biz = {
    prompt        = "A short, dark, and ominous soundscape with deep bass and eerie textures.",
    model         = "Woosh-DFlow",
    cfg           = 4.5,
    num_steps     = 4,
    steps_locked  = false,
    sampler_active= false,
    ode_method    = "dopri5",
    seed_random   = true,
    seed          = 0,
    batch_count   = 1,
    insert_mode   = "default",

    batch_remaining = 0,
    batch_total     = 0,

    busy            = false,
    start_time      = 0,
    status_text     = "Ready.",
    last_file       = "",
    server_ok       = nil,
    server_check_pending = false,
    server_starting = false,
  }
  apply_model_defaults(app._biz, app._biz.model)
  return app._biz
end

-- ══════════════════════════════════════════════
-- Server control
-- ══════════════════════════════════════════════

local function ping_server(on_done)
  local s = biz()
  if s.server_check_pending then return end
  s.server_check_pending = true

  local id = make_id()
  local res_path  = TMP_DIR .. sep .. "ping_res_"  .. id .. ".txt"
  local err_path  = TMP_DIR .. sep .. "ping_err_"  .. id .. ".log"
  local vbs_path  = TMP_DIR .. sep .. "ping_run_"  .. id .. ".vbs"
  local flag_path = TMP_DIR .. sep .. "ping_done_" .. id .. ".flag"

  local args = '-s --max-time 3 ""' .. PING_URL .. '""'
            .. ' > ""' .. win_path(res_path) .. '""'
            .. ' 2> ""' .. win_path(err_path) .. '""'

  if not launch_curl_silent(args, flag_path, vbs_path) then
    s.server_check_pending = false
    s.server_ok = false
    s.status_text = "Failed to launch ping."
    if on_done then on_done(false) end
    return
  end

  local count = 0
  local function poll()
    count = count + 1
    if file_exists(flag_path) then
      local body = read_file(res_path) or ""
      remove_files(res_path, err_path, vbs_path, flag_path)
      s.server_check_pending = false
      local ok = body:find('"status"%s*:%s*"ok"') ~= nil
      s.server_ok = ok
      s.status_text = ok and ("Server OK (" .. API_HOST .. ":" .. API_PORT .. ").") or "Server unreachable."
      if on_done then on_done(ok) end
      return
    end
    if count >= 120 then
      remove_files(res_path, err_path, vbs_path, flag_path)
      s.server_check_pending = false
      s.server_ok = false
      s.status_text = "Ping timeout."
      if on_done then on_done(false) end
      return
    end
    r.defer(poll)
  end
  r.defer(poll)
end

local function start_server()
  local s = biz()
  if s.server_starting then return end
  if not file_exists(SERVER_BAT) then
    s.status_text = "start_server.bat not found: " .. SERVER_BAT
    Log.warn(app.log, s.status_text)
    return
  end
  s.server_starting = true
  s.status_text = "Starting server... (model load may take 30-90s)"
  Log.info(app.log, "Launching " .. SERVER_BAT)

  local vbs_path = TMP_DIR .. sep .. "start_srv_" .. make_id() .. ".vbs"
  local bat = SERVER_BAT:gsub('"', '""')
  local vbs = 'On Error Resume Next\n'
           .. 'Set sh = WScript.CreateObject("WScript.Shell")\n'
           .. 'sh.Run """' .. bat .. '""", 1, False\n'
  if not write_file(vbs_path, vbs) then
    s.server_starting = false
    s.status_text = "Failed to write launcher VBS."
    return
  end
  r.CF_ShellExecute(win_path(vbs_path))

  local tries = 0
  local function try_ping()
    tries = tries + 1
    ping_server(function(ok)
      if ok then
        s.server_starting = false
        remove_files(vbs_path)
        s.status_text = "Server is up."
        Log.info(app.log, "Server reached after " .. tries .. " attempts.")
        return
      end
      if tries >= 40 then
        s.server_starting = false
        remove_files(vbs_path)
        s.status_text = "Server did not come up in 120s. Check the terminal window."
        Log.warn(app.log, s.status_text)
        return
      end
      local t0 = r.time_precise()
      local function wait()
        if r.time_precise() - t0 > 3 then try_ping() else r.defer(wait) end
      end
      wait()
    end)
  end
  try_ping()
end

-- ══════════════════════════════════════════════
-- 插入逻辑
-- ══════════════════════════════════════════════

local function get_target_track()
  return r.GetSelectedTrack(0, 0) or r.GetLastTouchedTrack()
end

local function insert_on_track(track, file_path, keep_cursor)
  local cur = r.GetCursorPositionEx(0)
  r.Main_OnCommand(40297, 0)
  r.SetOnlyTrackSelected(track)
  local rv = r.InsertMedia(file_path, 0)
  if keep_cursor then r.SetEditCurPos(cur, false, false) end
  return rv ~= 0
end

local function do_insert(file_path)
  local s = biz()
  local mode = s.insert_mode
  if mode == "default" then
    local tr = get_target_track()
    if not tr then s.status_text = "No track. Select one or use 'New track'."; return false end
    return insert_on_track(tr, file_path, false)
  elseif mode == "stay" then
    local tr = get_target_track()
    if not tr then s.status_text = "No track. Select one or use 'New track'."; return false end
    return insert_on_track(tr, file_path, true)
  elseif mode == "new_track" then
    local idx = r.CountTracks(0)
    local cur_tr = get_target_track()
    if cur_tr then
      idx = math.floor(r.GetMediaTrackInfo_Value(cur_tr, "IP_TRACKNUMBER"))
    end
    r.InsertTrackAtIndex(idx, true)
    local new_tr = r.GetTrack(0, idx)
    if not new_tr then s.status_text = "Failed to create track."; return false end
    r.GetSetMediaTrackInfo_String(new_tr, "P_NAME", "Woosh " .. os.date("%H:%M:%S"), true)
    return insert_on_track(new_tr, file_path, true)
  end
  return false
end

-- ══════════════════════════════════════════════
-- Generate
-- ══════════════════════════════════════════════

local generate_one, continue_batch

generate_one = function(seed_override)
  local s = biz()
  if s.busy then return end
  local prompt = (s.prompt or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if prompt == "" then
    s.status_text = "Prompt is empty."
    s.batch_remaining = 0
    return
  end

  local seed = seed_override
  if seed == nil then
    seed = s.seed_random and math.random(0, 2^31 - 1) or s.seed
  end

  local body = {
    version = "0.1",
    token   = "string",
    args = {
      model           = s.model,
      prompt          = prompt,
      cfg             = s.cfg,
      sampler         = "heun",
      num_steps       = s.num_steps,
      ode_method      = s.ode_method,
      sigma_min       = 0.0001,
      sigma_max       = 80,
      rho             = 7,
      S_churn         = 1,
      S_min           = 0,
      S_noise         = 1,
      guidance_scale  = 7.5,
      noise_scheduler = "karras",
      seed            = seed,
    },
  }

  local id = make_id()
  local save_dir  = resolve_save_dir()
  local req_path  = TMP_DIR  .. sep .. "req_"   .. id .. ".json"
  local out_path  = save_dir .. sep .. "woosh_" .. id .. ".flac"
  local err_path  = TMP_DIR  .. sep .. "err_"   .. id .. ".log"
  local vbs_path  = TMP_DIR  .. sep .. "run_"   .. id .. ".vbs"
  local flag_path = TMP_DIR  .. sep .. "done_"  .. id .. ".flag"

  if not write_file(req_path, json_value(body)) then
    s.status_text = "Failed to write request body."
    s.batch_remaining = 0
    return
  end

  local curl_args = '-s --max-time 300 -X POST'
                 .. ' -H ""Content-Type: application/json""'
                 .. ' -H ""Accept: audio/flac""'
                 .. ' --data-binary @""' .. win_path(req_path) .. '""'
                 .. ' --output ""' .. win_path(out_path) .. '""'
                 .. ' ""' .. API_URL .. '""'
                 .. ' 2> ""' .. win_path(err_path) .. '""'

  if not launch_curl_silent(curl_args, flag_path, vbs_path) then
    remove_files(req_path)
    s.status_text = "Failed to launch curl."
    s.batch_remaining = 0
    return
  end

  s.busy = true
  s.start_time = r.time_precise()
  local idx_in_batch = s.batch_total - s.batch_remaining + 1
  s.status_text = string.format("Generating [%d/%d], seed=%d...", idx_in_batch, s.batch_total, seed)
  Log.info(app.log, s.status_text)

  local count = 0
  local function poll()
    count = count + 1
    if file_exists(flag_path) then
      local sz  = file_size(out_path)
      local err = read_file(err_path) or ""
      local cleanup = {req_path, err_path, vbs_path, flag_path}
      if sz > 0 then
        r.PreventUIRefresh(1)
        r.Undo_BeginBlock()
        local ok = do_insert(out_path)
        r.Undo_EndBlock("Woosh: Insert generated audio", -1)
        r.PreventUIRefresh(-1)
        r.UpdateArrange()

        local elapsed = r.time_precise() - s.start_time
        s.status_text = string.format("[%d/%d] Done %.2fs (seed=%d)%s",
                                       idx_in_batch, s.batch_total, elapsed, seed,
                                       ok and "" or " — insert failed")
        Log.info(app.log, s.status_text)
        s.last_file = out_path
        remove_files(table.unpack(cleanup))
      else
        local resp_body = read_file(out_path) or ""
        remove_files(out_path)
        local detail = (#resp_body > 0) and resp_body:sub(1, 300)
                       or (#err > 0 and ("curl: " .. err:sub(1, 300))
                                     or "empty response, server may be offline")
        s.status_text = "Failed: " .. detail
        Log.warn(app.log, s.status_text)
        remove_files(table.unpack(cleanup))
        s.batch_remaining = 0
        s.busy = false
        return
      end
      s.busy = false
      continue_batch()
      return
    end
    if count >= 12000 then
      remove_files(req_path, err_path, vbs_path, flag_path)
      s.status_text = "Timeout (>5min)."
      Log.warn(app.log, s.status_text)
      s.busy = false
      s.batch_remaining = 0
      return
    end
    r.defer(poll)
  end
  r.defer(poll)
end

continue_batch = function()
  local s = biz()
  if s.batch_remaining <= 0 then return end
  s.batch_remaining = s.batch_remaining - 1
  if s.batch_remaining <= 0 then
    s.status_text = s.status_text .. " — batch done."
    Log.info(app.log, "Batch done.")
    return
  end
  r.defer(function() generate_one(nil) end)
end

local function start_batch()
  local s = biz()
  if s.busy then return end
  local n = math.max(1, math.floor(s.batch_count))
  s.batch_total     = n
  s.batch_remaining = n
  generate_one(nil)
end

-- ══════════════════════════════════════════════
-- UI sections
-- ══════════════════════════════════════════════

local function draw_header()
  local ctx = app.ctx
  local s = biz()

  -- 标题行 + 右侧关闭（无 LOG/TERM 等 Toolbox 顶栏，与本脚本无关）
  local close_w = 22
  if app._theme and app._theme.fonts and app._theme.fonts.heading1 then
    ImGui.PushFont(ctx, app._theme.fonts.heading1)
    ImGui.Text(ctx, "Woosh Sound Generator")
    ImGui.PopFont(ctx)
  else
    ImGui.Text(ctx, "Woosh Sound Generator")
  end
  ImGui.SameLine(ctx)
  if ImGui.GetContentRegionAvail and ImGui.SetCursorPosX and ImGui.GetCursorPosX then
    local avail = ImGui.GetContentRegionAvail(ctx)
    local cur_x = ImGui.GetCursorPosX(ctx)
    ImGui.SetCursorPosX(ctx, cur_x + avail - close_w)
  end
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF4040FF)
  if ImGui.Button(ctx, "X", close_w, 0) then app.open = false end
  ImGui.PopStyleColor(ctx, 4)

  ImGui.Separator(ctx)

  -- 服务器状态行
  if s.server_ok == true then
    ImGui.TextColored(ctx, 0x4ADE80FF, "● Server OK")
  elseif s.server_ok == false then
    ImGui.TextColored(ctx, 0xF87171FF, "● Server Down")
  else
    ImGui.TextColored(ctx, 0xA1A1AAFF, "● Checking...")
  end
  ImGui.SameLine(ctx); ImGui.Text(ctx, API_HOST .. ":" .. API_PORT)
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Ping") then ping_server() end
  ImGui.SameLine(ctx)
  if s.server_ok == false and not s.server_starting then
    if ImGui.SmallButton(ctx, "Start Server") then start_server() end
  elseif s.server_starting then
    ImGui.TextDisabled(ctx, "(starting...)")
  end
end

local function draw_prompt()
  local ctx = app.ctx
  local s = biz()
  W.separator_text(ctx, ImGui, "Prompt")

  local flags = ImGui.InputTextFlags_NoHorizontalScroll
  local _, new_prompt = ImGui.InputTextMultiline(ctx, "##prompt", s.prompt, -1, 56, flags)
  s.prompt = new_prompt

  if ImGui.TreeNode(ctx, "Preview (wrapped)") then
    ImGui.TextWrapped(ctx, s.prompt)
    ImGui.TreePop(ctx)
  end
end

local function draw_params()
  local ctx = app.ctx
  local s = biz()
  W.separator_text(ctx, ImGui, "Model & Params")

  ImGui.SetNextItemWidth(ctx, 200)
  if ImGui.BeginCombo(ctx, "Model", s.model) then
    for _, m in ipairs(MODELS) do
      local sel = (m == s.model)
      if ImGui.Selectable(ctx, m, sel) then
        if m ~= s.model then
          s.model = m
          apply_model_defaults(s, m)
          s.status_text = "Switched to " .. m .. ": " .. (MODEL_DEFAULTS[m].note or "")
          Log.info(app.log, s.status_text)
        end
      end
      if sel then ImGui.SetItemDefaultFocus(ctx) end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 160)
  if s.sampler_active then
    if ImGui.BeginCombo(ctx, "Sampler", s.ode_method) then
      for _, m in ipairs(ODE_METHODS) do
        local sel = (m == s.ode_method)
        if ImGui.Selectable(ctx, m, sel) then s.ode_method = m end
        if sel then ImGui.SetItemDefaultFocus(ctx) end
      end
      ImGui.EndCombo(ctx)
    end
  else
    ImGui.BeginDisabled(ctx, true)
    if ImGui.BeginCombo(ctx, "Sampler", "Euler (fixed)") then ImGui.EndCombo(ctx) end
    ImGui.EndDisabled(ctx)
  end

  ImGui.SetNextItemWidth(ctx, 200)
  local _, new_cfg = ImGui.SliderDouble(ctx, "CFG", s.cfg, 0.0, 15.0, "%.2f")
  s.cfg = new_cfg
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 160)
  if s.steps_locked then
    ImGui.BeginDisabled(ctx, true)
    ImGui.SliderInt(ctx, "Steps", 0, 0, 100, "auto")
    ImGui.EndDisabled(ctx)
  else
    local _, new_steps = ImGui.SliderInt(ctx, "Steps", s.num_steps, 1, 100)
    s.num_steps = new_steps
  end

  local _, sr = ImGui.Checkbox(ctx, "Random Seed", s.seed_random)
  s.seed_random = sr
  if not s.seed_random then
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 180)
    local _, ns = ImGui.InputInt(ctx, "Seed", s.seed)
    s.seed = ns
  end
end

local function draw_batch_and_insert()
  local ctx = app.ctx
  local s = biz()

  W.separator_text(ctx, ImGui, "Batch")
  ImGui.SetNextItemWidth(ctx, 180)
  local _, bc = ImGui.SliderInt(ctx, "Batch count", s.batch_count, 1, 16)
  s.batch_count = bc
  ImGui.SameLine(ctx)
  if s.seed_random then
    ImGui.TextDisabled(ctx, "(random seed per item)")
  else
    ImGui.TextDisabled(ctx, "(all items use seed " .. tostring(s.seed) .. ")")
  end

  W.separator_text(ctx, ImGui, "Insert mode")
  for _, m in ipairs(INSERT_MODES) do
    if ImGui.RadioButton(ctx, m.label, s.insert_mode == m.id) then
      s.insert_mode = m.id
    end
  end
end

local function draw_actions()
  local ctx = app.ctx
  local s = biz()
  ImGui.Separator(ctx)

  if s.busy or s.batch_remaining > 0 then
    ImGui.BeginDisabled(ctx, true)
    ImGui.Button(ctx, "Generating...", -1, 32)
    ImGui.EndDisabled(ctx)
    local elapsed = r.time_precise() - s.start_time
    ImGui.Text(ctx, string.format("Elapsed: %.1fs  (remaining %d)", elapsed, s.batch_remaining))
  else
    local label = (s.batch_count > 1)
      and string.format("Generate %d items", s.batch_count)
      or "Generate & Insert"
    if ImGui.Button(ctx, label, -1, 32) then start_batch() end
  end

  if s.last_file ~= "" then
    if ImGui.SmallButton(ctx, "Open output folder") then
      r.CF_ShellExecute(win_path(resolve_save_dir()))
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "last: " .. s.last_file:match("[^/\\]+$"))
  end

  ImGui.Separator(ctx)
  ImGui.TextWrapped(ctx, s.status_text)
end

local function draw()
  draw_header()
  draw_prompt()
  draw_params()
  draw_batch_and_insert()
  draw_actions()
end

-- ══════════════════════════════════════════════
-- Side windows + main loop（标准 Toolbox 模板）
-- ══════════════════════════════════════════════

local function draw_log_window()
  if not app.state.show_log then return end
  local ctx = app.ctx
  local visible, open = ImGui.Begin(ctx, "Woosh - Log", true)
  if visible then Log.draw(ctx, ImGui, app.log) end
  ImGui.End(ctx)
  if open == false then app.state.show_log = false end
end

local function draw_terminal_window()
  if not app.state.show_terminal then return end
  local ctx = app.ctx
  local visible, open = ImGui.Begin(ctx, "Woosh - Terminal", true)
  if visible then Terminal.draw(ctx, ImGui, app) end
  ImGui.End(ctx)
  if open == false then app.state.show_terminal = false end
end

local function draw_editors()
  if app.state.show_theme_editor then Editors.draw_theme(app.ctx, ImGui, app) end
  if app.state.show_style_editor then Editors.draw_style(app.ctx, ImGui, app) end
end

local first_frame = true
local destroyed = false

r.atexit(function()
  if not destroyed then
    destroyed = true
    pcall(function() Theme.destroy(app); app:destroy() end)
  end
end)

local function loop()
  Theme.begin(app)
  Dock.ensure(app.ctx, ImGui, 0)

  local visible, open
  if app.open == false then
    visible, open = false, false
  else
    visible, open = app:begin_window()
    if visible then draw() end
    app:end_window()
    if app.open == false then open = false end
  end

  if open then
    draw_log_window()
    draw_terminal_window()
    draw_editors()
  end

  Theme.end_(app)
  if open then AppState.tick(app, app.state.low_cpu and 2.0 or 0.75) end

  if open then
    if first_frame then
      first_frame = false
      ping_server()
    end
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
