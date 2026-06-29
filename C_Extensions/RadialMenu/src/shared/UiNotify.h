#pragma once

class ImGui_Context;

namespace lee::radial_menu {

void ShowUserMessage(const char* message, const char* title = "Lee RadialMenu");
void DestroyImGuiContext(ImGui_Context*& ctx);

}  // namespace lee::radial_menu
