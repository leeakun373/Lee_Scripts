#pragma once

namespace lee::radial_menu {

class InputHook {
 public:
  bool capture_trigger_key(double script_start_time);
  void set_manual_hold_mode(bool on = true);
  bool key_held() const;
  int trigger_key() const { return key_; }
  double script_start_time() const { return start_time_; }
  void intercept(int on);
  void defer_release_until_key_up();
  bool defer_pending() const { return defer_pending_; }
  void tick_defer();
  void tick_pending_intercept_release();
  void reset();
  void reset_local_state_only();

 private:
  bool try_capture_at(double script_start_time);

  int key_ = 0;
  double start_time_ = 0;
  bool defer_pending_ = false;
  bool manual_hold_ = false;
  bool pending_intercept_ = false;
  int pending_intercept_key_ = 0;
  int pending_intercept_on_ = 0;
  void schedule_intercept(int vk, int on);
};

}  // namespace lee::radial_menu
