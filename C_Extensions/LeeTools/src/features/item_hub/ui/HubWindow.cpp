#include "features/item_hub/ui/HubWindow.h"

#include <windows.h>

#include <cmath>
#include <cstdio>
#include <string>

#include "reaper_imgui_functions.h"

#include "features/item_hub/domain/Session.h"
#include "plugin/PluginContext.h"
#include "shared/reaper/ReaImGuiApi.h"
#include "shared/ui/LeeUiTheme.h"

namespace lee::item_hub {
namespace {

HubWindow g_hub;
ParamId g_drag_param = ParamId::Count;
ParamId g_wheel_param = ParamId::Count;

constexpr const char* kHubWindowTitle = "Item Hub##lee";
constexpr double kOffScreenPos = -10000.0;
constexpr double kRowWidth = 210.0;
constexpr double kCatColWidth = 116.0;
constexpr double kCatRowHeight = 26.0;
constexpr double kCatRowGap = 4.0;
constexpr double kParamRowHeight = 28.0;
constexpr double kItemSpacingY = 4.0;
constexpr double kWindowPadH = 16.0;
constexpr double kWindowPadV = 12.0;
constexpr double kWindowBorder = 2.0;
constexpr double kMinPaintIntervalMs = 20.0;
constexpr int kParamRowBg = 0;
constexpr int kParamRowBgHover = static_cast<int>(0xB4384840u);   // dark teal-gray
constexpr int kParamRowBgActive = static_cast<int>(0xC8485850u);  // slightly brighter when adjusting

int max_param_count() {
  int max_params = 0;
  for (int c = 0; c < static_cast<int>(Category::Count); ++c) {
    max_params = std::max(max_params, ParamCountInCategory(static_cast<Category>(c)));
  }
  return max_params;
}

double category_column_height() {
  const int n = static_cast<int>(Category::Count);
  return static_cast<double>(n) * kCatRowHeight + static_cast<double>(n - 1) * kCatRowGap;
}

double param_column_height(int param_count) {
  if (param_count <= 0) return 0.0;
  return static_cast<double>(param_count) * kParamRowHeight +
         static_cast<double>(param_count - 1) * kItemSpacingY;
}

void hub_content_size(double& w, double& h) {
  const double cat_h = category_column_height();
  const double param_h = param_column_height(max_param_count());
  h = std::max(cat_h, param_h) + kWindowPadV + kWindowBorder;
  w = kCatColWidth + kRowWidth + kWindowPadH + kWindowBorder;
}

void draw_progress_bar(ImGui_Context* ctx, double t) {
  if (!ImGui::GetWindowDrawList) return;
  ImGui_DrawList* dl = ImGui::GetWindowDrawList(ctx);
  if (!dl || !ImGui::GetItemRectMin || !ImGui::GetItemRectMax) return;
  double x0 = 0, y0 = 0, x1 = 0, y1 = 0;
  ImGui::GetItemRectMin(ctx, &x0, &y0);
  ImGui::GetItemRectMax(ctx, &x1, &y1);
  const double bar_h = 3.0;
  const double y = y1 - bar_h - 1.0;
  t = std::max(0.0, std::min(1.0, t));
  ImGui::DrawList_AddRectFilled(dl, x0, y, x1, y + bar_h, 0xFF303030, 0.0);
  const double fill_x = x0 + (x1 - x0) * t;
  ImGui::DrawList_AddRectFilled(dl, x0, y, fill_x, y + bar_h, 0xFF13C4C4, 0.0);
}

}  // namespace

HubWindow& GetHubWindow() {
  return g_hub;
}

int HubWindow::hub_window_flags(bool idle) const {
  int flags = ImGui::WindowFlags_NoTitleBar | ImGui::WindowFlags_NoDocking |
              ImGui::WindowFlags_NoSavedSettings | ImGui::WindowFlags_NoFocusOnAppearing;
  if (idle && ImGui::WindowFlags_NoInputs) {
    flags |= ImGui::WindowFlags_NoInputs;
  }
  return flags;
}

void HubWindow::refresh_hub_size() {
  hub_content_size(cached_w_, cached_h_);
}

void HubWindow::apply_hub_window_size() const {
  if (cached_w_ <= 0.0 || cached_h_ <= 0.0) return;
  if (ImGui::SetNextWindowSize) {
    ImGui::SetNextWindowSize(ctx_, cached_w_, cached_h_, ImGui::Cond_Always);
  }
}

bool HubWindow::should_skip_paint() const {
  if (first_frame_ || begin_retry_pending_) return false;
  if (!last_paint_qpc_valid_) return false;
  LARGE_INTEGER now{};
  LARGE_INTEGER freq{};
  if (!QueryPerformanceCounter(&now) || !QueryPerformanceFrequency(&freq) ||
      freq.QuadPart == 0) {
    return false;
  }
  const double ms =
      static_cast<double>(now.QuadPart - last_paint_qpc_.QuadPart) * 1000.0 /
      static_cast<double>(freq.QuadPart);
  return ms < kMinPaintIntervalMs;
}

void HubWindow::mark_painted() {
  if (!QueryPerformanceCounter(&last_paint_qpc_)) return;
  last_paint_qpc_valid_ = true;
}

void HubWindow::ensure_context() {
  if (ctx_ || !lee::reaimgui::Ready()) return;
  if (!ImGui::CreateContext) return;
  try {
    ctx_ = ImGui::CreateContext("Lee Item Hub");
  } catch (const ImGui_Error&) {
    ctx_ = nullptr;
    return;
  }
  if (ctx_) lee::ui::EnsureFonts(ctx_, theme_fonts_);
}

void HubWindow::destroy_context() {
  if (!ctx_) return;
  lee::ui::DestroyFonts(ctx_, theme_fonts_);
  ctx_ = nullptr;
}

void HubWindow::warm_native_window_once() {
  if (!ctx_ || native_warmed_ || !lee::reaimgui::Ready()) return;
  lee::ui::FrameTheme frame;
  bool began = false;
  try {
    frame = lee::ui::BeginCompactFrame(ctx_, theme_fonts_);
    began = true;
    if (ImGui::SetNextWindowPos) {
      ImGui::SetNextWindowPos(ctx_, kOffScreenPos, kOffScreenPos, ImGui::Cond_Always);
    }
    apply_hub_window_size();
    if (ImGui::SetNextWindowBgAlpha) ImGui::SetNextWindowBgAlpha(ctx_, 0.0);
    bool open = true;
    const int flags = ImGui::WindowFlags_NoTitleBar | ImGui::WindowFlags_NoSavedSettings |
                      ImGui::WindowFlags_NoInputs;
    if (ImGui::Begin(ctx_, kHubWindowTitle, &open, flags)) {
      if (ImGui::Dummy) ImGui::Dummy(ctx_, 1.0, 1.0);
    }
    ImGui::End(ctx_);
    lee::ui::EndFrame(ctx_, frame);
    native_warmed_ = true;
  } catch (...) {
    if (began) {
      try {
        lee::ui::EndFrame(ctx_, frame);
      } catch (...) {
      }
    }
    invalidate_context();
  }
}

void HubWindow::draw_idle_hidden() {
  if (!ctx_) return;

  if (ImGui::SetNextWindowPos) {
    ImGui::SetNextWindowPos(ctx_, kOffScreenPos, kOffScreenPos, ImGui::Cond_Always);
  }
  apply_hub_window_size();
  if (ImGui::SetNextWindowBgAlpha) ImGui::SetNextWindowBgAlpha(ctx_, 0.0);

  int style_pushed = 0;
  if (ImGui::PushStyleVar) {
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowPadding, 8.0, 6.0);
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowBorderSize, 0.0);
    style_pushed = 2;
  }
  bool open = true;
  if (!ImGui::Begin(ctx_, kHubWindowTitle, &open, hub_window_flags(true))) {
    ImGui::End(ctx_);
    if (style_pushed > 0 && ImGui::PopStyleVar) ImGui::PopStyleVar(ctx_, style_pushed);
    return;
  }
  ImGui::End(ctx_);
  if (style_pushed > 0 && ImGui::PopStyleVar) ImGui::PopStyleVar(ctx_, style_pushed);
}

