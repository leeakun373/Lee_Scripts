#include "shared/UiNotify.h"

#include <windows.h>

#include "plugin/PluginContext.h"
#include "reaper_imgui_functions.h"

namespace lee::radial_menu {

void ShowUserMessage(const char* message, const char* title) {
  if (!message) return;
  const auto& api = lee::Api();
  if (api.ShowMessageBox) {
    api.ShowMessageBox(message, title ? title : "Lee RadialMenu", 0);
    return;
  }
  HWND owner = nullptr;
  if (api.GetMainHwnd) owner = api.GetMainHwnd();
  MessageBoxA(owner, message, title ? title : "Lee RadialMenu", MB_OK | MB_ICONINFORMATION);
}

void DestroyImGuiContext(ImGui_Context*& ctx) {
  if (!ctx) return;
  // ReaImGui C++ header v0.10 may not export DestroyContext; extension GC releases
  // unused contexts after a short idle period. Drop our handle so we can recreate.
  ctx = nullptr;
}

}  // namespace lee::radial_menu
