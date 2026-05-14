local M = {}

local _, script_path = reaper.get_action_context()
local script_dir = script_path:match("^(.*[\\/])")

local config = dofile(script_dir .. "src/splitter_config.lua")
local item_reader = dofile(script_dir .. "src/splitter_item_reader.lua")
local json_min = dofile(script_dir .. "src/splitter_json_min.lua")
local Err = dofile(script_dir .. "src/splitter_errors.lua")

local EXE_BASENAME = "LeeStemSplitterCLI"

local function path_separator()
  return package.config:sub(1, 1)
end

local function normalize_path(path)
  return tostring(path or ""):gsub("[/\\]+", path_separator())
end

local function join_path(left, right)
  local sep = path_separator()
  local a = tostring(left or ""):gsub("[/\\]+$", "")
  local b = tostring(right or ""):gsub("^[/\\]+", "")
  return normalize_path(a .. sep .. b)
end

local function stem_name(path)
  local filename = tostring(path or ""):match("[^/\\]+$") or tostring(path or "")
  return filename:gsub("%.[^%.]*$", "")
end

local function quote_path(path)
  return '"' .. tostring(path or "") .. '"'
end

local function vbs_escape(text)
  return tostring(text or ""):gsub('"', '""')
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function read_text_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end

  local content = f:read("*a")
  f:close()
  return content
end

local function write_text_file(path, content)
  local f = io.open(path, "wb")
  if not f then
    return false
  end

  f:write(content)
  f:close()
  return true
end

local function delete_file(path)
  os.remove(path)
end

local function get_cli_exe_path()
  local sep = path_separator()
  local base_dir = tostring(script_dir or ""):gsub("[/\\]+$", "")
  return normalize_path(base_dir .. sep .. "bin" .. sep .. EXE_BASENAME .. sep .. EXE_BASENAME .. ".exe")
end

local function canonical_dir(path)
  local s = normalize_path(path):gsub("[/\\]+$", "")
  local os_name = reaper.GetOS and reaper.GetOS() or ""
  if tostring(os_name):match("Win") then
    s = s:lower()
  end
  return s
end

