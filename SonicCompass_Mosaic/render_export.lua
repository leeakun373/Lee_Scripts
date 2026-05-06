--[[
  SonicCompass Mosaic — REAPER 渲染导出模块

  职责：将当前选中 Item 的有效片段通过 REAPER 工程渲染导出为 WAV。
  方案：通过 GetSet_LoopTimeRange2 设定时间选区为 Item 起止，
       渲染模式为 Time Selection，然后调用 Main_OnCommand 触发渲染。

  输出：临时目录下 UUID 命名的 WAV 文件路径。

  公开 API:
    render_export.render_selected_item() -> string|nil, string
    返回 (wav_path, error_msg)
]]

local render_export = {}

-- 生成 UUID-like hex 字符串
local function uuid_hex()
  local s = ""
  for i = 1, 16 do
    s = s .. string.format("%02x", math.random(0, 255))
  end
  return s
end

-- 获取输出临时目录
local function get_temp_dir()
  local sep = package.config:sub(1, 1)
  local dir = reaper.GetResourcePath() .. sep .. "Scripts" .. sep
              .. "Lee_Scripts" .. sep .. "SonicCompass_Mosaic" .. sep .. "render_tmp"
  reaper.RecursiveCreateDirectory(dir, 0)
  return dir
end

--- 渲染当前选中 Item 的有效区间为 WAV。
-- @return string|nil  成功时返回 WAV 路径，失败返回 nil
-- @return string      错误信息（成功时为 ""）
function render_export.render_selected_item()
  -- 1. 检查选中 Item
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then
    return nil, "No media item selected in REAPER."
  end

  -- 2. 获取 Item 边界
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_pos + item_len

  if item_len <= 0 then
    return nil, "Selected item has zero or negative length."
  end

  -- 3. 保存当前时间选区（渲染后恢复）
  --    API: GetSet_LoopTimeRange2(proj, isSet, isLoop, start, end, allowAutoSeek)
  --    isLoop=false → 操作时间选区（Time Selection）
  local old_start, old_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)

  -- 4. 设置时间选区为 Item 边界
  reaper.GetSet_LoopTimeRange2(0, true, false, item_pos, item_end, false)

  -- 5. 配置渲染参数
  local out_dir = get_temp_dir()
  local out_name = "sc_mosaic_" .. uuid_hex()

  -- RENDER_FILE: 输出目录
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE", out_dir, true)
  -- RENDER_PATTERN: 文件名（不含扩展名，REAPER 自动加）
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", out_name, true)

  -- 渲染设置：
  -- GetSetProjectInfo(proj, desc, value, is_set) — 4 个参数，proj=0 表示当前工程
  -- Source: 0 = Master mix
  -- Bounds: 2 = Time selection
  reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 0, true)   -- Source = master mix
  local BOUNDS_TIME_SELECTION = 2
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", BOUNDS_TIME_SELECTION, true)

  -- 6. 执行渲染
  -- Action 42230 = File: Render project, using the most recent render settings, auto-close render dialog
  local RENDER_ACTION = 42230
  reaper.Main_OnCommand(RENDER_ACTION, 0)

  -- 7. 恢复原始时间选区
  reaper.GetSet_LoopTimeRange2(0, true, false, old_start, old_end, false)

  -- 8. 查找输出文件 — REAPER 可能加不同扩展名取决于渲染格式设置
  local sep = package.config:sub(1, 1)
  local candidates = {
    out_dir .. sep .. out_name .. ".wav",
    out_dir .. sep .. out_name .. ".aiff",
    out_dir .. sep .. out_name .. ".flac",
    out_dir .. sep .. out_name .. ".mp3",
    out_dir .. sep .. out_name .. ".ogg",
    out_dir .. sep .. out_name,  -- 无扩展名
  }

  for _, path in ipairs(candidates) do
    local f = io.open(path, "rb")
    if f then
      local size = f:seek("end")
      f:close()
      if size and size > 44 then  -- 至少比 WAV header 大
        return path, ""
      end
    end
  end

  return nil, "Render failed: output file not found.\n\n"
    .. "Expected at: " .. candidates[1] .. "\n\n"
    .. "Please check REAPER render settings:\n"
    .. "  - Format should be WAV (PCM)\n"
    .. "  - Output directory must be writable"
end

return render_export
