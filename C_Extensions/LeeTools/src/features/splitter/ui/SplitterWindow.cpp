#include "features/splitter/ui/SplitterWindow.h"

#include <windows.h>

#include <cstdio>

#include "reaper_imgui_functions.h"

#include "plugin/PluginContext.h"
#include "shared/reaper/ReaImGuiApi.h"
#include "shared/ui/LeeUiTheme.h"

namespace lee::splitter {
namespace {

SplitterWindow g_window;

constexpr const char* kWindowTitle = "Element Split##lee_splitter";
// ImGui::Cond_FirstUseEver — match Drop Station (Cond_Always every frame broke Begin).
constexpr int kCondFirstUseEver = 4;

constexpr int kColDefault = static_cast<int>(0xFFCCCCCCu);
constexpr int kColGreen = static_cast<int>(0xFF4CAF50u);
constexpr int kColRed = static_cast<int>(0xFFE57373u);

void draw_progress_bar(ImGui_Context* ctx, double t) {
  if (!ImGui::GetWindowDrawList) return;
  ImGui_DrawList* dl = ImGui::GetWindowDrawList(ctx);
  if (!dl || !ImGui::GetItemRectMin || !ImGui::GetItemRectMax) return;
  double x0 = 0, y0 = 0, x1 = 0, y1 = 0;
  ImGui::GetItemRectMin(ctx, &x0, &y0);
  ImGui::GetItemRectMax(ctx, &x1, &y1);
  const double bar_h = 4.0;
  const double y = y1 - bar_h - 2.0;
  t = (t < 0.0) ? 0.0 : (t > 1.0 ? 1.0 : t);
  ImGui::DrawList_AddRectFilled(dl, x0, y, x1, y + bar_h, 0xFF303030, 0.0);
  const double fill_x = x0 + (x1 - x0) * t;
  ImGui::DrawList_AddRectFilled(dl, x0, y, fill_x, y + bar_h, 0xFF13C4C4, 0.0);
}

int force_odd(int v) {
  if (v < 3) return 3;
  if (v > 31) return 31;
  if ((v & 1) == 0) ++v;
  return v;
}

}  // namespace

SplitterWindow& GetSplitterWindow() { return g_window; }

void SplitterWindow::ensure_context() {
  if (ctx_) return;
  if (!lee::reaimgui::Ready()) return;
  try {
    ctx_ = ImGui::CreateContext("Element Split");
  } catch (const ImGui_Error&) {
    ctx_ = nullptr;
    return;
  } catch (...) {
    ctx_ = nullptr;
    return;
  }
  lee::ui::EnsureFonts(ctx_, theme_fonts_);
}

void SplitterWindow::invalidate_context() {
  if (ctx_) lee::ui::DestroyFonts(ctx_, theme_fonts_);
  ctx_ = nullptr;
  theme_fonts_ = {};
}

void SplitterWindow::refresh_selection() {
  if (const auto& api = lee::Api(); api.EnumProjects) {
    proj_ = api.EnumProjects(-1, nullptr, 0);
  }
  selection_ = CollectSelection(proj_);
}

void SplitterWindow::update_idle_status() {
  status_color_ = 0;
  if (job_.running()) return;
  if (selection_.valid_audio == 0) {
    status_text_ = (selection_.total_selected == 0) ? "Select an item to process"
                                                    : "No valid audio items";
    return;
  }
  if (!prefs_.quick_mode && !selection_.exactly_one) {
    status_text_ = "Ready to preview";
    if (selection_.valid_audio != 1) {
      // Still can process multiple; preview needs 1.
    }
  } else if (!prefs_.quick_mode && selection_.exactly_one) {
    status_text_ = "Ready to preview";
  } else {
    status_text_ = "Select an item to process";
  }
}

void SplitterWindow::apply_window_size() {
  win_w_ = 440.0;
  if (prefs_.quick_mode) {
    win_h_ = 360.0;
  } else {
    win_h_ = 320.0;
    if (prefs_.algo_mode == AlgoMode::TransientSustain) {
      win_h_ += params_.show_advanced ? 160.0 : 60.0;
    } else if (prefs_.algo_mode == AlgoMode::MidSide) {
      win_h_ += 40.0;
    } else {
      win_h_ += 80.0;
    }
    win_h_ += 110.0;  // preview section + footer + status
  }
  if (ImGui::SetNextWindowSize) {
    ImGui::SetNextWindowSize(ctx_, win_w_, win_h_, kCondFirstUseEver);
  }
  if (ImGui::SetNextWindowPos) {
    ImGui::SetNextWindowPos(ctx_, 80.0, 80.0, kCondFirstUseEver);
  }
}

void SplitterWindow::open() {
  ensure_context();
  if (!ctx_) return;
  prefs_.load();
  params_.reset();
  advanced_mapped_ = false;
  open_ = true;
  refresh_selection();
  update_idle_status();
}

void SplitterWindow::close() {
  cancel_all();
  open_ = false;
  invalidate_context();
}

void SplitterWindow::destroy() {
  cancel_all();
  invalidate_context();
  open_ = false;
}

void SplitterWindow::cancel_all() {
  preview_.Stop();
  job_.ForceStop();
}

bool SplitterWindow::drag_param(const char* label, double* v, double vmin, double vmax,
                                const char* fmt) {
  if (!ImGui::DragDouble) return false;
  return ImGui::DragDouble(ctx_, label, v, 0.1, vmin, vmax, fmt);
}

bool SplitterWindow::drag_param_int(const char* label, int* v, int vmin, int vmax) {
  double d = static_cast<double>(*v);
  if (!drag_param(label, &d, static_cast<double>(vmin), static_cast<double>(vmax), "%.0f")) {
    return false;
  }
  *v = static_cast<int>(d + 0.5);
  return true;
}

void SplitterWindow::start_algorithm_process() {
  // Stop preview before cancel/process — avoids PlayPreview + batch write races.
  preview_.Stop();
  if (job_.running()) {
    job_.Cancel();
    return;
  }
  refresh_selection();
  if (selection_.valid_audio == 0) {
    status_text_ = "No audio items selected";
    status_color_ = 2;
    return;
  }

  std::vector<Layer> layers = {Layer::Layer1, Layer::Layer2};
  std::vector<std::string> suffixes;
  suffixes.push_back(LayerName(prefs_.algo_mode, Layer::Layer1));
  suffixes.push_back(LayerName(prefs_.algo_mode, Layer::Layer2));

  status_text_ = "Starting...";
  status_color_ = 0;
  if (job_.Start(proj_, selection_.items, prefs_.algo_mode, params_, layers, suffixes)) {
    status_text_ = "Processing 0/" + std::to_string(job_.total()) + " items...";
  }
}

void SplitterWindow::start_quick(QuickPreset preset) {
  if (job_.running()) return;
  preview_.Stop();
  refresh_selection();
  if (selection_.valid_audio == 0) {
    status_text_ = "No audio items selected";
    status_color_ = 2;
    return;
  }

  const QuickInfo qi = QuickPresetInfo(preset);
  SplitParams qp;
  qp.reset();

  std::vector<Layer> layers = {qi.layer};
  std::vector<std::string> suffixes = {qi.suffix};

  status_text_ = "Starting...";
  if (job_.Start(proj_, selection_.items, qi.mode, qp, layers, suffixes)) {
    status_text_ = "Processing 0/" + std::to_string(job_.total()) + " items...";
  }
}

void SplitterWindow::draw_header() {
  if (theme_fonts_.heading && ImGui::PushFont && ImGui::PopFont) {
    ImGui::PushFont(ctx_, theme_fonts_.heading, 20.0);
    ImGui::Text(ctx_, "Element Split");
    ImGui::PopFont(ctx_);
  } else {
    ImGui::Text(ctx_, "Element Split");
  }
  ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "Refresh")) refresh_selection();
  ImGui::SameLine(ctx_);
  const char* mode_btn = prefs_.quick_mode ? "Algorithm" : "Quick";
  if (ImGui::Button(ctx_, mode_btn)) {
    prefs_.quick_mode = !prefs_.quick_mode;
    prefs_.save();
    preview_.Stop();
    apply_window_size();
  }
}

