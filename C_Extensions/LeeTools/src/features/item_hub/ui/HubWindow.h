#pragma once

#include <vector>

#include "shared/ui/LeeUiTheme.h"

class ImGui_Context;

namespace lee::item_hub {

class HubWindow {
 public:
  bool is_active() const { return active_; }
  bool open_at_cursor(void* proj);
  void close();
  void destroy();
  void tick();

 private:
  void ensure_context();
  void destroy_context();
  void invalidate_context();
  void draw_ui();
  void draw_category_column();
  void draw_param_column();

  // Snapshot the physical keys held at open time so the timer loop can close
  // the window once the user lets go (REAPER provides no key-release callback).
  void capture_trigger_keys();
  bool trigger_released() const;

  bool active_ = false;
  ImGui_Context* ctx_ = nullptr;
  lee::ui::ThemeFonts theme_fonts_{};
  bool was_focused_ = false;
  bool first_frame_ = false;
  std::vector<int> trigger_keys_;
};

HubWindow& GetHubWindow();

}  // namespace lee::item_hub
