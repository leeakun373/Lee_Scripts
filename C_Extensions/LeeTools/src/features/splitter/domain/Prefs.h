#pragma once

#include "features/splitter/domain/SplitMode.h"

namespace lee::splitter {

// Persisted preferences (spec section 9). Stored in the global ExtState section
// "Lee_Splitter" with persist=true. Knob values and Show Advanced are NOT
// persisted.
struct Prefs {
  bool quick_mode = false;  // false = Algorithm (default), true = Quick
  AlgoMode algo_mode = AlgoMode::TransientSustain;
  bool route_to_track = false;

  void load();
  void save() const;
};

}  // namespace lee::splitter
