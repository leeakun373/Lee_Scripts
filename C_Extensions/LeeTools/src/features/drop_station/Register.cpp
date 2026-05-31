#include "features/drop_station/Register.h"

#include <windows.h>

#include "features/drop_station/domain/Store.h"
#include "features/drop_station/ui/Window.h"
#include "plugin/AppTimer.h"
#include "plugin/CommandRegistry.h"
#include "plugin/PluginContext.h"
#include "shared/reaper/ReaImGuiApi.h"

namespace lee::drop_station {
namespace {

void TimerTick() {
  lee::dropstation::GetWindow().tick();
}

bool g_drop_station_timer = false;

void WarnReaImGuiMissing() {  HWND owner = nullptr;
  if (const auto& api = lee::Api(); api.GetMainHwnd) {
    owner = api.GetMainHwnd();
  }
  ::MessageBoxW(
      owner,
      L"Drop Station 需要 ReaImGui 扩展。\n\n"
      L"请在 ReaPack 中安装 cfillion/ReaImGui，重启 REAPER 后再试。",
      L"Lee Drop Station",
      MB_OK | MB_ICONINFORMATION);
}

void HandleOpen() {
  if (!lee::reaimgui::Ready()) {
    WarnReaImGuiMissing();
    return;
  }
  lee::EnsureAppTimer();
  if (!g_drop_station_timer) {
    lee::RegisterTimerCallback(TimerTick);
    g_drop_station_timer = true;
  }
  auto& win = lee::dropstation::GetWindow();  if (win.is_open()) {
    win.hide();
  } else if (!win.show()) {
    WarnReaImGuiMissing();
  }
}

void HandleAddSelected() {
  auto& win = lee::dropstation::GetWindow();

  const auto& api = lee::Api();
  void* proj = api.EnumProjects ? api.EnumProjects(-1, nullptr, 0) : nullptr;
  if (!win.is_open()) {
    win.model().reset({});
    if (proj) {
      lee::dropstation::Store::Load(proj, win.model());
    }
  }

  int added = lee::dropstation::AddSelectedItemsToModel(win.model());
  if (added > 0 && proj) {
    lee::dropstation::Store::Save(proj, win.model());
  }
}

}  // namespace

void Register() {
  lee::RegisterCustomAction("Lee_DropStation_Open",
                            "Lee: Drop Station — Open window",
                            HandleOpen);
  lee::RegisterCustomAction("Lee_DropStation_AddSelected",
                            "Lee: Drop Station — Add selected items",
                            HandleAddSelected);
}

void Shutdown() {
  lee::UnregisterTimerCallback(TimerTick);
  lee::dropstation::GetWindow().destroy();
}
}  // namespace lee::drop_station