void SplitterWindow::draw_status_bar() {
  ImGui::Text(ctx_, status_text_.c_str());
  if (job_.running() && job_.total() > 0) {
    const double t = static_cast<double>(job_.done()) / static_cast<double>(job_.total());
    if (ImGui::Dummy) ImGui::Dummy(ctx_, -1.0, 6.0);
    draw_progress_bar(ctx_, t);
  }
}

void SplitterWindow::draw_algorithm_panel() {
  if (ImGui::Text) ImGui::Text(ctx_, "Algorithm");
  if (ImGui::Dummy) ImGui::Dummy(ctx_, -1.0, 2.0);

  const char* labels[] = {"Transient / Sustain", "Mid / Side", "Harmonic / Percussive",
                          "Tonal / Noise", "Foreground / Ambient"};
  int mode_i = static_cast<int>(prefs_.algo_mode);
  if (mode_i < 0 || mode_i >= 5) mode_i = 0;
  if (ImGui::BeginCombo && ImGui::BeginCombo(ctx_, "Mode", labels[mode_i])) {
    for (int i = 0; i < 5; ++i) {
      bool sel = (mode_i == i);
      if (ImGui::Selectable(ctx_, labels[i], &sel)) {
        prefs_.algo_mode = static_cast<AlgoMode>(i);
        prefs_.save();
        preview_.Stop();
        apply_window_size();
      }
    }
    if (ImGui::EndCombo) ImGui::EndCombo(ctx_);
  }

  switch (prefs_.algo_mode) {
    case AlgoMode::TransientSustain:
      drag_param("Trans Strength", &params_.trans_strength, 0.0, 100.0, "%.0f %%");
      drag_param("Trans Tail", &params_.trans_tail, 0.0, 100.0, "%.0f %%");
      if (ImGui::Checkbox) {
        if (ImGui::Checkbox(ctx_, "Show Advanced", &params_.show_advanced)) {
          if (params_.show_advanced && !advanced_mapped_) {
            params_.derive_advanced_from_simple();
            advanced_mapped_ = true;
          }
          apply_window_size();
        }
      }
      if (params_.show_advanced) {
        drag_param("Fast Attack", &params_.fast_attack_ms, 0.5, 5.0, "%.1f ms");
        drag_param("Slow Attack", &params_.slow_attack_ms, 10.0, 50.0, "%.0f ms");
        drag_param("Release", &params_.release_ms, 10.0, 100.0, "%.0f ms");
        drag_param("Smoothing", &params_.smoothing_ms, 1.0, 20.0, "%.0f ms");
        drag_param("Sensitivity", &params_.sensitivity, 1.0, 15.0, "%.0f");
      }
      if (ImGui::Checkbox) {
        ImGui::Checkbox(ctx_, "Stereo Link", &params_.stereo_link);
      }
      break;
    case AlgoMode::MidSide:
      drag_param("Mid Gain", &params_.mid_gain_db, -12.0, 12.0, "%.1f dB");
      drag_param("Side Gain", &params_.side_gain_db, -12.0, 12.0, "%.1f dB");
      break;
    case AlgoMode::Hpss:
      drag_param_int("Harmonic Len", &params_.harmonic_len, 3, 31);
      params_.harmonic_len = force_odd(params_.harmonic_len);
      drag_param_int("Percussive Len", &params_.percussive_len, 3, 31);
      params_.percussive_len = force_odd(params_.percussive_len);
      drag_param("Mask Power", &params_.hpss_mask_power, 1.0, 8.0, "%.0f");
      break;
    case AlgoMode::TonalNoise:
      drag_param_int("Peak Width", &params_.peak_width, 3, 31);
      params_.peak_width = force_odd(params_.peak_width);
      drag_param("Peak Threshold", &params_.peak_threshold_db, 0.0, 30.0, "%.0f dB");
      drag_param("Mask Power", &params_.tonal_mask_power, 1.0, 8.0, "%.0f");
      break;
    case AlgoMode::FgAmbient:
      drag_param("Ambient Time", &params_.ambient_time_s, 0.5, 10.0, "%.1f s");
      drag_param("Threshold", &params_.fg_threshold_db, 0.0, 30.0, "%.0f dB");
      drag_param("Mask Power", &params_.fg_mask_power, 1.0, 8.0, "%.0f");
      break;
    default:
      break;
  }

  if (ImGui::Dummy) ImGui::Dummy(ctx_, -1.0, 6.0);
  if (ImGui::Text) ImGui::Text(ctx_, "Preview");
  if (ImGui::Dummy) ImGui::Dummy(ctx_, -1.0, 2.0);

  if (ImGui::Checkbox) {
    bool route = prefs_.route_to_track;
    if (ImGui::Checkbox(ctx_, "Route to Track", &route)) {
      prefs_.route_to_track = route;
      prefs_.save();
    }
  }

  const bool can_preview = selection_.exactly_one && !job_.running();
  char btn1[64];
  char btn2[64];
  std::snprintf(btn1, sizeof(btn1), "Play %s", LayerName(prefs_.algo_mode, Layer::Layer1));
  std::snprintf(btn2, sizeof(btn2), "Play %s", LayerName(prefs_.algo_mode, Layer::Layer2));

  if (can_preview && ImGui::Button(ctx_, btn1)) {
    if (selection_.exactly_one) {
      status_text_ = "Processing preview...";
      if (preview_.RequestLayer(proj_, selection_.items[0], prefs_.algo_mode, params_,
                                Layer::Layer1, prefs_.route_to_track)) {
        status_text_ = preview_.is_working() ? "Processing preview..."
                                             : (preview_.is_playing() ? "Previewing..."
                                                                        : "Preview stopped");
      } else {
        status_text_ = "Preview failed";
        status_color_ = 2;
      }
    }
  }
  ImGui::SameLine(ctx_);
  if (can_preview && ImGui::Button(ctx_, btn2)) {
    if (selection_.exactly_one) {
      if (preview_.RequestLayer(proj_, selection_.items[0], prefs_.algo_mode, params_,
                                Layer::Layer2, prefs_.route_to_track)) {
        status_text_ = preview_.is_working() ? "Processing preview..."
                                             : (preview_.is_playing() ? "Previewing..."
                                                                        : "Preview stopped");
      } else {
        status_text_ = "Preview failed";
        status_color_ = 2;
      }
    }
  }
  if (!can_preview && !selection_.exactly_one && selection_.valid_audio > 0) {
    status_text_ = "Select 1 item to preview";
  }
}

