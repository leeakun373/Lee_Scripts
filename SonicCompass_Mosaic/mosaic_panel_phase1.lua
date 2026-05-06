--[[
  SonicCompass Mosaic Panel — Phase 3 主入口脚本

  功能：
    1. gfx 面板：关键词输入框 + Generate 按钮 + 实时 Item 选中状态
    2. 点击 Generate：渲染选中 Item → POST 到 SC HTTP → 轮询结果 → 回写 REAPER
    3. 全程非阻塞（reaper.defer 轮询）

  安装位置：
    C:\Users\DELL\AppData\Roaming\REAPER\Scripts\Lee_Scripts\SonicCompass_Mosaic\

  使用方式：
    REAPER → Actions → Load → 选择此脚本
    或在 Lee_Scripts 面板中挂载

  依赖：同目录下 http_client.lua, render_export.lua, writeback.lua
]]

-- ── 模块加载 ──
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
package.path = script_path .. "?.lua;" .. package.path

local http_client    = require("http_client")
local render_export  = require("render_export")
local writeback      = require("writeback")

-- ── 配置 ──
local SC_HOST       = "127.0.0.1"
local SC_PORT       = 18765
local SC_URL        = "http://" .. SC_HOST .. ":" .. SC_PORT
local GENERATE_URL  = SC_URL .. "/api/mosaic/generate"
local HEALTH_URL    = SC_URL .. "/api/mosaic/health"

-- ── UI 状态 ──
local query_text     = ""           -- 搜索关键词
local status_msg     = "Ready"      -- 底部状态栏
local status_color   = {0.6, 0.8, 0.6}  -- 绿色
local is_busy        = false        -- 防止重复点击
local writeback_mode = "new_track_mute"  -- 默认模式 B
local has_selection  = false        -- 实时 Item 选中状态

-- ── gfx 窗口 ──
local WIN_W = 420
local WIN_H = 280
gfx.init("SonicCompass Mosaic", WIN_W, WIN_H)
gfx.setfont(1, "Arial", 14)

-- ── 绘制辅助 ──

local function draw_text(x, y, text, r, g, b)
  gfx.set(r or 0.9, g or 0.9, b or 0.9, 1)
  gfx.x = x
  gfx.y = y
  gfx.drawstr(text)
end

local function draw_button(x, y, w, h, label, enabled)
  if enabled then
    gfx.set(0.3, 0.5, 0.8, 1)   -- 蓝色可点击
  else
    gfx.set(0.2, 0.2, 0.25, 1)  -- 深灰禁用
  end
  gfx.rect(x, y, w, h, true)
  -- 文字颜色
  if enabled then
    gfx.set(1, 1, 1, 1)
  else
    gfx.set(0.45, 0.45, 0.45, 1)
  end
  local tw, th = gfx.measurestr(label)
  gfx.x = x + (w - tw) / 2
  gfx.y = y + (h - th) / 2
  gfx.drawstr(label)
end

-- 检测点击区域（使用帧级 just_clicked 标志，不自己做边沿检测）
local function hit_test(x, y, w, h)
  return gfx.mouse_x >= x and gfx.mouse_x <= x + w
     and gfx.mouse_y >= y and gfx.mouse_y <= y + h
end

local function set_status(msg, r, g, b)
  status_msg = msg
  status_color = {r or 0.6, g or 0.8, b or 0.6}
end

-- ── 核心流程 ──

