#include "shared/ReaImGuiCoords.h"

#include "reaper_imgui_functions.h"

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
  if (!valid) return false;

  double x = screen_x;
  double y = screen_y;
  try {
    ImGui::PointConvertNative(ctx, &x, &y, false);
  } catch (const ImGui_Error&) {
    return false;
  }
  out_x = x;
  out_y = y;
  return true;
}

}  // namespace lee::radial_menu
