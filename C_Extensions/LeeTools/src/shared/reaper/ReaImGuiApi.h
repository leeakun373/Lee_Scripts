#pragma once

#include "reaper_plugin.h"

namespace lee::reaimgui {

// One-time init of the ReaImGui C++ binding shim. Pulls every ImGui_* function
// pointer out of the host process via rec->GetFunc. Returns true if a minimal
// set of essential calls (CreateContext / DestroyContext / Begin / End) is
// available, which is the cheapest reliable signal that the user has the
// ReaImGui extension installed and loaded.
bool Init(reaper_plugin_info_t* rec);

// True if Init() succeeded earlier. Cheaper than re-resolving every call site.
bool Ready();

}  // namespace lee::reaimgui
