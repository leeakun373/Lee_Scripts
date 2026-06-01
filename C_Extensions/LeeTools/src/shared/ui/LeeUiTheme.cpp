#include "shared/ui/LeeUiTheme.h"

#include "reaper_imgui_functions.h"

#include "shared/reaper/ReaImGuiApi.h"

#ifdef CreateFont
#undef CreateFont
#endif

namespace lee::ui {
namespace {

// u32 table from Shared/Toolbox/framework/ui_colors.lua
namespace colors {
constexpr int DragDropTarget = static_cast<int>(331192831u);
constexpr int FrameBg = static_cast<int>(1920102948u);
constexpr int FrameBgHovered = static_cast<int>(2155905124u);
constexpr int FrameBgActive = static_cast<int>(2155905152u);
constexpr int CheckMark = static_cast<int>(331192831u);
constexpr int TitleBg = static_cast<int>(623191551u);
constexpr int TitleBgActive = static_cast<int>(808464639u);
constexpr int TitleBgCollapsed = static_cast<int>(538976511u);
constexpr int Button = static_cast<int>(1616928870u);
constexpr int ButtonHovered = static_cast<int>(1616929023u);
constexpr int ButtonActive = static_cast<int>(2155905279u);
constexpr int Text = static_cast<int>(4294967262u);
constexpr int TextDisabled = static_cast<int>(4294967137u);
constexpr int TextSelectedBg = static_cast<int>(905958500u);
constexpr int ResizeGrip = static_cast<int>(2155905024u);
constexpr int Separator = static_cast<int>(2155905152u);
constexpr int SeparatorHovered = static_cast<int>(2155905223u);
constexpr int SeparatorActive = static_cast<int>(2155905279u);
constexpr int Tab = static_cast<int>(1616928870u);
constexpr int TabHovered = static_cast<int>(1616929023u);
constexpr int TabActive = static_cast<int>(1819045119u);
constexpr int WindowBg = static_cast<int>(538976511u);
constexpr int PopupBg = static_cast<int>(538976496u);
constexpr int ScrollbarBg = static_cast<int>(404232327u);
constexpr int Header = static_cast<int>(1616928870u);
constexpr int HeaderHovered = static_cast<int>(1616929023u);
constexpr int HeaderActive = static_cast<int>(2155905279u);
constexpr int NavHighlight = static_cast<int>(331192776u);
constexpr int TableRowBg = static_cast<int>(4294967040u);
constexpr int TableRowBgAlt = static_cast<int>(4294967044u);
constexpr int SliderGrab = static_cast<int>(331192776u);
constexpr int SliderGrabActive = static_cast<int>(905958621u);
constexpr int TableBorderLight = static_cast<int>(993737727u);
constexpr int TableBorderStrong = static_cast<int>(1330597887u);
constexpr int TableHeaderBg = static_cast<int>(858993663u);
constexpr int TabUnfocused = static_cast<int>(640034552u);
constexpr int TabUnfocusedActive = static_cast<int>(1819045119u);
}  // namespace colors

ImGui_Resource* as_resource(ImGui_Font* font) {
  return reinterpret_cast<ImGui_Resource*>(font);
}

void push_color(ImGui_Context* ctx, int col, int u32, int& count) {
  if (!ImGui::PushStyleColor || !col) return;
  ImGui::PushStyleColor(ctx, col, u32);
  ++count;
}

void push_var1(ImGui_Context* ctx, int var, double v, int& count) {
  if (!ImGui::PushStyleVar || !var) return;
  ImGui::PushStyleVar(ctx, var, v);
  ++count;
}

void push_var2(ImGui_Context* ctx, int var, double x, double y, int& count) {
  if (!ImGui::PushStyleVar || !var) return;
  ImGui::PushStyleVar(ctx, var, x, y);
  ++count;
}

int push_toolbox_colors(ImGui_Context* ctx) {
  int n = 0;
  using namespace colors;
  push_color(ctx, ImGui::Col_DragDropTarget, DragDropTarget, n);
  push_color(ctx, ImGui::Col_FrameBg, FrameBg, n);
  push_color(ctx, ImGui::Col_FrameBgHovered, FrameBgHovered, n);
  push_color(ctx, ImGui::Col_FrameBgActive, FrameBgActive, n);
  push_color(ctx, ImGui::Col_CheckMark, CheckMark, n);
  push_color(ctx, ImGui::Col_TitleBg, TitleBg, n);
  push_color(ctx, ImGui::Col_TitleBgActive, TitleBgActive, n);
  push_color(ctx, ImGui::Col_TitleBgCollapsed, TitleBgCollapsed, n);
  push_color(ctx, ImGui::Col_Button, Button, n);
  push_color(ctx, ImGui::Col_ButtonHovered, ButtonHovered, n);
  push_color(ctx, ImGui::Col_ButtonActive, ButtonActive, n);
  push_color(ctx, ImGui::Col_Text, Text, n);
  push_color(ctx, ImGui::Col_TextDisabled, TextDisabled, n);
  push_color(ctx, ImGui::Col_TextSelectedBg, TextSelectedBg, n);
  push_color(ctx, ImGui::Col_ResizeGrip, ResizeGrip, n);
  push_color(ctx, ImGui::Col_ResizeGripHovered, ResizeGrip, n);
  push_color(ctx, ImGui::Col_ResizeGripActive, ResizeGrip, n);
  push_color(ctx, ImGui::Col_Separator, Separator, n);
  push_color(ctx, ImGui::Col_SeparatorHovered, SeparatorHovered, n);
  push_color(ctx, ImGui::Col_SeparatorActive, SeparatorActive, n);
  push_color(ctx, ImGui::Col_Tab, Tab, n);
  push_color(ctx, ImGui::Col_TabHovered, TabHovered, n);
  push_color(ctx, ImGui::Col_TabSelected, TabActive, n);
  push_color(ctx, ImGui::Col_TabDimmed, TabUnfocused, n);
  push_color(ctx, ImGui::Col_TabDimmedSelected, TabUnfocusedActive, n);
  push_color(ctx, ImGui::Col_WindowBg, WindowBg, n);
  push_color(ctx, ImGui::Col_PopupBg, PopupBg, n);
  push_color(ctx, ImGui::Col_ScrollbarBg, ScrollbarBg, n);
  push_color(ctx, ImGui::Col_Header, Header, n);
  push_color(ctx, ImGui::Col_HeaderHovered, HeaderHovered, n);
  push_color(ctx, ImGui::Col_HeaderActive, HeaderActive, n);
  push_color(ctx, ImGui::Col_NavCursor, NavHighlight, n);
  push_color(ctx, ImGui::Col_TableRowBg, TableRowBg, n);
  push_color(ctx, ImGui::Col_TableRowBgAlt, TableRowBgAlt, n);
  push_color(ctx, ImGui::Col_TableBorderLight, TableBorderLight, n);
  push_color(ctx, ImGui::Col_TableBorderStrong, TableBorderStrong, n);
  push_color(ctx, ImGui::Col_TableHeaderBg, TableHeaderBg, n);
  push_color(ctx, ImGui::Col_SliderGrab, SliderGrab, n);
  push_color(ctx, ImGui::Col_SliderGrabActive, SliderGrabActive, n);
  push_color(ctx, ImGui::Col_Border, -2139062144, n);
  return n;
}

int push_toolbox_style(ImGui_Context* ctx) {
  // Shared/Toolbox/framework/ui_style.lua defaults
  int n = 0;
  push_var1(ctx, ImGui::StyleVar_Alpha, 1.0, n);
  push_var1(ctx, ImGui::StyleVar_DisabledAlpha, 0.6, n);
  push_var2(ctx, ImGui::StyleVar_WindowPadding, 8.0, 4.0, n);
  push_var2(ctx, ImGui::StyleVar_FramePadding, 4.0, 3.0, n);
  push_var2(ctx, ImGui::StyleVar_CellPadding, 4.0, 4.0, n);
  push_var2(ctx, ImGui::StyleVar_ItemSpacing, 4.0, 4.0, n);
  push_var2(ctx, ImGui::StyleVar_ItemInnerSpacing, 4.0, 4.0, n);
  push_var1(ctx, ImGui::StyleVar_IndentSpacing, 21.0, n);
  push_var1(ctx, ImGui::StyleVar_ScrollbarSize, 14.0, n);
  push_var1(ctx, ImGui::StyleVar_GrabMinSize, 12.0, n);
  push_var1(ctx, ImGui::StyleVar_WindowBorderSize, 1.0, n);
  push_var1(ctx, ImGui::StyleVar_ChildBorderSize, 1.0, n);
  push_var1(ctx, ImGui::StyleVar_PopupBorderSize, 1.0, n);
  push_var1(ctx, ImGui::StyleVar_FrameBorderSize, 0.0, n);
  push_var1(ctx, ImGui::StyleVar_WindowRounding, 8.0, n);
  push_var1(ctx, ImGui::StyleVar_ChildRounding, 0.0, n);
  push_var1(ctx, ImGui::StyleVar_FrameRounding, 2.0, n);
  push_var1(ctx, ImGui::StyleVar_PopupRounding, 4.0, n);
  push_var1(ctx, ImGui::StyleVar_ScrollbarRounding, 4.0, n);
  push_var1(ctx, ImGui::StyleVar_GrabRounding, 2.0, n);
  push_var1(ctx, ImGui::StyleVar_TabRounding, 2.0, n);
  push_var2(ctx, ImGui::StyleVar_WindowTitleAlign, 0.5, 0.5, n);
  push_var2(ctx, ImGui::StyleVar_ButtonTextAlign, 0.5, 0.5, n);
  push_var2(ctx, ImGui::StyleVar_SelectableTextAlign, 0.0, 0.5, n);
  return n;
}

int push_compact_colors(ImGui_Context* ctx) {
  int n = 0;
  using namespace colors;
  push_color(ctx, ImGui::Col_WindowBg, WindowBg, n);
  push_color(ctx, ImGui::Col_Text, Text, n);
  push_color(ctx, ImGui::Col_TextDisabled, TextDisabled, n);
  push_color(ctx, ImGui::Col_Button, Button, n);
  push_color(ctx, ImGui::Col_ButtonHovered, ButtonHovered, n);
  push_color(ctx, ImGui::Col_ButtonActive, ButtonActive, n);
  push_color(ctx, ImGui::Col_Border, -2139062144, n);
  push_color(ctx, ImGui::Col_Header, Header, n);
  push_color(ctx, ImGui::Col_HeaderHovered, HeaderHovered, n);
  push_color(ctx, ImGui::Col_FrameBg, FrameBg, n);
  return n;
}

int push_compact_style(ImGui_Context* ctx) {
  int n = 0;
  push_var2(ctx, ImGui::StyleVar_WindowPadding, 8.0, 4.0, n);
  push_var2(ctx, ImGui::StyleVar_FramePadding, 4.0, 3.0, n);
  push_var2(ctx, ImGui::StyleVar_ItemSpacing, 4.0, 4.0, n);
  push_var1(ctx, ImGui::StyleVar_WindowRounding, 8.0, n);
  push_var1(ctx, ImGui::StyleVar_WindowBorderSize, 1.0, n);
  return n;
}

}  // namespace

void EnsureFonts(ImGui_Context* ctx, ThemeFonts& fonts) {
  if (!ctx || fonts.attached || !lee::reaimgui::Ready()) return;
  auto create_font = ImGui::CreateFont;
  if (!create_font || !ImGui::Attach) return;
  try {
    fonts.default_font = create_font("Segoe UI");
    fonts.bold = create_font("Segoe UI", ImGui::FontFlags_Bold);
    fonts.heading = create_font("Segoe UI", ImGui::FontFlags_Bold);
    if (fonts.default_font) ImGui::Attach(ctx, as_resource(fonts.default_font));
    if (fonts.bold) ImGui::Attach(ctx, as_resource(fonts.bold));
    if (fonts.heading) ImGui::Attach(ctx, as_resource(fonts.heading));
    fonts.attached = fonts.default_font != nullptr;
  } catch (...) {
    fonts = {};
  }
}

void DestroyFonts(ImGui_Context* ctx, ThemeFonts& fonts) {
  if (!ctx || !fonts.attached || !ImGui::Detach) {
    fonts = {};
    return;
  }
  try {
    if (fonts.default_font) ImGui::Detach(ctx, as_resource(fonts.default_font));
    if (fonts.bold) ImGui::Detach(ctx, as_resource(fonts.bold));
    if (fonts.heading) ImGui::Detach(ctx, as_resource(fonts.heading));
  } catch (...) {
  }
  fonts = {};
}

FrameTheme BeginFrame(ImGui_Context* ctx, ThemeFonts& fonts) {
  FrameTheme frame;
  if (!ctx || !lee::reaimgui::Ready()) return frame;
  EnsureFonts(ctx, fonts);
  frame.var_count = push_toolbox_style(ctx);
  frame.color_count = push_toolbox_colors(ctx);
  if (fonts.default_font && ImGui::PushFont) {
    ImGui::PushFont(ctx, fonts.default_font, 14.0);
    frame.default_font_pushed = true;
  }
  return frame;
}

FrameTheme BeginCompactFrame(ImGui_Context* ctx, ThemeFonts& fonts) {
  FrameTheme frame;
  if (!ctx || !lee::reaimgui::Ready()) return frame;
  EnsureFonts(ctx, fonts);
  frame.var_count = push_compact_style(ctx);
  frame.color_count = push_compact_colors(ctx);
  if (fonts.default_font && ImGui::PushFont) {
    ImGui::PushFont(ctx, fonts.default_font, 14.0);
    frame.default_font_pushed = true;
  }
  return frame;
}

void EndFrame(ImGui_Context* ctx, const FrameTheme& frame) {
  if (!ctx) return;
  if (frame.default_font_pushed && ImGui::PopFont) {
    ImGui::PopFont(ctx);
  }
  if (frame.color_count > 0 && ImGui::PopStyleColor) {
    ImGui::PopStyleColor(ctx, frame.color_count);
  }
  if (frame.var_count > 0 && ImGui::PopStyleVar) {
    ImGui::PopStyleVar(ctx, frame.var_count);
  }
}

}  // namespace lee::ui
