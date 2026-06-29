#pragma once

#include "reaper_plugin.h"

namespace lee::jsapi {

bool Init(reaper_plugin_info_t* rec);
bool Ready();

using VKeysGetStateFn = const char* (*)(double time);
using VKeysGetDownFn = const char* (*)(double time);
using VKeysInterceptFn = void (*)(int key, int intercept);

VKeysGetStateFn GetVKeysGetState();
VKeysGetDownFn GetVKeysGetDown();
VKeysInterceptFn GetVKeysIntercept();

}  // namespace lee::jsapi
