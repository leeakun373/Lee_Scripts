--[[
  SonicCompass Mosaic — REAPER 回写模块

  职责：将 Sonic Compass 返回的 WAV 文件写入 REAPER 工程。

  两种模式：
    Mode A (replace):        替换当前选中 Item 的音频源
    Mode B (new_track_mute): 新建轨道插入结果，静音原始轨道

  公开 API:
    writeback.execute(wav_path, mode)
    mode: "replace" | "new_track_mute"  (默认 "new_track_mute")

  返回：(ok: boolean, error_msg: string)
]]

local writeback = {}

--- 回写 WAV 到 REAPER 工程。
-- @param wav_path  string  Sonic Compass 返回的 WAV 绝对路径
-- @param mode      string  "replace" | "new_track_mute"
-- @return boolean, string
function writeback.execute(wav_path, mode)
  mode = mode or "new_track_mute"

  -- 验证文件存在
  local f = io.open(wav_path, "r")
  if not f then
    return false, "Output WAV not found: " .. wav_path
  end
  f:close()

  -- 获取原始选中 Item 信息
  local orig_item = reaper.GetSelectedMediaItem(0, 0)
  if not orig_item then
    return false, "No media item selected — cannot determine writeback position."
  end

  local orig_pos = reaper.GetMediaItemInfo_Value(orig_item, "D_POSITION")
  local orig_track = reaper.GetMediaItem_Track(orig_item)

  reaper.Undo_BeginBlock()

  if mode == "replace" then
    -- ── Mode A: 替换当前 Item 的 PCM Source ──
    local take = reaper.GetActiveTake(orig_item)
    if not take then
      reaper.Undo_EndBlock("SC Mosaic Writeback (failed)", -1)
      return false, "Selected item has no active take."
    end

    local new_source = reaper.PCM_Source_CreateFromFile(wav_path)
    if not new_source then
      reaper.Undo_EndBlock("SC Mosaic Writeback (failed)", -1)
      return false, "Failed to create PCM source from: " .. wav_path
    end

    reaper.SetMediaItemTake_Source(take, new_source)

    -- 更新 Item 长度以匹配新源
    local new_src_len = reaper.GetMediaSourceLength(new_source)
    if new_src_len and new_src_len > 0 then
      reaper.SetMediaItemLength(orig_item, new_src_len, false)
    end

    reaper.UpdateItemInProject(orig_item)

  elseif mode == "new_track_mute" then
    -- ── Mode B: 新轨道 + 静音原轨 ──

    -- 获取原轨道索引
    local orig_track_idx = reaper.GetMediaTrackInfo_Value(orig_track, "IP_TRACKNUMBER")
    -- IP_TRACKNUMBER 返回 1-based，InsertTrackAtIndex 用 0-based
    local insert_idx = math.floor(orig_track_idx)  -- 在原轨道后面插入

    -- 插入新轨道
    reaper.InsertTrackAtIndex(insert_idx, true)
    local new_track = reaper.GetTrack(0, insert_idx)

    if not new_track then
      reaper.Undo_EndBlock("SC Mosaic Writeback (failed)", -1)
      return false, "Failed to insert new track."
    end

    -- 命名新轨道
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", "SC Mosaic Result", true)

    -- 在新轨道上插入 WAV
    -- SetEditCurPos 到原 Item 位置，然后 InsertMedia
    reaper.SetEditCurPos(orig_pos, false, false)

    -- 选中新轨道（InsertMedia 会插入到选中轨道）
    -- 先取消所有轨道选中
    local total_tracks = reaper.CountTracks(0)
    for i = 0, total_tracks - 1 do
      reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
    end
    reaper.SetTrackSelected(new_track, true)

    -- 插入媒体
    reaper.InsertMedia(wav_path, 0)  -- 0 = insert into selected track

    -- 静音原轨道
    reaper.SetMediaTrackInfo_Value(orig_track, "B_MUTE", 1.0)

  else
    reaper.Undo_EndBlock("SC Mosaic Writeback (unknown mode)", -1)
    return false, "Unknown writeback mode: " .. tostring(mode)
  end

  -- 刷新 UI
  reaper.UpdateArrange()
  reaper.TrackList_AdjustWindows(true)

  reaper.Undo_EndBlock("SC Mosaic Writeback (" .. mode .. ")", -1)

  return true, ""
end

return writeback
