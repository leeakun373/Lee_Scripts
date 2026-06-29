#include "features/project_explorer/Register.h"

#include <windows.h>

#include "features/project_explorer/ui/Window.h"
#include "plugin/AppTimer.h"
#include "plugin/CommandRegistry.h"
#include "plugin/PluginContext.h"
#include "shared/reaper/ReaImGuiApi.h"

namespace lee::project_explorer {
namespace {

void TimerTick() {
  lee::projectexplorer::GetWindow().tick();
}

bool g_timer = false;

void EnsureTimer() {
  lee::EnsureAppTimer();
  if (g_timer) return;
  lee::RegisterTimerCallback(TimerTick);
  g_timer = true;
}

void WarnReaImGuiMissing() {
  HWND owner = nullptr;
  if (const auto& api = lee::Api(); api.GetMainHwnd) owner = api.GetMainHwnd();
  ::MessageBoxW(owner,
                L"Project File Explorer 需要 ReaImGui 扩展。\n\n"
                L"请在 ReaPack 中安装 cfillion/ReaImGui，重启 REAPER 后再试。",
                L"Lee Project File Explorer",
                MB_OK | MB_ICONINFORMATION);
}

void OnOpen() {
  if (!lee::reaimgui::Ready()) {
    WarnReaImGuiMissing();
    return;
  }
  EnsureTimer();
  auto& win = lee::projectexplorer::GetWindow();
  if (win.is_open()) {
    win.hide();
  } else if (!win.show()) {
    WarnReaImGuiMissing();
  }
}

void OnOpenProjectFolder() {
  lee::projectexplorer::GetWindow().open_current_project_folder_external();
}

}  // namespace

void Register() {
  lee::RegisterCustomAction("Lee_ProjectExplorer_Open",
                            "Lee: Project File Explorer — Open window",
                            OnOpen);
  lee::RegisterCustomAction("Lee_ProjectExplorer_OpenProjectFolder",
                            "Lee: Project File Explorer — Open current project folder",
                            OnOpenProjectFolder);
}

void Shutdown() {
  lee::UnregisterTimerCallback(TimerTick);
  g_timer = false;
  lee::projectexplorer::GetWindow().destroy();
}

}  // namespace lee::project_explorer
