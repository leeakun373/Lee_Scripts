-- Centralized persistent settings for Lee Splitter actions.
-- Lua stays as the REAPER orchestration layer; algorithm parameters are only
-- stored, validated, and forwarded to the external CLI.

local M = {}

M.SECTION = "Lee.Splitter"

M.HOP_LENGTHS = { 256, 512, 1024, 2048 }
M.TRACK_MODES = {
  new_tracks = "new_tracks",
  reuse_tracks = "reuse_tracks",
}

M.DEFAULTS = {
  margin = 3.0,
  wiener_iters = 2,
  hop_length = 512,
  track_mode = M.TRACK_MODES.new_tracks,
  mute_source_item = false,
  reuse_tonal_track_guid = "",
  reuse_transient_track_guid = "",
  reuse_noise_track_guid = "",
}

local function clamp_number(value, min_value, max_value, default_value)
  local n = tonumber(value)
  if n == nil then
    return default_value
  end
  if n < min_value then
    return min_value
  end
  if n > max_value then
    return max_value
  end
  return n
end

local function clamp_integer(value, min_value, max_value, default_value)
  local n = clamp_number(value, min_value, max_value, default_value)
  return math.floor(n + 0.5)
end

local function is_allowed_hop(value)
  local n = tonumber(value)
  if n == nil then
    return false
  end
  n = math.floor(n + 0.5)
  for _, hop_length in ipairs(M.HOP_LENGTHS) do
    if n == hop_length then
      return true
    end
  end
  return false
end

local function normalize_hop_length(value)
  local n = tonumber(value)
  if n == nil then
    return M.DEFAULTS.hop_length
  end
  n = math.floor(n + 0.5)
  if is_allowed_hop(n) then
    return n
  end
  return M.DEFAULTS.hop_length
end

local function normalize_track_mode(value)
  if value == M.TRACK_MODES.reuse_tracks then
    return M.TRACK_MODES.reuse_tracks
  end
  return M.TRACK_MODES.new_tracks
end

local function normalize_boolean(value, default_value)
  if type(value) == "boolean" then
    return value
  end
  local s = tostring(value or ""):lower()
  if s == "1" or s == "true" then
    return true
  end
  if s == "0" or s == "false" then
    return false
  end
  return default_value
end

local function get_ext_state(key)
  local value = reaper.GetExtState(M.SECTION, key)
  if value == "" then
    return nil
  end
  return value
end

local function set_ext_state(key, value)
  reaper.SetExtState(M.SECTION, key, tostring(value), true)
end

function M.normalize_settings(settings)
  settings = settings or {}

  return {
    margin = clamp_number(settings.margin, 1.0, 10.0, M.DEFAULTS.margin),
    wiener_iters = clamp_integer(settings.wiener_iters, 0, 10, M.DEFAULTS.wiener_iters),
    hop_length = normalize_hop_length(settings.hop_length),
    track_mode = normalize_track_mode(settings.track_mode),
    mute_source_item = normalize_boolean(settings.mute_source_item, M.DEFAULTS.mute_source_item),
    reuse_tonal_track_guid = tostring(settings.reuse_tonal_track_guid or M.DEFAULTS.reuse_tonal_track_guid),
    reuse_transient_track_guid = tostring(settings.reuse_transient_track_guid or M.DEFAULTS.reuse_transient_track_guid),
    reuse_noise_track_guid = tostring(settings.reuse_noise_track_guid or M.DEFAULTS.reuse_noise_track_guid),
  }
end

function M.load_settings()
  return M.normalize_settings({
    margin = get_ext_state("margin") or M.DEFAULTS.margin,
    wiener_iters = get_ext_state("wiener_iters") or M.DEFAULTS.wiener_iters,
    hop_length = get_ext_state("hop_length") or M.DEFAULTS.hop_length,
    track_mode = get_ext_state("track_mode") or M.DEFAULTS.track_mode,
    mute_source_item = get_ext_state("mute_source_item") or M.DEFAULTS.mute_source_item,
    reuse_tonal_track_guid = get_ext_state("reuse_tonal_track_guid") or M.DEFAULTS.reuse_tonal_track_guid,
    reuse_transient_track_guid = get_ext_state("reuse_transient_track_guid") or M.DEFAULTS.reuse_transient_track_guid,
    reuse_noise_track_guid = get_ext_state("reuse_noise_track_guid") or M.DEFAULTS.reuse_noise_track_guid,
  })
end

function M.save_settings(settings)
  local normalized = M.normalize_settings(settings)

  set_ext_state("margin", normalized.margin)
  set_ext_state("wiener_iters", normalized.wiener_iters)
  set_ext_state("hop_length", normalized.hop_length)
  set_ext_state("track_mode", normalized.track_mode)
  set_ext_state("mute_source_item", normalized.mute_source_item and "1" or "0")
  set_ext_state("reuse_tonal_track_guid", normalized.reuse_tonal_track_guid)
  set_ext_state("reuse_transient_track_guid", normalized.reuse_transient_track_guid)
  set_ext_state("reuse_noise_track_guid", normalized.reuse_noise_track_guid)

  return normalized
end

return M
