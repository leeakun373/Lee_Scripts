#pragma once

#include "features/item_hub/domain/ParamSpec.h"

namespace lee::item_hub {

struct SessionData;

class Session {
 public:
  bool begin(void* proj);
  void end();
  bool active() const { return active_; }
  bool multi() const { return multi_; }

  Category category() const { return category_; }
  void set_category(Category c);
  void next_category(int delta);

  bool param_enabled(ParamId id) const;
  void format_value(ParamId id, char* buf, size_t buf_size) const;
  double normalized_value(ParamId id) const;

  void adjust_param(ParamId id, double delta, bool fine);
  void reset_param(ParamId id);
  void click_param(ParamId id);
  void on_param_drag_start(ParamId id);

  void tick(bool window_focused);

 private:
  void capture_selection(void* proj);
  void apply_randomize(ParamId id);
  void apply_item_gap();
  void apply_batch_trim(double target_len);

  bool active_ = false;
  bool multi_ = false;
  bool undo_open_ = false;
  void* proj_ = nullptr;
  Category category_ = Category::GainPitch;
  SessionData* data_ = nullptr;
};

Session& GetSession();

}  // namespace lee::item_hub
