--[[
  SonicCompass Mosaic — REAPER Lua HTTP Client (非阻塞、零窗口)

  架构：
    CF_ShellExecute("wscript.exe") → 临时 .vbs → 隐藏窗口 cmd /C curl
    → 响应写入 res_<id>.json → 完成标志 done_<id>.flag
    → reaper.defer() 轮询 flag 文件 → 读取 JSON → callback

  关键点：
    - CF_ShellExecute 不阻塞、不弹窗（SWS 扩展）
    - VBS 的 objShell.Run cmd, 0, True — 0=隐藏窗口, True=等 curl 完成再写 flag
    - done flag 避免读取未写完的 JSON（IO 竞态）
    - //B //Nologo 抑制 VBS 自身的错误弹窗

  公开 API:
    http_client.post_json(url, body_table, callback)
    http_client.get(url, callback)

  callback 签名: function(ok, response_table_or_errmsg)
]]

local http_client = {}

-- ── 临时目录 ──

local _tmp_dir = nil

local function get_tmp_dir()
  if _tmp_dir then return _tmp_dir end
  local sep = package.config:sub(1, 1)
  local dir = reaper.GetResourcePath() .. sep .. "Scripts" .. sep
              .. "Lee_Scripts" .. sep .. "SonicCompass_Mosaic" .. sep .. "tmp"
  reaper.RecursiveCreateDirectory(dir, 0)
  _tmp_dir = dir
  return dir
end

-- ── UUID ──

local function make_id()
  local t = math.floor(reaper.time_precise() * 1000000)
  return string.format("%x%04x", t, math.random(0, 0xFFFF))
end

-- ── JSON 编解码（平铺 key-value）──

