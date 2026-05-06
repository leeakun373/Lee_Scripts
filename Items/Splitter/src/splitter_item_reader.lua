-- Reads the currently selected REAPER item for Lee Splitter.
-- V1 intentionally supports exactly one selected media item.

local M = {}

local function message(message_text)
  reaper.ShowMessageBox(tostring(message_text), "Lee Splitter", 0)
end

local function fail(message_text, silent)
  if not silent then
    message(message_text)
  end
  return nil, message_text
end

local function get_source_path(take)
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then
    return nil
  end

  local path = reaper.GetMediaSourceFileName(source, "")
  if path == "" then
    return nil
  end

  return path
end

function M.read_selected_item(options)
  options = options or {}
  local silent = options.silent == true

  local selected_count = reaper.CountSelectedMediaItems(0)
  if selected_count ~= 1 then
    return fail("Lee Splitter V1 supports exactly one selected media item.", silent)
  end

  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then
    return fail("Unable to read the selected media item.", silent)
  end

  local take = reaper.GetActiveTake(item)
  if not take then
    return fail("The selected item has no active take.", silent)
  end

  if reaper.TakeIsMIDI(take) then
    return fail("The selected item is MIDI. Please select an audio item.", silent)
  end

  local source_path = get_source_path(take)
  if not source_path then
    return fail("Unable to resolve the selected take source file path.", silent)
  end

  local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local take_start_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local source_track = reaper.GetMediaItem_Track(item)
  local track_number = reaper.GetMediaTrackInfo_Value(source_track, "IP_TRACKNUMBER")
  local _, source_track_name = reaper.GetTrackName(source_track, "")
  if source_track_name == "" then
    source_track_name = "Track " .. tostring(math.floor(track_number))
  end

  return {
    item = item,
    take = take,
    source_track = source_track,
    source_track_index = math.floor(track_number - 1),
    source_track_name = source_track_name,
    source_path = source_path,
    position = position,
    length = length,
    take_start_offset = take_start_offset,
    playrate = playrate,
    source_start = take_start_offset,
    source_end = take_start_offset + (length * playrate),
  }
end

return M
