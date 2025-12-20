-- FXMiner/src/fx_engine.lua
-- 所有 REAPER API / SWS 调用集中在这里

local r = reaper

local Engine = {
  PUBLISH_OK = 0,
  PUBLISH_EXISTS = 1,
  PUBLISH_ERROR = 2,
}

local function show_error(msg)
  r.ShowMessageBox(tostring(msg or "Unknown error"), "FXMiner", 0)
end

function Engine.ensure_sws_or_quit()
  if not r.CF_GetClipboard then
    show_error("FXMiner requires SWS Extension to save FX Chains. Please install SWS.")
    return false
  end
  return true
end

function Engine.get_selected_track()
  return r.GetSelectedTrack(0, 0)
end

function Engine.get_selected_track_name()
  local tr = Engine.get_selected_track()
  if not tr then return nil end
  local ok, name = r.GetTrackName(tr, "")
  if ok then return name end
  return nil
end

local function sanitize_filename(name)
  name = tostring(name or "")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = "Untitled Chain" end

  -- Windows forbidden: <>:"/\\|?*
  -- 注意：这里用单引号字符串，避免转义双引号导致 Lua 解析错误
  name = name:gsub('[<>:"/\\|%?%*]', "_")
  name = name:gsub("%s+", " ")
  name = name:gsub("[%. ]+$", "")
  if name == "" then name = "Untitled Chain" end
  return name
end

local function ensure_dir(path)
  if r and r.RecursiveCreateDirectory then
    pcall(function()
      r.RecursiveCreateDirectory(path, 0)
    end)
  end
end

local function path_join(a, b)
  local sep = package.config:sub(1, 1)
  if not a or a == "" then return b end
  if not b or b == "" then return a end
  a = tostring(a):gsub("[\\/]+$", "")
  b = tostring(b):gsub("^[\\/]+", "")
  return a .. sep .. b
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function ensure_unique_rfx_path(dir_path, base_name)
  local sep = package.config:sub(1, 1)
  local function make(n)
    if n == 0 then
      return path_join(dir_path, base_name .. ".RfxChain")
    end
    return path_join(dir_path, string.format("%s_%02d.RfxChain", base_name, n))
  end

  local p0 = make(0)
  if not file_exists(p0) then
    return p0
  end

  for i = 1, 99 do
    local pi = make(i)
    if not file_exists(pi) then
      return pi
    end
  end

  -- 兜底：极端情况下仍避免覆盖
  return make(math.floor((r.time_precise and r.time_precise() or os.time()) % 100))
end

local function copy_file(src, dst)
  local rf = io.open(src, "rb")
  if not rf then return false, "Cannot open source file" end
  local data = rf:read("*all")
  rf:close()

  local wf = io.open(dst, "wb")
  if not wf then return false, "Cannot open target file" end
  wf:write(data)
  wf:close()
  return true
end

-- Expose copy_file for external use
Engine.copy_file = copy_file

-- Get filename from path
local function get_filename(path)
  path = tostring(path or "")
  -- Handle both / and \ separators
  local name = path:match("([^/\\]+)$")
  return name or path
end

Engine.get_filename = get_filename

-- Check if team publish path is valid and accessible
function Engine.is_team_path_valid(cfg)
  if not cfg or not cfg.TEAM_PUBLISH_PATH or cfg.TEAM_PUBLISH_PATH == "" then
    return false, "Team path not configured"
  end
  
  local path = cfg.TEAM_PUBLISH_PATH
  
  -- Try to create directory if it doesn't exist
  ensure_dir(path)
  
  -- Check if we can write to the directory by creating a temp file
  local test_path = path_join(path, ".fxminer_test_" .. os.time())
  local f = io.open(test_path, "w")
  if f then
    f:close()
    os.remove(test_path)
    return true
  end
  
  return false, "Cannot write to team path"
end

-- Publish result codes
Engine.PUBLISH_OK = "ok"
Engine.PUBLISH_EXISTS = "exists"           -- File exists, need user decision
Engine.PUBLISH_ERROR = "error"

-- Check if file exists on team server
function Engine.check_team_conflict(cfg, filename)
  if not cfg or not cfg.TEAM_PUBLISH_PATH or cfg.TEAM_PUBLISH_PATH == "" then
    return false, "Team path not configured"
  end
  
  local target_path = path_join(cfg.TEAM_PUBLISH_PATH, filename)
  if file_exists(target_path) then
    return true, target_path
  end
  return false, target_path