local function on_generate()
  if is_busy then return end

  -- 实时检测 Item 选中状态
  if reaper.CountSelectedMediaItems(0) == 0 then
    reaper.ShowMessageBox(
      "No media item is selected.\n\n"
      .. "Please select an item in the REAPER arrange view, then click Generate.",
      "SonicCompass Mosaic", 0)
    return
  end

  -- query 必填校验
  if query_text == "" then
    reaper.ShowMessageBox(
      "Please enter a search keyword before generating.\n\n"
      .. "The keyword is used to find candidate sounds in your Sonic Compass library.",
      "SonicCompass Mosaic", 0)
    return
  end

  is_busy = true
  set_status("Rendering selected item...", 1, 0.8, 0.2)

  -- Step 1: 渲染
  local wav_path, err = render_export.render_selected_item()
  if not wav_path then
    set_status("Render failed: " .. (err or "unknown"), 1, 0.3, 0.3)
    reaper.ShowMessageBox(
      "Failed to render selected item:\n" .. (err or "unknown"),
      "SonicCompass Mosaic — Render Error", 0)
    is_busy = false
    return
  end

  set_status("Searching & building pool...", 0.2, 0.7, 1)

  -- Step 2: POST 到 SC
  local request_body = {
    ref_path         = wav_path,
    query            = query_text,
    request_id       = tostring(math.floor(reaper.time_precise() * 100000)),
    pool_max         = 200,
    protocol_version = "mosaic_v1",
  }

  http_client.post_json(GENERATE_URL, request_body, function(ok, resp)
    if not ok then
      set_status("HTTP error: " .. tostring(resp), 1, 0.3, 0.3)
      reaper.ShowMessageBox(
        "Could not reach Sonic Compass HTTP service.\n\n"
        .. "Make sure Sonic Compass is running and the Mosaic bridge is active.\n\n"
        .. "Details: " .. tostring(resp),
        "SonicCompass Mosaic — Connection Error", 0)
      is_busy = false
      return
    end

    if resp.status ~= "ok" then
      local err_msg = resp.message or "unknown error"
      local title = "SonicCompass Mosaic — Error"

      if err_msg:find("No files found") then
        title = "SonicCompass Mosaic — No Results"
        err_msg = "No matching files found for: \"" .. query_text .. "\"\n\n"
                  .. "Try a different keyword or load a library with more content."
      elseif err_msg:find("not available") or err_msg:find("not fully initialized") then
        title = "SonicCompass Mosaic — Service Unavailable"
        err_msg = "Sonic Compass search engine is not ready.\n\n"
                  .. "Please load a library first, then try again."
      elseif err_msg:find("0 chunks") then
        title = "SonicCompass Mosaic — Pool Empty"
        err_msg = "Files were found but could not be chunked.\n\n"
                  .. "The matched audio files may be too short or corrupted."
      end

      set_status("Error: " .. (resp.message or ""), 1, 0.3, 0.3)
      reaper.ShowMessageBox(err_msg, title, 0)
      is_busy = false
      return
    end

    local output_path = resp.output_wav_path
    if not output_path or output_path == "" then
      set_status("SC returned empty path", 1, 0.3, 0.3)
      is_busy = false
      return
    end

    local pool_info = ""
    if resp.pool_file_count then
      pool_info = " [" .. tostring(resp.pool_file_count) .. " files, "
                  .. tostring(resp.pool_chunk_count or "?") .. " chunks]"
    end

    set_status("Writing back to REAPER..." .. pool_info, 0.2, 0.7, 1)

    -- Step 3: 回写
    local wb_ok, wb_err = writeback.execute(output_path, writeback_mode)
    if wb_ok then
      set_status("Done! (" .. writeback_mode .. ")" .. pool_info, 0.3, 1, 0.5)
    else
      set_status("Writeback failed: " .. (wb_err or ""), 1, 0.3, 0.3)
      reaper.ShowMessageBox(
        "Failed to write result back to REAPER:\n" .. (wb_err or "unknown"),
        "SonicCompass Mosaic — Writeback Error", 0)
    end

    is_busy = false
  end)
end

-- ── 主循环 ──

local prev_mouse_cap = 0

