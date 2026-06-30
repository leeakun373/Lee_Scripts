#include "domain/ConfigStore.h"

#include <cstdio>
#include <ctime>
#include <fstream>
#include <sstream>

#include <json.hpp>

#include "domain/ConfigDefaults.h"
#include "plugin/PluginContext.h"
#include "shared/UiNotify.h"

namespace lee::radial_menu {
namespace {

using json = nlohmann::json;

int SafeJsonInt(const json& j, int fallback) {
  if (j.is_number_integer()) return j.get<int>();
  if (j.is_number_unsigned()) return static_cast<int>(j.get<unsigned>());
  if (j.is_number_float()) return static_cast<int>(j.get<double>());
  return fallback;
}

Rgba ParseRgba(const json& j, Rgba fallback) {
  if (!j.is_array() || j.size() < 3) return fallback;
  Rgba c = fallback;
  c.r = SafeJsonInt(j[0], c.r);
  c.g = SafeJsonInt(j[1], c.g);
  c.b = SafeJsonInt(j[2], c.b);
  if (j.size() >= 4) c.a = SafeJsonInt(j[3], c.a);
  return c;
}

json RgbaToJson(const Rgba& c) {
  return json::array({c.r, c.g, c.b, c.a});
}

Slot ParseSlot(const json& j) {
  Slot s;
  if (!j.is_object()) return s;
  s.type = j.value("type", "empty");
  s.name = j.value("name", "");
  if (j.contains("data") && j["data"].is_object()) {
    const auto& d = j["data"];
    if (d.contains("command_id")) {
      if (d["command_id"].is_number_integer()) {
        s.command_id = d["command_id"].get<int>();
      } else if (d["command_id"].is_string()) {
        s.command_name = d["command_id"].get<std::string>();
      }
    }
    s.fx_name = d.value("fx_name", "");
    s.path = d.value("path", "");
  }
  if (s.fx_name.empty() && j.contains("fx_name")) s.fx_name = j["fx_name"].get<std::string>();
  if (s.path.empty() && j.contains("path")) s.path = j["path"].get<std::string>();
  if (s.command_id == 0 && s.command_name.empty() && j.contains("command_id")) {
    if (j["command_id"].is_number()) {
      s.command_id = j["command_id"].get<int>();
    } else if (j["command_id"].is_string()) {
      s.command_name = j["command_id"].get<std::string>();
    }
  }
  return s;
}

json SlotToJson(const Slot& s) {
  json j;
  j["type"] = s.type;
  if (!s.name.empty()) j["name"] = s.name;
  json d = json::object();
  if (s.type == "action") {
    if (!s.command_name.empty()) {
      d["command_id"] = s.command_name;
    } else {
      d["command_id"] = s.command_id;
    }
  }
  if (s.type == "fx") d["fx_name"] = s.fx_name;
  if (s.type == "chain" || s.type == "template") d["path"] = s.path;
  if (!d.empty()) j["data"] = d;
  return j;
}

Sector ParseSector(const json& j) {
  Sector sec;
  if (!j.is_object()) return sec;
  sec.id = j.value("id", 0);
  sec.name = j.value("name", "");
  sec.icon = j.value("icon", "");
  sec.color = ParseRgba(j["color"], sec.color);
  if (j.contains("slots") && j["slots"].is_array()) {
    for (const auto& sl : j["slots"]) sec.slots.push_back(ParseSlot(sl));
  }
  return sec;
}

json SectorToJson(const Sector& sec) {
  json j;
  j["id"] = sec.id;
  j["name"] = sec.name;
  j["icon"] = sec.icon;
  j["color"] = RgbaToJson(sec.color);
  json slots = json::array();
  for (const auto& s : sec.slots) slots.push_back(SlotToJson(s));
  j["slots"] = slots;
  return j;
}

AppConfig ParseAppConfig(const json& j) {
  AppConfig c = MakeDefaultAppConfig();
  if (!j.is_object()) return c;
  c.version = j.value("version", kConfigSchemaVersion);
  if (j.contains("menu") && j["menu"].is_object()) {
    const auto& m = j["menu"];
    c.menu.outer_radius = m.value("outer_radius", c.menu.outer_radius);
    c.menu.inner_radius = m.value("inner_radius", c.menu.inner_radius);
    c.menu.sector_border_width = m.value("sector_border_width", c.menu.sector_border_width);
    c.menu.hover_brightness = m.value("hover_brightness", c.menu.hover_brightness);
    c.menu.animation_speed = m.value("animation_speed", c.menu.animation_speed);
    c.menu.max_slots_per_sector = m.value("max_slots_per_sector", c.menu.max_slots_per_sector);
    c.menu.hover_to_open = m.value("hover_to_open", c.menu.hover_to_open);
    c.menu.enable_sector_expansion = m.value("enable_sector_expansion", c.menu.enable_sector_expansion);
    c.menu.hover_expansion_pixels = m.value("hover_expansion_pixels", c.menu.hover_expansion_pixels);
    c.menu.hover_animation_speed = m.value("hover_animation_speed", c.menu.hover_animation_speed);
    c.menu.slot_width = m.value("slot_width", c.menu.slot_width);
    c.menu.slot_height = m.value("slot_height", c.menu.slot_height);
    c.menu.submenu_width = m.value("submenu_width", c.menu.submenu_width);
    c.menu.submenu_height = m.value("submenu_height", c.menu.submenu_height);
    c.menu.submenu_gap = m.value("submenu_gap", c.menu.submenu_gap);
    c.menu.submenu_padding = m.value("submenu_padding", c.menu.submenu_padding);
    if (m.contains("animation") && m["animation"].is_object()) {
      const auto& a = m["animation"];
      c.menu.anim_enable = a.value("enable", c.menu.anim_enable);
      c.menu.duration_open = a.value("duration_open", c.menu.duration_open);
      c.menu.duration_submenu = a.value("duration_submenu", c.menu.duration_submenu);
    }
  }
  if (j.contains("colors") && j["colors"].is_object()) {
    const auto& col = j["colors"];
    c.colors.background = ParseRgba(col["background"], c.colors.background);
    c.colors.center_circle = ParseRgba(col["center_circle"], c.colors.center_circle);
    c.colors.border = ParseRgba(col["border"], c.colors.border);
    c.colors.hover_overlay = ParseRgba(col["hover_overlay"], c.colors.hover_overlay);
    c.colors.text = ParseRgba(col["text"], c.colors.text);
    c.colors.text_shadow = ParseRgba(col["text_shadow"], c.colors.text_shadow);
  }
  if (j.contains("sectors") && j["sectors"].is_array()) {
    c.sectors.clear();
    for (const auto& s : j["sectors"]) c.sectors.push_back(ParseSector(s));
  }
  if (j.contains("debug") && j["debug"].is_object()) {
    c.show_perf_hud = j["debug"].value("show_perf_hud", false);
  }
  return c;
}

json AppConfigToJson(const AppConfig& c) {
  json j;
  j["version"] = c.version;
  j["menu"] = {
      {"outer_radius", c.menu.outer_radius},
      {"inner_radius", c.menu.inner_radius},
      {"sector_border_width", c.menu.sector_border_width},
      {"hover_brightness", c.menu.hover_brightness},
      {"animation_speed", c.menu.animation_speed},
      {"max_slots_per_sector", c.menu.max_slots_per_sector},
      {"hover_to_open", c.menu.hover_to_open},
      {"enable_sector_expansion", c.menu.enable_sector_expansion},
      {"hover_expansion_pixels", c.menu.hover_expansion_pixels},
      {"hover_animation_speed", c.menu.hover_animation_speed},
      {"slot_width", c.menu.slot_width},
      {"slot_height", c.menu.slot_height},
      {"submenu_width", c.menu.submenu_width},
      {"submenu_height", c.menu.submenu_height},
      {"submenu_gap", c.menu.submenu_gap},
      {"submenu_padding", c.menu.submenu_padding},
      {"animation",
       {{"enable", c.menu.anim_enable},
        {"duration_open", c.menu.duration_open},
        {"duration_submenu", c.menu.duration_submenu}}}};
  j["colors"] = {{"background", RgbaToJson(c.colors.background)},
                 {"center_circle", RgbaToJson(c.colors.center_circle)},
                 {"border", RgbaToJson(c.colors.border)},
                 {"hover_overlay", RgbaToJson(c.colors.hover_overlay)},
                 {"text", RgbaToJson(c.colors.text)},
                 {"text_shadow", RgbaToJson(c.colors.text_shadow)}};
  json sectors = json::array();
  for (const auto& s : c.sectors) sectors.push_back(SectorToJson(s));
  j["sectors"] = sectors;
  j["debug"] = {{"show_perf_hud", c.show_perf_hud}};
  return j;
}

// Extract a top-level JSON object value for |key| without parsing sibling keys (e.g. presets).
std::string ExtractJsonObjectForKey(const std::string& text, const char* key) {
  if (!key || !key[0]) return {};
  const std::string needle = std::string("\"") + key + "\"";
  const size_t key_pos = text.find(needle);
  if (key_pos == std::string::npos) return {};
  size_t brace = text.find('{', key_pos + needle.size());
  if (brace == std::string::npos) return {};
  int depth = 0;
  bool in_string = false;
  bool escape = false;
  for (size_t i = brace; i < text.size(); ++i) {
    const char c = text[i];
    if (in_string) {
      if (escape) {
        escape = false;
      } else if (c == '\\') {
        escape = true;
      } else if (c == '"') {
        in_string = false;
      }
      continue;
    }
    if (c == '"') {
      in_string = true;
      continue;
    }
    if (c == '{') {
      ++depth;
    } else if (c == '}') {
      --depth;
      if (depth == 0) return text.substr(brace, i - brace + 1);
    }
  }
  return {};
}

void SplitTextLines(const std::string& text, std::vector<std::string>& out) {
  out.clear();
  std::string t = text;
  size_t pos = 0;
  while ((pos = t.find("\\n")) != std::string::npos) {
    t.replace(pos, 2, "\n");
  }
  std::istringstream ss(t);
  std::string line;
  while (std::getline(ss, line)) out.push_back(line);
}

}  // namespace

ConfigStore& ConfigStore::Instance() {
  static ConfigStore inst;
  return inst;
}

std::string ConfigStore::ConfigFilePath() const {
  const auto& api = lee::Api();
  const char* resource_path = api.GetResourcePath ? api.GetResourcePath() : nullptr;
  std::string base = resource_path ? resource_path : "";
  if (!base.empty() && base.back() != '\\' && base.back() != '/') base += "/";
  return base + "Scripts/Lee_Scripts/RadialMenu_Tool/config.json";
}

void ConfigStore::PreprocessSectorText(AppConfig& cfg) {
  for (auto& sec : cfg.sectors) {
    SplitTextLines(sec.name, sec.cached_lines);
  }
}

void ConfigStore::MergeWithDefaults(AppConfig& cfg) {
  AppConfig def = MakeDefaultAppConfig();
  if (cfg.version.empty()) cfg.version = def.version;
  if (cfg.sectors.empty()) cfg.sectors = def.sectors;
}

bool ConfigStore::Validate(const AppConfig& cfg, std::string& err) const {
  if (cfg.sectors.empty()) {
    err = "至少需要一个扇区";
    return false;
  }
  for (const auto& sec : cfg.sectors) {
    for (const auto& sl : sec.slots) {
      if (sl.type != "action" && sl.type != "fx" && sl.type != "chain" && sl.type != "template" &&
          sl.type != "empty") {
        err = "无效插槽类型: " + sl.type;
        return false;
      }
    }
  }
  return true;
}

bool ConfigStore::LoadFull(FullConfig& out) {
  auto apply_defaults = [&]() {
    out = {};
    out.active_config = MakeDefaultAppConfig();
    out.presets["Default"] = out.active_config;
    out.current_preset_name = "Default";
    PreprocessSectorText(out.active_config);
  };

  try {
    const std::string path = ConfigFilePath();
    std::ifstream in(path);
    if (!in) {
      apply_defaults();
      return true;
    }
    json root;
    in >> root;
    if (!root.is_object()) {
      apply_defaults();
      return true;
    }

    if (!root.contains("presets")) {
      out.active_config = ParseAppConfig(root);
      MergeWithDefaults(out.active_config);
      out.presets.clear();
      out.presets["Default"] = out.active_config;
      out.current_preset_name = "Default";
    } else {
      out.current_preset_name = root.value("current_preset_name", "Default");
      if (root.contains("active_config")) {
        out.active_config = ParseAppConfig(root["active_config"]);
      }
      if (root.contains("presets") && root["presets"].is_object()) {
        for (auto it = root["presets"].begin(); it != root["presets"].end(); ++it) {
          out.presets[it.key()] = ParseAppConfig(it.value());
          MergeWithDefaults(out.presets[it.key()]);
        }
      }
      if (out.presets.find(out.current_preset_name) == out.presets.end()) {
        out.current_preset_name = "Default";
      }
      if (out.presets.find("Default") == out.presets.end()) {
        out.presets["Default"] = MakeDefaultAppConfig();
      }
      MergeWithDefaults(out.active_config);
    }
    PreprocessSectorText(out.active_config);
    for (auto& p : out.presets) PreprocessSectorText(p.second);
    return true;
  } catch (...) {
    apply_defaults();
    return true;
  }
}

bool ConfigStore::LoadActive(AppConfig& out) {
  return LoadActiveOrDefault(out, nullptr);
}

bool ConfigStore::LoadActiveOnly(AppConfig& out) {
  auto fallback = [&]() -> bool {
    out = MakeDefaultAppConfig();
    MergeWithDefaults(out);
    PreprocessSectorText(out);
    return false;
  };
  try {
    const std::string path = ConfigFilePath();
    std::ifstream in(path);
    if (!in) return fallback();
    std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());

    std::string active_json = ExtractJsonObjectForKey(content, "active_config");
    json cfg_json;
    if (!active_json.empty()) {
      cfg_json = json::parse(active_json);
    } else {
      cfg_json = json::parse(content);
    }
    if (!cfg_json.is_object()) return fallback();
    out = ParseAppConfig(cfg_json);
    MergeWithDefaults(out);
    std::string err;
    if (!Validate(out, err)) return fallback();
    PreprocessSectorText(out);
    return true;
  } catch (...) {
    return fallback();
  }
}

