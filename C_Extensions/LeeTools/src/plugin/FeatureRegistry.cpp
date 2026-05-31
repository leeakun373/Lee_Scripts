#include "plugin/FeatureRegistry.h"

#include "features/drop_station/Register.h"
#include "features/item_hub/Register.h"

namespace lee {

void RegisterAllFeatures() {
  drop_station::Register();
  item_hub::Register();
}

void ShutdownAllFeatures() {
  item_hub::Shutdown();
  drop_station::Shutdown();
}

}  // namespace lee
