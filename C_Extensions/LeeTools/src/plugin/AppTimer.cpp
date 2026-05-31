#include "plugin/AppTimer.h"

#include "plugin/PluginContext.h"

#include <vector>

namespace lee {
namespace {

bool g_installed = false;
std::vector<TimerCallback> g_callbacks;

void TimerTick() {
  for (TimerCallback cb : g_callbacks) {
    if (cb) cb();
  }
}

}  // namespace

void EnsureAppTimer() {
  if (g_installed) return;
  auto* rec = GetPluginInfo();
  if (!rec || !rec->Register) return;
  rec->Register("timer", reinterpret_cast<void*>(&TimerTick));
  g_installed = true;
}

void RemoveAppTimer() {
  if (!g_installed) return;
  auto* rec = GetPluginInfo();
  if (rec && rec->Register) {
    rec->Register("-timer", reinterpret_cast<void*>(&TimerTick));
  }
  g_installed = false;
  g_callbacks.clear();
}

void RegisterTimerCallback(TimerCallback cb) {
  if (!cb) return;
  g_callbacks.push_back(cb);
}

void UnregisterTimerCallback(TimerCallback cb) {
  if (!cb) return;
  for (auto it = g_callbacks.begin(); it != g_callbacks.end(); ++it) {
    if (*it == cb) {
      g_callbacks.erase(it);
      return;
    }
  }
}

}  // namespace lee
