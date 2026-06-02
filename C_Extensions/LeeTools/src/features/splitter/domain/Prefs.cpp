#include "features/splitter/domain/Prefs.h"

#include <cstring>

#include "plugin/PluginContext.h"

namespace lee::splitter {

namespace {
constexpr const char* kSection = "Lee_Splitter";
}

void Prefs::load() {
  const char* ui = lee::GetExtState(kSection, "ui_mode");
  quick_mode = (ui && std::strcmp(ui, "quick") == 0);

  const char* mode = lee::GetExtState(kSection, "algo_mode");
  algo_mode = AlgoModeFromKey(mode);

  const char* route = lee::GetExtState(kSection, "route_to_track");
  route_to_track = (route && route[0] == '1');
}

void Prefs::save() const {
  const auto& api = lee::Api();
  if (!api.SetExtState) return;
  api.SetExtState(kSection, "ui_mode", quick_mode ? "quick" : "algo", true);
  api.SetExtState(kSection, "algo_mode", AlgoModeKey(algo_mode), true);
  api.SetExtState(kSection, "route_to_track", route_to_track ? "1" : "0", true);
}

}  // namespace lee::splitter
