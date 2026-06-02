#include "features/splitter/Register.h"

#include <windows.h>

#include "features/splitter/ui/SplitterWindow.h"
#include "plugin/AppTimer.h"
#include "plugin/CommandRegistry.h"
#include "plugin/PluginContext.h"
#include "shared/reaper/ReaImGuiApi.h"

namespace lee::splitter {
namespace {

void TimerTick() { GetSplitterWindow().tick(); }

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
                L"Element Split 需要 ReaImGui 扩展。\n\n"
                L"请在 ReaPack 中安装 cfillion/ReaImGui，重启 REAPER 后再试。",
                L"Lee Splitter",
                MB_OK | MB_ICONINFORMATION);
}

void OnOpen() {
  if (!lee::reaimgui::Ready()) {
    WarnReaImGuiMissing();
    return;
  }
  EnsureTimer();
  auto& w = GetSplitterWindow();
  if (w.is_open()) {
    w.close();
    return;
  }
  w.open();
}

}  // namespace

void Register() {
  lee::RegisterCustomAction("Lee_Splitter_Open", "Lee: Splitter — Open window", OnOpen);
  if (lee::reaimgui::Ready()) EnsureTimer();
}

void Shutdown() {
  lee::UnregisterTimerCallback(TimerTick);
  g_timer = false;
  GetSplitterWindow().destroy();
}

}  // namespace lee::splitter
