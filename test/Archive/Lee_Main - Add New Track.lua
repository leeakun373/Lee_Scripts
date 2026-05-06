-- @noindex
-- Insert track, but keep folder structure

local r = reaper

------------------------------------------------------------
-- utils
------------------------------------------------------------

-- 0-based index
local function track_idx(tr)
  return r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1
end

-- 找折叠 folder 的最后一条子轨
local function get_last_child_of_folder(folder_tr)
  local tc = r.CountTracks(0)
  local start_i = track_idx(folder_tr)
  local depth = 1
  local last_tr = folder_tr

  for i = start_i + 1, tc - 1 do
    local tr = r.GetTrack(0, i)
    last_tr = tr
    depth = depth + r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    if depth <= 0 then
      break
    end
  end

  return last_tr
end

------------------------------------------------------------
-- main
------------------------------------------------------------
r.Undo_BeginBlock()
r.PreventUIRefresh(1)

-- 先用选中的轨，没有就用 last touched
local src = r.GetSelectedTrack(0, 0)
if not src then
  src = r.GetLastTouchedTrack()
end

local new_tr = nil

if not src then
  -- 没有轨就直接插最后
  local ins = r.CountTracks(0)
  r.InsertTrackAtIndex(ins, true)
  new_tr = r.GetTrack(0, ins)
else
  local fd = r.GetMediaTrackInfo_Value(src, "I_FOLDERDEPTH")
  local fc = r.GetMediaTrackInfo_Value(src, "I_FOLDERCOMPACT") -- 2 = collapsed
  local insert_idx = nil
  local donor_tr = nil
  local donor_val = 0

  -- A. 选中的是"折叠的 folder 头"
  if fd == 1 and fc == 2 then
    local last_child = get_last_child_of_folder(src) or src
    insert_idx = track_idx(last_child) + 1
    local lc_fd = r.GetMediaTrackInfo_Value(last_child, "I_FOLDERDEPTH")
    if lc_fd < 0 then
      donor_tr = last_child
      donor_val = lc_fd
    end

  -- B. 选中的是"关口"（文件夹的最后一条子轨）
  elseif fd < 0 then
    insert_idx = track_idx(src) + 1
    donor_tr = src
    donor_val = fd

  -- C. 普通轨
  else
    insert_idx = track_idx(src) + 1
  end

  -- 真正插入
  r.InsertTrackAtIndex(insert_idx, true)
  new_tr = r.GetTrack(0, insert_idx)

  -- 关键：把关口搬到新轨上
  if donor_tr and donor_val < 0 then
    -- 此时 donor_tr 还是原来的那个 pointer，REAPER 会在插入时把它的 -1 变成 0
    -- 我们再显式写一遍，保证万无一失
    r.SetMediaTrackInfo_Value(donor_tr, "I_FOLDERDEPTH", 0)
    r.SetMediaTrackInfo_Value(new_tr, "I_FOLDERDEPTH", donor_val)
  end
end

-- 选中新轨道
if new_tr then
  r.Main_OnCommand(40297, 0) -- Unselect all
  r.SetTrackSelected(new_tr, true)
end

r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.PreventUIRefresh(-1)
r.Undo_EndBlock("Smart insert track (keep folder end)", -1)