void HubWindow::paint_idle_frame() {
  if (!ctx_ || !lee::reaimgui::Ready()) return;

  lee::ui::FrameTheme frame;
  bool began = false;
  try {
    frame = lee::ui::BeginCompactFrame(ctx_, theme_fonts_);
    began = true;
    draw_idle_hidden();
    lee::ui::EndFrame(ctx_, frame);
    mark_painted();
  } catch (...) {
    if (began) {
      try {
        lee::ui::EndFrame(ctx_, frame);
      } catch (...) {
      }
    }
    invalidate_context();
  }
}

void HubWindow::prepare() {
  ensure_context();
  refresh_hub_size();
  warm_native_window_once();
}

bool HubWindow::open_at_cursor(void* proj) {
  if (!lee::reaimgui::Ready()) return false;
  if (active_) return true;
  if (!ctx_) ensure_context();
  if (!ctx_) return false;
  if (!GetSession().begin(proj)) return false;
  refresh_hub_size();
  active_ = true;
  first_frame_ = true;
  begin_retry_pending_ = false;
  last_paint_qpc_valid_ = false;
  was_focused_ = false;
  category_pulse_ = 0;
  g_drag_param = ParamId::Count;
  g_wheel_param = ParamId::Count;
  capture_trigger_keys();
  return true;
}