void SplitterWindow::draw_quick_panel() {
  if (ImGui::Text) ImGui::Text(ctx_, "Quick — click to process");
  if (ImGui::Dummy) ImGui::Dummy(ctx_, -1.0, 4.0);

  const char* names[] = {"Punch", "Body", "Center", "Width", "Drone", "Rhythm",
                         "Tonal", "Noise", "Event", "Bed"};
  for (int i = 0; i < 10; ++i) {
    if (i > 0 && (i % 2) == 0) ImGui::SameLine(ctx_);
    if (ImGui::Button(ctx_, names[i])) {
      start_quick(static_cast<QuickPreset>(i));
    }
  }
}

void SplitterWindow::draw_footer(bool& stay_open) {
  if (ImGui::Dummy) ImGui::Dummy(ctx_, -1.0, 8.0);

  if (prefs_.quick_mode) {
    if (ImGui::Button(ctx_, "Close")) stay_open = false;
  } else {
    const char* proc_label = job_.running() ? "Cancel" : "Process";
    if (ImGui::Button(ctx_, proc_label)) {
      start_algorithm_process();
    }
    ImGui::SameLine(ctx_);
    if (ImGui::Button(ctx_, "Close")) {
      stay_open = false;
    }
  }
}

void SplitterWindow::draw_ui() {
  const lee::ui::FrameTheme frame = lee::ui::BeginFrame(ctx_, theme_fonts_);
  apply_window_size();

  bool stay_open = true;
  bool began = false;
  if (ImGui::Begin) {
    began = ImGui::Begin(ctx_, kWindowTitle, &stay_open);
  }
  if (!began) {
    // Do not call End() when Begin returned false (ReaImGui throws otherwise).
    lee::ui::EndFrame(ctx_, frame);
    if (!stay_open) close();
    return;
  }

  draw_header();
  if (prefs_.quick_mode) {
    draw_quick_panel();
  } else {
    draw_algorithm_panel();
  }
  draw_footer(stay_open);
  draw_status_bar();

  if (!prefs_.quick_mode && ImGui::IsKeyPressed && ImGui::IsKeyPressed(ctx_, ImGui::Key_Enter)) {
    if (!job_.running()) start_algorithm_process();
  }

  if (ImGui::End) ImGui::End(ctx_);
  lee::ui::EndFrame(ctx_, frame);
  if (!stay_open) close();
}

