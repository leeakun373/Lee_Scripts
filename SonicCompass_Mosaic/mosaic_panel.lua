-- @description SonicCompass Mosaic — 口技参考马赛克回写面板
-- @version 1.1
-- @author Lee / SonicCompass
-- @about
--   REAPER 选中 Item → 渲染 → 发送到 Sonic Compass → 马赛克检索合成 → 回写
--   基于 Lee_Scripts/Shared/Toolbox 框架（ReaImGui）

local r = reaper

-- ── 路径解析 ──
local function script_dir()
  local src = debug.getinfo(1, "S").source
  return src:match("^@(.+[\\/])")
end

local this_dir = script_dir()
-- 同目录模块
package.path = this_dir .. "?.lua;" .. package.path
-- Toolbox 框架
local toolbox_root = r.GetResourcePath() .. "/Scripts/Lee_Scripts/Shared/Toolbox/"
package.path = toolbox_root .. "framework/?.lua;" .. package.path

-- ── 依赖加载 ──
local bootstrap = require("bootstrap")
local ImGui = bootstrap.ensure_imgui("0.9")
if not ImGui then return end

local App    = require("app").App
local W      = require("widgets")
local Colors = require("ui_colors")
local Theme  = require("ui_theme")
local Log    = require("log")

local http_client   = require("http_client")
local render_export = require("render_export")
local writeback     = require("writeback")

-- ── 配置 ──
local SC_PORT       = 18765
local SC_URL        = "http://127.0.0.1:" .. SC_PORT
local GENERATE_URL  = SC_URL .. "/api/mosaic/generate"
local HEALTH_URL    = SC_URL .. "/api/mosaic/health"

-- ── App 实例 ──
local app = App.new(ImGui, {
  title      = "SonicCompass Mosaic",
  ext_section = "SonicCompass_Mosaic",
})

-- ── 状态 ──
local state = {
  query            = "",
  frequency_bias   = 0.5,    -- 0.0=物理特征优先, 1.0=音色(MFCC)优先
  envelope_strict  = 1.0,    -- 0.0=忽略包络, 1.0=严格匹配参考包络
  writeback_mode   = 0,      -- 0=new_track_mute, 1=replace
  is_busy          = false,
  status_msg       = "",
  status_level     = "info", -- "info" | "warn" | "error" | "ok"
  -- SC 连接状态
  sc_connected     = false,
  sc_check_time    = 0,      -- 上次检查时间
  -- 最近一次结果
  last_pool_files  = 0,
  last_pool_chunks = 0,
  last_duration    = 0,
  last_elapsed     = 0,
  -- 动画
  anim_dots        = 0,
  anim_time        = 0,
}

-- ── 状态颜色 ──
local function status_color(level)
  if level == "ok"    then return 0xFF80FF50 end  -- 绿
  if level == "warn"  then return 0xFFE0CC33 end  -- 黄
  if level == "error" then return 0xFF6666FF end  -- 红（ImGui ABGR）
  return 0xFFCCCCCC                                -- 灰
end

local function set_status(msg, level)
  state.status_msg = msg
  state.status_level = level or "info"
  Log.info(app.log, "[Mosaic] " .. msg)
end

-- ── 错误弹窗辅助 ──
local function show_error(title, msg)
  r.ShowMessageBox(msg, title, 0)
end

local function handle_server_error(resp)
  local err_msg = resp.message or "unknown error"
  local title = "SonicCompass Mosaic"

  if err_msg:find("No files found") then
    show_error(title .. " — No Results",
      "No matching files found for: \"" .. state.query .. "\"\n\n"
      .. "Try a different keyword or load a library with more content.")
  elseif err_msg:find("not available") or err_msg:find("not fully initialized") then
    show_error(title .. " — Service Unavailable",
      "Sonic Compass search engine is not ready.\n\n"
      .. "Please load a library first, then try again.")
  elseif err_msg:find("0 chunks") then
    show_error(title .. " — Pool Empty",
      "Files were found but could not be chunked.\n\n"
      .. "The matched audio files may be too short or corrupted.")
  elseif err_msg:find("Library changed") then
    show_error(title .. " — Library Switched",
      "The active library was switched while the request was in progress.\n\n"
      .. "Please try again with the current library.")
  elseif err_msg:find("Missing") then
    show_error(title .. " — Bad Request", err_msg)
  elseif err_msg:find("Reference file not found") then
    show_error(title .. " — File Missing",
      "The rendered reference WAV could not be found by Sonic Compass.\n\n"
      .. err_msg)
  else
    show_error(title .. " — Error", err_msg)
  end
end

-- ── SC 健康检查（后台非阻塞，同一时间只有一个 in-flight）──
-- 在线时 5 秒检查一次，离线时 15 秒检查一次（减少 curl 进程堆积）
local sc_health_in_flight = false

local function check_sc_health()
  if sc_health_in_flight then return end
  local now = r.time_precise()
  local interval = state.sc_connected and 5.0 or 15.0
  if now - state.sc_check_time < interval then return end
  state.sc_check_time = now
  sc_health_in_flight = true

  http_client.get(HEALTH_URL, function(ok, resp)
    sc_health_in_flight = false
    if ok and resp and resp.status == "ok" then
      state.sc_connected = true
    else
      state.sc_connected = false
    end
  end)
