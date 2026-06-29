#pragma once

class ImGui_Context;

namespace lee::radial_menu {

bool ScreenToImGui(ImGui_Context* ctx, double screen_x, double screen_y, double& out_x,
                   double& out_y);

// ReaImGui on Windows expects (R<<24)|(G<<16)|(B<<8)|A — same as Lua correct_rgba_to_u32.
int RgbaToU32(int r, int g, int b, int a);

}  // namespace lee::radial_menu