void SplitterWindow::tick() {
  if (!open_) return;
  if (!lee::reaimgui::Ready()) {
    close();
    return;
  }
  ensure_context();
  if (!ctx_) return;

  // Do not start new preview playback while a batch job is active.
  if (!job_.running()) {
    preview_.Tick(proj_);
  }

  if (preview_.is_working()) {
    status_text_ = "Processing preview...";
    status_color_ = 0;
  }

  if (job_.running()) {
    job_.Tick();
    const int d = job_.done();
    const int t = job_.total();
    status_text_ = "Processing " + std::to_string(d) + "/" + std::to_string(t) + " items...";
    status_color_ = 0;
    if (!job_.running()) {
      if (job_.state() == BatchJob::State::Done) {
        status_text_ = "Split complete: " + std::to_string(job_.ok()) + "/" +
                         std::to_string(job_.total()) + " items";
        status_color_ = 1;
      } else if (job_.state() == BatchJob::State::Cancelled) {
        status_text_ = "Processing cancelled";
        status_color_ = 2;
      }
    }
  }

  try {
    draw_ui();
  } catch (const ImGui_Error&) {
    preview_.Stop();
    job_.ForceStop();
    open_ = false;
    invalidate_context();
  } catch (...) {
    preview_.Stop();
    job_.ForceStop();
    open_ = false;
    invalidate_context();
  }
}

}  // namespace lee::splitter