bool ConfigStore::LoadActiveOrDefault(AppConfig& out, std::string* warn) {
  FullConfig full;
  if (!LoadFull(full)) {
    if (warn) *warn = "无法加载 config.json";
    out = MakeDefaultAppConfig();
    PreprocessSectorText(out);
    return false;
  }
  out = full.active_config;
  std::string err;
  if (!Validate(out, err)) {
    if (warn) *warn = err;
    out = MakeDefaultAppConfig();
    MergeWithDefaults(out);
    PreprocessSectorText(out);
    return false;
  }
  return true;
}

bool ConfigStore::RenamePreset(FullConfig& full, const std::string& old_name,
                               const std::string& new_name, std::string& err) {
  if (old_name.empty() || new_name.empty()) {
    err = "预设名称不能为空";
    return false;
  }
  if (old_name == "Default") {
    err = "不能重命名 Default 预设";
    return false;
  }
  if (full.presets.find(old_name) == full.presets.end()) {
    err = "预设不存在";
    return false;
  }
  if (full.presets.find(new_name) != full.presets.end()) {
    err = "目标名称已存在";
    return false;
  }
  full.presets[new_name] = full.presets[old_name];
  full.presets.erase(old_name);
  if (full.current_preset_name == old_name) full.current_preset_name = new_name;
  return true;
}

