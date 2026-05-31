#include "features/drop_station/domain/SliceReplicator.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cwctype>

#include "plugin/PluginContext.h"

namespace lee::dropstation {

namespace {

constexpr unsigned long long kDetectWindowMs = 5000;

std::wstring to_lower(std::wstring s) {
  std::transform(s.begin(), s.end(), s.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return s;
}

std::wstring utf8_to_wide(const char* p) {
  return lee::Utf8ToWide(p);
}

bool read_item_guid(void* item, std::string& out) {
  const auto& api = lee::Api();
  if (!api.GetSetMediaItemInfo || !api.guidToString) return false;
  const void* guid = api.GetSetMediaItemInfo(item, "GUID", nullptr);
  if (!guid) return false;
  char buf[64] = {0};
  api.guidToString(guid, buf);
  if (!buf[0]) return false;
  out.assign(buf);
  return true;
}

bool read_item_source_path_lower(void* item, std::wstring& out) {
  const auto& api = lee::Api();
  if (!api.GetActiveTake || !api.GetMediaItemTake_Source ||
      !api.GetMediaSourceFileName) {
    return false;
  }
  void* take = api.GetActiveTake(item);
  if (!take) return false;
  void* src = api.GetMediaItemTake_Source(take);
  if (!src) return false;
  char buf[4096] = {0};
  api.GetMediaSourceFileName(src, buf, static_cast<int>(sizeof(buf)));
  if (!buf[0]) return false;
  out = to_lower(utf8_to_wide(buf));
  return true;
}

}  // namespace

void SliceReplicator::Begin(void* proj, const std::vector<DropEntry>& slices) {
  Cancel();
  if (!proj) return;

  const auto& api = lee::Api();
  if (!api.CountMediaItems || !api.GetMediaItem ||
      !api.GetSetMediaItemInfo) {
    // Without GUID-based item enumeration we can't tell which items are new.
    OutputDebugStringA("[Lee] Replicator: missing API, skipping arm\n");
    return;
  }

  proj_ = proj;

  // Snapshot every existing item GUID. Items that materialise later and are
  // *not* in this set are the ones REAPER just created as a result of our
  // CF_HDROP drop.
  const int n = api.CountMediaItems(proj);
  known_guids_.clear();
  char abuf[64];
  std::snprintf(abuf, sizeof(abuf), "[Lee] Replicator: arm, %d existing items\n", n);
  OutputDebugStringA(abuf);
  for (int i = 0; i < n; ++i) {
    void* item = api.GetMediaItem(proj, i);
    if (!item) continue;
    if (api.ValidatePtr2 && !api.ValidatePtr2(proj, item, "MediaItem*")) continue;
    std::string g;
    if (read_item_guid(item, g)) known_guids_.insert(std::move(g));
  }

  pending_.clear();
  pending_.reserve(slices.size());
  for (const auto& e : slices) {
    PendingSlice p;
    p.source_path_lower = to_lower(e.path);
    p.take_offset = e.take_offset;
    p.length      = e.length;
    p.fade_in     = e.fade_in;
    p.fade_out    = e.fade_out;
    p.item_volume = e.item_volume;
    p.take_volume = e.take_volume;
    p.playrate    = e.playrate;
    pending_.push_back(p);
  }

  if (pending_.empty()) {
    // Nothing to replicate (no slice metadata). Stay inactive.
    proj_ = nullptr;
    known_guids_.clear();
    return;
  }

  deadline_tick_ms_ = ::GetTickCount64() + kDetectWindowMs;
  active_ = true;
}

void SliceReplicator::Tick() {
  if (!active_) return;

  if (::GetTickCount64() > deadline_tick_ms_ || pending_.empty()) {
    Cancel();
    return;
  }

  const auto& api = lee::Api();
  if (!api.CountMediaItems || !api.GetMediaItem) {
    Cancel();
    return;
  }

  // Active project changed mid-detection? Drop everything.
  if (api.EnumProjects) {
    void* now_active = api.EnumProjects(-1, nullptr, 0);
    if (now_active != proj_) {
      Cancel();
      return;
    }
  }

  const int n = api.CountMediaItems(proj_);
  bool dirty = false;
  for (int i = 0; i < n && !pending_.empty(); ++i) {
    void* item = api.GetMediaItem(proj_, i);
    if (!item) continue;
    // Project enumeration is racy w.r.t. user edits during the detection
    // window (delete/cut/glue may invalidate item pointers between the
    // CountMediaItems call and this loop body). Validate before touching.
    if (api.ValidatePtr2 && !api.ValidatePtr2(proj_, item, "MediaItem*")) continue;

    std::string g;
    if (!read_item_guid(item, g)) continue;
    if (known_guids_.count(g)) continue;  // already-existed or already-handled

    std::wstring src_lower;
    if (!read_item_source_path_lower(item, src_lower)) continue;

    // FIFO match: the first pending slice with a matching source wins. This
    // assumes REAPER honours hDrop order when creating items for a multi-file
    // drop, which it does in current builds; if the order ever desynchronises
    // the per-slice metadata is still self-contained so the worst case is a
    // mis-assignment between identical sources.
    auto it = std::find_if(
        pending_.begin(), pending_.end(),
        [&](const PendingSlice& s) { return s.source_path_lower == src_lower; });
    if (it == pending_.end()) continue;

    // Patch the item / take. Order matters: D_LENGTH last so the take offset
    // takes effect first (REAPER clamps length to source bounds otherwise).
    void* take = api.GetActiveTake ? api.GetActiveTake(item) : nullptr;
    if (take && api.ValidatePtr2 &&
        !api.ValidatePtr2(proj_, take, "MediaItem_Take*")) {
      take = nullptr;
    }
    if (take && api.SetMediaItemTakeInfo_Value) {
      api.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", it->take_offset);
      api.SetMediaItemTakeInfo_Value(take, "D_VOL",       it->take_volume);
      // Guard against zero/negative playrate which would assert in REAPER.
      const double rate = it->playrate > 0.0 ? it->playrate : 1.0;
      api.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE",  rate);
    }
    if (api.SetMediaItemInfo_Value) {
      api.SetMediaItemInfo_Value(item, "D_FADEINLEN",  it->fade_in);
      api.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", it->fade_out);
      api.SetMediaItemInfo_Value(item, "D_VOL",        it->item_volume);
      // Apply length last; clamp to a tiny positive so we never poison the
      // item with a zero/negative length even if the snapshot was corrupt.
      const double len = it->length > 0.0 ? it->length : 0.001;
      api.SetMediaItemInfo_Value(item, "D_LENGTH", len);
    }
    OutputDebugStringA("[Lee] Replicator: patched one new item\n");

    known_guids_.insert(std::move(g));
    pending_.erase(it);
    dirty = true;
  }

  if (dirty && api.UpdateArrange) api.UpdateArrange();

  if (pending_.empty()) {
    Cancel();
  }
}

void SliceReplicator::FlushAfterDrop() {
  if (!active_) {
    return;
  }
  const auto& api = lee::Api();
  if (api.PreventUIRefresh) {
    api.PreventUIRefresh(1);
  }
  // REAPER usually instantiates dropped items before DoDragDrop returns. Run a
  // few synchronous passes while UI refresh is frozen so the arrange view never
  // paints the transient "full source length" state.
  constexpr int kMaxPass = 8;
  for (int pass = 0; pass < kMaxPass && active_; ++pass) {
    Tick();
  }
  if (api.PreventUIRefresh) {
    api.PreventUIRefresh(-1);
  }
  if (api.UpdateArrange) {
    api.UpdateArrange();
  }
}

void SliceReplicator::Cancel() {
  active_ = false;
  proj_ = nullptr;
  deadline_tick_ms_ = 0;
  known_guids_.clear();
  pending_.clear();
}

SliceReplicator& GetReplicator() {
  static SliceReplicator instance;
  return instance;
}

}  // namespace lee::dropstation
