#pragma once

#include <string>

#include "features/splitter/domain/BatchJob.h"
#include "features/splitter/domain/Prefs.h"
#include "features/splitter/domain/PreviewPlayer.h"
#include "features/splitter/domain/Selection.h"
#include "features/splitter/domain/SplitParams.h"
#include "shared/ui/LeeUiTheme.h"

class ImGui_Context;

namespace lee::splitter {

class SplitterWindow {
 public:
  bool is_open() const { return open_; }
  void open();
  void close();
  void destroy();
  void tick();

 private:
  void ensure_context();
  void invalidate_context();
  void draw_ui();
  void draw_header();
  void draw_status_bar();
  void draw_algorithm_panel();
  void draw_quick_panel();
  void draw_footer(bool& stay_open);
  void refresh_selection();
  void update_idle_status();
  void apply_window_size();
  void start_algorithm_process();
  void start_quick(QuickPreset preset);
  void cancel_all();
  bool drag_param(const char* label, double* v, double vmin, double vmax, const char* fmt);
  bool drag_param_int(const char* label, int* v, int vmin, int vmax);

  bool open_ = false;
  ImGui_Context* ctx_ = nullptr;
  lee::ui::ThemeFonts theme_fonts_{};
  void* proj_ = nullptr;

  Prefs prefs_;
  SplitParams params_;
  SelectionInfo selection_;
  BatchJob job_;
  PreviewPlayer preview_;

  std::string status_text_;
  int status_color_ = 0;  // 0=default, 1=green, 2=red
  bool advanced_mapped_ = false;
  double win_w_ = 400.0;
  double win_h_ = 420.0;
};

SplitterWindow& GetSplitterWindow();

}  // namespace lee::splitter
