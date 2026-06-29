#include "domain/ConfigDefaults.h"

namespace lee::radial_menu {

AppConfig MakeDefaultAppConfig() {
  AppConfig c;
  c.version = kConfigSchemaVersion;
  c.sectors = {
      {1, "Actions", "!", {70, 130, 180, 200}, {}},
      {2, "FX", "P", {138, 43, 226, 200}, {}},
      {3, "View", "j", {34, 139, 34, 200}, {}},
  };
  return c;
}

}  // namespace lee::radial_menu
