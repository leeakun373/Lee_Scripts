#pragma once

#include <string>
#include <vector>

#include "features/splitter/domain/AudioBuffer.h"
#include "features/splitter/domain/ItemSnapshot.h"

namespace lee::splitter {

// Creates output tracks below each source track and places synthesised layer
// items aligned to the original item. Reuses one output track per
// (source track, suffix) within a batch. Main thread only.
class TrackWriter {
 public:
  explicit TrackWriter(void* proj) : proj_(proj) {}

  // Writes one layer for one item. Returns true on success.
  bool Write(const ItemSnapshot& snap, const AudioBuffer& layer, const char* suffix);

 private:
  void* ensure_track(const ItemSnapshot& snap, const char* suffix);

  struct Record {
    void* src_track = nullptr;
    std::string suffix;
    void* out_track = nullptr;
  };

  void* proj_ = nullptr;
  std::vector<Record> records_;
};

}  // namespace lee::splitter
