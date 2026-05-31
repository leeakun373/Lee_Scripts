#pragma once

class ImGui_Context;
class ImGui_Font;

namespace lee::ui {

// C++ port of Shared/Toolbox/framework/ui_colors.lua + ui_style.lua + ui_font.lua.
// Applies the same dark + teal Toolbox skin through ReaImGui (no embedded ImGui).

struct ThemeFonts {
  ImGui_Font* default_font = nullptr;
  ImGui_Font* bold = nullptr;
  ImGui_Font* heading = nullptr;
  bool attached = false;
};

struct FrameTheme {
  int color_count = 0;
  int var_count = 0;
  bool default_font_pushed = false;
};

// Attach Segoe UI fonts to `ctx` (idempotent per context pointer).
void EnsureFonts(ImGui_Context* ctx, ThemeFonts& fonts);

void DestroyFonts(ImGui_Context* ctx, ThemeFonts& fonts);

// Call once per ImGui frame, before ImGui::Begin. Pushes StyleVar + Col_* overrides.
FrameTheme BeginFrame(ImGui_Context* ctx, ThemeFonts& fonts);

// Call after all ImGui::End for this frame.
void EndFrame(ImGui_Context* ctx, const FrameTheme& frame);

// Semantic colors from ui_colors.lua (not ImGui.Col_*).
constexpr int kSemanticTextDim = static_cast<int>(4294967193u);
constexpr int kSemanticTextHighlight = static_cast<int>(866944255u);
constexpr int kSemanticTitle = static_cast<int>(1403886591u);

}  // namespace lee::ui
