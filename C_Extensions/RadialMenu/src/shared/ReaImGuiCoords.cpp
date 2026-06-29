#include "shared/ReaImGuiCoords.h"

#include <cstdio>

#include "reaper_imgui_functions.h"
#include "shared/DebugSessionLog.h"

namespace lee::radial_menu {

int RgbaToU32(int r, int g, int b, int a) {
  return ((r & 255) << 24) | ((g & 255) << 16) | ((b & 255) << 8) | (a & 255);
}

bool ScreenToImGui(ImGui_Context* ctx, double screen_x, double screen_y, double& out_x,
                   double& out_y) {
  out_x = screen_x;
  out_y = screen_y;
  if (!ctx || !ImGui::PointConvertNative) return false;
  const int valid =
      ImGui::ValidatePtr ? (ImGui::ValidatePtr(ctx, "ImGui_Context*") ? 1 : 0) : 1;
  // #region agent log
  {
    char buf[160];
    snprintf(buf, sizeof(buf),
             "{\"ctx\":\"%p\",\"valid\":%d,\"sx\":%.0f,\"sy\":%.0f,\"hasConvert\":%d}",
             static_cast<void*>(ctx), valid, screen_x, screen_y,
             ImGui::PointConvertNative ? 1 : 0);
    lee::radial_menu::dbg::Log("B", "ReaImGuiCoords.cpp:ScreenToImGui", "before PointConvert",
                                 buf);
  }
  // #endregion
  if (!valid) return false;

  double x = screen_x;
  double y = screen_y;
  try {
    ImGui::PointConvertNative(ctx, &x, &y, false);
  } catch (const ImGui_Error& e) {
    // #region agent log
    {
      char buf[128];
      snprintf(buf, sizeof(buf), "{\"err\":\"%s\"}", e.what());
      lee::radial_menu::dbg::Log("B", "ReaImGuiCoords.cpp:ScreenToImGui", "ImGui_Error", buf);
    }
    // #endregion
    return false;
  }
  out_x = x;
  out_y = y;
  // #region agent log
  {
    char buf[96];
    snprintf(buf, sizeof(buf), "{\"gx\":%.1f,\"gy\":%.1f}", out_x, out_y);
    lee::radial_menu::dbg::Log("B", "ReaImGuiCoords.cpp:ScreenToImGui", "convert ok", buf);
  }
  // #endregion
  return true;
}

}  // namespace lee::radial_menu
