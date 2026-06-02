#pragma once

#include <string>

namespace lee::splitter {

// All item / take properties needed to (a) read its audio and (b) reproduce its
// timeline placement on a new output track. Captured on the main thread.
struct ItemSnapshot {
  void* item = nullptr;
  void* take = nullptr;
  void* track = nullptr;
  void* source = nullptr;

  int source_track_index = 0;  // 0-based
  std::string source_track_name;

  // Timeline placement.
  double position = 0.0;
  double length = 0.0;
  double item_vol = 1.0;

  // Take placement / playback.
  double take_offset = 0.0;
  double playrate = 1.0;
  double take_vol = 1.0;
  double take_pan = 0.0;
  int chanmode = 0;

  // Fades.
  double fadein_len = 0.0;
  double fadeout_len = 0.0;
  double fadein_len_auto = -1.0;
  double fadeout_len_auto = -1.0;
  int fadein_shape = 0;
  int fadeout_shape = 0;
  double fadein_dir = 0.0;
  double fadeout_dir = 0.0;

  // Source format.
  int source_sr = 0;
  int source_channels = 0;

  bool valid = false;
  bool is_stereo() const { return source_channels >= 2; }
};

// Captures a snapshot from a selected MediaItem. Returns false if the item has
// no audio take (e.g. MIDI / empty). Main thread only.
bool CaptureItemSnapshot(void* item, ItemSnapshot& out);

}  // namespace lee::splitter
