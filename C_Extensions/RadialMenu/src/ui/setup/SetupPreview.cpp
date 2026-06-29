#include "ui/setup/SetupPreview.h"

#include <cmath>
#include <string>
#include <vector>

#include "domain/ConfigTypes.h"
#include "domain/Geometry.h"
#include "reaper_imgui_functions.h"
#include "shared/ReaImGuiCoords.h"

namespace lee::radial_menu {
namespace {

constexpr float kGapSize = 3.f;
constexpr int kPinSize = 6;
constexpr int kColSectorIn = 0x1E2023E6;
constexpr int kColSectorOut = 0x2D3037E6;
constexpr int kColSectorInSel = 0x283C50FF;
constexpr int kColSectorOutSel = 0x3C648CFF;
constexpr int kColText = 0xB4B4B4FF;
constexpr int kColTextActive = 0xFFFFFFFF;
constexpr int kColTextShadow = 0x000000C8;
constexpr int kColPinInactive = 0x505050B4;
constexpr int kColPinShadow = 0x00000096;

void SectorAngles(int index, int total, float& a0, float& a1) {
  if (total <= 0) {
    a0 = a1 = 0;
    return;
  }
  const float step = static_cast<float>(kTwoPi / total);
  a0 = static_cast<float>(kStartOffset + index * step);
  a1 = static_cast<float>(kStartOffset + (index + 1) * step);
}

}  // namespace

void DrawSetupPreview(ImGui_Context* ctx, const AppConfig& cfg, int selected_sector_index,
                      double center_x, double center_y) {
  if (!ctx || !ImGui::GetWindowDrawList) return;
  ImGui_DrawList* dl = ImGui::GetWindowDrawList(ctx);
  if (!dl) return;

  const int n = static_cast<int>(cfg.sectors.size());
  if (n < 1) return;

  const float cx = static_cast<float>(center_x);
  const float cy = static_cast<float>(center_y);
  const float inner = static_cast<float>(cfg.menu.inner_radius);
  const float outer = static_cast<float>(cfg.menu.outer_radius);
  const float gap = (outer > 0.f) ? (kGapSize / outer) : 0.f;

  for (int i = 0; i < n; ++i) {
    float a0, a1;
    SectorAngles(i, n, a0, a1);
    const float draw_start = a0 + gap;
    const float draw_end = a1 - gap;
    float span = draw_end - draw_start;
    if (span < 0) span += static_cast<float>(kTwoPi);

    const bool sel = (i == selected_sector_index);
    const int col_in = sel ? kColSectorInSel : kColSectorIn;
    const int col_out = sel ? kColSectorOutSel : kColSectorOut;

    const int segments = std::max(16, static_cast<int>(64.f * span / static_cast<float>(kTwoPi)));
    const float overlap = 1.f * static_cast<float>(kPi) / 180.f;

    for (int j = 0; j < segments; ++j) {
      float t0 = draw_start + span * (static_cast<float>(j) / segments);
      float t1 = draw_start + span * (static_cast<float>(j + 1) / segments);
      if (j > 0) t0 -= overlap;
      if (j < segments - 1) t1 += overlap;

      const float x1i = cx + inner * std::cos(t0);
      const float y1i = cy + inner * std::sin(t0);
      const float x1o = cx + outer * std::cos(t0);
      const float y1o = cy + outer * std::sin(t0);
      const float x2o = cx + outer * std::cos(t1);
      const float y2o = cy + outer * std::sin(t1);
      const float x2i = cx + inner * std::cos(t1);
      const float y2i = cy + inner * std::sin(t1);

      if (ImGui::DrawList_AddQuadFilled) {
        ImGui::DrawList_AddQuadFilled(dl, x1i, y1i, x1o, y1o, x2o, y2o, x2i, y2i, col_in);
      }
      (void)col_out;
    }

    if (sel && ImGui::DrawList_AddLine) {
      const int rim = RgbaToU32(255, 255, 255, 200);
      for (int j = 0; j < 32; ++j) {
        const float t0 = draw_start + span * (static_cast<float>(j) / 32.f);
        const float t1 = draw_start + span * (static_cast<float>(j + 1) / 32.f);
        const float r = outer - 1.f;
        ImGui::DrawList_AddLine(dl, cx + r * std::cos(t0), cy + r * std::sin(t0),
                                cx + r * std::cos(t1), cy + r * std::sin(t1), rim, 2.f);
      }
    }

    const float mid_a = (a0 + a1) * 0.5f;
    const float text_r = (inner + outer) * 0.5f;
    const float tx = cx + text_r * std::cos(mid_a);
    const float ty = cy + text_r * std::sin(mid_a);
    const int text_col = sel ? kColTextActive : kColText;

    std::vector<std::string> lines;
    const std::string& raw = cfg.sectors[i].name;
    size_t start = 0;
    while (start <= raw.size()) {
      size_t nl = raw.find('\n', start);
      if (nl == std::string::npos) {
        lines.push_back(raw.substr(start));
        break;
      }
      lines.push_back(raw.substr(start, nl - start));
      start = nl + 1;
    }
    if (lines.empty()) lines.push_back("");

    float line_h = 14.f;
    if (ImGui::GetTextLineHeight) line_h = static_cast<float>(ImGui::GetTextLineHeight(ctx));
    float total_h = line_h * static_cast<float>(lines.size());
    float cursor_y = ty - total_h * 0.5f;

    for (const auto& line : lines) {
      if (!line.empty() && ImGui::CalcTextSize && ImGui::DrawList_AddText) {
        double tw = 0, th = 0;
        ImGui::CalcTextSize(ctx, line.c_str(), &tw, &th);
        const float text_x = tx - static_cast<float>(tw) * 0.5f;
        ImGui::DrawList_AddText(dl, text_x + 1, cursor_y + 1, kColTextShadow, line.c_str());
        ImGui::DrawList_AddText(dl, text_x, cursor_y, text_col, line.c_str());
      }
      cursor_y += line_h;
    }
  }

  if (ImGui::DrawList_AddQuadFilled) {
    const int pin_shadow = kColPinShadow;
    const int pin_col = kColPinInactive;
    ImGui::DrawList_AddQuadFilled(dl, cx, cy - kPinSize + 2, cx + kPinSize + 2, cy + 2, cx,
                                  cy + kPinSize + 4, cx - kPinSize + 2, cy + 2, pin_shadow);
    ImGui::DrawList_AddQuadFilled(dl, cx, cy - kPinSize, cx + kPinSize, cy, cx, cy + kPinSize,
                                  cx - kPinSize, cy, pin_col);
  }
}

}  // namespace lee::radial_menu
