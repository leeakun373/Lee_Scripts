#include "runtime/RuntimeWindow.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

#include "domain/ConfigDefaults.h"
#include "domain/ConfigStore.h"
#include "domain/Execution.h"
#include "domain/HitTest.h"
#include "domain/LayoutBake.h"
#include "reaper_imgui_functions.h"
#include "runtime/WheelView.h"
#include "plugin/PluginContext.h"
#include "shared/reaper/JsApi.h"
#include "shared/reaper/ReaImGuiApi.h"
#include "shared/UiNotify.h"
#include "shared/ReaImGuiCoords.h"
#include "ui/setup/SetupWindow.h"

namespace lee::radial_menu {
namespace {

RuntimeWindow g_runtime;
constexpr const char* kTitle = "RadialMenu##lee_runtime";
constexpr double kIdlePaintMs = 50.0;

void GetCursorScreen(double& x, double& y) {
  POINT p;
  GetCursorPos(&p);
  x = static_cast<double>(p.x);
  y = static_cast<double>(p.y);
}

int WindowFlags(bool interactive) {
  int f = ImGui::WindowFlags_NoDecoration | ImGui::WindowFlags_NoMove |
          ImGui::WindowFlags_NoResize | ImGui::WindowFlags_NoDocking |
          ImGui::WindowFlags_NoSavedSettings | ImGui::WindowFlags_NoFocusOnAppearing;
  if (!interactive && ImGui::WindowFlags_NoInputs) f |= ImGui::WindowFlags_NoInputs;
  return f;
}

void BuildManagementConfig(const FullConfig& full, AppConfig& c,
                           std::vector<std::string>& names_out) {
  c = full.active_config;
  c.sectors.clear();
  names_out.clear();
  names_out.push_back("__setup__");
  Sector setup_sec;
  setup_sec.id = 1;
  setup_sec.name = "Setup";
  setup_sec.icon = "!";
  setup_sec.color = {200, 120, 60, 220};
  c.sectors.push_back(setup_sec);
  int id = 2;
  for (const auto& p : full.presets) {
    names_out.push_back(p.first);
    Sector s;
    s.id = id++;
    s.name = p.first + (p.first == full.current_preset_name ? " *" : "");
    s.icon = "P";
    s.color = {80, 160, 220, 220};
    c.sectors.push_back(s);
  }
}

}  // namespace

RuntimeWindow& GetRuntimeWindow() { return g_runtime; }

AppConfig& RuntimeWindow::config() {
  if (!config_storage_) {
    config_storage_ = std::make_unique<AppConfig>(MakeDefaultAppConfig());
  }
  return *config_storage_;
}

const AppConfig& RuntimeWindow::config() const {
  return const_cast<RuntimeWindow*>(this)->config();
}

bool RuntimeWindow::context_is_valid() const {
  if (!ctx_) return false;
  if (!ImGui::ValidatePtr) return true;
  return ImGui::ValidatePtr(ctx_, "ImGui_Context*") != 0;
}

void RuntimeWindow::ensure_context() {
  if (!lee::reaimgui::Ready() || !ImGui::CreateContext) return;
  if (context_is_valid()) return;

  if (ctx_) {
    if (context_is_valid()) {
      lee::ui::DestroyFonts(ctx_, theme_fonts_);
    } else {
      theme_fonts_ = {};
    }
    DestroyImGuiContext(ctx_);
    native_warmed_ = false;
  }

  try {
    ctx_ = ImGui::CreateContext("RadialMenu_Wheel");
  } catch (...) {
    ctx_ = nullptr;
  }
  if (ctx_) lee::ui::EnsureFonts(ctx_, theme_fonts_);
}

void RuntimeWindow::invalidate_context() {
  if (ctx_ && context_is_valid()) lee::ui::DestroyFonts(ctx_, theme_fonts_);
  ctx_ = nullptr;
  theme_fonts_ = {};
  native_warmed_ = false;
  frame_open_ = false;
  context_release_pending_ = false;
}

void RuntimeWindow::destroy() {
  invalidate_context();
  active_ = false;
  show_submenu_ = false;
  defer_key_ = false;
  config_storage_.reset();
  input_.reset();
  input_.tick_pending_intercept_release();
  const auto& api = lee::Api();
  if (api.SetExtState) api.SetExtState("RadialMenu_Tool", "Running", "0", false);
}

void RuntimeWindow::maybe_reload_config() {
  const std::string tok = ConfigStore::Instance().LastConfigUpdateToken();
  if (!tok.empty() && tok != last_config_token_) {
    (void)ConfigStore::Instance().LoadActiveOnly(config());
    last_config_token_ = tok;
    sector_expand_.assign(config().sectors.size(), 0.f);
  }
}

void RuntimeWindow::force_reset_config() {
  config_storage_ = std::make_unique<AppConfig>(MakeDefaultAppConfig());
  sector_expand_.clear();
}

bool RuntimeWindow::open_with_hotkey(double trigger_time) {
  if (active_ && !context_is_valid()) {
    active_ = false;
    show_submenu_ = false;
    input_.reset();
    input_.tick_pending_intercept_release();
    invalidate_context();
  }
  const char* running = lee::GetExtState("RadialMenu_Tool", "Running");
  if (running && running[0] == '1') return false;

  if (!lee::jsapi::Ready()) {
    const auto& api = lee::Api();
    if (api.ShowMessageBox) {
      api.ShowMessageBox(
          "RadialMenu 需要 JS_ReaScriptAPI 扩展（JS_VKeys）。\n请安装后重启 REAPER。",
          "Lee RadialMenu", 0);
    }
    return false;
  }

  defer_key_ = false;

  const auto& api = lee::Api();
  if (trigger_time <= 0) trigger_time = api.time_precise ? api.time_precise() : 0.0;

  if (!input_.capture_trigger_key(trigger_time)) {
    input_.set_manual_hold_mode(true);
  }

  force_reset_config();
  (void)ConfigStore::Instance().LoadActiveOnly(config());
  ConfigStore::Instance().MergeWithDefaults(config());
  ConfigStore::Instance().PreprocessSectorText(config());
  sector_expand_.assign(config().sectors.size(), 0.f);
  last_config_token_ = ConfigStore::Instance().LastConfigUpdateToken();

  if (api.SetExtState) api.SetExtState("RadialMenu_Tool", "Running", "1", false);

  GetCursorScreen(anchor_screen_x_, anchor_screen_y_);
  // Defer ImGui CreateContext to TimerTick (matches reaimgui hello_world.cpp).
  last_paint_valid_ = false;
  native_warmed_ = false;
  active_ = true;
  is_pinned_ = false;
  show_submenu_ = false;
  management_mode_ = false;
  anim_open_ = 0.f;
  last_tick_time_ = api.time_precise ? api.time_precise() : 0;
  hovered_sector_ = -1;
  active_sector_ = -1;
  clicked_sector_ = -1;
  suppress_render_ = 0;
  return true;
}

void RuntimeWindow::tick_input_hooks() {
  input_.tick_pending_intercept_release();
}

void RuntimeWindow::dismiss_for_toggle() {
  active_ = false;
  show_submenu_ = false;
  defer_key_ = false;
  input_.reset();
  if (frame_open_) context_release_pending_ = true;
  else invalidate_context();
  const auto& api = lee::Api();
  if (api.SetExtState) api.SetExtState("RadialMenu_Tool", "Running", "0", false);
}

void RuntimeWindow::close() {
  if (!is_pinned_) {
    active_ = false;
    show_submenu_ = false;
    if (!defer_key_) {
      input_.reset();
      const auto& api = lee::Api();
      if (api.SetExtState) api.SetExtState("RadialMenu_Tool", "Running", "0", false);
    }
    if (frame_open_) context_release_pending_ = true;
    else invalidate_context();
  } else {
    show_submenu_ = false;
    active_sector_ = -1;
  }
}

void RuntimeWindow::update_animations(double dt) {
  if (config().menu.anim_enable) {
    const float dur = static_cast<float>(std::max(0.001, config().menu.duration_open));
    const float rate = 1.f / dur;
    if (anim_open_ < 1.f) anim_open_ = std::min(1.f, anim_open_ + static_cast<float>(dt * rate));
  } else {
    anim_open_ = 1.f;
  }
  const int n = static_cast<int>(config().sectors.size());
  if (static_cast<int>(sector_expand_.size()) != n) sector_expand_.assign(n, 0.f);
  if (!config().menu.enable_sector_expansion) {
    for (int i = 0; i < n; ++i) {
      sector_expand_[i] =
          (i == hovered_sector_ || i == active_sector_) ? 1.f : 0.f;
    }
    return;
  }
  const float k = 6.f + static_cast<float>(std::clamp(config().menu.hover_animation_speed, 1, 10) - 1) * 2.f;
  for (int i = 0; i < n; ++i) {
    const float target = (i == hovered_sector_ || i == active_sector_) ? 1.f : 0.f;
    if (target > sector_expand_[i]) {
      sector_expand_[i] += (1.f - sector_expand_[i]) * (1.f - std::exp(-k * static_cast<float>(dt)));
      if (sector_expand_[i] > 0.999f) sector_expand_[i] = 1.f;
    } else {
      sector_expand_[i] = 0.f;
    }
  }
}

bool RuntimeWindow::should_paint() const {
  if (active_) return true;
  if (!last_paint_valid_) return true;
  LARGE_INTEGER now, freq;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&now);
  const double ms =
      (now.QuadPart - last_paint_qpc_.QuadPart) * 1000.0 / static_cast<double>(freq.QuadPart);
  return ms >= kIdlePaintMs;
}

