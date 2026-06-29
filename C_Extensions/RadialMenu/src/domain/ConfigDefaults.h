#pragma once

#include "domain/ConfigTypes.h"

namespace lee::radial_menu {

inline constexpr const char* kConfigSchemaVersion = "1.1.14";

AppConfig MakeDefaultAppConfig();

}  // namespace lee::radial_menu
