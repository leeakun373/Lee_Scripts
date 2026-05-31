#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace lee::dropstation {

// A "slice snapshot" of one REAPER item taken at the moment Add Selected ran.
// Stored data is purely declarative -- no audio is rendered. It is sufficient
// to (later) re-create an equivalent item via REAPER API or to reason about
// the slice's effective audio range without re-walking the project.
struct DropEntry {
  // Display name. Take name if non-empty, else the source basename, optionally
  // suffixed with a time range like " [0:01.5 - 0:06.3]".
  std::wstring label;

  // Absolute path to the underlying raw source file (UTF-16).
  std::wstring path;

  // REAPER item GUID at capture time, formatted as "{XXXX-...}". Empty if
  // REAPER didn't expose guidToString / GetSetMediaItemInfo_String. Used as
  // the dedup key when present -- two distinct items on the same source are
  // intentionally kept as separate entries.
  std::string item_guid;

  // Source-time offset of the take into the source file (seconds).
  // Corresponds to D_STARTOFFS on the take.
  double take_offset = 0.0;

  // Effective project-time length of the item (seconds). D_LENGTH on the item.
  double length = 0.0;

  // Item fades (seconds). D_FADEINLEN / D_FADEOUTLEN. We do not capture the
  // fade *shape* in v1; if you need that later we can add D_FADEINSHAPE etc.
  double fade_in = 0.0;
  double fade_out = 0.0;

  // Linear gains and rate. 1.0 means unity / native speed.
  double item_volume = 1.0;   // D_VOL on item
  double take_volume = 1.0;   // D_VOL on take
  double playrate = 1.0;      // D_PLAYRATE on take
};

class Model {
 public:
  Model() = default;

  const std::vector<DropEntry>& entries() const { return entries_; }

  // Append entry; returns true if added, false if duplicate.
  // Dedup rule: if both entries carry a non-empty item_guid, dedup by GUID.
  // Otherwise dedup by (path lowercase, take_offset, length) tuple so that
  // three slices of the same source still count as three distinct entries.
  bool add(const DropEntry& entry);

  // Remove entry at index. No-op if out-of-range.
  void remove_at(size_t index);

  // Remove multiple entries by indices. Indices may be unsorted.
  void remove_indices(const std::vector<size_t>& indices);

  void clear() { entries_.clear(); bump(); }

  void sort_by_label();

  // Whole-list replacement used by the store on project reload.
  void reset(std::vector<DropEntry> entries) {
    entries_ = std::move(entries);
    bump();
  }

  // Bumped on every mutation; the store reads this to decide whether to flush.
  unsigned int revision() const { return revision_; }

 private:
  std::vector<DropEntry> entries_;
  unsigned int revision_ = 0;

  void bump() { ++revision_; }
};

}  // namespace lee::dropstation
