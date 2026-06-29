#include "Register.h"

#include <cstdio>

#include "plugin/AppTimer.h"

#include "plugin/CommandRegistry.h"

#include "plugin/PluginContext.h"

#include "runtime/RuntimeWindow.h"

#include "shared/reaper/ReaImGuiApi.h"

#include "ui/setup/SetupWindow.h"

#include "shared/UiNotify.h"
#include "shared/DebugSessionLog.h"
#include "reaper_imgui_functions.h"



namespace lee::radial_menu {

namespace {



void TimerTick() {
  try {
    auto& runtime = GetRuntimeWindow();
    runtime.tick_input_hooks();
    if (runtime.is_active() || runtime.defer_pending()) runtime.tick();
    GetSetupWindow().tick();
  } catch (const ImGui_Error& e) {
    // #region agent log
    {
      char buf[256];
      snprintf(buf, sizeof(buf), "{\"err\":\"%s\"}", e.what());
      dbg::Log("B", "Register.cpp:TimerTick", "ImGui_Error caught", buf);
    }
    // #endregion
    GetRuntimeWindow().destroy();
    GetSetupWindow().destroy();
    ShowUserMessage(e.what(), "Lee RadialMenu");
  } catch (...) {
    // #region agent log
    dbg::Log("B", "Register.cpp:TimerTick", "unknown exception caught", "{}");
    // #endregion
    GetRuntimeWindow().destroy();
    GetSetupWindow().destroy();
    ShowUserMessage(
        "RadialMenu 绘图时发生内部错误，已重置界面。\n请重试；若仍失败请重启 REAPER。",
        "Lee RadialMenu");
  }
}



bool g_timer = false;



void EnsureTimer() {

  lee::EnsureAppTimer();

  if (g_timer) return;

  lee::RegisterTimerCallback(TimerTick);

  g_timer = true;

}



void OnOpenRadial() {
  // #region agent log
  dbg::Log("E", "Register.cpp:OnOpenRadial", "entry", "{\"runId\":\"r3\"}");
  // #endregion
  if (!lee::reaimgui::Ready()) {

    ShowUserMessage(

        "需要 ReaImGui 扩展。\n请在 ReaPack 安装 cfillion/ReaImGui 后重启 REAPER。",

        "Lee RadialMenu");

    return;

  }

  EnsureTimer();
  // #region agent log
  dbg::Log("E", "Register.cpp:OnOpenRadial", "after EnsureTimer", "{\"runId\":\"post-fix2\"}");
  // #endregion

  const bool was_active = GetRuntimeWindow().is_active();
  // #region agent log
  {
    char buf[32];
    snprintf(buf, sizeof(buf), "{\"wasActive\":%d}", was_active ? 1 : 0);
    dbg::Log("E", "Register.cpp:OnOpenRadial", "before open branch", buf);
  }
  // #endregion

  if (was_active) {
    // #region agent log
    dbg::Log("E", "Register.cpp:OnOpenRadial", "toggle dismiss", "{}");
    // #endregion
    GetRuntimeWindow().dismiss_for_toggle();
    return;
  }

  const auto& api = lee::Api();

  const double trigger_time = api.time_precise ? api.time_precise() : 0.0;

  // Paint on next REAPER timer tick — avoid reentrant ImGui with timer callback.
  (void)GetRuntimeWindow().open_with_hotkey(trigger_time);
  // #region agent log
  dbg::Log("E", "Register.cpp:OnOpenRadial", "open_with_hotkey returned", "{\"runId\":\"r3\"}");
  // #endregion

}



void OnOpenSetup() {

  if (!lee::reaimgui::Ready()) {

    ShowUserMessage("需要 ReaImGui 扩展。", "Lee RadialMenu Setup");

    return;

  }

  EnsureTimer();

  if (GetSetupWindow().is_open()) {

    GetSetupWindow().close();

    return;

  }

  GetSetupWindow().open();

}



void OpenSetupWindow() { OnOpenSetup(); }

}  // namespace



void Register() {

  if (const auto& api = lee::Api(); api.SetExtState) {

    api.SetExtState("RadialMenu_Tool", "Running", "0", false);

    api.SetExtState("RadialMenu", "SettingsOpen", "0", false);

  }

  lee::RegisterCustomAction("Lee_RadialMenu_Open", "Lee: Radial Menu — Open (hold hotkey)",

                            OnOpenRadial);

  lee::RegisterCustomAction("Lee_RadialMenu_Setup", "Lee: Radial Menu — Setup", OnOpenSetup);

  if (lee::reaimgui::Ready()) EnsureTimer();

}



void Shutdown() {

  lee::UnregisterTimerCallback(TimerTick);

  GetRuntimeWindow().destroy();

  GetSetupWindow().destroy();

  g_timer = false;

}



}  // namespace lee::radial_menu

