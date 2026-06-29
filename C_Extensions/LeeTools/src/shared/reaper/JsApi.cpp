#include "shared/reaper/JsApi.h"

namespace lee::jsapi {
namespace {

VKeysGetStateFn g_get_state = nullptr;
VKeysGetDownFn g_get_down = nullptr;
VKeysInterceptFn g_intercept = nullptr;

template <typename Fn>
void LoadFn(reaper_plugin_info_t* rec, const char* name, Fn*& slot) {
  if (!rec || !rec->GetFunc) return;
  slot = reinterpret_cast<Fn*>(rec->GetFunc(name));
}

}  // namespace

bool Init(reaper_plugin_info_t* rec) {
  g_get_state = nullptr;
  g_get_down = nullptr;
  g_intercept = nullptr;
  LoadFn(rec, "JS_VKeys_GetState", g_get_state);
  LoadFn(rec, "JS_VKeys_GetDown", g_get_down);
  LoadFn(rec, "JS_VKeys_Intercept", g_intercept);
  return g_get_state && g_get_down;
}

bool Ready() {
  return g_get_state && g_get_down;
}

VKeysGetStateFn GetVKeysGetState() { return g_get_state; }
VKeysGetDownFn GetVKeysGetDown() { return g_get_down; }
VKeysInterceptFn GetVKeysIntercept() { return g_intercept; }

}  // namespace lee::jsapi
