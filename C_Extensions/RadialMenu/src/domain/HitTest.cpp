#include "domain/HitTest.h"

#include <cmath>

#include "domain/Geometry.h"

namespace lee::radial_menu {
namespace {

double NormalizeAngle(double a) {
  while (a < 0) a += kTwoPi;
  while (a >= kTwoPi) a -= kTwoPi;
  return a;
}

bool AngleInRange(double angle, double lower, double upper) {
  const double range_span = std::fmod(upper - lower + kTwoPi, kTwoPi);
  if (range_span >= kTwoPi - 0.01) return true;
  return std::fmod(angle - lower + kTwoPi + 0.005, kTwoPi) <=
         std::fmod(upper - 0.005 - lower + kTwoPi, kTwoPi);
}

}  // namespace

bool IsInCenterCircle(double mouse_x, double mouse_y, double cx, double cy, double inner_radius) {
  const double dx = mouse_x - cx;
  const double dy = mouse_y - cy;
  return (dx * dx + dy * dy) <= inner_radius * inner_radius;
}

HitTestResult HitTestWheel(double mouse_x, double mouse_y, double cx, double cy,
                           const AppConfig& cfg) {
  HitTestResult r;
  const double dx = mouse_x - cx;
  const double dy = mouse_y - cy;
  const double dist_sq = dx * dx + dy * dy;
  const double inner = cfg.menu.inner_radius;
  const double inner_sq = inner * inner;

  if (dist_sq <= inner_sq) {
    r.in_center = true;
    r.in_dead_zone = true;
    r.sector_index = -1;
    return r;
  }

  // Match Lua: outside inner ring, sector hit extends without outer radius cap.
  r.in_dead_zone = false;

  const int n = static_cast<int>(cfg.sectors.size());
  if (n < 1) return r;
  if (n == 1) {
    r.sector_index = 0;
    return r;
  }

  double angle = std::atan2(dy, dx);
  if (angle < 0) angle += kTwoPi;
  const double step = kTwoPi / n;
  for (int i = 0; i < n; ++i) {
    const double ang_min = kStartOffset + i * step;
    const double ang_max = kStartOffset + (i + 1) * step;
    if (AngleInRange(angle, ang_min, ang_max)) {
      r.sector_index = i;
      break;
    }
  }
  return r;
}

}  // namespace lee::radial_menu
