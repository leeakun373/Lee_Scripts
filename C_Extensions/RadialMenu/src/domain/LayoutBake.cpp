#include "domain/LayoutBake.h"

#include <algorithm>
#include <cmath>

#include <windows.h>

#include "domain/Geometry.h"

namespace lee::radial_menu {
namespace {

double SectorCenterAngle(int sector_index_0, int num_sectors) {
  if (num_sectors <= 0) return 0;
  if (num_sectors == 1) return kStartOffset + kPi;
  const double step = kTwoPi / num_sectors;
  const double a0 = kStartOffset + sector_index_0 * step;
  const double a1 = kStartOffset + (sector_index_0 + 1) * step;
  return (a0 + a1) * 0.5;
}

}  // namespace

int CountNonEmptySlots(const std::vector<Slot>& slots) {
  int n = 0;
  for (const auto& sl : slots) {
    if (sl.type != "empty") ++n;
  }
  return std::max(1, n);
}

SubmenuLayout ComputeSubmenuLayout(const AppConfig& cfg, int slot_count) {
  SubmenuLayout L;
  L.slot_w = cfg.menu.slot_width;
  L.slot_h = cfg.menu.slot_height;
  L.gap = cfg.menu.submenu_gap;
  L.padding = cfg.menu.submenu_padding;
  L.cols = 4;
  const int count =
      std::max(12, std::min(cfg.menu.max_slots_per_sector, std::max(slot_count, 12)));
  L.rows = (count + L.cols - 1) / L.cols;
  L.slot_count = count;
  L.win_w = L.slot_w * L.cols + L.gap * (L.cols - 1) + L.padding * 2;
  L.win_h = L.slot_h * L.rows + L.gap * (L.rows - 1) + L.padding * 2;
  return L;
}

SubmenuPosition ComputeSubmenuPosition(const AppConfig& cfg, int sector_index_0based,
                                       double wheel_cx, double wheel_cy) {
  SubmenuPosition pos;
  const int n = static_cast<int>(cfg.sectors.size());
  if (sector_index_0based < 0 || sector_index_0based >= n) return pos;

  const int slots =
      CountNonEmptySlots(cfg.sectors[sector_index_0based].slots);
  const SubmenuLayout layout = ComputeSubmenuLayout(cfg, slots);

  const double angle = SectorCenterAngle(sector_index_0based, n);
  const double outer = cfg.menu.outer_radius;
  const double overlap = 12.0;
  const double anchor_dist = outer - overlap;
  const double ax = wheel_cx + anchor_dist * std::cos(angle);
  const double ay = wheel_cy + anchor_dist * std::sin(angle);

  pos.y = ay - layout.win_h * 0.5;
  if (std::cos(angle) >= 0) {
    pos.x = ax + 5;
  } else {
    pos.x = ax - layout.win_w - 5;
  }
  ClampToMonitor(pos.x, pos.y, layout.win_w, layout.win_h);
  return pos;
}

void ClampToMonitor(double& x, double& y, double w, double h) {
  POINT pt = {static_cast<LONG>(x), static_cast<LONG>(y)};
  HMONITOR mon = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi = {sizeof(mi)};
  if (!GetMonitorInfo(mon, &mi)) return;
  const RECT& r = mi.rcWork;
  if (x + w > r.right) x = r.right - w - 8;
  if (x < r.left) x = static_cast<double>(r.left) + 8;
  if (y + h > r.bottom) y = r.bottom - h - 8;
  if (y < r.top) y = static_cast<double>(r.top) + 8;
}

}  // namespace lee::radial_menu