bool ConfigStore::DeletePreset(FullConfig& full, const std::string& name, std::string& err) {
  if (name.empty()) {
    err = "预设名称不能为空";
    return false;
  }
  if (name == "Default") {
    err = "不能删除 Default 预设";
    return false;
  }
  if (full.presets.find(name) == full.presets.end()) {
    err = "预设不存在";
    return false;
  }
  full.presets.erase(name);
  if (full.current_preset_name == name) {
    full.current_preset_name = "Default";
    auto it = full.presets.find("Default");
    if (it != full.presets.end()) full.active_config = it->second;
  }
  return true;
}

bool ConfigStore::SaveFull(const FullConfig& full) {
  json root;
  root["current_preset_name"] = full.current_preset_name;
  root["active_config"] = AppConfigToJson(full.active_config);
  json presets = json::object();
  for (const auto& p : full.presets) presets[p.first] = AppConfigToJson(p.second);
  root["presets"] = presets;
  const std::string path = ConfigFilePath();
  std::ofstream out(path);
  if (!out) return false;
  out << root.dump(2);
  return true;
}

bool ConfigStore::SaveActive(const AppConfig& cfg) {
  FullConfig full;
  if (!LoadFull(full)) {
    full.active_config = cfg;
    full.presets["Default"] = cfg;
    full.current_preset_name = "Default";
  } else {
    full.active_config = cfg;
    auto it = full.presets.find(full.current_preset_name);
    if (it != full.presets.end()) it->second = cfg;
  }
  std::string err;
  if (!Validate(cfg, err)) {
    ShowUserMessage(err.c_str(), "Lee RadialMenu Setup");
    return false;
  }
  if (!SaveFull(full)) {
    ShowUserMessage("无法写入 config.json，请检查路径与权限。", "Lee RadialMenu Setup");
    return false;
  }
  NotifyConfigUpdated();
  return true;
}

void ConfigStore::NotifyConfigUpdated() {
  const auto& api = lee::Api();
  if (!api.SetExtState) return;
  const auto now = static_cast<long long>(time(nullptr));
  api.SetExtState("RadialMenu", "ConfigUpdated", std::to_string(now).c_str(), false);
}

std::string ConfigStore::LastConfigUpdateToken() const {
  const char* v = lee::GetExtState("RadialMenu", "ConfigUpdated");
  return v ? v : "";
}

}  // namespace lee::radial_menu
