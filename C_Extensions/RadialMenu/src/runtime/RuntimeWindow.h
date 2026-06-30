#pragma once

#include <memory>
#include <string>
#include <vector>

#include <windows.h>

#include "domain/ConfigTypes.h"
#include "runtime/InputHook.h"
#include "shared/ui/LeeUiTheme.h"

class ImGui_Context;

namespace lee::radial_menu {

class RuntimeWindow {
 public:
  bool is_active() const { return active_; }
  bool defer_pending() const { return input_.defer_pending(); }
  bool open_with_hotkey(double trigger_time = 0.0);
  void close();
  void dismiss_for_toggle();
  void destroy();
  void tick();
  void tick_input_hooks();
  void maybe_reload_config();

 private:
  void ensure_context();
  void invalidate_context();
  bool context_is_valid() const;
  void update_animations(double dt);
  bool should_paint() const;
  void mark_painted();
  void handle_deferred_exec();
  AppConfig& config();
  const AppConfig& config() const;

  bool active_ = false;
  bool is_pinned_ = false;
  bool show_submenu_ = false;
  bool management_mode_ = false;
  int suppress_render_ = 0;
  int hovered_sector_ = -1;
  int active_sector_ = -1;
  int clicked_sector_ = -1;
  double anchor_screen_x_ = 0;
  double anchor_screen_y_ = 0;
  std::string last_config_token_;
  std::unique_ptr<AppConfig> config_storage_;
  AppConfig mgmt_config_;
  FullConfig full_for_mgmt_;
  std::vector<std::string> mgmt_preset_names_;
  ImGui_Context* ctx_ = nullptr;
  lee::ui::ThemeFonts theme_fonts_{};
  InputHook input_;
  bool defer_key_ = false;
  float anim_open_ = 0.f;
  double last_tick_time_ = 0;
  std::vector<float> sector_expand_;
  bool drag_slot_active_ = false;
  Slot drag_slot_{};
  LARGE_INTEGER last_paint_qpc_{};
  bool last_paint_valid_ = false;
  bool native_warmed_ = false;
  bool in_tick_ = false;
  bool frame_open_ = false;
  bool context_release_pending_ = false;
  void force_reset_config();
};

RuntimeWindow& GetRuntimeWindow();

}  // namespace lee::radial_menu