end

-- ── 核心：生成 ──
local function on_generate()
  if state.is_busy then return end

  -- 实时检测 Item 选中
  if r.CountSelectedMediaItems(0) == 0 then
    show_error("SonicCompass Mosaic",
      "No media item is selected.\n\n"
      .. "Please select an item in the REAPER arrange view, then click Generate.")
    return
  end

  -- query 校验
  local q = state.query:match("^%s*(.-)%s*$") -- trim
  if q == "" then
    show_error("SonicCompass Mosaic",
      "Please enter a search keyword before generating.\n\n"
      .. "The keyword is used to find candidate sounds in your Sonic Compass library.")
    return
  end

  -- SC 可达检查 — 避免渲染完才发现连不上
  if not state.sc_connected then
    show_error("SonicCompass Mosaic — Not Connected",
      "Sonic Compass is not running or not reachable.\n\n"
      .. "Please start Sonic Compass first, then try again.\n\n"
      .. "Expected service at: " .. SC_URL)
    return
  end

  state.is_busy = true
  set_status("Rendering selected item...", "warn")

  -- Step 1: 渲染
  local wav_path, err = render_export.render_selected_item()
  if not wav_path then
    set_status("Render failed: " .. (err or "unknown"), "error")
    show_error("SonicCompass Mosaic — Render Error",
      "Failed to render selected item:\n" .. (err or "unknown"))
    state.is_busy = false
    return
  end

  set_status("Searching & synthesizing...", "warn")

  -- Step 2: POST
  local wb_mode = state.writeback_mode == 0 and "new_track_mute" or "replace"
  local request_body = {
    ref_path            = wav_path,
    query               = q,
    request_id          = tostring(math.floor(r.time_precise() * 100000)),
    pool_max            = 200,
    frequency_bias      = state.frequency_bias,
    envelope_strictness = state.envelope_strict,
    protocol_version    = "mosaic_v1",
  }

  http_client.post_json(GENERATE_URL, request_body, function(ok, resp)
    if not ok then
      set_status("Connection error", "error")
      show_error("SonicCompass Mosaic — Connection Error",
        "Could not reach Sonic Compass HTTP service.\n\n"
        .. "Make sure Sonic Compass is running and the Mosaic bridge is active.\n\n"
        .. "Details: " .. tostring(resp))
      state.sc_connected = false
      state.is_busy = false
      return
    end

    if resp.status ~= "ok" then
      set_status("Error: " .. (resp.message or ""), "error")
      handle_server_error(resp)
      state.is_busy = false
      return
    end

    local output_path = resp.output_wav_path
    if not output_path or output_path == "" then
      set_status("Server returned empty path", "error")
      state.is_busy = false
      return
    end

    -- 记录统计
    state.last_pool_files  = tonumber(resp.pool_file_count) or 0
    state.last_pool_chunks = tonumber(resp.pool_chunk_count) or 0
    state.last_duration    = tonumber(resp.duration_sec) or 0
    state.last_elapsed     = tonumber(resp.elapsed_sec) or 0

    set_status("Writing back to REAPER...", "warn")

    -- Step 3: 回写
    local wb_ok, wb_err = writeback.execute(output_path, wb_mode)
    if wb_ok then
      set_status(string.format(
        "Done! %.1fs output, %d files, %d chunks (%.1fs)",
        state.last_duration, state.last_pool_files,
        state.last_pool_chunks, state.last_elapsed), "ok")
    else
      set_status("Writeback failed: " .. (wb_err or ""), "error")
      show_error("SonicCompass Mosaic — Writeback Error",
        "Failed to write result back to REAPER:\n" .. (wb_err or "unknown"))
    end

    state.is_busy = false
  end)
end

