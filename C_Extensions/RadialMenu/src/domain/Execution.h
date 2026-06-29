#pragma once

#include "domain/ConfigTypes.h"

namespace lee::radial_menu {

class Execution {
 public:
  static void SetLastValidContext(int ctx);
  static void TriggerSlot(const Slot& slot, void* proj = nullptr);
  static void HandleDrop(const Slot& slot, int screen_x, int screen_y, void* proj = nullptr);
};

}  // namespace lee::radial_menu