void HubWindow::close() {
  if (!active_) return;
  GetSession().end();
  active_ = false;
  anchor_valid_ = false;
  was_focused_ = false;
  category_pulse_ = 0;
  trigger_keys_.clear();
  g_drag_param = ParamId::Count;
  g_wheel_param = ParamId::Count;
  last_paint_qpc_valid_ = false;
}

void HubWindow::capture_trigger_keys() {
  trigger_keys_.clear();
  BYTE state[256] = {};
  if (!::GetKeyboardState(state)) return;
  for (int vk = 0x08; vk <= 0xFE; ++vk) {
    switch (vk) {
      case VK_LBUTTON:
      case VK_RBUTTON:
      case VK_CANCEL:
      case VK_MBUTTON:
      case VK_XBUTTON1:
      case VK_XBUTTON2:
        continue;
      default:
        break;
    }
    if (state[vk] & 0x80) trigger_keys_.push_back(vk);
  }
}

bool HubWindow::trigger_released() const {
  if (trigger_keys_.empty()) return false;
  for (int vk : trigger_keys_) {
    if (!(::GetAsyncKeyState(vk) & 0x8000)) return true;
  }
  return false;
}

void HubWindow::destroy() {
  close();
  destroy_context();
}

void HubWindow::draw_category_column() {
  auto& session = GetSession();
  const bool can_style = ImGui::PushStyleColor && ImGui::PopStyleColor;
  const double col_h = category_column_height();
  const bool can_style_var = ImGui::PushStyleVar && ImGui::PopStyleVar;
  if (can_style_var) {
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_ItemSpacing, 0.0, kCatRowGap);
  }

  if (!ImGui::BeginChild(ctx_, "##catcol_hub", kCatColWidth, col_h, ImGui::ChildFlags_None)) {
    if (can_style_var) ImGui::PopStyleVar(ctx_, 1);
    ImGui::EndChild(ctx_);
    return;
  }

  if (ImGui::IsWindowHovered && ImGui::IsWindowHovered(ctx_)) {
    double wheel_v = 0.0, wheel_h = 0.0;
    if (ImGui::GetMouseWheel) ImGui::GetMouseWheel(ctx_, &wheel_v, &wheel_h);
    if (wheel_v > 0.0) {
      session.next_category(-1);
      category_pulse_ = 14;
    } else if (wheel_v < 0.0) {
      session.next_category(1);
      category_pulse_ = 14;
    }
  }

  for (int i = 0; i < static_cast<int>(Category::Count); ++i) {
    char cat_stack_id[24];
    std::snprintf(cat_stack_id, sizeof(cat_stack_id), "cat_%d", i);
    if (ImGui::PushID) ImGui::PushID(ctx_, cat_stack_id);

    const Category cat = static_cast<Category>(i);
    const bool sel = session.category() == cat;
    const bool pulse = sel && category_pulse_ > 0;
    int pushed = 0;

    if (sel && can_style) {
      const int bg = pulse ? lee::ui::kSemanticTitle : lee::ui::kSemanticTextHighlight;
      ImGui::PushStyleColor(ctx_, ImGui::Col_Button, bg);
      ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonHovered, lee::ui::kSemanticTextHighlight);
      ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonActive, lee::ui::kSemanticTitle);
      ImGui::PushStyleColor(ctx_, ImGui::Col_Border, lee::ui::kSemanticTextHighlight);
      pushed = 4;
    }

    char cat_id[64];
    std::snprintf(cat_id, sizeof(cat_id), "%s##cat%d", kCategoryLabels[i], i);
    if (ImGui::Button(ctx_, cat_id, kCatColWidth - 8.0, kCatRowHeight)) {
      session.set_category(cat);
      category_pulse_ = 10;
    }

    if (sel && ImGui::GetItemRectMin && ImGui::GetItemRectMax && ImGui::GetWindowDrawList) {
      double x0 = 0.0, y0 = 0.0, x1 = 0.0, y1 = 0.0;
      ImGui::GetItemRectMin(ctx_, &x0, &y0);
      ImGui::GetItemRectMax(ctx_, &x1, &y1);
      ImGui_DrawList* dl = ImGui::GetWindowDrawList(ctx_);
      if (dl) {
        const double bar_w = pulse ? 4.0 : 3.0;
        ImGui::DrawList_AddRectFilled(dl, x0, y0, x0 + bar_w, y1,
                                      lee::ui::kSemanticTextHighlight, 0.0);
      }
    }

    if (pushed > 0) ImGui::PopStyleColor(ctx_, pushed);
    if (ImGui::PopID) ImGui::PopID(ctx_);
  }

  ImGui::EndChild(ctx_);
  if (can_style_var) ImGui::PopStyleVar(ctx_, 1);
}

