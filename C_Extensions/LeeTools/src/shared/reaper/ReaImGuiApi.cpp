// IMPORTANT: This is the only translation unit that defines the storage for
// the ReaImGui binding function pointers. Everywhere else just sees them as
// `extern` declarations from reaper_imgui_functions.h.
#define REAIMGUIAPI_IMPLEMENT
#include "reaper_imgui_functions.h"

#include "shared/reaper/ReaImGuiApi.h"

#include "plugin/PluginContext.h"

namespace lee::reaimgui {

namespace {

bool g_ready = false;

}  // namespace

bool Init(reaper_plugin_info_t* rec) {
  g_ready = false;
  if (!rec || !rec->GetFunc) {
    return false;
  }
  // ImGui::init() throws ImGui_Error if ReaImGui isn't installed or is older
  // than this header expects (any required enum/function missing). We swallow
  // that here and just report "not ready" so the rest of the DLL can still
  // load -- Drop Station becomes inert but Lee_StartOSDragDrop etc. keep
  // working.
  try {
    ImGui::init(rec->GetFunc);
  } catch (const ImGui_Error&) {
    lee::DebugLog(L"ReaImGui not available (extension not installed or too old)");
    return false;
  } catch (...) {
    lee::DebugLog(L"ReaImGui init threw an unknown exception");
    return false;
  }
  // ReaImGui owns context lifetime via internal GC -- contexts that aren't
  // touched for a few seconds are released automatically. So we only require
  // the calls we actually need every frame.
  if (!ImGui::CreateContext || !ImGui::Begin || !ImGui::End) {
    lee::DebugLog(L"ReaImGui essential entry points are missing");
    return false;
  }
  g_ready = true;
  return true;
}

bool Ready() {
  return g_ready;
}

}  // namespace lee::reaimgui
