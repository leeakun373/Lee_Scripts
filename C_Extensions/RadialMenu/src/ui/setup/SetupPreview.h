#pragma once

class ImGui_Context;

namespace lee::radial_menu {

struct AppConfig;

void DrawSetupPreview(ImGui_Context* ctx, const AppConfig& cfg, int selected_sector_index,
                      double center_x, double center_y);

}  // namespace lee::radial_menu