void HubWindow::draw_param_column() {
  auto& session = GetSession();
  const Category cat = session.category();
  const int n = ParamCountInCategory(cat);
  const double col_h = param_column_height(max_param_count());
  const bool can_style_var = ImGui::PushStyleVar && ImGui::PopStyleVar;
  if (can_style_var) {
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_ItemSpacing, 0.0, kItemSpacingY);
  }

  if (!ImGui::BeginChild(ctx_, "##paramcol_hub", kRowWidth + 8.0, col_h,
                         ImGui::ChildFlags_None)) {
    if (can_style_var) ImGui::PopStyleVar(ctx_, 1);
    ImGui::EndChild(ctx_);
    return;
  }

  for (int i = 0; i < n; ++i) {
    const ParamId id = ParamAt(cat, i);
    const ParamDef& def = Def(id);
    const bool enabled = session.param_enabled(id);
    const bool can_row_style = ImGui::PushStyleColor && ImGui::PopStyleColor;

    char param_stack_id[24];
    std::snprintf(param_stack_id, sizeof(param_stack_id), "param_%d", static_cast<int>(id));
    if (ImGui::PushID) ImGui::PushID(ctx_, param_stack_id);

    const bool dim = !enabled && ImGui::PushStyleVar && ImGui::PopStyleVar;
    if (dim) {
      ImGui::PushStyleVar(ctx_, ImGui::StyleVar_Alpha, 0.45);
    }

    int row_colors = 0;
    if (enabled && can_row_style) {
      ImGui::PushStyleColor(ctx_, ImGui::Col_Header, kParamRowBg);
      ImGui::PushStyleColor(ctx_, ImGui::Col_HeaderHovered, kParamRowBgHover);
      ImGui::PushStyleColor(ctx_, ImGui::Col_HeaderActive, kParamRowBgActive);
      row_colors = 3;
    }

    char val[64];
    session.format_value(id, val, sizeof(val));
    char row_display[128];
    std::snprintf(row_display, sizeof(row_display), "%-14s  [%s]", def.label, val);

    bool row_selected = false;
    ImGui::Selectable(ctx_, row_display, &row_selected, ImGui::SelectableFlags_None, kRowWidth,
                      kParamRowHeight);

    const bool hovered = ImGui::IsItemHovered && ImGui::IsItemHovered(ctx_);
    const bool adjusting = g_drag_param == id || g_wheel_param == id;
    if (!hovered && g_wheel_param == id) g_wheel_param = ParamId::Count;

    if (enabled && (hovered || adjusting) && ImGui::GetItemRectMin && ImGui::GetItemRectMax &&
        ImGui::GetWindowDrawList) {
      double x0 = 0.0, y0 = 0.0, x1 = 0.0, y1 = 0.0;
      ImGui::GetItemRectMin(ctx_, &x0, &y0);
      ImGui::GetItemRectMax(ctx_, &x1, &y1);
      ImGui_DrawList* dl = ImGui::GetWindowDrawList(ctx_);
      if (dl) {
        ImGui::DrawList_AddRectFilled(dl, x0, y0, x0 + 3.0, y1, lee::ui::kSemanticTextHighlight, 0.0);
      }
    }

    if (enabled && hovered) {
      double wheel_v = 0.0, wheel_h = 0.0;
      if (ImGui::GetMouseWheel) ImGui::GetMouseWheel(ctx_, &wheel_v, &wheel_h);
      if (wheel_v != 0.0) {
        const bool fine =
            ImGui::IsMouseDown && ImGui::IsMouseDown(ctx_, ImGui::MouseButton_Right);
        if (g_wheel_param != id) {
          session.on_param_drag_start(id);
          g_wheel_param = id;
        }
        session.wheel_param(id, wheel_v, fine);
      }

      if (ImGui::IsMouseClicked && ImGui::IsMouseClicked(ctx_, ImGui::MouseButton_Left)) {
        if (def.kind == ParamKind::Toggle) session.click_param(id);
      }
      if (ImGui::IsMouseDoubleClicked && ImGui::IsMouseDoubleClicked(ctx_, ImGui::MouseButton_Left)) {
        session.reset_param(id);
      }

      const bool left_drag =
          ImGui::IsMouseDragging && ImGui::IsMouseDragging(ctx_, ImGui::MouseButton_Left);
      const bool right_drag =
          ImGui::IsMouseDragging && ImGui::IsMouseDragging(ctx_, ImGui::MouseButton_Right);
      if (left_drag || right_drag) {
        const bool fine = right_drag;
        const int button = right_drag ? ImGui::MouseButton_Right : ImGui::MouseButton_Left;
        if (g_drag_param != id) {
          session.on_param_drag_start(id);
          g_drag_param = id;
        }
        double dx = 0.0, dy = 0.0;
        if (ImGui::GetMouseDragDelta) ImGui::GetMouseDragDelta(ctx_, &dx, &dy, button);
        if (std::abs(dx) > 0.5) {
          session.adjust_param(id, dx, fine);
          if (ImGui::ResetMouseDragDelta) ImGui::ResetMouseDragDelta(ctx_, button);
        }
      }
      if (ImGui::IsMouseReleased &&
          (ImGui::IsMouseReleased(ctx_, ImGui::MouseButton_Left) ||
           ImGui::IsMouseReleased(ctx_, ImGui::MouseButton_Right))) {
        g_drag_param = ParamId::Count;
      }
    }

    draw_progress_bar(ctx_, session.normalized_value(id));

    if (row_colors > 0) ImGui::PopStyleColor(ctx_, row_colors);
    if (dim) ImGui::PopStyleVar(ctx_, 1);
    if (ImGui::PopID) ImGui::PopID(ctx_);
  }

  ImGui::EndChild(ctx_);
  if (can_style_var) ImGui::PopStyleVar(ctx_, 1);
}

