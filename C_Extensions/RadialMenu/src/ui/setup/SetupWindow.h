#pragma once

#include <string>
#include <unordered_map>
#include <vector>

#include "domain/ConfigTypes.h"
#include "shared/ui/LeeUiTheme.h"

class ImGui_Context;

namespace lee::radial_menu {

class SetupWindow {
 public:
  bool is_open() const { return open_; }
  void open();
  void close();
  void destroy();
  void tick();

 private:
  bool context_is_valid() const;
  void ensure_context();
  void draw_ui();
  void draw_action_bar();
  void draw_preview_column();
  void draw_editor_column();
  void draw_grid();
  void draw_inspector();
  void draw_browser();
  void adjust_sector_count(int new_count);
  void push_setup_theme(int& colors, int& vars);
  void pop_setup_theme(int colors, int vars);
  bool save();
  bool try_close_with_confirm();
  void discard_with_confirm();
  void reset_to_default_with_confirm();
  void rename_sectors_for_language();
  void draw_new_preset_modal();
  static void ApplyActionPayload(Slot& sl, const char* payload);
  static void ApplyFxPayload(Slot& sl, const char* payload);

  bool open_ = false;
  ImGui_Context* ctx_ = nullptr;
  lee::ui::ThemeFonts theme_fonts_{};
  bool native_warmed_ = false;
  FullConfig full_;
  AppConfig edit_;
  AppConfig original_;
  int selected_sector_ = 0;
  int selected_slot_ = -1;
  bool browser_tab_seen_ = false;
  char search_actions_[128] = {};
  char search_fx_[128] = {};
  char rename_buf_[128] = {};
  char new_preset_name_[128] = {};
  int new_preset_mode_ = 0;
  bool show_new_preset_modal_ = false;
  std::string fx_filter_ = "All";
  bool dirty_ = false;
  bool in_tick_ = false;
  bool pending_close_confirm_ = false;
  double save_feedback_time_ = 0;
  int browser_tab_ = 0;
  int browser_tab_prev_ = -1;
  bool focus_search_actions_ = false;
  bool focus_search_fx_ = false;
  int selected_browser_action_id_ = 0;
  std::unordered_map<int, Sector> sector_stash_;
};

SetupWindow& GetSetupWindow();

}  // namespace lee::radial_menu