end

-- Generate auto-rename path (add _v2, _v3, etc.)
function Engine.get_auto_rename_path(cfg, filename)
  if not cfg or not cfg.TEAM_PUBLISH_PATH or cfg.TEAM_PUBLISH_PATH == "" then
    return nil, "Team path not configured"
  end
  
  local base, ext = filename:match("^(.+)(%.RfxChain)$")
  if not base then
    base = filename
    ext = ""
  end
  
  local team_dir = cfg.TEAM_PUBLISH_PATH
  
  -- Find next available version number
  for v = 2, 999 do
    local new_name = string.format("%s_v%d%s", base, v, ext)
    local new_path = path_join(team_dir, new_name)
    if not file_exists(new_path) then
      return new_path, new_name
    end
  end
  
  return nil, "Cannot find available filename"
end

-- Publish to team (core function)
-- Returns: result_code, message, published_path
function Engine.publish_to_team(cfg, source_path, opts)
  opts = opts or {}
  
  -- Validate inputs
  if not cfg or not cfg.TEAM_PUBLISH_PATH or cfg.TEAM_PUBLISH_PATH == "" then
    return Engine.PUBLISH_ERROR, "Team path not configured", nil
  end
  
  if not source_path or not file_exists(source_path) then
    return Engine.PUBLISH_ERROR, "Source file not found", nil
  end
  
  local filename = get_filename(source_path)
  local target_path = path_join(cfg.TEAM_PUBLISH_PATH, filename)
  
  -- Ensure target directory exists
  ensure_dir(cfg.TEAM_PUBLISH_PATH)
  
  -- Check for conflict
  local exists = file_exists(target_path)
  
  if exists and not opts.force_overwrite and not opts.auto_rename then
    -- Return conflict status - caller should handle UI
    return Engine.PUBLISH_EXISTS, target_path, nil
  end
  
  -- Handle auto-rename
  if exists and opts.auto_rename then
    local new_path, new_name = Engine.get_auto_rename_path(cfg, filename)
    if new_path then
      target_path = new_path
      filename = new_name
    else
      return Engine.PUBLISH_ERROR, "Cannot find available filename", nil
    end
  end
  
  -- Copy file
  local ok, err = copy_file(source_path, target_path)
  if not ok then
    return Engine.PUBLISH_ERROR, "Failed to copy: " .. tostring(err), nil
  end
  
  return Engine.PUBLISH_OK, "Published successfully", target_path
end

function Engine.copy_selected_track_fxchain_to_clipboard()
  -- Track: Copy FX chain
  r.Main_OnCommand(40210, 0)
end

function Engine.get_clipboard_text()
  if not Engine.ensure_sws_or_quit() then
    return nil
  end
  local text = r.CF_GetClipboard("")
  return text
end

function Engine._with_preserved_clipboard(fn)
  if not Engine.ensure_sws_or_quit() then
    return false, "SWS missing"
  end

  local old = r.CF_GetClipboard("") or ""
  local ok, a, b, c = pcall(fn)

  -- 尽力恢复（不影响主流程）
  if r.CF_SetClipboard then
    pcall(function()
      r.CF_SetClipboard(old)
    end)
  end

  if not ok then
    return false, tostring(a)
  end
  return true, a, b, c
end