void RuntimeWindow::mark_painted() {
  QueryPerformanceCounter(&last_paint_qpc_);
  last_paint_valid_ = true;
}

void RuntimeWindow::handle_deferred_exec() {
  input_.tick_defer();
}

void RuntimeWindow::tick() {
  if (in_tick_) return;
  struct TickGuard {
    bool& flag;
    explicit TickGuard(bool& f) : flag(f) { flag = true; }
    ~TickGuard() { flag = false; }
  } guard(in_tick_);

  if (!active_ && !input_.defer_pending()) return;
  handle_deferred_exec();
  if (defer_key_ && !input_.defer_pending()) defer_key_ = false;
  if (!active_) return;

  if (const auto& api = lee::Api(); api.GetCursorContext) {
    Execution::SetLastValidContext(api.GetCursorContext());
  }

  maybe_reload_config();

  const auto& api = lee::Api();
  double now = api.time_precise ? api.time_precise() : 0;
  const double dt = std::max(0.0, now - last_tick_time_);
  last_tick_time_ = now;
  update_animations(dt);

  if (!is_pinned_ && !input_.defer_pending() && !input_.key_held()) {
    close();
    if (!active_) return;
  }

  ensure_context();
  if (!context_is_valid() || !ImGui::SetNextWindowPos || !ImGui::Begin) return;

  const AppConfig& draw_cfg = management_mode_ ? mgmt_config_ : config();
  const double diameter = draw_cfg.menu.outer_radius * 2.0 + 20.0;

  if (!should_paint() && suppress_render_ <= 0) return;

  int style_pushed = 0;
  int color_pushed = 0;
  bool font_pushed = false;
  auto pop_frame_styles = [&]() {
    if (font_pushed && ImGui::PopFont) {
      ImGui::PopFont(ctx_);
      font_pushed = false;
    }
    if (color_pushed > 0 && ImGui::PopStyleColor) {
      ImGui::PopStyleColor(ctx_, color_pushed);
      color_pushed = 0;
    }
    if (style_pushed > 0 && ImGui::PopStyleVar) {
      ImGui::PopStyleVar(ctx_, style_pushed);
      style_pushed = 0;
    }
  };

  double anchor_gui_x = anchor_screen_x_;
  double anchor_gui_y = anchor_screen_y_;
  if (!ScreenToImGui(ctx_, anchor_screen_x_, anchor_screen_y_, anchor_gui_x, anchor_gui_y)) {
    theme_fonts_ = {};
    DestroyImGuiContext(ctx_);
    native_warmed_ = false;
    ensure_context();
    if (!context_is_valid() ||
        !ScreenToImGui(ctx_, anchor_screen_x_, anchor_screen_y_, anchor_gui_x, anchor_gui_y)) {
      pop_frame_styles();
      return;
    }
  }
  if (!native_warmed_) {
    if (ImGui::SetNextWindowPos) {
      ImGui::SetNextWindowPos(ctx_, -10000.0, -10000.0, ImGui::Cond_Always);
    }
    if (ImGui::SetNextWindowSize) ImGui::SetNextWindowSize(ctx_, 64, 64, ImGui::Cond_Always);
    bool warm_open = true;
    const bool warm_began =
        ImGui::Begin(ctx_, "RadialMenu##lee_runtime_warm", &warm_open,
                     ImGui::WindowFlags_NoTitleBar | ImGui::WindowFlags_NoInputs);
    if (warm_began) {
      if (ImGui::Dummy) ImGui::Dummy(ctx_, 1.0, 1.0);
      ImGui::End(ctx_);
    }
    native_warmed_ = true;
  }

  if (ImGui::SetNextWindowBgAlpha) ImGui::SetNextWindowBgAlpha(ctx_, 0.0);
  if (ImGui::PushStyleVar) {
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowPadding, 0.0, 0.0);
    ++style_pushed;
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowBorderSize, 0.0);
    ++style_pushed;
  }
  if (theme_fonts_.default_font && ImGui::PushFont) {
    ImGui::PushFont(ctx_, theme_fonts_.default_font, 14.0);
    font_pushed = true;
  }

  ImGui::SetNextWindowPos(ctx_, anchor_gui_x - diameter * 0.5, anchor_gui_y - diameter * 0.5,
                          ImGui::Cond_Always);
  ImGui::SetNextWindowSize(ctx_, diameter, diameter, ImGui::Cond_Always);

  mark_painted();
  if (suppress_render_ > 0) --suppress_render_;

  if (ImGui::PushStyleColor) {
    ImGui::PushStyleColor(ctx_, ImGui::Col_WindowBg, RgbaToU32(0, 0, 0, 0));
    color_pushed = 1;
  }
  bool wheel_open = true;
  bool wheel_began = false;
  if (ImGui::Begin)
    wheel_began = ImGui::Begin(ctx_, kTitle, &wheel_open, WindowFlags(!drag_slot_active_));
  if (color_pushed > 0 && ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, color_pushed);
  color_pushed = 0;
  if (!wheel_began) {
    pop_frame_styles();
    return;
  }
  frame_open_ = true;

  double mx = 0, my = 0;
  POINT cursor_pt;
  GetCursorPos(&cursor_pt);
  ScreenToImGui(ctx_, static_cast<double>(cursor_pt.x), static_cast<double>(cursor_pt.y), mx, my);
  double wx = 0, wy = 0;
  ImGui::GetWindowPos(ctx_, &wx, &wy);
  double ww = 0, wh = 0;
  ImGui::GetWindowSize(ctx_, &ww, &wh);
  const double cx = wx + ww * 0.5;
  const double cy = wy + wh * 0.5;

  bool submenu_hovered = false;
  if (suppress_render_ <= 0 && !drag_slot_active_) {
    HitTestResult hit = HitTestWheel(mx, my, cx, cy, draw_cfg);
    if (is_pinned_ && !hit.in_center) {
      const double odx = mx - cx;
      const double ody = my - cy;
      const double outer = draw_cfg.menu.outer_radius * static_cast<double>(anim_open_);
      if (odx * odx + ody * ody > outer * outer) {
        hit.sector_index = -1;
        hit.in_dead_zone = true;
      }
    }
    hovered_sector_ = hit.in_dead_zone ? -1 : hit.sector_index;

    if (config().menu.hover_to_open && hovered_sector_ >= 0) {
      show_submenu_ = true;
      active_sector_ = hovered_sector_;
    }

    if (ImGui::IsMouseClicked && ImGui::IsMouseClicked(ctx_, 0)) {
      if (hit.in_center) {
        is_pinned_ = !is_pinned_;
      } else if (hovered_sector_ >= 0) {
        if (!config().menu.hover_to_open) {
          if (clicked_sector_ == hovered_sector_) {
            show_submenu_ = false;
            clicked_sector_ = -1;
            active_sector_ = -1;
          } else {
            show_submenu_ = true;
            clicked_sector_ = hovered_sector_;
            active_sector_ = hovered_sector_;
          }
        }
      } else {
        const double odx = mx - cx;
        const double ody = my - cy;
        const double outer = draw_cfg.menu.outer_radius * static_cast<double>(anim_open_);
        if (odx * odx + ody * ody > outer * outer) {
          if (show_submenu_) {
            show_submenu_ = false;
            active_sector_ = -1;
            clicked_sector_ = -1;
          } else if (!is_pinned_) {
            close();
          }
        }
      }
    }

    if (ImGui::IsMouseClicked && ImGui::IsMouseClicked(ctx_, 1) && hit.in_center) {
      management_mode_ = !management_mode_;
      suppress_render_ = 3;
      show_submenu_ = false;
      if (management_mode_) {
        ConfigStore::Instance().LoadFull(full_for_mgmt_);
        BuildManagementConfig(full_for_mgmt_, mgmt_config_, mgmt_preset_names_);
      }
    }

    if (ImGui::IsKeyPressed && ImGui::IsKeyPressed(ctx_, ImGui::Key_Escape)) {
      if (is_pinned_) show_submenu_ = false;
      else close();
    }
  }

  DrawWheel(ctx_, draw_cfg, hovered_sector_, active_sector_, is_pinned_, anim_open_,
            sector_expand_.data(), static_cast<int>(sector_expand_.size()));

  if (show_submenu_ && active_sector_ >= 0 &&
      active_sector_ < static_cast<int>(draw_cfg.sectors.size()) && suppress_render_ <= 0) {
    const Sector& sec = draw_cfg.sectors[active_sector_];
    SubmenuPosition sp = ComputeSubmenuPosition(draw_cfg, active_sector_, cx, cy);
    const int slot_n = std::max(static_cast<int>(sec.slots.size()),
                                CountNonEmptySlots(sec.slots));
    SubmenuLayout layout = ComputeSubmenuLayout(draw_cfg, slot_n);
    ClampToMonitor(sp.x, sp.y, layout.win_w, layout.win_h);

    ImGui::SetNextWindowPos(ctx_, sp.x, sp.y, ImGui::Cond_Always);
    ImGui::SetNextWindowSize(ctx_, layout.win_w, layout.win_h, ImGui::Cond_Always);
    if (ImGui::SetNextWindowBgAlpha) ImGui::SetNextWindowBgAlpha(ctx_, 240.0 / 255.0);
    int sub_colors = 0;
    int sub_vars = 0;
    if (ImGui::PushStyleColor && ImGui::PopStyleColor) {
      ImGui::PushStyleColor(ctx_, ImGui::Col_WindowBg, RgbaToU32(25, 25, 28, 245));
      ImGui::PushStyleColor(ctx_, ImGui::Col_Border, RgbaToU32(0, 0, 0, 255));
      sub_colors = 2;
    }
    if (ImGui::PushStyleVar && ImGui::PopStyleVar) {
      ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowPadding, layout.padding, layout.padding);
      ImGui::PushStyleVar(ctx_, ImGui::StyleVar_ItemSpacing, layout.gap, layout.gap);
      ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowRounding, 8);
      ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowBorderSize, 1);
      sub_vars = 4;
    }
    bool sub_open = true;
    const int wheel_flags = drag_slot_active_ ? WindowFlags(false) : WindowFlags(true);
    if (ImGui::Begin(ctx_, "Submenu##lee_rm", &sub_open,
                     ImGui::WindowFlags_NoTitleBar | ImGui::WindowFlags_NoDocking |
                         ImGui::WindowFlags_NoSavedSettings | wheel_flags)) {
      if (ImGui::IsWindowHovered && ImGui::IsWindowHovered(ctx_)) submenu_hovered = true;
      const int cols = layout.cols;
      const int grid_count = layout.slot_count;
      for (int idx = 0; idx < grid_count; ++idx) {
        Slot sl;
        if (idx < static_cast<int>(sec.slots.size())) sl = sec.slots[idx];
        else sl.type = "empty";
        if (idx > 0 && idx % cols != 0 && ImGui::SameLine) ImGui::SameLine(ctx_);
        const bool filled = (sl.type != "empty");
        int button_colors = 0;
        int button_vars = 0;
        if (ImGui::PushStyleColor && ImGui::PopStyleColor) {
          if (filled) {
            ImGui::PushStyleColor(ctx_, ImGui::Col_Button, RgbaToU32(60, 62, 66, 255));
            ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonHovered, RgbaToU32(60, 100, 140, 255));
            ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonActive, RgbaToU32(40, 60, 80, 255));
            ImGui::PushStyleColor(ctx_, ImGui::Col_Border, RgbaToU32(85, 85, 90, 100));
            ImGui::PushStyleColor(ctx_, ImGui::Col_Text, RgbaToU32(180, 180, 180, 255));
          } else {
            ImGui::PushStyleColor(ctx_, ImGui::Col_Button, RgbaToU32(30, 30, 32, 100));
            ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonHovered, RgbaToU32(50, 50, 55, 150));
            ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonActive, RgbaToU32(60, 60, 65, 150));
            ImGui::PushStyleColor(ctx_, ImGui::Col_Border, RgbaToU32(60, 60, 60, 60));
            ImGui::PushStyleColor(ctx_, ImGui::Col_Text, RgbaToU32(128, 128, 128, 200));
          }
          button_colors = 5;
        }
        if (ImGui::PushStyleVar && ImGui::PopStyleVar) {
          ImGui::PushStyleVar(ctx_, ImGui::StyleVar_FrameRounding, 4);
          ImGui::PushStyleVar(ctx_, ImGui::StyleVar_FrameBorderSize, 1);
          button_vars = 2;
        }
        const std::string label = filled ? (sl.name.empty() ? sl.type : sl.name) : "";
        if (ImGui::Button(ctx_, (label + "##s" + std::to_string(idx)).c_str(), layout.slot_w,
                          layout.slot_h)) {
          if (filled) {
            Execution::TriggerSlot(sl);
            if (!is_pinned_) {
              defer_key_ = true;
              input_.defer_release_until_key_up();
              close();
            }
          }
        }
        if (button_vars > 0) ImGui::PopStyleVar(ctx_, button_vars);
        if (button_colors > 0) ImGui::PopStyleColor(ctx_, button_colors);
        if (filled && ImGui::IsItemHovered && ImGui::IsItemHovered(ctx_) &&
            ImGui::BeginTooltip && ImGui::BeginTooltip(ctx_)) {
          ImGui::Text(ctx_, label.c_str());
          ImGui::EndTooltip(ctx_);
        }
        if (filled && ImGui::BeginDragDropSource && ImGui::BeginDragDropSource(ctx_)) {
          drag_slot_ = sl;
          drag_slot_active_ = true;
          if (ImGui::SetDragDropPayload) {
            ImGui::SetDragDropPayload(ctx_, "RM_SLOT", nullptr, 0);
          }
          if (ImGui::PushStyleVar) {
            ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowPadding, 0, 0);
          }
          ImGui::Text(ctx_, label.c_str());
          if (ImGui::PopStyleVar) ImGui::PopStyleVar(ctx_, 1);
          ImGui::EndDragDropSource(ctx_);
        }
      }
      ImGui::End(ctx_);
    }
    if (sub_vars > 0 && ImGui::PopStyleVar) ImGui::PopStyleVar(ctx_, sub_vars);
    if (sub_colors > 0 && ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, sub_colors);
  }

  if (config().menu.hover_to_open && hovered_sector_ < 0 && show_submenu_ && !submenu_hovered) {
    show_submenu_ = false;
    active_sector_ = -1;
  }

  if (drag_slot_active_ && ImGui::IsMouseReleased && ImGui::IsMouseReleased(ctx_, 0)) {
    POINT sp;
    GetCursorPos(&sp);
    Execution::HandleDrop(drag_slot_, sp.x, sp.y);
    drag_slot_active_ = false;
    if (!is_pinned_) {
      defer_key_ = true;
      input_.defer_release_until_key_up();
      close();
    }
  }

  if (management_mode_ && ImGui::IsMouseClicked && ImGui::IsMouseClicked(ctx_, 0) &&
      hovered_sector_ >= 0 &&
      hovered_sector_ < static_cast<int>(mgmt_preset_names_.size())) {
    const std::string& pname = mgmt_preset_names_[static_cast<size_t>(hovered_sector_)];
    if (pname == "__setup__") {
      GetSetupWindow().open();
      management_mode_ = false;
      close();
      ImGui::End(ctx_);
      frame_open_ = false;
      pop_frame_styles();
      if (context_release_pending_) invalidate_context();
      return;
    }
    auto it = full_for_mgmt_.presets.find(pname);
    if (it != full_for_mgmt_.presets.end()) {
      full_for_mgmt_.current_preset_name = pname;
      full_for_mgmt_.active_config = it->second;
      ConfigStore::Instance().SaveFull(full_for_mgmt_);
      config() = it->second;
      ConfigStore::Instance().NotifyConfigUpdated();
      management_mode_ = false;
    }
  }

  if (config().show_perf_hud && ImGui::GetForegroundDrawList && ImGui::DrawList_AddText) {
    ImGui_DrawList* fdl = ImGui::GetForegroundDrawList(ctx_);
    if (fdl) {
      static double wheel_ms = 0;
      static int perf_n = 0;
      wheel_ms += dt * 1000.0;
      if (++perf_n >= 30) {
        perf_n = 0;
        wheel_ms = 0;
      }
      char buf[96];
      snprintf(buf, sizeof(buf), "Wheel: %.1fms | active=%d pin=%d", wheel_ms / 30.0,
               active_ ? 1 : 0, is_pinned_ ? 1 : 0);
      ImGui::DrawList_AddText(fdl, static_cast<float>(wx + ww - 220), static_cast<float>(wy + 8),
                              RgbaToU32(255, 255, 255, 200), buf);
    }
  }

  if (!wheel_open && !is_pinned_) close();

  ImGui::End(ctx_);
  frame_open_ = false;
  pop_frame_styles();
  if (context_release_pending_) invalidate_context();
}

}  // namespace lee::radial_menu
