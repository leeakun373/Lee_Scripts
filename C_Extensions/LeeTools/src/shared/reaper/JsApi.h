#pragma once

#include "reaper_plugin.h"

namespace lee::jsapi {

bool Init(reaper_plugin_info_t* rec);
bool Ready();

// Native JS_ReaScriptAPI signatures. These differ from the Lua wrappers:
// GetState/GetDown write a 255-byte result into the caller-provided buffer.
using VKeysGetStateFn = void (*)(double time, char* state_out, int state_out_size);
using VKeysGetDownFn = void (*)(double time, char* state_out, int state_out_size);
using VKeysInterceptFn = int (*)(int key, int intercept);

VKeysGetStateFn GetVKeysGetState();
VKeysGetDownFn GetVKeysGetDown();
VKeysInterceptFn GetVKeysIntercept();

}  // namespace lee::jsapi
