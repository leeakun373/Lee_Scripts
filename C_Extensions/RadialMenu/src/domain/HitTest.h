#pragma once

#include "domain/ConfigTypes.h"

namespace lee::radial_menu {

struct HitTestResult {
  int sector_index = -1;  // 0-based index into config.sectors
  bool in_center = false;
  bool in_dead_zone = true;
};

HitTestResult HitTestWheel(double mouse_x, double mouse_y, double cx, double cy,
                           const AppConfig& cfg);

bool IsInCenterCircle(double mouse_x, double mouse_y, double cx, double cy, double inner_radius);

}  // namespace lee::radial_menu
