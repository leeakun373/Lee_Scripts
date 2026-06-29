#include "reaper_plugin.h"

#include "plugin/CommandRegistry.h"
#include "plugin/FeatureRegistry.h"
#include "plugin/PluginContext.h"
#include "shared/reaper/JsApi.h"
#include "shared/reaper/ReaImGuiApi.h"

extern "C" REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE hInst,
                                                                 reaper_plugin_info_t* rec) {
  if (!rec) {
    lee::ShutdownAllFeatures();
    lee::UninstallAllActions();
    lee::ShutdownPluginApi();
    return 0;
  }

  if (rec->caller_version != REAPER_PLUGIN_VERSION) {
    return 0;
  }

  if (!lee::InitPluginApi(rec)) {
    return 0;
  }
  lee::SetDllHInstance(hInst);

  lee::reaimgui::Init(rec);
  lee::jsapi::Init(rec);

  lee::RegisterAllFeatures();

  if (!lee::InstallAllActions(rec)) {
    lee::ShutdownAllFeatures();
    lee::UninstallAllActions();
    lee::ShutdownPluginApi();
    return 0;
  }

  return 1;
}