local function is_under_dir(path, dir)
  local p = canonical_dir(path)
  local d = canonical_dir(dir)
  if p == "" or d == "" then
    return false
  end
  return p == d or p:sub(1, #d + 1) == d .. path_separator()
end

local function is_temp_project_path(project_path)
  if tostring(project_path or "") == "" then
    return true
  end

  local temp_candidates = {
    os.getenv("TEMP"),
    os.getenv("TMP"),
    os.getenv("TMPDIR"),
  }

  local os_name = reaper.GetOS and reaper.GetOS() or ""
  if tostring(os_name):match("Win") then
    temp_candidates[#temp_candidates + 1] = "C:\\Windows\\Temp"
  else
    temp_candidates[#temp_candidates + 1] = "/tmp"
    temp_candidates[#temp_candidates + 1] = "/var/tmp"
  end

  for _, temp_dir in ipairs(temp_candidates) do
    if temp_dir and temp_dir ~= "" and is_under_dir(project_path, temp_dir) then
      return true
    end
  end

  return false
end

local function get_project_output_dir()
  local ok, project_path = pcall(function()
    return reaper.GetProjectPath(0, "")
  end)

  if not ok or type(project_path) ~= "string" then
    ok, project_path = pcall(function()
      return reaper.GetProjectPath("")
    end)
  end

  if not ok or type(project_path) ~= "string" then
    project_path = ""
  end

  project_path = normalize_path(project_path)
  if is_temp_project_path(project_path) then
    return nil, Err.wrap("CLI_PROJECT_PATH", "请先保存 REAPER 工程以指定音频生成路径")
  end

  return project_path
end

local function build_output_paths(source_path, outdir)
  local base = stem_name(source_path)
  return {
    outdir = outdir,
    tonal = join_path(outdir, base .. "_Tonal.wav"),
    transient = join_path(outdir, base .. "_Transient.wav"),
    noise = join_path(outdir, base .. "_Noise.wav"),
  }
end

local function build_cli_command(exe_path, source_path, outdir, settings)
  return quote_path(exe_path)
    .. " --input " .. quote_path(source_path)
    .. " --margin " .. tostring(settings.margin)
    .. " --wiener " .. tostring(settings.wiener_iters)
    .. " --hop " .. tostring(settings.hop_length)
    .. " --outdir " .. quote_path(outdir)
end

local function new_run_id()
  local guid = reaper.genGuid and reaper.genGuid() or tostring(math.floor(reaper.time_precise() * 1000000))
  guid = tostring(guid):gsub("[{}%-]", ""):gsub("[^%w_]", "")
  return guid
end

local function build_done_file(outdir, run_id)
  local sep = path_separator()
  return normalize_path(outdir:gsub("[/\\]+$", "") .. sep .. ".splitter_done_" .. run_id)
end

local function build_manifest_file(outdir, run_id)
  local sep = path_separator()
  return normalize_path(outdir:gsub("[/\\]+$", "") .. sep .. ".splitter_stdout_" .. run_id)
end

local function build_vbs_file(outdir, done_file)
  return done_file .. ".vbs"
end

local function start_background_process(cli_command, done_file, vbs_file, manifest_file)
  local cmd_payload = cli_command
    .. " > "
    .. quote_path(manifest_file)
    .. " 2>&1 & echo %ERRORLEVEL% > "
    .. quote_path(done_file)
  local cmd_line = 'cmd /c "' .. cmd_payload .. '"'
  local vbs_content = table.concat({
    'Set WshShell = CreateObject("WScript.Shell")',
    'WshShell.Run "' .. vbs_escape(cmd_line) .. '", 0, False',
    "",
  }, "\r\n")

  if not write_text_file(vbs_file, vbs_content) then
    return nil, Err.wrap("CLI_VBS_WRITE", "Unable to create VBS launcher file.")
  end

  local launch = "wscript.exe " .. quote_path(vbs_file)
  local ok = os.execute(launch)
  if ok == false or ok == nil then
    delete_file(vbs_file)
    return nil, Err.wrap("CLI_VBS_LAUNCH", "Unable to start VBS launcher.")
  end

  return true
end

local STEM_KEYS = { "tonal", "transient", "noise" }

local function apply_stdout_paths_to_result(raw, output_paths)
  if type(raw) ~= "string" or raw == "" then
    return false
  end
  local d = json_min.decode(raw)
  if type(d) ~= "table" then
    return false
  end
  local t, tr, n = d.tonal, d.transient, d.noise
  if type(t) ~= "string" or t == "" or type(tr) ~= "string" or tr == "" or type(n) ~= "string" or n == "" then
    return false
  end
  output_paths.tonal = normalize_path(t)
  output_paths.transient = normalize_path(tr)
  output_paths.noise = normalize_path(n)
  return true
end

local function all_stem_files_exist(output_paths)
  for _, key in ipairs(STEM_KEYS) do
    local p = output_paths[key]
    if not p or not file_exists(p) then
      return false
    end
  end
  return true
end

local function format_stem_path_lines(output_paths)
  local lines = {}
  for _, key in ipairs(STEM_KEYS) do
    lines[#lines + 1] = tostring(key) .. ": " .. tostring(output_paths[key] or "")
  end
  return table.concat(lines, "\n")
end

function M.build_command_preview(source_path, settings)
  local exe_path = get_cli_exe_path()
  local outdir = get_project_output_dir()
  if not outdir then
    return nil
  end
  return build_cli_command(exe_path, source_path, outdir, config.normalize_settings(settings))
end

M.build_output_paths = build_output_paths

function M.run(item_info, settings, on_success, on_error)
  if not item_info then
    local read_error
    item_info, read_error = item_reader.read_selected_item({ silent = true })
    if not item_info then
      return nil, read_error
    end
  end

  settings = config.normalize_settings(settings or config.load_settings())
  local exe_path = get_cli_exe_path()
  if not file_exists(exe_path) then
    return nil, Err.wrap("CLI_EXE_MISSING", "Splitter CLI executable not found:\n" .. exe_path)
  end

  local outdir, outdir_error = get_project_output_dir()
  if not outdir then
    return nil, outdir_error
  end

  local output_paths = build_output_paths(item_info.source_path, outdir)
  local cli_command = build_cli_command(exe_path, item_info.source_path, output_paths.outdir, settings)
  local run_id = new_run_id()
  local done_file = build_done_file(output_paths.outdir, run_id)
  local manifest_file = build_manifest_file(output_paths.outdir, run_id)
  local vbs_file = build_vbs_file(output_paths.outdir, done_file)

  local started, start_error = start_background_process(cli_command, done_file, vbs_file, manifest_file)
  if not started then
    return nil, start_error
  end

  local result = {
    item_info = item_info,
    settings = settings,
    command = cli_command,
    done_file = done_file,
    vbs_file = vbs_file,
    manifest_file = manifest_file,
    output_paths = output_paths,
  }

  local function finish_error(err)
    delete_file(done_file)
    delete_file(vbs_file)
    delete_file(manifest_file)
    if on_error then
      on_error(err, result)
    end
  end

  local function check_status()
    local content = read_text_file(done_file)
    if not content then
      reaper.defer(check_status)
      return
    end

    local exit_code = tonumber(tostring(content):match("(-?%d+)"))
    delete_file(done_file)
    delete_file(vbs_file)

    if exit_code ~= 0 then
      local err_blob = read_text_file(manifest_file)
      delete_file(manifest_file)
      local msg = Err.wrap(
        "CLI_FAILED",
        "Splitter CLI failed with exit code " .. tostring(exit_code or "unknown")
      )
      if type(err_blob) == "string" and err_blob ~= "" then
        local clip = err_blob
        if #clip > 4000 then
          clip = clip:sub(1, 4000) .. "\n...(truncated)"
        end
        msg = msg .. "\n\n" .. clip
      end
      finish_error(msg)
      return
    end

    local raw_stdout = read_text_file(manifest_file)
    delete_file(manifest_file)
    apply_stdout_paths_to_result(raw_stdout, result.output_paths)

    local wait_ticks = 0
    local max_wait_ticks = 150

    local function finalize_success()
      if on_success then
        on_success(result)
      end
    end

    local function wait_for_stem_files()
      if all_stem_files_exist(result.output_paths) then
        finalize_success()
        return
      end
      wait_ticks = wait_ticks + 1
      if wait_ticks >= max_wait_ticks then
        finish_error(
          Err.wrap(
            "CLI_STEMS_TIMEOUT",
            "CLI 已成功结束，但在磁盘上仍无法打开全部输出文件（已等待 "
              .. tostring(max_wait_ticks)
              .. " 帧）。常见于杀毒扫描、企业受控文件夹或云同步延迟。\n"
              .. format_stem_path_lines(result.output_paths)
          )
        )
        return
      end
      reaper.defer(wait_for_stem_files)
    end

    if all_stem_files_exist(result.output_paths) then
      finalize_success()
    else
      reaper.defer(wait_for_stem_files)
    end
  end

  reaper.defer(check_status)
  return result
end

return M
