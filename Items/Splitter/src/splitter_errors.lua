-- Lee Splitter: stable error tags for logs / screenshots / grep.
-- Format: [LeeSplitter:CODE] human message (keep CODE stable; change message freely).

local M = {}

--- @param code string  Upper_snake identifier
--- @param message string|nil  Detail text; optional
function M.wrap(code, message)
  local head = "[LeeSplitter:" .. tostring(code) .. "]"
  if message == nil or tostring(message) == "" then
    return head
  end
  return head .. " " .. tostring(message)
end

--[[
  Code reference (search repo for the CODE string):

  ITEM_SELECTION      必须且只能选中一个媒体 item
  ITEM_READ           读不到选中 item
  ITEM_NO_TAKE        无 active take
  ITEM_MIDI           选中为 MIDI
  ITEM_SOURCE_PATH    无法解析源文件路径

  CLI_EXE_MISSING     bin 下找不到 LeeStemSplitterCLI.exe
  CLI_PROJECT_PATH    工程未保存或路径落在临时目录
  CLI_VBS_WRITE       无法写入后台启动用 .vbs
  CLI_VBS_LAUNCH      无法执行 wscript 启动后台任务
  CLI_FAILED          CLI 非零退出（正文常含 Python traceback）
  CLI_STEMS_TIMEOUT   CLI 已成功但多帧内仍打不开全部输出 wav

  TRACK_NEW_FAIL      新建目标轨失败
  TRACK_REUSE_FAIL    复用轨模式下创建缺失轨失败

  STEM_FILE_MISSING   预期路径上 wav 不存在（写入前检查）
  STEM_PCM_FAIL       PCM_Source_CreateFromFile 失败
  STEM_ITEM_FAIL      AddMediaItemToTrack 失败
  STEM_TAKE_FAIL      AddTakeToMediaItem 失败

  UI_IMGUI_MISSING    未安装 ReaImGui
  UI_WRITE_UNKNOWN    写回轨道阶段未知错误（应有更具体的 STEM_* / TRACK_*）

  （Python CLI stderr 行前缀）[LeeSplitterCLI:EXCEPTION] 后跟异常类型与简要说明
]]

return M
