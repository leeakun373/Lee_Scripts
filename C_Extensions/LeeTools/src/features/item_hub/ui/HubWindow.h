#pragma once

#include <vector>

#include <windows.h>

#include "shared/ui/LeeUiTheme.h"

class ImGui_Context;

namespace lee::item_hub {

class HubWindow {
 public:
  bool is_active() const { return active_; }
  void prepare();
  bool open_at_cursor(void* proj);
  void close();
  void destroy();
  void tick();

 private:
  void ensure_context();
  void destroy_context();
  void invalidate_context();
  void draw_idle_hidden();
  void paint_idle_frame();
  void warm_native_window_once();
  void draw_ui();
  void draw_hub_content();
  void draw_category_column();
  void draw_param_column();

  void capture_trigger_keys();
  bool trigger_released() const;
  bool should_skip_paint() const;
  void mark_painted();

  void refresh_hub_size();
  void apply_hub_window_size() const;
  int hub_window_flags(bool idle) const;

  bool active_ = false;
  bool begin_retry_pending_ = false;
  ImGui_Context* ctx_ = nullptr;
  lee::ui::ThemeFonts theme_fonts_{};
  bool was_focused_ = false;
  bool first_frame_ = false;
  bool anchor_valid_ = false;
  bool native_warmed_ = false;
  int category_pulse_ = 0;
  double anchor_x_ = 0.0;
  double anchor_y_ = 0.0;
  double cached_w_ = 0.0;
  double cached_h_ = 0.0;
  LARGE_INTEGER last_paint_qpc_{};
  bool last_paint_qpc_valid_ = false;
  std::vector<int> trigger_keys_;
};

HubWindow& GetHubWindow();

}  // namespace lee::item_hub
