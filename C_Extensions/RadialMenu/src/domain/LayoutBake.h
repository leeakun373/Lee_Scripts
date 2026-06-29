#pragma once

#include "domain/ConfigTypes.h"

namespace lee::radial_menu {

struct SubmenuLayout {
  double slot_w = 65;
  double slot_h = 25;
  double win_w = 0;
  double win_h = 0;
  double gap = 3;
  double padding = 10;
  int cols = 4;
  int rows = 3;
  int slot_count = 0;
};

struct SubmenuPosition {
  double x = 0;
  double y = 0;
};

int CountNonEmptySlots(const std::vector<Slot>& slots);
SubmenuLayout ComputeSubmenuLayout(const AppConfig& cfg, int slot_count);
SubmenuPosition ComputeSubmenuPosition(const AppConfig& cfg, int sector_index_0based,
                                       double wheel_cx, double wheel_cy);
void ClampToMonitor(double& x, double& y, double w, double h);

}  // namespace lee::radial_menu
