#pragma once

class ImGui_Context;

namespace lee::radial_menu {

struct AppConfig;

void DrawWheel(ImGui_Context* ctx, const AppConfig& cfg, int hovered_sector_index,
               int active_sector_index, bool is_pinned, float anim_scale,
               const float* sector_expansion_progress, int sector_count);

}  // namespace lee::radial_menu