local function json_encode(tbl)
  local parts = {}
  for k, v in pairs(tbl) do
    local vstr
    if type(v) == "string" then
      vstr = '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
    elseif type(v) == "number" then
      vstr = tostring(v)
    elseif type(v) == "boolean" then
      vstr = v and "true" or "false"
    else
      vstr = '"' .. tostring(v) .. '"'
    end
    parts[#parts + 1] = '"' .. k .. '":' .. vstr
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function json_decode(s)
  if not s or s == "" then return nil end
  local t = {}
  for k, v in s:gmatch('"([^"]+)"%s*:%s*(".-"[^,}]-)') do
    v = v:match("^%s*(.-)%s*[,}]?$") or v
    if v:sub(1, 1) == '"' then
      t[k] = v:sub(2, -2):gsub('\\"', '"'):gsub('\\\\', '\\')
    elseif v == "true" then
      t[k] = true
    elseif v == "false" then
      t[k] = false
    elseif v == "null" then
      t[k] = nil
    else
      t[k] = tonumber(v) or v
    end
  end
  for k, v in s:gmatch('"([^"]+)"%s*:%s*([%d%.%-]+)') do
    if not t[k] then t[k] = tonumber(v) end
  end
  return t
end

-- ── 文件操作 ──

local function write_file(path, content)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

local function remove_files(...)
  for _, p in ipairs({...}) do pcall(os.remove, p) end
end

-- ── VBS 生成 + CF_ShellExecute 触发 ──

--- 生成 .vbs 并通过 CF_ShellExecute 静默执行
-- @param curl_args  string  curl 的完整参数（不含 curl 本身）
-- @param res_path   string  curl 输出写入的文件路径
-- @param err_path   string  curl stderr 写入的文件路径
-- @param flag_path  string  完成标志文件路径
-- @param vbs_path   string  VBS 脚本文件路径
local function launch_curl_silent(curl_args, res_path, err_path, flag_path, vbs_path)
  -- cmd /C curl <args> > "res.json" 2> "err.log" & echo 1 > "done.flag"
  local cmd_line = 'curl ' .. curl_args
                   .. ' > ""' .. (res_path:gsub("/", "\\")) .. '""'
                   .. ' 2> ""' .. (err_path:gsub("/", "\\")) .. '""'
                   .. ' & echo 1 > ""' .. (flag_path:gsub("/", "\\")) .. '""'

  local vbs_content = 'On Error Resume Next\n'
                    .. 'Set s = WScript.CreateObject("WScript.Shell")\n'
                    .. 's.Run "cmd /C ' .. cmd_line .. '", 0, True\n'

  if not write_file(vbs_path, vbs_content) then return false end

  local vbs_win = (vbs_path:gsub("/", "\\"))
  reaper.CF_ShellExecute(vbs_win)
  return true
end

-- ── defer 轮询引擎 ──

--- 启动 defer 轮询，等待 flag 文件出现后读取 JSON 并回调
-- @param flag_path   string    完成标志文件
-- @param res_path    string    JSON 响应文件
-- @param err_path    string    curl stderr 日志文件
-- @param cleanup     table     需要清理的文件路径列表
-- @param callback    function  function(ok, resp_or_err)
-- @param max_polls   number    最大轮询次数（超时保护）
local function start_poll(flag_path, res_path, err_path, cleanup, callback, max_polls)
  local count = 0

  local function poll()
    count = count + 1

    -- 检查完成标志
    if file_exists(flag_path) then
      local content = read_file(res_path)
      local curl_err = read_file(err_path)
      remove_files(table.unpack(cleanup))

      if content and #content > 0 then
        local resp = json_decode(content)
        if resp then
          callback(true, resp)
        else
          callback(false, "Failed to parse JSON: " .. content:sub(1, 200))
        end
      else
        -- flag 存在但 JSON 为空 → curl 连接失败
        local detail = "empty response, server may be offline"
        if curl_err and #curl_err > 0 then
          detail = "curl: " .. curl_err:sub(1, 300)
        end
        callback(false, "Request failed (" .. detail .. ")")
      end
      return
    end

    -- 超时
    if count >= max_polls then
      local curl_err = read_file(err_path)
      remove_files(table.unpack(cleanup))
      local detail = "no response within timeout"
      if curl_err and #curl_err > 0 then
        detail = "curl: " .. curl_err:sub(1, 300)
      end
      callback(false, "Request timed out (" .. detail .. ")")
      return
    end

    reaper.defer(poll)
  end

  reaper.defer(poll)
end

-- ══════════════════════════════════════════════
-- 公开 API
-- ══════════════════════════════════════════════

--- POST JSON 请求（非阻塞、零窗口）
-- @param url       string
-- @param body_tbl  table
-- @param callback  function(ok, resp_table_or_errmsg)
function http_client.post_json(url, body_tbl, callback)
  local id  = make_id()
  local dir = get_tmp_dir()
  local sep = package.config:sub(1, 1)

  local req_path  = dir .. sep .. "req_"  .. id .. ".json"
  local res_path  = dir .. sep .. "res_"  .. id .. ".json"
  local err_path  = dir .. sep .. "err_"  .. id .. ".log"
  local vbs_path  = dir .. sep .. "run_"  .. id .. ".vbs"
  local flag_path = dir .. sep .. "done_" .. id .. ".flag"

  -- 写请求体到文件
  local body_json = json_encode(body_tbl)
  if not write_file(req_path, body_json) then
    callback(false, "Failed to write request body file")
    return
  end

  -- curl 参数
  local curl_args = '-s --max-time 120'
                  .. ' -X POST'
                  .. ' -H ""Content-Type: application/json""'
                  .. ' -d @""' .. (req_path:gsub("/", "\\")) .. '""'
                  .. ' ""' .. url .. '""'

  local ok = launch_curl_silent(curl_args, res_path, err_path, flag_path, vbs_path)
  if not ok then
    remove_files(req_path)
    callback(false, "Failed to create VBS launcher")
    return
  end

  local all_files = {req_path, res_path, err_path, vbs_path, flag_path}
  start_poll(flag_path, res_path, err_path, all_files, callback, 4000)
end

--- GET 请求（非阻塞、零窗口）
-- @param url       string
-- @param callback  function(ok, resp_table_or_errmsg)
function http_client.get(url, callback)
  local id  = make_id()
  local dir = get_tmp_dir()
  local sep = package.config:sub(1, 1)

  local res_path  = dir .. sep .. "res_"  .. id .. ".json"
  local err_path  = dir .. sep .. "err_"  .. id .. ".log"
  local vbs_path  = dir .. sep .. "run_"  .. id .. ".vbs"
  local flag_path = dir .. sep .. "done_" .. id .. ".flag"

  local curl_args = '-s --max-time 3 ""' .. url .. '""'

  local ok = launch_curl_silent(curl_args, res_path, err_path, flag_path, vbs_path)
  if not ok then
    callback(false, "Failed to create VBS launcher")
    return
  end

  local all_files = {res_path, err_path, vbs_path, flag_path}
  start_poll(flag_path, res_path, err_path, all_files, callback, 50)
end

return http_client
