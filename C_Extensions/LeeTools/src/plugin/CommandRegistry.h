#pragma once

#include "reaper_plugin.h"

namespace lee {

using ActionCallback = void (*)();

bool RegisterCustomAction(const char* id, const char* desc, ActionCallback callback);
bool InstallAllActions(reaper_plugin_info_t* rec);
void UninstallAllActions();

}  // namespace lee