-- ── UI 绘制 ──
local function draw()
  local ctx = app.ctx

  -- ▸ Header: 标题行
  -- 关闭按钮（右上角）
  ImGui.SameLine(ctx, ImGui.GetWindowWidth(ctx) - 36)
  if ImGui.SmallButton(ctx, " X ") then
    app.open = false
    return
  end

  -- 标题 + 连接状态同行
  ImGui.Text(ctx, "SonicCompass Mosaic")
  ImGui.SameLine(ctx)
  if state.sc_connected then
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF80FF50)
    ImGui.Text(ctx, "[Online]")
    ImGui.PopStyleColor(ctx, 1)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF6666FF)
    ImGui.Text(ctx, "[Offline]")
    ImGui.PopStyleColor(ctx, 1)
  end

  -- ▸ Item 选中状态（实时）
  local has_sel = r.CountSelectedMediaItems(0) > 0
  if has_sel then
    local item = r.GetSelectedMediaItem(0, 0)
    local take = item and r.GetActiveTake(item)
    local name = ""
    if take then
      local _, n = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
      if n and n ~= "" then
        name = n
      else
        local src = r.GetMediaItemTake_Source(take)
        if src then
          local _, fn = r.GetMediaSourceFileName(src, "")
          if fn then name = fn:match("([^\\/]+)$") or fn end
        end
      end
    end
    if #name > 50 then name = "..." .. name:sub(-47) end
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF80FF50)
    ImGui.Text(ctx, "Item: " .. name)
    ImGui.PopStyleColor(ctx, 1)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF5599FF)
    ImGui.Text(ctx, "No item selected — select one in Arrange")
    ImGui.PopStyleColor(ctx, 1)
  end

  ImGui.Separator(ctx)

  -- ▸ Search Keywords
  W.separator_text(ctx, ImGui, "Search Keywords")
  ImGui.SetNextItemWidth(ctx, -1)
  local changed
  changed, state.query = ImGui.InputText(ctx, "##query", state.query)
  -- 不监听 Enter / IsItemDeactivatedAfterEdit：中文 IME 选词会误触发

  -- ▸ Parameters
  W.separator_text(ctx, ImGui, "Parameters")

  ImGui.Text(ctx, "Frequency Bias")
  ImGui.SameLine(ctx)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text,
    Colors.semantic and Colors.semantic.TextDim or 0xFFAAAAAA)
  ImGui.Text(ctx, "(0=physical  1=timbre)")
  ImGui.PopStyleColor(ctx, 1)
  ImGui.SetNextItemWidth(ctx, -1)
  changed, state.frequency_bias = ImGui.SliderDouble(
    ctx, "##freq_bias", state.frequency_bias, 0.0, 1.0, "%.2f")

  ImGui.Spacing(ctx)

  ImGui.Text(ctx, "Envelope Strictness")
  ImGui.SameLine(ctx)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text,
    Colors.semantic and Colors.semantic.TextDim or 0xFFAAAAAA)
  ImGui.Text(ctx, "(0=loose  1=strict)")
  ImGui.PopStyleColor(ctx, 1)
  ImGui.SetNextItemWidth(ctx, -1)
  changed, state.envelope_strict = ImGui.SliderDouble(
    ctx, "##env_strict", state.envelope_strict, 0.0, 1.0, "%.2f")

  ImGui.Spacing(ctx)

  -- ▸ Writeback Mode
  W.separator_text(ctx, ImGui, "Writeback Mode")
  changed = ImGui.RadioButton(ctx, "New Track + Mute Original", state.writeback_mode == 0)
  if changed then state.writeback_mode = 0 end
  ImGui.SameLine(ctx)
  changed = ImGui.RadioButton(ctx, "Replace Source", state.writeback_mode == 1)
  if changed then state.writeback_mode = 1 end

  ImGui.Spacing(ctx)

  -- ▸ Generate Button
  local can_generate = has_sel and (not state.is_busy) and (state.query ~= "") and state.sc_connected
  if not can_generate then
    ImGui.BeginDisabled(ctx)
  end
  local btn_label = state.is_busy and "Processing..." or "Generate"
  if ImGui.Button(ctx, btn_label, -1, 36) then
    on_generate()
  end
  if not can_generate then
    ImGui.EndDisabled(ctx)
  end
  -- 禁用原因提示
  if not state.is_busy and not state.sc_connected then
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF6666FF)
    ImGui.Text(ctx, "Start Sonic Compass to enable Generate")
    ImGui.PopStyleColor(ctx, 1)
  end

  ImGui.Spacing(ctx)

  -- ▸ Status bar
  ImGui.Separator(ctx)
  if state.status_msg ~= "" then
    local display_msg = state.status_msg
    -- 动画点（仅 busy 状态）
    if state.is_busy then
      local now = r.time_precise()
      if now - state.anim_time > 0.4 then
        state.anim_dots = (state.anim_dots % 3) + 1
        state.anim_time = now
      end
      display_msg = display_msg .. string.rep(".", state.anim_dots)
    end
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, status_color(state.status_level))
    ImGui.TextWrapped(ctx, display_msg)
    ImGui.PopStyleColor(ctx, 1)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Text,
      Colors.semantic and Colors.semantic.TextDim or 0xFFAAAAAA)
    ImGui.Text(ctx, "Ready — Select an item and type a keyword")
    ImGui.PopStyleColor(ctx, 1)
  end

  -- ▸ Footer
  ImGui.Separator(ctx)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF666666)
  ImGui.Text(ctx, "Port " .. SC_PORT .. " | v1.1")
  ImGui.PopStyleColor(ctx, 1)
end

-- ── 主循环 ──
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

local function loop()
  -- 后台健康检查（非阻塞，每 5 秒）
  check_sc_health()

  Theme.begin(app)

  local visible, open
  if app.open == false then
    visible, open = false, false
  else
    ImGui.SetNextWindowSize(app.ctx, 460, 540, ImGui.Cond_FirstUseEver)
    visible, open = app:begin_window()
    if visible then draw() end
    app:end_window()
    if app.open == false then open = false end
  end

  Theme.end_(app)

  if open then
    reaper.defer(loop)
  else
    if not destroyed then
      destroyed = true
      Theme.destroy(app)
      app:destroy()
    end
  end
end

reaper.defer(loop)
