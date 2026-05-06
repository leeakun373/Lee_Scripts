--[[
  SonicCompass Spot — REAPER 收件箱消费者（生产级）

  设计：
    SC 写命令文件 → SC 写完成 flag → 本脚本 reaper.defer 节流轮询
    → 解析 JSON → 在 REAPER 中插入媒体 → 写 ack/err → 清理临时文件

  关键约束（与《第一期执行细则》第 5.3 节一致）：
    1. 不破坏用户工作上下文：插入前后必须保存/恢复 edit cursor 与轨道选区。
    2. 空工程兜底：找不到目标轨道时，自动在末尾新建一条新轨。
    3. IO 竞争锁：用 pcall 包裹 io.open / read，文件被占用时跳过本 tick，
       下一个 defer 周期再试，最多 MAX_PARSE_RETRIES 次。
    4. 多文件兼容：cmd.file_path 既可以是字符串也可以是数组，
       底层统一为 for 循环，连续 InsertMedia 自然首尾相接。
    5. 性能：250ms 节流 + 每 tick ≤ 2 条 ≈ 不超过 4 次/秒目录扫描。
]]

-- ─── 自助查找当前脚本目录，避免依赖父脚本设置 package.path ───
local function script_dir()
  local src = debug.getinfo(1, "S").source
  return src:match("^@(.+[\\/])")
end
local _this_dir = script_dir()
if _this_dir then
  package.path = _this_dir .. "?.lua;" .. package.path
end

local cfg = require("spot_config")

local M = {}

-- ══════════════════════════════════════════════════════
-- 1. 文件 IO（全部用 pcall 包裹，避免外部进程占用句柄时崩溃）
-- ══════════════════════════════════════════════════════

local function ensure_tmp_dir()
  reaper.RecursiveCreateDirectory(cfg.TMP_DIR, 0)
end

--- 安全读文件：失败返回 nil（不抛错）
local function read_file_safe(path)
  local ok_open, fh = pcall(io.open, path, "rb")
  if not ok_open or not fh then return nil end

  local ok_read, content = pcall(function() return fh:read("*a") end)
  pcall(function() fh:close() end)

  if not ok_read or not content then return nil end
  return content
end

--- 安全写文件
local function write_file_safe(path, content)
  local ok_open, fh = pcall(io.open, path, "wb")
  if not ok_open or not fh then return false end
  local ok_write = pcall(function() fh:write(content or "") end)
  pcall(function() fh:close() end)
  return ok_write
end

local function file_exists(path)
  local ok, fh = pcall(io.open, path, "rb")
  if ok and fh then fh:close(); return true end
  return false
end

local function safe_remove(path)
  pcall(os.remove, path)
end


-- ══════════════════════════════════════════════════════
-- 2. JSON 解析器（轻量纯 Lua 实现，支持对象/数组/字符串/数字/布尔/null）
--    替代 Cursor 原版的脆弱正则，且严格不依赖 reaper.json_decode（不存在）。
-- ══════════════════════════════════════════════════════

