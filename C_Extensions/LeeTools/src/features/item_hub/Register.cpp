#include "features/item_hub/Register.h"

#include <windows.h>

#include "features/item_hub/ui/HubWindow.h"
#include "plugin/AppTimer.h"
#include "plugin/CommandRegistry.h"
#include "plugin/PluginContext.h"
#include "shared/reaper/ReaImGuiApi.h"

namespace lee::item_hub {
namespace {

void TimerTick() {
  GetHubWindow().tick();
}

bool g_item_hub_timer = false;

void EnsureItemHubTimer() {
  lee::EnsureAppTimer();
  if (g_item_hub_timer) return;
  lee::RegisterTimerCallback(TimerTick);
  g_item_hub_timer = true;
}

void WarnReaImGuiMissing() {
  HWND owner = nullptr;
  if (const auto& api = lee::Api(); api.GetMainHwnd) owner = api.GetMainHwnd();
  ::MessageBoxW(owner,
                L"Item Hub 需要 ReaImGui 扩展。\n\n"
                L"请在 ReaPack 中安装 cfillion/ReaImGui，重启 REAPER 后再试。",
                L"Lee Item Hub",
                MB_OK | MB_ICONINFORMATION);
}

void OnTrigger() {
  if (!lee::reaimgui::Ready()) {
    WarnReaImGuiMissing();
    return;
  }
  EnsureItemHubTimer();

  if (GetHubWindow().is_active()) {
    return;
  }

  void* proj = nullptr;
  if (const auto& api = lee::Api(); api.EnumProjects) {
    proj = api.EnumProjects(-1, nullptr, 0);
  }
  if (GetHubWindow().open_at_cursor(proj)) {
    GetHubWindow().tick();
  } else {
    GetHubWindow().close();
  }
}

}  // namespace

void Register() {
  lee::RegisterCustomAction("Lee_ItemHub_Show",
                            "Lee: Item Hub — Hold to adjust",
                            OnTrigger);
  if (lee::reaimgui::Ready()) {
    EnsureItemHubTimer();
    GetHubWindow().prepare();
  }
}

void Shutdown() {
  lee::UnregisterTimerCallback(TimerTick);
  GetHubWindow().destroy();
}

}  // namespace lee::item_hub