local function main_loop()
  local ch = gfx.getchar()
  if ch == -1 then return end  -- 窗口已关闭

  -- ▸ 帧级边沿检测（整个帧只算一次，所有按钮共享）
  local just_clicked = (gfx.mouse_cap == 1 and prev_mouse_cap == 0)
  prev_mouse_cap = gfx.mouse_cap

  -- ▸ 实时检测 REAPER 选中 Item 状态
  has_selection = (reaper.CountSelectedMediaItems(0) > 0)

  -- 处理键盘输入到 query_text
  if ch > 0 and ch < 256 then
    if ch == 8 then -- Backspace
      query_text = query_text:sub(1, -2)
    elseif ch == 13 then -- Enter → 触发 Generate
      if not is_busy then
        on_generate()
      end
    elseif ch >= 32 then
      query_text = query_text .. string.char(ch)
    end
  end

  -- ── 绘制 ──
  gfx.set(0.12, 0.12, 0.15, 1)
  gfx.rect(0, 0, gfx.w, gfx.h, true)

  -- 标题
  gfx.setfont(1, "Arial", 16)
  draw_text(15, 10, "SonicCompass Mosaic", 0.5, 0.8, 1)

  -- Item 选中状态指示
  gfx.setfont(1, "Arial", 12)
  if has_selection then
    local item = reaper.GetSelectedMediaItem(0, 0)
    local take = item and reaper.GetActiveTake(item)
    local item_name = ""
    if take then
      local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
      if name and name ~= "" then
        item_name = name
      else
        local src = reaper.GetMediaItemTake_Source(take)
        if src then
          local _, fn = reaper.GetMediaSourceFileName(src, "")
          if fn then item_name = fn:match("([^\\/]+)$") or fn end
        end
      end
    end
    if #item_name > 40 then item_name = "..." .. item_name:sub(-37) end
    draw_text(15, 30, "Item: " .. item_name, 0.4, 0.9, 0.5)
  else
    draw_text(15, 30, "No item selected — select one in Arrange", 1.0, 0.5, 0.3)
  end

  -- 关键词标签 + 输入框
  gfx.setfont(1, "Arial", 13)
  draw_text(15, 52, "Search Keywords:", 0.7, 0.7, 0.7)

  gfx.set(0.18, 0.18, 0.22, 1)
  gfx.rect(15, 72, gfx.w - 30, 24, true)
  gfx.set(1, 1, 1, 1)
  gfx.x = 19
  gfx.y = 76
  local display_text = query_text
  if #display_text > 45 then
    display_text = "..." .. display_text:sub(-42)
  end
  gfx.drawstr(display_text .. (math.floor(reaper.time_precise() * 2) % 2 == 0 and "|" or ""))

  -- 模式选择
  draw_text(15, 108, "Writeback Mode:", 0.7, 0.7, 0.7)

  local mode_b_active = writeback_mode == "new_track_mute"
  gfx.set(mode_b_active and 0.3 or 0.15, mode_b_active and 0.6 or 0.15, mode_b_active and 0.3 or 0.15, 1)
  gfx.rect(15, 128, 180, 22, true)
  gfx.set(1, 1, 1, 1)
  gfx.x = 20; gfx.y = 131
  gfx.drawstr("New Track + Mute (B)")

  local mode_a_active = writeback_mode == "replace"
  gfx.set(mode_a_active and 0.3 or 0.15, mode_a_active and 0.6 or 0.15, mode_a_active and 0.3 or 0.15, 1)
  gfx.rect(205, 128, 180, 22, true)
  gfx.set(1, 1, 1, 1)
  gfx.x = 210; gfx.y = 131
  gfx.drawstr("Replace Source (A)")

  -- 模式切换点击
  if just_clicked then
    if hit_test(15, 128, 180, 22) then
      writeback_mode = "new_track_mute"
    elseif hit_test(205, 128, 180, 22) then
      writeback_mode = "replace"
    end
  end

  -- Generate 按钮 — 仅在有选中 Item 且不忙时可点击
  gfx.setfont(1, "Arial", 15)
  local can_generate = has_selection and (not is_busy)
  local btn_label = is_busy and "Processing..." or "Generate"
  draw_button(15, 168, gfx.w - 30, 32, btn_label, can_generate)

  if just_clicked and can_generate and hit_test(15, 168, gfx.w - 30, 32) then
    on_generate()
  end

  -- 状态栏
  gfx.setfont(1, "Arial", 12)
  draw_text(15, 215, status_msg, status_color[1], status_color[2], status_color[3])

  -- 版本信息
  gfx.set(0.35, 0.35, 0.35, 1)
  gfx.x = 15; gfx.y = gfx.h - 18
  gfx.drawstr("Phase 3 — Mosaic Synthesis | Port " .. SC_PORT)

  gfx.update()
  reaper.defer(main_loop)
end

-- ── 启动 ──
set_status("Ready — Select an item and type a keyword", 0.6, 0.8, 0.6)
reaper.defer(main_loop)
