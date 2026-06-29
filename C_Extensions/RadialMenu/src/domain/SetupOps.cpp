#include "domain/SetupOps.h"

#include <algorithm>

namespace lee::radial_menu {

void PreserveSlotPositions(AppConfig& cfg) {
  const int max_slots = std::max(1, cfg.menu.max_slots_per_sector);
  for (auto& sector : cfg.sectors) {
    int real_max = static_cast<int>(sector.slots.size());
    for (const auto& sl : sector.slots) {
      (void)sl;
    }
    real_max = std::max(real_max, max_slots);
    const int target = std::max(max_slots, real_max);
    std::vector<Slot> fixed;
    fixed.reserve(static_cast<size_t>(target));
    for (int i = 0; i < target; ++i) {
      if (i < static_cast<int>(sector.slots.size()) && sector.slots[i].type != "empty") {
        fixed.push_back(sector.slots[i]);
      } else {
        Slot e;
        e.type = "empty";
        fixed.push_back(e);
      }
    }
    sector.slots = std::move(fixed);
  }
}

}  // namespace lee::radial_menu
