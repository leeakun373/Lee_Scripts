-- Writes generated Lee Splitter stems back to REAPER tracks.
-- Uses low-level item/take/source APIs so insertion never depends on edit cursor.

local M = {}

local _, script_path = reaper.get_action_context()
local script_dir = script_path:match("^(.*[\\/])")
local Err = dofile(script_dir .. "src/splitter_errors.lua")

local STEMS = {
  { key = "tonal", suffix = "Tonal" },
  { key = "transient", suffix = "Transient" },
  { key = "noise", suffix = "Noise" },
}

local function message(message_text)
  reaper.MB(tostring(message_text), "Lee Splitter", 0)
end

local function fail(message_text)
  message(message_text)
  return nil, message_text
end

local function file_exists(path)
  local ok, f = pcall(io.open, path, "rb")
  if ok and f then
    f:close()
    return true
  end
  return false
end

local function track_count()
  return reaper.CountTracks(0)
end

local function get_track_at(index)
  if index < 0 or index >= track_count() then
    return nil
  end
  return reaper.GetTrack(0, index)
end

local function ensure_track_at(index)
  while index >= track_count() do
    reaper.InsertTrackAtIndex(track_count(), true)
  end
  return get_track_at(index)
end

local function set_track_name(track, name)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
end

local function is_track_empty(track)
  return reaper.CountTrackMediaItems(track) == 0
end

local function source_track_name(item_info)
  local name = tostring(item_info.source_track_name or "")
  if name ~= "" then
    return name
  end
  return "Source"
end

local function new_tracks(item_info)
  local source_index = item_info.source_track_index
  local base_name = source_track_name(item_info)
  local tracks = {}

  for i, stem in ipairs(STEMS) do
    local target_index = source_index + i
    reaper.InsertTrackAtIndex(target_index, true)
    local track = get_track_at(target_index)
    if not track then
      return fail(Err.wrap("TRACK_NEW_FAIL", "Unable to create target track for " .. stem.suffix .. "."))
    end
    set_track_name(track, base_name .. "_" .. stem.suffix)
    tracks[#tracks + 1] = track
  end

  return tracks
end

local function reuse_tracks(item_info)
  local source_index = item_info.source_track_index
  local base_name = source_track_name(item_info)
  local tracks = {}
  local total = track_count()

  -- Prefer reusing empty tracks directly below the source track.
  for idx = source_index + 1, total - 1 do
    if #tracks >= #STEMS then
      break
    end
    local track = get_track_at(idx)
    if track and is_track_empty(track) then
      tracks[#tracks + 1] = track
    end
  end

  while #tracks < #STEMS do
    local target_index = source_index + #tracks + 1
    reaper.InsertTrackAtIndex(target_index, true)
    local track = get_track_at(target_index)
    if not track then
      return fail(Err.wrap("TRACK_REUSE_FAIL", "Unable to create missing reuse track."))
    end
    tracks[#tracks + 1] = track
  end

  for i, stem in ipairs(STEMS) do
    set_track_name(tracks[i], base_name .. "_" .. stem.suffix)
  end

  return tracks
end

local function resolve_tracks(settings, item_info)
  if settings.track_mode == "reuse_tracks" then
    return reuse_tracks(item_info)
  end
  return new_tracks(item_info)
end

local function create_aligned_item(track, file_path, item_info)
  if not file_exists(file_path) then
    return fail(Err.wrap("STEM_FILE_MISSING", "Generated stem file does not exist:\n" .. tostring(file_path)))
  end

  local source = reaper.PCM_Source_CreateFromFile(file_path)
  if not source then
    return fail(Err.wrap("STEM_PCM_FAIL", "Unable to create PCM source from file:\n" .. tostring(file_path)))
  end

  local item = reaper.AddMediaItemToTrack(track)
  if not item then
    return fail(Err.wrap("STEM_ITEM_FAIL", "Unable to create media item on target track."))
  end

  local take = reaper.AddTakeToMediaItem(item)
  if not take then
    return fail(Err.wrap("STEM_TAKE_FAIL", "Unable to create take for generated stem item."))
  end

  reaper.SetMediaItemTake_Source(take, source)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", item_info.position)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", item_info.length)
  reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", item_info.take_start_offset)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", item_info.playrate)
  reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
  reaper.UpdateItemInProject(item)

  return item
end

function M.write_stems(result, settings)
  if not result or not result.output_paths or not result.item_info then
    return fail(Err.wrap("RESULT_INCOMPLETE", "Splitter result is incomplete; cannot write stems."))
  end

  local item_info = result.item_info
  local tracks, track_error = resolve_tracks(settings or result.settings or {}, item_info)
  if not tracks then
    return nil, track_error
  end

  local written_items = {}
  for i, stem in ipairs(STEMS) do
    local file_path = result.output_paths[stem.key]
    local item, item_error = create_aligned_item(tracks[i], file_path, item_info)
    if not item then
      return nil, item_error
    end
    written_items[stem.key] = item
  end

  return {
    tracks = tracks,
    items = written_items,
  }
end

return M
