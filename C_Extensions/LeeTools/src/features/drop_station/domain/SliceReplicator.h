#pragma once

#include <set>
#include <string>
#include <vector>

#include "features/drop_station/domain/Model.h"

namespace lee::dropstation {

// After the user drags one or more Drop Station entries out via CF_HDROP, the
// receiving REAPER project creates new media items that are blank (SOFFS=0,
// LENGTH=full source length, no fade/vol/rate). The replicator catches those
// new items as they appear and patches them so that the drop result is
// indistinguishable from the original slice that lived in the source project.
//
// Lifecycle:
//   Begin(proj, slices)  before DoDragDrop is invoked
//   Tick()               every REAPER timer beat for ~5 seconds afterwards
//   Cancel()             explicit reset (e.g. user closed Drop Station)
//
// The replicator deliberately scopes itself to a single REAPER project: if the
// user switches the active project mid-detection the pending state is dropped.
class SliceReplicator {
 public:
  // Snapshot every existing item's GUID in `proj` and copy the provided slice
  // info into the pending queue. Replaces any previous pending state.
  void Begin(void* proj, const std::vector<DropEntry>& slices);

  // Called from the REAPER timer hook while active(). Scans for newly created
  // items matching pending slices and patches their properties. Self-cancels
  // when the time budget expires or the pending queue empties.
  void Tick();

  // Run Tick() immediately after DoDragDrop returns, with UI refresh suppressed
  // so the user never sees the transient "full source length" item state.
  void FlushAfterDrop();

  bool Active() const { return active_; }

  // Drop any pending state. Safe to call repeatedly.
  void Cancel();

 private:
  struct PendingSlice {
    std::wstring source_path_lower;  // case-folded full path used for matching
    double take_offset;
    double length;
    double fade_in;
    double fade_out;
    double item_volume;
    double take_volume;
    double playrate;
  };

  bool active_ = false;
  void* proj_ = nullptr;
  unsigned long long deadline_tick_ms_ = 0;

  // GUIDs of items that already existed when Begin() was called. New items
  // are anything not in this set; once we successfully replicate onto one
  // we add its GUID here too to avoid re-touching it on subsequent ticks.
  std::set<std::string> known_guids_;
  std::vector<PendingSlice> pending_;
};

// Singleton accessor used by the timer + drag-start code.
SliceReplicator& GetReplicator();

}  // namespace lee::dropstation