void HubWindow::draw_hub_content() {
  if (ImGui::PushID) ImGui::PushID(ctx_, "hub_content");
  ImGui::BeginGroup(ctx_);
  draw_category_column();
  ImGui::EndGroup(ctx_);

  ImGui::SameLine(ctx_);
  ImGui::BeginGroup(ctx_);
  draw_param_column();
  ImGui::EndGroup(ctx_);
  if (ImGui::PopID) ImGui::PopID(ctx_);
}

void HubWindow::draw_ui() {
  if (!ctx_ || !active_) return;

  const bool was_first = first_frame_;

  if (first_frame_) {
    POINT pt{};
    ::GetCursorPos(&pt);
    anchor_x_ = pt.x + 12.0;
    anchor_y_ = pt.y + 12.0;
    anchor_valid_ = true;
    first_frame_ = false;
  }

  if (category_pulse_ > 0) --category_pulse_;

  if (ImGui::SetNextWindowPos) {
    ImGui::SetNextWindowPos(ctx_, anchor_x_, anchor_y_, ImGui::Cond_Always);
  }
  apply_hub_window_size();

  const lee::ui::FrameTheme frame = lee::ui::BeginCompactFrame(ctx_, theme_fonts_);

  if (ImGui::PushStyleVar) ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowPadding, 8.0, 6.0);
  bool open = true;
  if (ImGui::SetNextWindowBgAlpha) ImGui::SetNextWindowBgAlpha(ctx_, 0.96);

  if (!ImGui::Begin(ctx_, kHubWindowTitle, &open, hub_window_flags(false))) {
    ImGui::End(ctx_);
    if (ImGui::PopStyleVar) ImGui::PopStyleVar(ctx_, 1);
    lee::ui::EndFrame(ctx_, frame);
    if (was_first) {
      begin_retry_pending_ = true;
      first_frame_ = true;
      return;
    }
    close();
    return;
  }
  begin_retry_pending_ = false;

  draw_hub_content();

  const bool focused =
      ImGui::IsWindowFocused && ImGui::IsWindowFocused(ctx_, ImGui::FocusedFlags_RootAndChildWindows);

  bool close_on_focus_loss = false;
  if (trigger_keys_.empty()) {
    if (was_focused_ && !focused) close_on_focus_loss = true;
    was_focused_ = focused;
  }

  GetSession().tick(focused);

  ImGui::End(ctx_);
  if (ImGui::PopStyleVar) ImGui::PopStyleVar(ctx_, 1);
  lee::ui::EndFrame(ctx_, frame);

  if (!open || close_on_focus_loss) close();
}

void HubWindow::invalidate_context() {
  theme_fonts_ = {};
  ctx_ = nullptr;
  anchor_valid_ = false;
  native_warmed_ = false;
  begin_retry_pending_ = false;
  last_paint_qpc_valid_ = false;
}

void HubWindow::tick() {
  if (!lee::reaimgui::Ready()) return;

  if (!active_) {
    if (!ctx_) {
      prepare();
      return;
    }

    paint_idle_frame();
    return;
  }

  if (should_skip_paint()) return;

  if (!ctx_) {
    close();
    return;
  }

  if (trigger_released()) {
    close();
    paint_idle_frame();
    return;
  }

  try {
    draw_ui();
    if (active_) {
      GetSession().flush_deferred_reverse_applies();
      mark_painted();
    } else {
      paint_idle_frame();
    }
  } catch (...) {
    invalidate_context();
    close();
    return;
  }

  if (!GetSession().active()) {
    active_ = false;
  }
}

}  // namespace lee::item_hub
