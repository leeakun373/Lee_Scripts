#include "runtime/InputHook.h"

#include <windows.h>

#include "plugin/PluginContext.h"
#include "shared/reaper/JsApi.h"

namespace lee::radial_menu {
namespace {

constexpr int kVKeyMin = 1;
constexpr int kVKeyMax = 255;

unsigned char vkey_byte(const char* st, int vk) {
  if (!st || vk < kVKeyMin || vk > kVKeyMax) return 0;
  return static_cast<unsigned char>(st[vk]);
}

bool is_valid_vk(int vk) { return vk >= kVKeyMin && vk <= kVKeyMax; }

}  // namespace

void InputHook::schedule_intercept(int vk, int on) {
  if (!is_valid_vk(vk)) return;
  pending_intercept_key_ = vk;
  pending_intercept_on_ = on;
  pending_intercept_ = true;
}

bool InputHook::try_capture_at(double script_start_time) {
  auto* get_state = lee::jsapi::GetVKeysGetState();
  auto* get_down = lee::jsapi::GetVKeysGetDown();
  if (get_state && get_down) {
    const char* st = get_state(script_start_time - 1.0);
    const char* dn = get_down(script_start_time);
    if (st && dn) {
      for (int i = kVKeyMin; i <= kVKeyMax; ++i) {
        if (vkey_byte(st, i) != 0 || vkey_byte(dn, i) != 0) {
          key_ = i;
          start_time_ = script_start_time;
          schedule_intercept(i, 1);
          return true;
        }
      }
    }
  }

  for (int vk = kVKeyMin; vk <= kVKeyMax; ++vk) {
    if (GetAsyncKeyState(vk) & 0x8000) {
      key_ = vk;
      start_time_ = script_start_time;
      schedule_intercept(vk, 1);
      return true;
    }
  }

  return false;
}

bool InputHook::capture_trigger_key(double script_start_time) {
  manual_hold_ = false;
  key_ = 0;
  if (script_start_time <= 0) {
    const auto& api = lee::Api();
    script_start_time = api.time_precise ? api.time_precise() : 0.0;
  }
  const double offsets[] = {0.0, -0.05, -0.12, -0.25, -0.5};
  for (double off : offsets) {
    if (try_capture_at(script_start_time + off)) return true;
  }
  return false;
}

void InputHook::set_manual_hold_mode(bool on) {
  manual_hold_ = on;
  key_ = 0;
  if (on) {
    const auto& api = lee::Api();
    start_time_ = api.time_precise ? api.time_precise() : 0.0;
  }
}

bool InputHook::key_held() const {
  if (manual_hold_) return true;
  if (!is_valid_vk(key_)) return false;

  if (GetAsyncKeyState(key_) & 0x8000) return true;

  auto* get_state = lee::jsapi::GetVKeysGetState();
  if (!get_state) return false;

  const char* st = get_state(start_time_ - 1.0);
  if (!st) return false;

  return vkey_byte(st, key_) != 0;
}

void InputHook::intercept(int on) {
  if (!is_valid_vk(key_)) return;
  schedule_intercept(key_, on);
}

void InputHook::tick_pending_intercept_release() {
  if (!pending_intercept_ || !is_valid_vk(pending_intercept_key_)) {
    pending_intercept_ = false;
    pending_intercept_key_ = 0;
    return;
  }
  if (auto* fn = lee::jsapi::GetVKeysIntercept()) {
    fn(pending_intercept_key_, pending_intercept_on_);
  }
  pending_intercept_ = false;
  pending_intercept_key_ = 0;
  pending_intercept_on_ = 0;
}

void InputHook::reset_local_state_only() {
  key_ = 0;
  manual_hold_ = false;
  defer_pending_ = false;
  pending_intercept_ = false;
  pending_intercept_key_ = 0;
  pending_intercept_on_ = 0;
}

void InputHook::defer_release_until_key_up() {
  defer_pending_ = true;
}

void InputHook::tick_defer() {
  if (!defer_pending_) return;
  if (manual_hold_) return;
  if (key_held()) return;
  const int vk = key_;
  schedule_intercept(vk, -1);
  defer_pending_ = false;
  key_ = 0;
  const auto& api = lee::Api();
  if (api.SetExtState) api.SetExtState("RadialMenu_Tool", "Running", "0", false);
}

void InputHook::reset() {
  if (is_valid_vk(key_)) schedule_intercept(key_, -1);
  key_ = 0;
  manual_hold_ = false;
  defer_pending_ = false;
}

}  // namespace lee::radial_menu
