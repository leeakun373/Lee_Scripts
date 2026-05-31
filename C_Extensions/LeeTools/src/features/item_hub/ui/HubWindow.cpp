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

// Fixed row width. Selectable() with width 0 fills the available content
// region, which combined with WindowFlags_AlwaysAutoResize creates a feedback
// loop that grows the window every frame until ReaImGui asserts and REAPER
// crashes. An explicit width keeps auto-resize stable.
constexpr double kRowWidth = 210.0;

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

bool HubWindow::open_at_cursor(void* proj) {
  if (!lee::reaimgui::Ready()) return false;
  ensure_context();
  if (!ctx_) return false;
  if (!GetSession().begin(proj)) return false;
  active_ = true;
  first_frame_ = true;
  was_focused_ = false;
  capture_trigger_keys();
  return true;
}

void HubWindow::close() {
  if (!active_) return;
  GetSession().end();
  active_ = false;
  was_focused_ = false;
  trigger_keys_.clear();
}

void HubWindow::capture_trigger_keys() {
  trigger_keys_.clear();
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
    if (::GetAsyncKeyState(vk) & 0x8000) trigger_keys_.push_back(vk);
  }
}

bool HubWindow::trigger_released() const {
  // No key was held when we opened (e.g. triggered from a menu / mouse gesture):
  // fall back to focus-loss closing handled in draw_ui.
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
  const bool can_color = ImGui::PushStyleColor && ImGui::PopStyleColor;
  for (int i = 0; i < static_cast<int>(Category::Count); ++i) {
    const Category cat = static_cast<Category>(i);
    const bool sel = session.category() == cat;
    const bool pushed = sel && can_color;
    if (pushed) {
      ImGui::PushStyleColor(ctx_, ImGui::Col_Border, lee::ui::kSemanticTextHighlight);
    }
    if (ImGui::Button(ctx_, kCategoryLabels[i], 108.0, 26.0)) {
      session.set_category(cat);
    }
    if (pushed) ImGui::PopStyleColor(ctx_, 1);
  }
}

void HubWindow::draw_param_column() {
  auto& session = GetSession();
  const Category cat = session.category();
  const int n = ParamCountInCategory(cat);
  for (int i = 0; i < n; ++i) {
    const ParamId id = ParamAt(cat, i);
    const ParamDef& def = Def(id);
    const bool enabled = session.param_enabled(id);

    ImGui::PushID(ctx_, std::to_string(static_cast<int>(id)).c_str());
    const bool dim = !enabled && ImGui::PushStyleVar && ImGui::PopStyleVar;
    if (dim) {
      ImGui::PushStyleVar(ctx_, ImGui::StyleVar_Alpha, 0.45);
    }

    char val[64];
    session.format_value(id, val, sizeof(val));
    char row[128];
    std::snprintf(row, sizeof(row), "%-14s  [%s]", def.label, val);

    bool row_selected = false;
    ImGui::Selectable(ctx_, row, &row_selected, ImGui::SelectableFlags_None, kRowWidth, 0.0);
    const bool hovered = ImGui::IsItemHovered && ImGui::IsItemHovered(ctx_);

    if (enabled && hovered) {
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
        // Right-drag = fine mode (lower sensitivity), per the spec.
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

    if (dim) ImGui::PopStyleVar(ctx_, 1);
    ImGui::PopID(ctx_);
  }
}

void HubWindow::draw_ui() {
  if (!ctx_ || !active_) return;

  if (first_frame_) {
    POINT pt{};
    ::GetCursorPos(&pt);
    if (ImGui::SetNextWindowPos) {
      ImGui::SetNextWindowPos(ctx_, pt.x + 12.0, pt.y + 12.0, ImGui::Cond_Always);
    }
    if (ImGui::SetNextWindowFocus) ImGui::SetNextWindowFocus(ctx_);
    first_frame_ = false;
  }

  const int flags = ImGui::WindowFlags_NoTitleBar | ImGui::WindowFlags_NoDocking |
                    ImGui::WindowFlags_AlwaysAutoResize | ImGui::WindowFlags_NoSavedSettings;
  if (ImGui::PushStyleVar) ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowPadding, 8.0, 6.0);
  bool open = true;
  if (ImGui::SetNextWindowBgAlpha) ImGui::SetNextWindowBgAlpha(ctx_, 0.96);
  if (!ImGui::Begin(ctx_, "Item Hub##lee", &open, flags)) {
    ImGui::End(ctx_);
    if (ImGui::PopStyleVar) ImGui::PopStyleVar(ctx_, 1);
    close();
    return;
  }

  double wheel_v = 0.0, wheel_h = 0.0;
  if (ImGui::GetMouseWheel) ImGui::GetMouseWheel(ctx_, &wheel_v, &wheel_h);
  if (wheel_v > 0.0) GetSession().next_category(-1);
  if (wheel_v < 0.0) GetSession().next_category(1);

  ImGui::BeginGroup(ctx_);
  draw_category_column();
  ImGui::EndGroup(ctx_);

  ImGui::SameLine(ctx_);
  ImGui::BeginGroup(ctx_);
  draw_param_column();
  ImGui::EndGroup(ctx_);

  const bool focused =
      ImGui::IsWindowFocused && ImGui::IsWindowFocused(ctx_, ImGui::FocusedFlags_RootAndChildWindows);

  // Focus-loss closing is only a fallback for triggers with no held key (e.g.
  // mouse-gesture / menu). When a key is held, tick()'s key polling owns the
  // close so we don't fight the OS focus that stays in the arrange view.
  bool close_on_focus_loss = false;
  if (trigger_keys_.empty()) {
    if (was_focused_ && !focused) close_on_focus_loss = true;
    was_focused_ = focused;
  }

  GetSession().tick(focused);

  ImGui::End(ctx_);
  if (ImGui::PopStyleVar) ImGui::PopStyleVar(ctx_, 1);
  if (!open || close_on_focus_loss) close();
}

void HubWindow::invalidate_context() {
  // Drop the context AND the fonts together. Fonts are attached per-context, so
  // forgetting the context without clearing theme_fonts_ would make the next
  // BeginFrame PushFont() throw (font not attached to the fresh context), which
  // leaks the style stack and surfaces as "Missing PopStyleColor".
  theme_fonts_ = {};
  ctx_ = nullptr;
}

void HubWindow::tick() {
  if (!active_ || !ctx_) return;
  // Momentary behaviour: once the user releases the trigger key, close.
  if (trigger_released()) {
    close();
    return;
  }

  // ReaImGui throws if a frame goes wrong (e.g. invalidated context). Whatever
  // happens, the style stack pushed by BeginFrame must be unwound by EndFrame,
  // otherwise the next frame reports "Missing PopStyleColor" and ImGui asserts.
  lee::ui::FrameTheme frame;
  bool began = false;
  bool failed = false;
  try {
    frame = lee::ui::BeginFrame(ctx_, theme_fonts_);
    began = true;
    draw_ui();
    lee::ui::EndFrame(ctx_, frame);
    began = false;
  } catch (...) {
    failed = true;
  }

  if (failed) {
    if (began) {
      try {
        lee::ui::EndFrame(ctx_, frame);
      } catch (...) {
      }
    }
    invalidate_context();
    close();
    return;
  }

  if (!GetSession().active()) {
    active_ = false;
  }
}

}  // namespace lee::item_hub
