#pragma once

#include <string>

#include "domain/ConfigTypes.h"

namespace lee::radial_menu {

class ConfigStore {
 public:
  static ConfigStore& Instance();

  std::string ConfigFilePath() const;
  bool LoadActive(AppConfig& out);
  bool LoadFull(FullConfig& out);
  bool SaveActive(const AppConfig& cfg);
  bool SaveFull(const FullConfig& full);
  void NotifyConfigUpdated();
  std::string LastConfigUpdateToken() const;

  void PreprocessSectorText(AppConfig& cfg);
  void MergeWithDefaults(AppConfig& cfg);
  bool Validate(const AppConfig& cfg, std::string& err) const;

  bool LoadActiveOrDefault(AppConfig& out, std::string* warn = nullptr);
  // Runtime hotkey path: parse file once but only build active_config (skip presets map).
  bool LoadActiveOnly(AppConfig& out);
  bool RenamePreset(FullConfig& full, const std::string& old_name, const std::string& new_name,
                    std::string& err);
  bool DeletePreset(FullConfig& full, const std::string& name, std::string& err);

 private:
  ConfigStore() = default;
};

}  // namespace lee::radial_menu
