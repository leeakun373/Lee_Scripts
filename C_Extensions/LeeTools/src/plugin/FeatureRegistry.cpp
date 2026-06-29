#include "plugin/FeatureRegistry.h"

#include "features/drop_station/Register.h"
#include "features/item_hub/Register.h"
#include "features/project_explorer/Register.h"
#include "features/splitter/Register.h"
#include "Register.h"

namespace lee {

void RegisterAllFeatures() {
  drop_station::Register();
  item_hub::Register();
  project_explorer::Register();
  splitter::Register();
  radial_menu::Register();
}

void ShutdownAllFeatures() {
  radial_menu::Shutdown();
  splitter::Shutdown();
  project_explorer::Shutdown();
  item_hub::Shutdown();
  drop_station::Shutdown();
}

}  // namespace lee