local function json_parse(s)
  if type(s) ~= "string" or #s == 0 then return nil, "empty" end

  local pos = 1
  local len = #s

  local function err(msg)
    error(msg .. " at pos " .. tostring(pos), 0)
  end

  local function skip_ws()
    while pos <= len do
      local b = s:byte(pos)
      if b == 32 or b == 9 or b == 10 or b == 13 then
        pos = pos + 1
      else
        return
      end
    end
  end

  local parse_value -- forward declaration

  local function parse_string()
    -- 当前 pos 指向开引号
    pos = pos + 1
    local out = {}
    while pos <= len do
      local c = s:sub(pos, pos)
      if c == '"' then
        pos = pos + 1
        return table.concat(out)
      elseif c == '\\' then
        pos = pos + 1
        local esc = s:sub(pos, pos)
        if     esc == '"'  then out[#out+1] = '"'
        elseif esc == '\\' then out[#out+1] = '\\'
        elseif esc == '/'  then out[#out+1] = '/'
        elseif esc == 'n'  then out[#out+1] = '\n'
        elseif esc == 't'  then out[#out+1] = '\t'
        elseif esc == 'r'  then out[#out+1] = '\r'
        elseif esc == 'b'  then out[#out+1] = '\b'
        elseif esc == 'f'  then out[#out+1] = '\f'
        elseif esc == 'u'  then
          -- \uXXXX 转 UTF-8（够用即可，不处理代理对，路径里不会出现）
          local hex = s:sub(pos+1, pos+4)
          local cp = tonumber(hex, 16)
          if cp then
            if cp < 0x80 then
              out[#out+1] = string.char(cp)
            elseif cp < 0x800 then
              out[#out+1] = string.char(0xC0 + math.floor(cp/0x40),
                                         0x80 + (cp % 0x40))
            else
              out[#out+1] = string.char(0xE0 + math.floor(cp/0x1000),
                                         0x80 + math.floor((cp % 0x1000)/0x40),
                                         0x80 + (cp % 0x40))
            end
          end
          pos = pos + 4
        else
          out[#out+1] = esc
        end
        pos = pos + 1
      else
        out[#out+1] = c
        pos = pos + 1
      end
    end
    err("unterminated string")
  end

  local function parse_number()
    local start = pos
    if s:sub(pos, pos) == '-' then pos = pos + 1 end
    while pos <= len do
      local c = s:sub(pos, pos)
      if c:match('[%d%.eE%+%-]') then
        pos = pos + 1
      else
        break
      end
    end
    return tonumber(s:sub(start, pos - 1))
  end

  local function parse_array()
    pos = pos + 1  -- 吃掉 [
    local arr = {}
    skip_ws()
    if s:sub(pos, pos) == ']' then pos = pos + 1; return arr end
    while true do
      skip_ws()
      arr[#arr+1] = parse_value()
      skip_ws()
      local c = s:sub(pos, pos)
      if c == ',' then pos = pos + 1
      elseif c == ']' then pos = pos + 1; return arr
      else err("expected , or ] in array") end
    end
  end

  local function parse_object()
    pos = pos + 1  -- 吃掉 {
    local obj = {}
    skip_ws()
    if s:sub(pos, pos) == '}' then pos = pos + 1; return obj end
    while true do
      skip_ws()
      if s:sub(pos, pos) ~= '"' then err("expected string key") end
      local key = parse_string()
      skip_ws()
      if s:sub(pos, pos) ~= ':' then err("expected : after key") end
      pos = pos + 1
      skip_ws()
      obj[key] = parse_value()
      skip_ws()
      local c = s:sub(pos, pos)
      if c == ',' then pos = pos + 1
      elseif c == '}' then pos = pos + 1; return obj
      else err("expected , or } in object") end
    end
  end

  parse_value = function()
    skip_ws()
    local c = s:sub(pos, pos)
    if     c == '"' then return parse_string()
    elseif c == '{' then return parse_object()
    elseif c == '[' then return parse_array()
    elseif c == 't' and s:sub(pos, pos+3) == 'true'  then pos = pos + 4; return true
    elseif c == 'f' and s:sub(pos, pos+4) == 'false' then pos = pos + 5; return false
    elseif c == 'n' and s:sub(pos, pos+3) == 'null'  then pos = pos + 4; return nil
    else return parse_number()
    end
  end

  local ok, result = pcall(parse_value)
  if not ok then return nil, tostring(result) end
  return result
end


-- ══════════════════════════════════════════════════════
-- 3. REAPER 工程上下文 — 保存/恢复（避免插入产生副作用）
-- ══════════════════════════════════════════════════════

--- 抓取当前所有选中的轨道（按全局索引保存，不持有 MediaTrack 指针，避免后续误用）
local function capture_selected_tracks()
  local list = {}
  local total = reaper.CountTracks(0)
  for i = 0, total - 1 do
    local tr = reaper.GetTrack(0, i)
    if tr and reaper.IsTrackSelected(tr) then
      list[#list + 1] = i
    end
  end
  return list
end

local function deselect_all_tracks()
  local total = reaper.CountTracks(0)
  for i = 0, total - 1 do
    local tr = reaper.GetTrack(0, i)
    if tr then reaper.SetTrackSelected(tr, false) end
  end
end

local function restore_selected_tracks(indices)
  deselect_all_tracks()
  if not indices then return end
  for _, idx in ipairs(indices) do
    local tr = reaper.GetTrack(0, idx)
    if tr then reaper.SetTrackSelected(tr, true) end
  end
end


-- ══════════════════════════════════════════════════════
-- 4. 目标解析（time / track）+ 空工程兜底
-- ══════════════════════════════════════════════════════

local function get_first_selected_item_start()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then return nil end
  return reaper.GetMediaItemInfo_Value(item, "D_POSITION")
end

local function resolve_time(mode, fallback_cursor)
  if mode == "selected_item_start" then
    local pos = get_first_selected_item_start()
    if pos then return pos end
  end
  -- 默认 / 回退：编辑光标
  return fallback_cursor
end

--- 解析目标轨道；
--- 若按策略找不到任何可用轨，则在工程末尾新建一条空轨。
--- @return MediaTrack（永远不会返回 nil）
local function ensure_target_track(mode)
  local tr = nil

  if mode == "first_selected_item_track" then
    local item = reaper.GetSelectedMediaItem(0, 0)
    if item then tr = reaper.GetMediaItem_Track(item) end
  end

  -- 默认 selected_track，或 fallback
  if not tr then
    tr = reaper.GetSelectedTrack(0, 0)
  end

  -- 仍然没有 → 空工程或没选中任何东西，在末尾插一条新轨
  if not tr then
    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)  -- true = 默认按使能/默认 envelope
    tr = reaper.GetTrack(0, idx)
  end

  return tr
end


-- ══════════════════════════════════════════════════════
-- 5. 插入媒体（核心）— 多文件兼容 + 上下文恢复
-- ══════════════════════════════════════════════════════

--- 从 cmd 中归一化出文件路径数组，兼容三种写法：
---   { "file_path": "x.wav" }
---   { "file_path": ["a.wav", "b.wav"] }
---   { "file_paths": ["a.wav", "b.wav"] }
local function normalize_files(cmd)
  local out = {}

  local function push_if_str(v)
    if type(v) == "string" and v ~= "" then out[#out + 1] = v end
  end

  if type(cmd.file_paths) == "table" then
    for _, p in ipairs(cmd.file_paths) do push_if_str(p) end
  elseif type(cmd.file_path) == "table" then
    for _, p in ipairs(cmd.file_path) do push_if_str(p) end
  else
    push_if_str(cmd.file_path)
  end

  return out
end

local function insert_media(cmd)
  local files = normalize_files(cmd)
  if #files == 0 then
    return false, "Missing file_path / file_paths"
  end

  -- 入轨前先全部检查存在性（防止部分插入 + 部分失败导致错乱）
  for _, p in ipairs(files) do
    if not file_exists(p) then
      return false, "Audio file not found: " .. p
    end
  end

  local time_mode  = cmd.time_mode  or "edit_cursor"
  local track_mode = cmd.track_mode or "selected_track"

  -- ── 保存上下文 ──
  local prev_cursor          = reaper.GetCursorPosition()
  local prev_selected_tracks = capture_selected_tracks()

  local target_time  = resolve_time(time_mode, prev_cursor)
  local target_track = ensure_target_track(track_mode)  -- 永不为 nil

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- ── 设置插入所需的临时上下文 ──
  -- InsertMedia 会用到"被选中的轨道"，因此先清空再仅选中目标轨
  deselect_all_tracks()
  reaper.SetTrackSelected(target_track, true)
  reaper.SetEditCurPos(target_time, false, false)

  -- 连续 InsertMedia(mode=0)：每次插入后 cursor 自动推进到末尾，
  -- 因此多文件会自然首尾相接，无需手动算 offset
  for _, path in ipairs(files) do
    reaper.InsertMedia(path, 0)  -- 0 = insert at edit cursor on selected track
  end

  -- ── 恢复上下文：cursor + 轨道选区 ──
  reaper.SetEditCurPos(prev_cursor, false, false)
  restore_selected_tracks(prev_selected_tracks)

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("SonicCompass Spot Insert (" .. #files .. " file(s))", -1)

  return true, ""
end


-- ══════════════════════════════════════════════════════
-- 6. 单条命令处理（带重试，避免 IO 竞态丢任务）
-- ══════════════════════════════════════════════════════

-- per-id 重试计数：key=id, value=已重试 tick 数
local _retry_counts = {}

local function paths_for(id)
  local sep = cfg.PATH_SEP
  return {
    done = cfg.TMP_DIR .. sep .. "spot_done_" .. id .. ".flag",
    cmd  = cfg.TMP_DIR .. sep .. "spot_cmd_"  .. id .. ".json",
    ack  = cfg.TMP_DIR .. sep .. "spot_ack_"  .. id .. ".json",
    err  = cfg.TMP_DIR .. sep .. "spot_err_"  .. id .. ".txt",
  }
end

--- 处理一个 done flag。
--- @return processed boolean — true 表示本 tick 消耗了一个处理槽位（成功或最终失败）
---                              false 表示需要在下一个 tick 重试（IO 锁未释放）
local function process_one(done_file)
  local id = done_file:match("^spot_done_(.+)%.flag$")
  if not id then return false end

  local p = paths_for(id)

  -- ── 步骤 1：尝试读取命令 JSON ──
  local cmd_raw = read_file_safe(p.cmd)
  if not cmd_raw or #cmd_raw == 0 then
    -- 可能是：文件不存在（彻底失败） / 文件被占用（IO 锁，重试）
    if not file_exists(p.cmd) then
      -- 真的不存在 → 直接放弃，写错误日志清理 flag
      write_file_safe(p.err, "Missing command file: " .. p.cmd)
      safe_remove(p.done)
      _retry_counts[id] = nil
      return true
    end
    -- 文件存在但读不到 → 大概率是 SC 还没释放句柄，下个 tick 再试
    _retry_counts[id] = (_retry_counts[id] or 0) + 1
    if _retry_counts[id] >= cfg.MAX_PARSE_RETRIES then
      write_file_safe(p.err, "Cannot read command file after "
                              .. cfg.MAX_PARSE_RETRIES .. " retries (file locked?)")
      safe_remove(p.done); safe_remove(p.cmd)
      _retry_counts[id] = nil
      return true
    end
    return false  -- 本 tick 跳过，重试
  end

  -- ── 步骤 2：解析 JSON ──
  local cmd, parse_err = json_parse(cmd_raw)
  if not cmd then
    -- JSON 不完整/损坏 → 也许是半写入，重试几次
    _retry_counts[id] = (_retry_counts[id] or 0) + 1
    if _retry_counts[id] >= cfg.MAX_PARSE_RETRIES then
      write_file_safe(p.err, "Invalid JSON after " .. cfg.MAX_PARSE_RETRIES
                              .. " retries: " .. tostring(parse_err)
                              .. "\n--- raw ---\n" .. cmd_raw:sub(1, 500))
      safe_remove(p.done); safe_remove(p.cmd)
      _retry_counts[id] = nil
      return true
    end
    return false
  end

  -- ── 步骤 3：协议版本校验（软警告，不阻塞执行）──
  if cmd.protocol_version and cmd.protocol_version ~= cfg.PROTOCOL_VERSION then
    -- 仅记录到错误日志，仍尝试执行（向后兼容）
    write_file_safe(p.err, "Protocol mismatch: got '"
      .. tostring(cmd.protocol_version) .. "', expected '"
      .. cfg.PROTOCOL_VERSION .. "'. Attempting anyway.")
  end

  -- ── 步骤 4：执行插入 ──
  -- pcall 一次拿全部返回值，区分"崩溃"与"业务失败"，避免重复调用污染状态
  local ok, ret_ok, ret_msg = pcall(insert_media, cmd)
  if ok and ret_ok == true then
    write_file_safe(p.ack,
      '{"status":"ok","id":"' .. id:gsub('"','\\"') .. '"}')
    safe_remove(p.err)
    -- 成功插入后，把 REAPER 主窗口拉到前台。
    -- 依赖 SC 端在写收件箱前已调过 AllowSetForegroundWindow(ASFW_ANY) 授权。
    pcall(function()
      local hwnd = reaper.GetMainHwnd()
      if hwnd then
        if reaper.BR_Win32_SetForegroundWindow then
          reaper.BR_Win32_SetForegroundWindow(hwnd)
        elseif reaper.JS_Window_SetForeground then
          reaper.JS_Window_SetForeground(hwnd)
        end
      end
    end)
  else
    local detail
    if not ok then
      detail = "insert crashed: " .. tostring(ret_ok)  -- 此时 ret_ok 是错误对象
    else
      detail = tostring(ret_msg or "insert failed")
    end
    write_file_safe(p.err, detail)
  end

  -- 不论成功失败，都清理 flag/cmd（业务失败靠 err 文件保留诊断信息）
  safe_remove(p.done)
  safe_remove(p.cmd)
  _retry_counts[id] = nil
  return true
end


-- ══════════════════════════════════════════════════════
-- 7. 目录扫描 + 节流主循环
-- ══════════════════════════════════════════════════════

local function list_done_files()
  local out = {}
  local idx = 0
  while true do
    local name = reaper.EnumerateFiles(cfg.TMP_DIR, idx)
    if not name then break end
    if name:match("^spot_done_.+%.flag$") then
      out[#out + 1] = name
    end
    idx = idx + 1
  end
  table.sort(out)  -- 按文件名（含时间戳前缀）顺序处理，FIFO
  return out
end

local function is_enabled()
  return reaper.GetExtState(cfg.LISTENER_SECTION, cfg.LISTENER_ENABLED_KEY) == "1"
end

-- ── 单例锁：同一个脚本实例内只允许一个主循环存在 ──
local _running = false

--- 检查"心跳"是否新鲜，用于跨脚本实例判活（多个 Focus Search 实例可能并存）
local function is_listener_alive_externally()
  local last = tonumber(reaper.GetExtState(cfg.LISTENER_SECTION,
                                              cfg.LISTENER_HEARTBEAT_KEY))
  if not last then return false end
  return (reaper.time_precise() - last) < cfg.HEARTBEAT_STALE_SEC
end

function M.start()
  -- 同一脚本实例内重入：直接 return
  if _running then return false end

  -- 跨脚本实例（用户多次按 Focus Search）：心跳新鲜则礼让
  if is_listener_alive_externally() then return false end

  ensure_tmp_dir()
  reaper.SetExtState(cfg.LISTENER_SECTION, cfg.LISTENER_ENABLED_KEY, "1", false)
  _running = true

  -- 读取自定义轮询间隔（用户可通过 ExtState 覆盖）
  local poll_ms = tonumber(reaper.GetExtState(cfg.LISTENER_SECTION,
                                                cfg.LISTENER_POLL_MS_KEY))
  if not poll_ms or poll_ms < cfg.MIN_POLL_MS then
    poll_ms = cfg.DEFAULT_POLL_MS
  end
  local poll_sec = poll_ms / 1000.0

  local next_at = 0.0

  local function loop()
    -- 用户调用 stop / 二次启动 → 退出当前循环
    if not is_enabled() then
      _running = false
      return
    end

    local now = reaper.time_precise()

    -- 写心跳：让其他脚本实例知道我还活着
    reaper.SetExtState(cfg.LISTENER_SECTION, cfg.LISTENER_HEARTBEAT_KEY,
                         tostring(now), false)

    if now >= next_at then
      next_at = now + poll_sec

      local done_files = list_done_files()
      local processed = 0
      for i = 1, #done_files do
        if processed >= cfg.MAX_COMMANDS_PER_TICK then break end
        if process_one(done_files[i]) then
          processed = processed + 1
        end
      end
    end

    reaper.defer(loop)
  end

  reaper.defer(loop)
  return true
end

function M.stop()
  reaper.SetExtState(cfg.LISTENER_SECTION, cfg.LISTENER_ENABLED_KEY, "0", false)
  _running = false
end

return M
