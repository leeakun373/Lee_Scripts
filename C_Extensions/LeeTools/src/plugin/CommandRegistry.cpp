#include "plugin/CommandRegistry.h"

#include <windows.h>

#include <vector>

namespace lee {
namespace {

struct RegisteredAction {
  const char* id = nullptr;
  const char* desc = nullptr;
  ActionCallback callback = nullptr;
  int commandId = 0;
  gaccel_register_t gaccel{};
  bool gaccelRegistered = false;
};

std::vector<RegisteredAction> g_actions;
int (*g_register)(const char* name, void* infostruct) = nullptr;
bool g_hook2Registered = false;

using HookCommand2Fn = bool (*)(KbdSectionInfo*, int, int, int, int, HWND);
HookCommand2Fn g_hookCommand2 = nullptr;

bool DispatchAction(int command) {
  for (auto& action : g_actions) {
    if (action.commandId == 0 || command != action.commandId) continue;
    if (action.callback) action.callback();
    return true;
  }
  return false;
}

bool HookCommand2(KbdSectionInfo* sec, int command, int val, int val2, int relmode, HWND hwnd) {
  UNREFERENCED_PARAMETER(sec);
  UNREFERENCED_PARAMETER(val);
  UNREFERENCED_PARAMETER(val2);
  UNREFERENCED_PARAMETER(relmode);
  UNREFERENCED_PARAMETER(hwnd);
  return DispatchAction(command);
}

}  // namespace

bool RegisterCustomAction(const char* id, const char* desc, ActionCallback callback) {
  if (!id || !desc || !callback) return false;
  g_actions.push_back({id, desc, callback, 0, {}, false});
  return true;
}

bool InstallAllActions(reaper_plugin_info_t* rec) {
  if (!rec || !rec->Register) return false;
  g_register = rec->Register;
  g_hookCommand2 = &HookCommand2;

  for (auto& action : g_actions) {
    action.commandId = g_register("command_id", reinterpret_cast<void*>(const_cast<char*>(action.id)));
    if (!action.commandId) {
      UninstallAllActions();
      return false;
    }

    ZeroMemory(&action.gaccel, sizeof(action.gaccel));
    action.gaccel.desc = action.desc;
    action.gaccel.accel.fVirt = 0;
    action.gaccel.accel.key = 0;
    action.gaccel.accel.cmd = static_cast<WORD>(action.commandId);

    if (!g_register("gaccel", &action.gaccel)) {
      UninstallAllActions();
      return false;
    }
    action.gaccelRegistered = true;
  }

  if (!g_register("hookcommand2", reinterpret_cast<void*>(g_hookCommand2))) {
    UninstallAllActions();
    return false;
  }
  g_hook2Registered = true;
  return true;
}

void UninstallAllActions() {
  if (g_register) {
    if (g_hook2Registered && g_hookCommand2) {
      g_register("-hookcommand2", reinterpret_cast<void*>(g_hookCommand2));
    }
    for (auto& action : g_actions) {
      if (action.gaccelRegistered) {
        g_register("-gaccel", &action.gaccel);
      }
      action.gaccelRegistered = false;
      ZeroMemory(&action.gaccel, sizeof(action.gaccel));
      action.commandId = 0;
    }
  }
  g_hook2Registered = false;
  g_hookCommand2 = nullptr;
  g_register = nullptr;
}

}  // namespace lee
