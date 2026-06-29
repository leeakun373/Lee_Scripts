#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace lee::radial_menu {

struct Rgba {
  int r = 255, g = 255, b = 255, a = 255;
};

struct MenuSettings {
  double outer_radius = 115;
  double inner_radius = 55;
  int sector_border_width = 2;
  double hover_brightness = 1.3;
  double animation_speed = 0.2;
  int max_slots_per_sector = 12;
  bool hover_to_open = true;
  bool enable_sector_expansion = true;
  double hover_expansion_pixels = 4;
  int hover_animation_speed = 8;
  double slot_width = 65;
  double slot_height = 25;
  double submenu_width = 250;
  double submenu_height = 150;
  double submenu_gap = 3;
  double submenu_padding = 10;
  bool anim_enable = false;
  double duration_open = 0.06;
  double duration_submenu = 0.05;
};

struct ColorPalette {
  Rgba background{30, 30, 30, 240};
  Rgba center_circle{50, 50, 50, 255};
  Rgba border{100, 100, 100, 200};
  Rgba hover_overlay{255, 255, 255, 50};
  Rgba text{255, 255, 255, 255};
  Rgba text_shadow{0, 0, 0, 150};
};

struct Slot {
  std::string type = "empty";
  std::string name;
  int command_id = 0;
  std::string command_name;  // named command id string (NamedCommandLookup)
  std::string fx_name;
  std::string path;
};

struct Sector {
  int id = 0;
  std::string name;
  std::string icon;
  Rgba color{100, 100, 100, 200};
  std::vector<Slot> slots;
  std::vector<std::string> cached_lines;
};

struct AppConfig {
  std::string version = "1.1.14";
  MenuSettings menu;
  ColorPalette colors;
  std::vector<Sector> sectors;
  bool show_perf_hud = false;
};

struct FullConfig {
  AppConfig active_config;
  std::unordered_map<std::string, AppConfig> presets;
  std::string current_preset_name = "Default";
};

}  // namespace lee::radial_menu
