#include "runtime/WheelView.h"

#include <algorithm>
#include <cmath>

#include "domain/ConfigTypes.h"
#include "domain/Geometry.h"
#include "reaper_imgui_functions.h"
#include "shared/ReaImGuiCoords.h"

namespace lee::radial_menu {
namespace {

constexpr float kGapSize = 3.f;
constexpr int kPinSize = 6;

// Mantrika palette (gui/styles.lua) — (R<<24)|(G<<16)|(B<<8)|A
constexpr int kColSectorIn0 = 0x1E2023E6;
constexpr int kColSectorOut0 = 0x2D3037E6;
constexpr int kColSectorIn1 = 0x283C50FF;
constexpr int kColSectorOut1 = 0x3C648CFF;
constexpr int kColBorder = 0x0F0F0F96;
constexpr int kColText = 0xB4B4B4FF;
constexpr int kColTextActive = 0xFFFFFFFF;
constexpr int kColTextShadow = 0x000000C8;
constexpr int kColPinActive = 0xFFBE28FF;
constexpr int kColPinInactive = 0x505050B4;
constexpr int kColPinShadow = 0x00000096;
constexpr int kColPinGlow = 0xFFD70060;

int BlendWithSector(int base, const Sector& sector, float amount) {
  const int br = (base >> 24) & 0xFF;
  const int bg = (base >> 16) & 0xFF;
  const int bb = (base >> 8) & 0xFF;
  const int ba = base & 0xFF;
  const auto blend = [amount](int a, int b) {
    return static_cast<int>(a + (b - a) * amount);
  };
  return RgbaToU32(blend(br, sector.color.r), blend(bg, sector.color.g),
                   blend(bb, sector.color.b), ba);
}

int SectorColors(const Sector& sector, float expansion_progress, int& col_out) {
  expansion_progress = std::max(0.f, std::min(1.f, expansion_progress));
  const int normal_in = BlendWithSector(kColSectorIn0, sector, 0.18f);
  const int normal_out = BlendWithSector(kColSectorOut0, sector, 0.24f);
  const int active_in = BlendWithSector(kColSectorIn1, sector, 0.12f);
  const int active_out = BlendWithSector(kColSectorOut1, sector, 0.16f);
  if (expansion_progress <= 0.f) {
    col_out = normal_out;
    return normal_in;
  }
  if (expansion_progress >= 1.f) {
    col_out = active_out;
    return active_in;
  }
  auto lerp_u32 = [](int a, int b, float t) -> int {
    const int ar = (a >> 24) & 0xFF, ag = (a >> 16) & 0xFF, ab = (a >> 8) & 0xFF, aa = a & 0xFF;
    const int br = (b >> 24) & 0xFF, bg = (b >> 16) & 0xFF, bb = (b >> 8) & 0xFF, ba = b & 0xFF;
    return RgbaToU32(static_cast<int>(ar + (br - ar) * t), static_cast<int>(ag + (bg - ag) * t),
                     static_cast<int>(ab + (bb - ab) * t), static_cast<int>(aa + (ba - aa) * t));
  };
  const float t = expansion_progress;
  col_out = lerp_u32(normal_out, active_out, t);
  return lerp_u32(normal_in, active_in, t);
}

int SegmentCount(float avg_radius, float angle_span) {
  int segments = 32;
  if (avg_radius < 50.f) segments = 16;
  else if (avg_radius < 100.f) segments = 24;
  const float ratio = std::abs(angle_span) / static_cast<float>(kTwoPi);
  return std::max(12, static_cast<int>(segments * ratio));
}

void DrawArcStroke(ImGui_DrawList* dl, float cx, float cy, float inner_r, float outer_r,
                   float a0, float a1, int color) {
  if (!dl || !ImGui::DrawList_PathClear || !ImGui::DrawList_PathArcTo) return;
  const float thickness = outer_r - inner_r;
  const float avg_r = (inner_r + outer_r) * 0.5f;
  const float span = a1 - a0;
  const int segments = SegmentCount(avg_r, span);

  ImGui::DrawList_PathClear(dl);
  ImGui::DrawList_PathArcTo(dl, cx, cy, avg_r, a0, a1, segments);
  if (ImGui::DrawList_PathStroke) {
    ImGui::DrawList_PathStroke(dl, color, 0, thickness);
    return;
  }

  if (!ImGui::DrawList_PathFillConvex) return;
  ImGui::DrawList_PathClear(dl);
  ImGui::DrawList_PathArcTo(dl, cx, cy, outer_r, a0, a1, segments);
  ImGui::DrawList_PathArcTo(dl, cx, cy, inner_r, a1, a0, segments);
  ImGui::DrawList_PathFillConvex(dl, color);
}

void DrawBorderArc(ImGui_DrawList* dl, float cx, float cy, float radius, float a0, float a1,
                   int color, float thickness) {
  if (!dl || !ImGui::DrawList_AddLine) return;

  const float span = a1 - a0;
  const int segments = SegmentCount(radius, span);
  for (int i = 0; i < segments; ++i) {
    const float t0 = static_cast<float>(i) / segments;
    const float t1 = static_cast<float>(i + 1) / segments;
    const float x1 = cx + radius * std::cos(a0 + span * t0);
    const float y1 = cy + radius * std::sin(a0 + span * t0);
    const float x2 = cx + radius * std::cos(a0 + span * t1);
    const float y2 = cy + radius * std::sin(a0 + span * t1);
    ImGui::DrawList_AddLine(dl, x1, y1, x2, y2, color, thickness);
  }
}

void DrawSectorGapFill(ImGui_DrawList* dl, float cx, float cy, float inner_r, float outer_r,
                       float start_angle, float draw_start, float end_angle, float draw_end) {
  const float overlap = 1.5f / std::max(outer_r, 1.f);
  if (draw_start > start_angle) {
    DrawArcStroke(dl, cx, cy, inner_r, outer_r, start_angle, draw_start + overlap, kColBorder);
    DrawBorderArc(dl, cx, cy, inner_r, start_angle, draw_start + overlap, kColBorder, kGapSize);
    DrawBorderArc(dl, cx, cy, outer_r, start_angle, draw_start + overlap, kColBorder, kGapSize);
  }
  if (end_angle > draw_end) {
    DrawArcStroke(dl, cx, cy, inner_r, outer_r, draw_end - overlap, end_angle, kColBorder);
    DrawBorderArc(dl, cx, cy, inner_r, draw_end - overlap, end_angle, kColBorder, kGapSize);
    DrawBorderArc(dl, cx, cy, outer_r, draw_end - overlap, end_angle, kColBorder, kGapSize);
  }
}

void DrawRimLight(ImGui_DrawList* dl, float cx, float cy, float outer_r, float a0, float a1,
                  float expansion_progress) {
  if (!dl || expansion_progress <= 0.f || !ImGui::DrawList_AddLine) return;

  const int alpha = std::min(255, std::max(0, static_cast<int>(30.f * expansion_progress)));
  const int rim = RgbaToU32(255, 255, 255, alpha);
  const float span = a1 - a0;
  const int segments = 32;
  for (int i = 0; i < segments; ++i) {
    const float t0 = static_cast<float>(i) / segments;
    const float t1 = static_cast<float>(i + 1) / segments;
    const float r = outer_r - 1.f;
    ImGui::DrawList_AddLine(dl, cx + r * std::cos(a0 + span * t0), cy + r * std::sin(a0 + span * t0),
                            cx + r * std::cos(a0 + span * t1), cy + r * std::sin(a0 + span * t1),
                            rim, 2.0);
  }
}

void DrawPinButton(ImGui_DrawList* dl, float cx, float cy, bool is_pinned) {
  if (!dl || !ImGui::DrawList_AddQuadFilled) return;

  const float s = static_cast<float>(kPinSize);
  const int color = is_pinned ? kColPinActive : kColPinInactive;

  ImGui::DrawList_AddQuadFilled(dl, cx, cy - s + 2.f, cx + s + 2.f, cy + 2.f, cx, cy + s + 4.f,
                                cx - s + 2.f, cy + 2.f, kColPinShadow);
  ImGui::DrawList_AddQuadFilled(dl, cx, cy - s, cx + s, cy, cx, cy + s, cx - s, cy, color);

  if (is_pinned && ImGui::DrawList_AddQuad) {
    ImGui::DrawList_AddQuad(dl, cx, cy - s - 3.f, cx + s + 3.f, cy, cx, cy + s + 3.f,
                            cx - s - 3.f, cy, kColPinGlow, 2.0);
  }
}

void DrawWheelFoundation(ImGui_DrawList* dl, float cx, float cy, float inner_r,
                         float outer_r) {
  if (!dl) return;
  // Soft ring shadow plus a translucent center plate. This keeps the wheel
  // readable over REAPER's arrange grid while retaining the overlay feel.
  DrawArcStroke(dl, cx, cy + 3.f, std::max(0.f, inner_r - 3.f), outer_r + 7.f,
                0.f, static_cast<float>(kTwoPi), RgbaToU32(0, 0, 0, 42));
  DrawArcStroke(dl, cx, cy + 2.f, std::max(0.f, inner_r - 1.f), outer_r + 4.f,
                0.f, static_cast<float>(kTwoPi), RgbaToU32(0, 0, 0, 64));
  if (ImGui::DrawList_AddCircleFilled) {
    ImGui::DrawList_AddCircleFilled(dl, cx, cy, std::max(0.f, inner_r - 1.f),
                                    RgbaToU32(50, 50, 50, 218), 48);
  }
  if (ImGui::DrawList_AddCircle) {
    ImGui::DrawList_AddCircle(dl, cx, cy, inner_r, RgbaToU32(15, 15, 15, 190), 48, 2.0);
  }
}

void DrawSectorText(ImGui_Context* ctx, ImGui_DrawList* dl, float cx, float cy, float text_radius,
                    float a0, float a1, const Sector& sector, bool is_active) {
  if (!ctx || !dl || !ImGui::GetTextLineHeight || !ImGui::CalcTextSize ||
      !ImGui::DrawList_AddText) {
    return;
  }

  const float center_angle = (a0 + a1) * 0.5f;
  const float tx = cx + text_radius * std::cos(center_angle);
  const float ty = cy + text_radius * std::sin(center_angle);

  const auto& lines = sector.cached_lines;
  if (lines.empty()) return;

  const float line_h = static_cast<float>(ImGui::GetTextLineHeight(ctx));
  const float total_h = line_h * static_cast<float>(lines.size());
  float cursor_y = ty - total_h * 0.5f;

  const int text_u32 = is_active ? kColTextActive : kColText;

  for (const std::string& line : lines) {
    if (line.empty()) {
      cursor_y += line_h;
      continue;
    }
    double text_w = 0;
    double text_h_unused = 0;
    ImGui::CalcTextSize(ctx, line.c_str(), &text_w, &text_h_unused);
    const float text_x = tx - static_cast<float>(text_w) * 0.5f;
    ImGui::DrawList_AddText(dl, text_x + 1.f, cursor_y + 1.f, kColTextShadow, line.c_str());
    ImGui::DrawList_AddText(dl, text_x, cursor_y, text_u32, line.c_str());
    cursor_y += line_h;
  }
}

}  // namespace

void DrawWheel(ImGui_Context* ctx, const AppConfig& cfg, int hovered_sector_index,
               int active_sector_index, bool is_pinned, float anim_scale,
               const float* sector_expansion_progress, int sector_count) {
  if (!ctx || !ImGui::GetWindowDrawList || !ImGui::GetWindowSize || !ImGui::GetWindowPos) return;

  ImGui_DrawList* dl = ImGui::GetWindowDrawList(ctx);
  if (!dl) return;

  double ww = 0, wh = 0, wx = 0, wy = 0;
  ImGui::GetWindowSize(ctx, &ww, &wh);
  ImGui::GetWindowPos(ctx, &wx, &wy);
  if (ww <= 0 || wh <= 0) return;

  const float cx = static_cast<float>(wx + ww * 0.5);
  const float cy = static_cast<float>(wy + wh * 0.5);
  const float inner = static_cast<float>(cfg.menu.inner_radius * anim_scale);
  const float outer_base = static_cast<float>(cfg.menu.outer_radius * anim_scale);
  const int n = static_cast<int>(cfg.sectors.size());
  if (n < 1) return;

  int style_pushed = 0;
  if (ImGui::PushStyleVar) {
    ImGui::PushStyleVar(ctx, ImGui::StyleVar_Alpha, static_cast<double>(anim_scale));
    ++style_pushed;
  }

  const float step = static_cast<float>(kTwoPi / n);
  const bool expansion_enabled = cfg.menu.enable_sector_expansion;
  const float max_expand_px =
      std::min(static_cast<float>(cfg.menu.hover_expansion_pixels), 10.f);

  DrawWheelFoundation(dl, cx, cy, inner, outer_base);

  for (int i = 0; i < n; ++i) {
    const float a0 = static_cast<float>(kStartOffset + i * step);
    const float a1 = static_cast<float>(kStartOffset + (i + 1) * step);

    const bool hot = (i == hovered_sector_index) || (i == active_sector_index);
    float expansion_progress = 0.f;
    if (sector_expansion_progress && i < sector_count) {
      expansion_progress = sector_expansion_progress[i];
    }
    if (!expansion_enabled) {
      expansion_progress = hot ? 1.f : 0.f;
    }

    float expand_px = 0.f;
    if (expansion_enabled && hot) expand_px = max_expand_px;
    expand_px *= expansion_progress;

    const float outer = outer_base + expand_px;
    const float gap_rad =
        kGapSize / std::max(1.f, static_cast<float>(cfg.menu.outer_radius));
    const float draw_start = a0 + gap_rad;
    const float draw_end = a1 - gap_rad;

    int col_out = kColSectorOut0;
    SectorColors(cfg.sectors[i], expansion_progress, col_out);

    DrawSectorGapFill(dl, cx, cy, inner, outer, a0, draw_start, a1, draw_end);
    DrawArcStroke(dl, cx, cy, inner, outer, draw_start, draw_end, col_out);
    if (expansion_progress > 0.f) {
      DrawRimLight(dl, cx, cy, outer, draw_start, draw_end, expansion_progress);
    }
    DrawBorderArc(dl, cx, cy, inner, draw_start, draw_end, kColBorder, kGapSize);
    DrawBorderArc(dl, cx, cy, outer, draw_start, draw_end, kColBorder, kGapSize);

    const float text_radius = (inner + outer) * 0.5f;
    DrawSectorText(ctx, dl, cx, cy, text_radius, a0, a1, cfg.sectors[i],
                   expansion_progress > 0.5f);
  }

  // Redraw the center plate after the thick sector strokes so the inner edge
  // remains clean and circular.
  if (ImGui::DrawList_AddCircleFilled) {
    ImGui::DrawList_AddCircleFilled(dl, cx, cy, std::max(0.f, inner - 1.f),
                                    RgbaToU32(50, 50, 50, 218), 48);
  }
  if (ImGui::DrawList_AddCircle) {
    ImGui::DrawList_AddCircle(dl, cx, cy, inner, RgbaToU32(15, 15, 15, 190), 48, 2.0);
  }
  DrawPinButton(dl, cx, cy, is_pinned);

  if (style_pushed > 0 && ImGui::PopStyleVar) ImGui::PopStyleVar(ctx, style_pushed);
}

}  // namespace lee::radial_menu