function Engine.extract_plugins(rfx_text)
  local plugins = {}
  local seen = {}

  if type(rfx_text) ~= "string" then
    return plugins
  end

  for line in rfx_text:gmatch("[^\r\n]+") do
    -- Match plugin lines: <VST "...", <JS "...", <AU "...", <DX "...", <CLAP "..."
    -- Typical: <VST "VST: ReaEQ (Cockos)" reacomp.dll ...>
    local name = line:match('^<%w+%s+"([^"]+)"')
    if name and not seen[name] then
      seen[name] = true
      plugins[#plugins + 1] = name
    end
  end

  return plugins
end

-- Parse RfxChain file and extract plugin names
-- Returns: table of plugin name strings, e.g., {"ReaEQ", "Pro-Q 3"}
function Engine.parse_rfxchain_file(file_path)
  if not file_path or file_path == "" then
    return {}
  end

  if not file_exists(file_path) then
    return {}
  end

  local f = io.open(file_path, "rb")
  if not f then
    return {}
  end

  local content = f:read("*all")
  f:close()

  if not content or content == "" then
    return {}
  end

  return Engine.extract_plugins(content)
end

local function extract_fxchain_from_track_chunk(tr)
  if not tr then return nil end
  if not r.GetTrackStateChunk then return nil end

  local ok, chunk = r.GetTrackStateChunk(tr, "", false)
  if not ok or type(chunk) ~= "string" then
    return nil
  end

  -- 关键点：
  -- - Chunk 里 <FXCHAIN 往往有缩进，所以不能用 ^<FXCHAIN 严格匹配。
  -- - 深度计算必须基于“行首标签”（忽略缩进），不能按字符统计 "<"，
  --   因为插件行中会出现类似 ... 123<565354...> ... 这种“非块结构”的尖括号。
  local started = false
  local depth = 0
  local out = {}

  for line in chunk:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$") or line

    if not started then
      if trimmed:match("^<FXCHAIN") then
        started = true
        depth = 1
        -- 确保文件第一行严格以 <FXCHAIN 开头（去掉缩进）
        out[#out + 1] = line:gsub("^%s+", "")
      end
    else
      out[#out + 1] = line

      -- 子块起始：允许缩进，但必须是行首 "<"
      if trimmed:sub(1, 1) == "<" then
        depth = depth + 1
      elseif trimmed == ">" then
        depth = depth - 1
        if depth <= 0 then
          break
        end
      end
    end
  end

  if #out == 0 then
    return nil
  end

  -- 以 \n 写入，REAPER 可正常识别
  return table.concat(out, "\n") .. "\n"
end

local function normalize_fxchain_text(text)
  if type(text) ~= "string" or text == "" then return text end

  -- 只对“带 <FXCHAIN 外层”的文本做补全；如果是另一种无外层格式（像某些旧 .RfxChain），不动它。
  local started = false
  local depth = 0

  for line in text:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$") or line
    if not started then
      if trimmed:find("^<FXCHAIN", 1, false) then
        started = true
        depth = 1
      end
    else
      if trimmed:sub(1, 1) == "<" then
        depth = depth + 1
      elseif trimmed == ">" then
        depth = depth - 1
      end
    end
  end

  if started and depth > 0 and depth < 8 then
    -- 极端情况下剪贴板/截取可能少了外层闭合：补齐剩余的 ">"
    text = text:gsub("\r\n", "\n")
    if not text:match("\n$") then text = text .. "\n" end
    for _ = 1, depth do
      text = text .. ">\n"
    end
  end

  return text
end

local function fxchain_block_to_rfxchain_file(text)
  -- REAPER 的 .RfxChain 文件（通过 FX chain 菜单加载的那种）通常不包含最外层的 <FXCHAIN ... >
  -- 而是直接以 BYPASS / <VST ...> 等内容开头。
  if type(text) ~= "string" or text == "" then return text end

  local lines = {}
  for line in text:gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  if #lines == 0 then return text end

  -- 检测是否是 <FXCHAIN 包裹格式
  local first = (lines[1]:match("^%s*(.-)%s*$") or lines[1])
  if not first:match("^<FXCHAIN") then
    return text
  end

  -- 去掉第一行 <FXCHAIN（并确保后续不带外壳的格式）
  table.remove(lines, 1)

  -- 去掉末尾的外层 ">"（可能末尾有空行）
  while #lines > 0 do
    local t = (lines[#lines]:match("^%s*(.-)%s*$") or lines[#lines])
    if t == "" then
      table.remove(lines, #lines)
    elseif t == ">" then
      table.remove(lines, #lines)
      break
    else
      break
    end
  end

  local out = {}
  local has_bypass = false

  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or line

    -- 这些是 FXCHAIN 窗口状态/摆放信息，对 “FX chain 文件” 读取没必要，甚至可能导致兼容问题
    if trimmed:match("^WNDRECT%s") then
      goto continue
    end
    if trimmed:match("^SHOW%s") then
      goto continue
    end
    if trimmed:match("^LASTSEL%s") then
      goto continue
    end
    if trimmed:match("^DOCKED%s") then
      goto continue
    end
    if trimmed:match("^FLOATPOS%s") then
      goto continue
    end

    -- Track chunk 里常见 BYPASS 三参数，.RfxChain 文件通常是两参数
    local b1, b2 = trimmed:match("^BYPASS%s+([%-%d]+)%s+([%-%d]+)%s+[%-%d]+%s*$")
    if b1 and b2 then
      trimmed = ("BYPASS %s %s"):format(b1, b2)
      has_bypass = true
      out[#out + 1] = trimmed
      goto continue
    end

    if trimmed:match("^BYPASS%s") then
      has_bypass = true
    end

    out[#out + 1] = trimmed

    ::continue::
  end

  if not has_bypass then
    table.insert(out, 1, "BYPASS 0 0")
  end

  local s = table.concat(out, "\n")
  if not s:match("\n$") then
    s = s .. "\n"
  end
  return s
end

-- Save selected track FX chain as .RfxChain
-- return: ok, abs_path, plugins_or_err
function Engine.save_chain_to_disk(cfg, name, subdir_rel, opts)
  opts = opts or {}

  local tr = Engine.get_selected_track()
  if not tr then
    return false, nil, "No selected track"
  end

  name = sanitize_filename(name)

  local fx_root = (cfg and cfg.FXCHAINS_ROOT) or path_join(r.GetResourcePath(), "FXChains")
  local sep = package.config:sub(1, 1)

  local out_dir = fx_root
  if subdir_rel and subdir_rel ~= "" then
    -- allow '/' in rel
    local rel = tostring(subdir_rel):gsub("/", sep):gsub("\\", sep)
    out_dir = path_join(fx_root, rel)
  end

  ensure_dir(out_dir)

  local out_path = ensure_unique_rfx_path(out_dir, name)

  -- 1) 首选：直接从 TrackStateChunk 提取（最稳定、非侵入、无剪贴板副作用、无需 SWS）
  local text = extract_fxchain_from_track_chunk(tr)
  if text and text ~= "" then
    text = normalize_fxchain_text(text)
    text = fxchain_block_to_rfxchain_file(text)
  end

  -- 2) 兜底：chunk 提取失败时，再尝试 SWS 剪贴板（并且尽力恢复剪贴板）
  if not text or text == "" then
    if Engine.ensure_sws_or_quit() then
      local ok_clip, text_or_err = Engine._with_preserved_clipboard(function()
  Engine.copy_selected_track_fxchain_to_clipboard()
        return Engine.get_clipboard_text() or ""
      end)
      if ok_clip and type(text_or_err) == "string" and text_or_err:find("<FXCHAIN", 1, true) then
        text = normalize_fxchain_text(text_or_err)
        text = fxchain_block_to_rfxchain_file(text)
      end
    end
  end

  if not text or text == "" then
    return false, nil, "Failed to extract FX Chain data (Empty)."
  end

  -- 兼容两种格式：
  -- 1) 带外壳：<FXCHAIN ...
  -- 2) 传统 FXChain 文件：以 BYPASS ... 开头
  local head = tostring(text):gsub("^[%s\r\n]+", "")
  if (not head:find("<FXCHAIN", 1, true)) and (not head:match("^BYPASS%s")) then
    return false, nil, "Failed to extract FX Chain data (Unrecognized)."
  end

  -- Write file
  local f, err = io.open(out_path, "wb")
  if not f then
    return false, nil, "Cannot write file: " .. tostring(err)
  end
  f:write(text)
  if not text:match("\n$") then
    f:write("\n")
  end
  f:close()

  -- Optional publish
  if opts.publish_to_team and cfg and cfg.TEAM_PUBLISH_PATH and cfg.TEAM_PUBLISH_PATH ~= "" then
    local team_dir = cfg.TEAM_PUBLISH_PATH
    local team_target_dir = team_dir
    if subdir_rel and subdir_rel ~= "" then
      local rel = tostring(subdir_rel):gsub("/", sep):gsub("\\", sep)
      team_target_dir = path_join(team_dir, rel)
    end
    ensure_dir(team_target_dir)
    local team_path = path_join(team_target_dir, name .. ".RfxChain")
    pcall(function()
      copy_file(out_path, team_path)
    end)
  end

  local plugins = Engine.extract_plugins(text)
  return true, out_path, plugins
end

return Engine
