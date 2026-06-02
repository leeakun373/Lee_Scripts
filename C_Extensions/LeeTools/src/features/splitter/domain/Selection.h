#pragma once

#include <vector>

#include "features/splitter/domain/ItemSnapshot.h"

namespace lee::splitter {

struct SelectionInfo {
  int total_selected = 0;
  int valid_audio = 0;
  bool exactly_one = false;
  std::vector<ItemSnapshot> items;
};

// Enumerate selected audio items on the main thread.
SelectionInfo CollectSelection(void* proj);

}  // namespace lee::splitter
