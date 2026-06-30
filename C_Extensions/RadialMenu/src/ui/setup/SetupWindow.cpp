#include "ui/setup/SetupWindow.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>

#include "domain/Catalog.h"
#include "domain/ConfigDefaults.h"
#include "domain/ConfigStore.h"
#include "domain/Execution.h"
#include "domain/HitTest.h"
#include "domain/I18n.h"
#include "domain/SetupOps.h"
#include "reaper_imgui_functions.h"
#include "plugin/PluginContext.h"
#include "ui/setup/SetupPreview.h"
#include "shared/reaper/ReaImGuiApi.h"
#include "shared/ReaImGuiCoords.h"
#include "shared/ui/LeeUiTheme.h"
#include "shared/UiNotify.h"

namespace lee::radial_menu {
namespace {

SetupWindow g_setup;
constexpr const char* kTitle = "RadialMenu Setup##lee";
constexpr float kGridBtnH = 40.f;
constexpr int kGridCols = 4;
constexpr float kGridSpacing = 8.f;

void EnsureSectorSlots(Sector& sec, int count) {
  if (static_cast<int>(sec.slots.size()) < count) {
    const int old = static_cast<int>(sec.slots.size());
    sec.slots.resize(count);
    for (int i = old; i < count; ++i) sec.slots[i].type = "empty";
  }
}

}  // namespace

SetupWindow& GetSetupWindow() { return g_setup; }

bool SetupWindow::context_is_valid() const {
  if (!ctx_) return false;
  if (!ImGui::ValidatePtr) return true;
  return ImGui::ValidatePtr(ctx_, "ImGui_Context*") != 0;
}

void SetupWindow::ensure_context() {
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
    ctx_ = ImGui::CreateContext("RadialMenu_Setup");
    if (ctx_) lee::ui::EnsureFonts(ctx_, theme_fonts_);
  } catch (...) {
    ctx_ = nullptr;
  }
}

void SetupWindow::push_setup_theme(int& colors, int& vars) {
  colors = 0;
  vars = 0;
  if (!ctx_) return;
  if (ImGui::PushStyleVar) {
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowPadding, 10, 10);
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_ItemSpacing, 8, 8);
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_FramePadding, 10, 6);
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_FrameRounding, 4);
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_GrabRounding, 4);
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_WindowRounding, 6);
    ImGui::PushStyleVar(ctx_, ImGui::StyleVar_PopupRounding, 4);
    vars = 7;
  }
  if (ImGui::PushStyleColor) {
    ImGui::PushStyleColor(ctx_, ImGui::Col_WindowBg, RgbaToU32(24, 27, 27, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_PopupBg, RgbaToU32(29, 29, 32, 240));
    ImGui::PushStyleColor(ctx_, ImGui::Col_Border, RgbaToU32(39, 39, 42, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_FrameBg, RgbaToU32(9, 9, 11, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_FrameBgHovered, RgbaToU32(24, 27, 27, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_FrameBgActive, RgbaToU32(32, 32, 32, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_Button, RgbaToU32(39, 39, 42, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonHovered, RgbaToU32(63, 63, 70, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonActive, RgbaToU32(24, 27, 27, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_Text, RgbaToU32(228, 228, 231, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_TextDisabled, RgbaToU32(161, 161, 170, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_TitleBg, RgbaToU32(24, 27, 27, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_TitleBgActive, RgbaToU32(24, 27, 27, 255));
    colors = 13;
  }
}

void SetupWindow::pop_setup_theme(int colors, int vars) {
  if (!ctx_) return;
  if (colors > 0 && ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, colors);
  if (vars > 0 && ImGui::PopStyleVar) ImGui::PopStyleVar(ctx_, vars);
}

void SetupWindow::open() {
  const char* st = lee::GetExtState("RadialMenu", "SettingsOpen");
  if (st && st[0] == '1') {
    if (const auto& api = lee::Api(); api.SetExtState) {
      api.SetExtState("RadialMenu", "SettingsOpen", "0", false);
    }
  }
  I18n::Instance().LoadFromExtState();
  ConfigStore::Instance().LoadFull(full_);
  edit_ = full_.active_config;
  original_ = edit_;
  selected_sector_ = edit_.sectors.empty() ? 0 : 0;
  selected_slot_ = -1;
  dirty_ = false;
  sector_stash_.clear();
  ensure_context();
  GetCatalog().RequestBuild();
  open_ = true;
  browser_tab_seen_ = false;
  const auto& api = lee::Api();
  if (api.SetExtState) api.SetExtState("RadialMenu", "SettingsOpen", "1", false);
}

void SetupWindow::close() {
  open_ = false;
  const auto& api = lee::Api();
  if (api.SetExtState) api.SetExtState("RadialMenu", "SettingsOpen", "0", false);
}

void SetupWindow::destroy() {
  close();
  if (ctx_ && context_is_valid()) {
    lee::ui::DestroyFonts(ctx_, theme_fonts_);
    DestroyImGuiContext(ctx_);
  }
  ctx_ = nullptr;
  native_warmed_ = false;
  in_tick_ = false;
}

void SetupWindow::ApplyActionPayload(Slot& sl, const char* payload) {
  if (!payload) return;
  std::string s(payload);
  const auto bar = s.find('|');
  if (bar != std::string::npos) {
    sl.command_id = atoi(s.substr(0, bar).c_str());
    sl.name = s.substr(bar + 1);
    sl.command_name.clear();
  } else {
    sl.command_id = atoi(s.c_str());
  }
  sl.type = "action";
}

void SetupWindow::ApplyFxPayload(Slot& sl, const char* payload) {
  if (!payload) return;
  std::string s(payload);
  const auto bar = s.find('|');
  if (bar == std::string::npos) {
    sl.type = "fx";
    sl.fx_name = s;
    return;
  }
  const std::string ptype = s.substr(0, bar);
  const std::string pid = s.substr(bar + 1);
  if (ptype == "chain") {
    sl.type = "chain";
    sl.path = pid;
    const auto slash = pid.find_last_of("/\\");
    sl.name = (slash != std::string::npos) ? pid.substr(slash + 1) : pid;
  } else if (ptype == "template") {
    sl.type = "template";
    sl.path = pid;
    const auto slash = pid.find_last_of("/\\");
    sl.name = (slash != std::string::npos) ? pid.substr(slash + 1) : pid;
  } else {
    sl.type = "fx";
    sl.fx_name = pid;
    sl.name = pid;
  }
}

bool SetupWindow::save() {
  PreserveSlotPositions(edit_);
  std::string err;
  if (!ConfigStore::Instance().Validate(edit_, err)) {
    ShowUserMessage(err.c_str(), "Lee RadialMenu Setup");
    return false;
  }
  full_.active_config = edit_;
  auto it = full_.presets.find(full_.current_preset_name);
  if (it != full_.presets.end()) it->second = edit_;
  if (!ConfigStore::Instance().SaveFull(full_)) return false;
  ConfigStore::Instance().NotifyConfigUpdated();
  original_ = edit_;
  dirty_ = false;
  const auto& api = lee::Api();
  if (api.time_precise) save_feedback_time_ = api.time_precise();
  return true;
}

bool SetupWindow::try_close_with_confirm() {
  if (!dirty_) return true;
  const auto& api = lee::Api();
  if (!api.ShowMessageBox) return true;
  const int r = api.ShowMessageBox(
      I18n::Instance().Tr("confirm_close_unsaved"), I18n::Instance().Tr("confirm"), 4);
  return r == 4;
}

void SetupWindow::discard_with_confirm() {
  const auto& api = lee::Api();
  if (dirty_ && api.ShowMessageBox) {
    const int r = api.ShowMessageBox(
        I18n::Instance().Tr("confirm_discard_changes"), I18n::Instance().Tr("confirm"), 4);
    if (r != 4) return;
  }
  edit_ = original_;
  dirty_ = false;
}

void SetupWindow::reset_to_default_with_confirm() {
  const auto& api = lee::Api();
  if (api.ShowMessageBox) {
    const int r = api.ShowMessageBox(I18n::Instance().Tr("confirm_reset"),
                                     I18n::Instance().Tr("confirm"), 4);
    if (r != 4) return;
  }
  edit_ = MakeDefaultAppConfig();
  ConfigStore::Instance().MergeWithDefaults(edit_);
  dirty_ = true;
}

void SetupWindow::rename_sectors_for_language() {
  const bool zh = (I18n::Instance().lang() == Lang::Zh);
  for (size_t i = 0; i < edit_.sectors.size(); ++i) {
    auto& name = edit_.sectors[i].name;
    const std::string prefix_en = "Sector ";
    const std::string prefix_zh = "扇区 ";
    if (name.rfind(prefix_en, 0) == 0 || name.rfind(prefix_zh, 0) == 0) {
      name = (zh ? prefix_zh : prefix_en) + std::to_string(i + 1);
    }
  }
}

void SetupWindow::draw_new_preset_modal() {
  if (!show_new_preset_modal_) return;
  if (ImGui::OpenPopup) ImGui::OpenPopup(ctx_, "NewPresetModal");
  if (!ImGui::BeginPopupModal ||
      !ImGui::BeginPopupModal(ctx_, "NewPresetModal", nullptr, ImGui::WindowFlags_AlwaysAutoResize)) {
    return;
  }
  auto& i18n = I18n::Instance();
  ImGui::Text(ctx_, i18n.Tr("new_preset_name"));
  ImGui::InputText(ctx_, "##npname", new_preset_name_, sizeof(new_preset_name_));
  bool blank_sel = (new_preset_mode_ == 0);
  bool dup_sel = (new_preset_mode_ == 1);
  if (ImGui::RadioButton(ctx_, i18n.Tr("preset_blank"), &blank_sel) && blank_sel) {
    new_preset_mode_ = 0;
  }
  if (ImGui::RadioButton(ctx_, i18n.Tr("preset_duplicate"), &dup_sel) && dup_sel) {
    new_preset_mode_ = 1;
  }
  if (ImGui::Button(ctx_, "OK")) {
    std::string name = new_preset_name_;
    if (name.empty()) name = "Preset";
    int n = 1;
    while (full_.presets.count(name)) name = "Preset" + std::to_string(n++);
    AppConfig cfg = (new_preset_mode_ == 0) ? MakeDefaultAppConfig() : edit_;
    ConfigStore::Instance().MergeWithDefaults(cfg);
    full_.presets[name] = cfg;
    full_.current_preset_name = name;
    edit_ = cfg;
    dirty_ = true;
    show_new_preset_modal_ = false;
    if (ImGui::CloseCurrentPopup) ImGui::CloseCurrentPopup(ctx_);
  }
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "Cancel")) {
    show_new_preset_modal_ = false;
    if (ImGui::CloseCurrentPopup) ImGui::CloseCurrentPopup(ctx_);
  }
  ImGui::EndPopup(ctx_);
}

void SetupWindow::adjust_sector_count(int new_count) {
  new_count = std::clamp(new_count, 2, 8);
  const int cur = static_cast<int>(edit_.sectors.size());
  if (new_count == cur) return;

  if (new_count < cur) {
    for (int i = cur; i > new_count; --i) {
      sector_stash_[i] = edit_.sectors[static_cast<size_t>(i - 1)];
      edit_.sectors.pop_back();
    }
    if (selected_sector_ >= new_count) {
      selected_sector_ = std::max(0, new_count - 1);
      selected_slot_ = -1;
    }
  } else {
    for (int i = cur + 1; i <= new_count; ++i) {
      auto it = sector_stash_.find(i);
      if (it != sector_stash_.end()) {
        Sector restored = it->second;
        restored.id = i;
        edit_.sectors.push_back(std::move(restored));
      } else {
        Sector s;
        s.id = i;
        s.name = "Sector " + std::to_string(i);
        s.color = {26, 26, 26, 180};
        edit_.sectors.push_back(s);
      }
    }
  }
  for (size_t i = 0; i < edit_.sectors.size(); ++i) edit_.sectors[i].id = static_cast<int>(i) + 1;
  dirty_ = true;
}

void SetupWindow::draw_action_bar() {
  auto& i18n = I18n::Instance();
  if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("preset"));
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::BeginCombo &&
      ImGui::BeginCombo(ctx_, "##preset_combo", full_.current_preset_name.c_str())) {
    for (const auto& p : full_.presets) {
      bool sel = (p.first == full_.current_preset_name);
      if (ImGui::Selectable(ctx_, p.first.c_str(), &sel)) {
        full_.current_preset_name = p.first;
        edit_ = p.second;
        dirty_ = true;
        selected_sector_ = 0;
        selected_slot_ = -1;
      }
    }
    ImGui::EndCombo(ctx_);
  }
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, i18n.Tr("new_preset"))) {
    strncpy_s(new_preset_name_, "Preset", sizeof(new_preset_name_) - 1);
    new_preset_mode_ = 1;
    show_new_preset_modal_ = true;
  }
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "Dup")) {
    std::string name = full_.current_preset_name + " Copy";
    int n = 1;
    while (full_.presets.count(name)) name = full_.current_preset_name + " Copy" + std::to_string(n++);
    full_.presets[name] = edit_;
    full_.current_preset_name = name;
    edit_ = full_.presets[name];
    dirty_ = true;
  }
  const bool can_rename = full_.current_preset_name != "Default";
  if (!can_rename && ImGui::BeginDisabled) ImGui::BeginDisabled(ctx_);
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, i18n.Tr("rename"))) {
    strncpy_s(rename_buf_, full_.current_preset_name.c_str(), sizeof(rename_buf_) - 1);
    if (ImGui::OpenPopup) ImGui::OpenPopup(ctx_, "Rename Preset");
  }
  if (!can_rename && ImGui::EndDisabled) ImGui::EndDisabled(ctx_);
  const bool can_delete = full_.current_preset_name != "Default";
  if (!can_delete && ImGui::BeginDisabled) ImGui::BeginDisabled(ctx_);
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, i18n.Tr("delete"))) {
    const auto& api = lee::Api();
    if (api.ShowMessageBox) {
      const int r = api.ShowMessageBox(I18n::Instance().Tr("confirm_delete_preset"),
                                       I18n::Instance().Tr("confirm"), 4);
      if (r != 4) goto delete_done;
    }
    std::string err;
    if (ConfigStore::Instance().DeletePreset(full_, full_.current_preset_name, err)) {
      edit_ = full_.active_config;
      dirty_ = true;
    } else {
      ShowUserMessage(err.c_str(), "Lee RadialMenu Setup");
    }
  }
delete_done:
  if (!can_delete && ImGui::EndDisabled) ImGui::EndDisabled(ctx_);

  if (ImGui::BeginPopupModal &&
      ImGui::BeginPopupModal(ctx_, "Rename Preset", nullptr, ImGui::WindowFlags_AlwaysAutoResize)) {
    ImGui::InputText(ctx_, "Name", rename_buf_, sizeof(rename_buf_));
    if (ImGui::Button(ctx_, "OK")) {
      std::string err;
      const std::string old_name = full_.current_preset_name;
      if (ConfigStore::Instance().RenamePreset(full_, old_name, rename_buf_, err)) {
        edit_ = full_.presets[full_.current_preset_name];
        dirty_ = true;
        if (ImGui::CloseCurrentPopup) ImGui::CloseCurrentPopup(ctx_);
      } else {
        ShowUserMessage(err.c_str(), "Lee RadialMenu Setup");
      }
    }
    if (ImGui::SameLine) ImGui::SameLine(ctx_);
    if (ImGui::Button(ctx_, "Cancel") && ImGui::CloseCurrentPopup) {
      ImGui::CloseCurrentPopup(ctx_);
    }
    ImGui::EndPopup(ctx_);
  }

  if (ImGui::Separator) ImGui::Separator(ctx_);
  if (ImGui::PushStyleColor) {
    ImGui::PushStyleColor(ctx_, ImGui::Col_Button, RgbaToU32(37, 99, 235, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonHovered, RgbaToU32(59, 130, 246, 255));
  }
  if (ImGui::Button(ctx_, (std::string(i18n.Tr("save")) + "##ActionBarSave").c_str())) save();
  if (ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, 2);
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, (std::string(i18n.Tr("discard")) + "##ActionBarDiscard").c_str())) {
    discard_with_confirm();
  }
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::PushStyleColor) {
    ImGui::PushStyleColor(ctx_, ImGui::Col_Button, RgbaToU32(153, 34, 34, 255));
    ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonHovered, RgbaToU32(185, 43, 43, 255));
  }
  if (ImGui::Button(ctx_, i18n.Tr("reset"))) reset_to_default_with_confirm();
  if (ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, 2);
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "中文##ActionBarLanguage")) {
    I18n::Instance().SetLang(Lang::Zh);
    rename_sectors_for_language();
  }
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "EN##ActionBarLanguage")) {
    I18n::Instance().SetLang(Lang::En);
    rename_sectors_for_language();
  }
  const auto& api = lee::Api();
  if (save_feedback_time_ > 0 && api.time_precise &&
      (api.time_precise() - save_feedback_time_) < 2.0) {
    if (ImGui::SameLine) ImGui::SameLine(ctx_);
    if (ImGui::PushStyleColor) ImGui::PushStyleColor(ctx_, ImGui::Col_Text, RgbaToU32(76, 175, 80, 255));
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("saved_ok"));
    if (ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, 1);
  } else if (dirty_) {
    if (ImGui::SameLine) ImGui::SameLine(ctx_);
    if (ImGui::TextDisabled) ImGui::TextDisabled(ctx_, "*");
  }
  draw_new_preset_modal();
}

void SetupWindow::draw_preview_column() {
  if (edit_.sectors.empty()) return;
  auto& i18n = I18n::Instance();
  selected_sector_ = std::clamp(selected_sector_, 0, static_cast<int>(edit_.sectors.size()) - 1);

  if (ImGui::BeginChild(ctx_, "PreviewFrame", 0, 220, 1, 0)) {
    double w = 0, h = 0;
    if (ImGui::GetContentRegionAvail) ImGui::GetContentRegionAvail(ctx_, &w, &h);
    double px = 0, py = 0;
    if (ImGui::GetCursorScreenPos) ImGui::GetCursorScreenPos(ctx_, &px, &py);
    const double cx = px + w * 0.5;
    const double cy = py + h * 0.5;

    AppConfig vis = edit_;
    const double padding = 10.0;
    const double max_r = std::min(w, h) * 0.5 - padding;
    const double scale =
        (vis.menu.outer_radius > 0) ? std::min(1.0, max_r / vis.menu.outer_radius) : 1.0;
    vis.menu.outer_radius *= scale;
    vis.menu.inner_radius *= scale;

    DrawSetupPreview(ctx_, vis, selected_sector_, cx, cy);
    if (scale < 1.0 && ImGui::DrawList_AddText) {
      ImGui_DrawList* pdl = ImGui::GetWindowDrawList(ctx_);
      if (pdl) {
        ImGui::DrawList_AddText(pdl, static_cast<float>(px) + 6.f, static_cast<float>(py) + 6.f,
                                RgbaToU32(180, 180, 180, 160), i18n.Tr("preview_scaled"));
      }
    }

    if (ImGui::IsWindowHovered && ImGui::IsMouseClicked &&
        ImGui::IsWindowHovered(ctx_) && ImGui::IsMouseClicked(ctx_, 0)) {
      double mx = 0, my = 0;
      if (ImGui::GetMousePos) ImGui::GetMousePos(ctx_, &mx, &my);
      const auto hit = HitTestWheel(mx, my, cx, cy, vis);
      if (hit.sector_index >= 0) {
        if (selected_sector_ != hit.sector_index) selected_slot_ = -1;
        selected_sector_ = hit.sector_index;
      }
    }

    if (ImGui::SetCursorScreenPos && ImGui::Button) {
      const float btn_size = 24.f;
      const float btn_pad = 8.f;
      ImGui::SetCursorScreenPos(ctx_, px + static_cast<float>(w) - btn_size - btn_pad,
                                py + static_cast<float>(h) - btn_size - btn_pad);
      if (ImGui::PushStyleColor) {
        ImGui::PushStyleColor(ctx_, ImGui::Col_Button, RgbaToU32(255, 82, 82, 180));
        ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonHovered, RgbaToU32(255, 112, 112, 220));
        ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonActive, RgbaToU32(229, 57, 53, 255));
      }
      if (ImGui::Button(ctx_, "x", btn_size, btn_size)) {
        edit_.sectors[selected_sector_].slots.clear();
        selected_slot_ = -1;
        dirty_ = true;
      }
      if (ImGui::IsItemHovered && ImGui::BeginTooltip) {
        if (ImGui::IsItemHovered(ctx_) && ImGui::BeginTooltip(ctx_)) {
          ImGui::Text(ctx_, i18n.Tr("clear_sector"));
          ImGui::EndTooltip(ctx_);
        }
      }
      if (ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, 3);
    }
    ImGui::EndChild(ctx_);
  }

  if (ImGui::BeginChild(ctx_, "LeftSettingsRegion", 0, 0, 1, 0)) {
    if (ImGui::Spacing) ImGui::Spacing(ctx_);
    Sector& sec = edit_.sectors[selected_sector_];
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("current_sector_name"));
    if (ImGui::SetNextItemWidth) ImGui::SetNextItemWidth(ctx_, -1);
    char sname[256] = {};
    strncpy_s(sname, sec.name.c_str(), sizeof(sname) - 1);
    if (ImGui::InputText(ctx_, "##SectorName", sname, sizeof(sname))) {
      sec.name = sname;
      dirty_ = true;
    }
    if (ImGui::Separator) ImGui::Separator(ctx_);
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("global_settings"));
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("sector_count"));
    int sc = static_cast<int>(edit_.sectors.size());
    if (ImGui::SliderInt(ctx_, "##SectorCount", &sc, 2, 8, "%d")) {
      adjust_sector_count(sc);
    }
    if (ImGui::TextDisabled) ImGui::TextDisabled(ctx_, i18n.Tr("wheel_size"));
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("outer_radius"));
    int outer = static_cast<int>(edit_.menu.outer_radius);
    if (ImGui::SliderInt(ctx_, "##OuterRadius", &outer, 80, 300, "%d px")) {
      edit_.menu.outer_radius = outer;
      dirty_ = true;
    }
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("inner_radius"));
    int inner = static_cast<int>(edit_.menu.inner_radius);
    if (ImGui::SliderInt(ctx_, "##InnerRadius", &inner, 20, 100, "%d px")) {
      edit_.menu.inner_radius = inner;
      dirty_ = true;
    }
    if (ImGui::Checkbox) {
      bool v = edit_.menu.hover_to_open;
      if (ImGui::Checkbox(ctx_, i18n.Tr("hover_to_open"), &v)) {
        edit_.menu.hover_to_open = v;
        dirty_ = true;
      }
    }
    if (ImGui::TextDisabled) ImGui::TextDisabled(ctx_, i18n.Tr("submenu_size"));
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("submenu_width"));
    int sw = static_cast<int>(edit_.menu.submenu_width);
    if (ImGui::SliderInt(ctx_, "##SubW", &sw, 200, 400, "%d px")) {
      edit_.menu.submenu_width = sw;
      dirty_ = true;
    }
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("submenu_height"));
    int sh = static_cast<int>(edit_.menu.submenu_height);
    if (ImGui::SliderInt(ctx_, "##SubH", &sh, 100, 300, "%d px")) {
      edit_.menu.submenu_height = sh;
      dirty_ = true;
    }
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("slot_width"));
    int slw = static_cast<int>(edit_.menu.slot_width);
    if (ImGui::SliderInt(ctx_, "##SlotW", &slw, 60, 150, "%d px")) {
      edit_.menu.slot_width = slw;
      dirty_ = true;
    }
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("slot_height"));
    int slh = static_cast<int>(edit_.menu.slot_height);
    if (ImGui::SliderInt(ctx_, "##SlotH", &slh, 24, 60, "%d px")) {
      edit_.menu.slot_height = slh;
      dirty_ = true;
    }
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("submenu_gap"));
    int gap = static_cast<int>(edit_.menu.submenu_gap);
    if (ImGui::SliderInt(ctx_, "##Gap", &gap, 1, 10, "%d")) {
      edit_.menu.submenu_gap = gap;
      dirty_ = true;
    }
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("submenu_padding"));
    int pad = static_cast<int>(edit_.menu.submenu_padding);
    if (ImGui::SliderInt(ctx_, "##Pad", &pad, 2, 15, "%d")) {
      edit_.menu.submenu_padding = pad;
      dirty_ = true;
    }
    if (ImGui::Checkbox) {
      bool anim = edit_.menu.anim_enable;
      if (ImGui::Checkbox(ctx_, i18n.Tr("enable_ui_animation"), &anim)) {
        edit_.menu.anim_enable = anim;
        dirty_ = true;
      }
    }
    if (edit_.menu.anim_enable) {
      int ms = static_cast<int>(edit_.menu.duration_open * 1000);
      if (ImGui::SliderInt(ctx_, "##DurOpenMs", &ms, 0, 500, "%d ms")) {
        edit_.menu.duration_open = ms / 1000.0;
        dirty_ = true;
      }
    }
    if (ImGui::Checkbox) {
      bool exp = edit_.menu.enable_sector_expansion;
      if (ImGui::Checkbox(ctx_, i18n.Tr("enable_sector_expansion"), &exp)) {
        edit_.menu.enable_sector_expansion = exp;
        dirty_ = true;
      }
    }
    if (edit_.menu.enable_sector_expansion) {
      int px_exp = static_cast<int>(edit_.menu.hover_expansion_pixels);
      if (ImGui::SliderInt(ctx_, i18n.Tr("hover_expansion_pixels"), &px_exp, 0, 10, "%d")) {
        edit_.menu.hover_expansion_pixels = px_exp;
        dirty_ = true;
      }
      int spd = edit_.menu.hover_animation_speed;
      if (ImGui::SliderInt(ctx_, i18n.Tr("hover_animation_speed"), &spd, 1, 10, "%d")) {
        edit_.menu.hover_animation_speed = spd;
        dirty_ = true;
      }
    }
    ImGui::EndChild(ctx_);
  }
}

void SetupWindow::draw_grid() {
  if (edit_.sectors.empty()) return;
  auto& i18n = I18n::Instance();
  Sector& sec = edit_.sectors[selected_sector_];
  const int max_slots = edit_.menu.max_slots_per_sector;
  EnsureSectorSlots(sec, max_slots);
  const int display_count = std::max(12, max_slots);

  double avail_w = 200;
  if (ImGui::GetContentRegionAvail) ImGui::GetContentRegionAvail(ctx_, &avail_w, nullptr);
  const float btn_w =
      static_cast<float>((avail_w - kGridSpacing * (kGridCols - 1)) / kGridCols);

  for (int i = 0; i < display_count; ++i) {
    if (i > 0 && (i % kGridCols) != 0 && ImGui::SameLine) {
      ImGui::SameLine(ctx_, 0, kGridSpacing);
    }
    if (i >= static_cast<int>(sec.slots.size())) EnsureSectorSlots(sec, i + 1);
    Slot& sl = sec.slots[i];
    const bool is_real = (sl.type != "empty");
    const bool sel = (selected_slot_ == i);
    const std::string id = "##Slot" + std::to_string(i);

    if (ImGui::PushID) ImGui::PushID(ctx_, id.c_str());

    int pushed = 0;
    if (is_real) {
      int bg = RgbaToU32(42, 42, 47, 255);
      int hov = RgbaToU32(58, 58, 63, 255);
      int act = RgbaToU32(74, 74, 79, 255);
      if (sel) {
        bg = RgbaToU32(63, 63, 70, 255);
        hov = RgbaToU32(79, 79, 86, 255);
        act = RgbaToU32(95, 95, 102, 255);
      }
      if (ImGui::PushStyleColor) {
        ImGui::PushStyleColor(ctx_, ImGui::Col_Button, bg);
        ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonHovered, hov);
        ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonActive, act);
        pushed = 3;
      }
      std::string label = sl.name.empty() ? sl.type : sl.name;
      if (ImGui::Button(ctx_, (label + "##b").c_str(), btn_w, kGridBtnH)) {
        selected_slot_ = i;
      }
      if (ImGui::BeginPopupContextItem && ImGui::BeginPopupContextItem(ctx_)) {
        if (ImGui::MenuItem(ctx_, i18n.Tr("clear_slot"))) {
          sl = Slot{};
          sl.type = "empty";
          if (selected_slot_ == i) selected_slot_ = -1;
          dirty_ = true;
        }
        ImGui::EndPopup(ctx_);
      }
    } else {
      if (ImGui::PushStyleColor) {
        ImGui::PushStyleColor(ctx_, ImGui::Col_Button, RgbaToU32(20, 20, 20, 255));
        ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonHovered, RgbaToU32(30, 30, 30, 255));
        ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonActive, RgbaToU32(40, 40, 40, 255));
        pushed = 3;
      }
      if (sel && ImGui::PushStyleColor) {
        ImGui::PushStyleColor(ctx_, ImGui::Col_Button, RgbaToU32(42, 42, 42, 255));
        ++pushed;
      }
      if (ImGui::Button(ctx_, (std::string(I18n::Instance().Tr("empty_slot")) + "##e").c_str(),
                        btn_w, kGridBtnH)) {
        selected_slot_ = i;
      }
    }

    if (ImGui::BeginDragDropSource && ImGui::BeginDragDropSource(ctx_)) {
      const std::string idx = std::to_string(i);
      if (ImGui::SetDragDropPayload) {
        ImGui::SetDragDropPayload(ctx_, "DND_GRID_SWAP", idx.c_str(),
                                  static_cast<int>(idx.size() + 1));
      }
      ImGui::EndDragDropSource(ctx_);
    }
    if (ImGui::BeginDragDropTarget && ImGui::BeginDragDropTarget(ctx_)) {
      char pbuf[512] = {};
      if (ImGui::AcceptDragDropPayload &&
          ImGui::AcceptDragDropPayload(ctx_, "DND_GRID_SWAP", pbuf, sizeof(pbuf),
                                       ImGui::DragDropFlags_None)) {
        const int src = atoi(pbuf);
        if (src >= 0 && src < display_count && src != i) {
          std::swap(sec.slots[src], sec.slots[i]);
          if (selected_slot_ == src) selected_slot_ = i;
          else if (selected_slot_ == i) selected_slot_ = src;
          dirty_ = true;
        }
      } else if (ImGui::AcceptDragDropPayload &&
                 ImGui::AcceptDragDropPayload(ctx_, "DND_ACTION", pbuf, sizeof(pbuf),
                                              ImGui::DragDropFlags_None)) {
        ApplyActionPayload(sl, pbuf);
        selected_slot_ = i;
        dirty_ = true;
      } else if (ImGui::AcceptDragDropPayload &&
                 ImGui::AcceptDragDropPayload(ctx_, "RM_ACTION", pbuf, sizeof(pbuf),
                                              ImGui::DragDropFlags_None)) {
        ApplyActionPayload(sl, pbuf);
        selected_slot_ = i;
        dirty_ = true;
      } else if (ImGui::AcceptDragDropPayload &&
                 ImGui::AcceptDragDropPayload(ctx_, "DND_FX", pbuf, sizeof(pbuf),
                                              ImGui::DragDropFlags_None)) {
        ApplyFxPayload(sl, pbuf);
        selected_slot_ = i;
        dirty_ = true;
      } else if (ImGui::AcceptDragDropPayload &&
                 ImGui::AcceptDragDropPayload(ctx_, "RM_FX", pbuf, sizeof(pbuf),
                                              ImGui::DragDropFlags_None)) {
        ApplyFxPayload(sl, pbuf);
        selected_slot_ = i;
        dirty_ = true;
      }
      ImGui::EndDragDropTarget(ctx_);
    }

    if (pushed > 0 && ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, pushed);
    if (ImGui::PopID) ImGui::PopID(ctx_);
  }
  if (ImGui::Button(ctx_, i18n.Tr("add_slot"))) {
    Slot ns;
    ns.type = "action";
    ns.command_id = 0;
    ns.name = I18n::Instance().lang() == Lang::Zh ? "新插槽" : "New slot";
    sec.slots.push_back(ns);
    dirty_ = true;
  }
}

void SetupWindow::draw_inspector() {
  if (selected_slot_ < 0 || edit_.sectors.empty()) return;
  auto& sec = edit_.sectors[selected_sector_];
  if (selected_slot_ >= static_cast<int>(sec.slots.size())) return;
  Slot& sl = sec.slots[selected_slot_];
  if (sl.type == "empty") return;

  auto& i18n = I18n::Instance();
  const std::string header =
      std::string(i18n.Tr("slot_n")) + " " + std::to_string(selected_slot_ + 1);
  if (ImGui::Text) ImGui::Text(ctx_, header.c_str());
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  double avail = 100;
  if (ImGui::GetContentRegionAvail) ImGui::GetContentRegionAvail(ctx_, &avail, nullptr);
  if (ImGui::SetCursorPosX && ImGui::GetCursorPosX) {
    const double x = ImGui::GetCursorPosX(ctx_) + avail - 130;
    ImGui::SetCursorPosX(ctx_, x);
  }
  if (ImGui::Button(ctx_, i18n.Tr("clear_slot"))) {
    sl = Slot{};
    sl.type = "empty";
    selected_slot_ = -1;
    dirty_ = true;
    return;
  }
  const bool show_delete = static_cast<int>(sec.slots.size()) > 9;
  if (show_delete) {
    if (ImGui::SameLine) ImGui::SameLine(ctx_);
    if (ImGui::PushStyleColor) {
      ImGui::PushStyleColor(ctx_, ImGui::Col_Button, RgbaToU32(153, 34, 34, 255));
      ImGui::PushStyleColor(ctx_, ImGui::Col_ButtonHovered, RgbaToU32(185, 43, 43, 255));
    }
    if (ImGui::Button(ctx_, i18n.Tr("delete_slot"))) {
      sec.slots.erase(sec.slots.begin() + selected_slot_);
      selected_slot_ = -1;
      dirty_ = true;
      if (ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, 2);
      return;
    }
    if (ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, 2);
  }
  if (ImGui::Separator) ImGui::Separator(ctx_);

  if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("display_name"));
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::SetNextItemWidth) ImGui::SetNextItemWidth(ctx_, -1);
  char name[256] = {};
  strncpy_s(name, sl.name.c_str(), sizeof(name) - 1);
  if (ImGui::InputText(ctx_, "##SlotName", name, sizeof(name))) {
    sl.name = name;
    dirty_ = true;
  }

  const char* type_label = "Content";
  if (sl.type == "action") type_label = "Cmd ID";
  else if (sl.type == "fx") type_label = "FX";
  else if (sl.type == "chain") type_label = "Chain";
  else if (sl.type == "template") type_label = "Template";
  if (ImGui::Text) ImGui::Text(ctx_, type_label);
  if (ImGui::SameLine) ImGui::SameLine(ctx_);
  if (ImGui::SetNextItemWidth) ImGui::SetNextItemWidth(ctx_, -1);

  if (sl.type == "action") {
    char idbuf[256] = {};
    if (sl.command_id != 0) {
      snprintf(idbuf, sizeof(idbuf), "%d", sl.command_id);
    } else {
      strncpy_s(idbuf, sl.command_name.c_str(), sizeof(idbuf) - 1);
    }
    if (ImGui::InputText(ctx_, "##ContentInput", idbuf, sizeof(idbuf))) {
      const int num = atoi(idbuf);
      if (num > 0) {
        sl.command_id = num;
        sl.command_name.clear();
      } else {
        sl.command_id = 0;
        sl.command_name = idbuf;
      }
      const auto& api = lee::Api();
      int lookup = sl.command_id;
      if (lookup <= 0 && !sl.command_name.empty() && api.NamedCommandLookup) {
        lookup = api.NamedCommandLookup(sl.command_name.c_str());
      }
      if (lookup > 0 && (api.kbd_getTextFromCmd || api.CF_GetCommandText)) {
        void* section = api.SectionFromUniqueID ? api.SectionFromUniqueID(0) : nullptr;
        const char* command_text = api.kbd_getTextFromCmd
                                       ? api.kbd_getTextFromCmd(lookup, section)
                                       : api.CF_GetCommandText(0, lookup);
        if (command_text && *command_text) {
          sl.name = command_text;
        }
      }
      dirty_ = true;
    }
  } else if (sl.type == "fx") {
    char fx[512] = {};
    strncpy_s(fx, sl.fx_name.c_str(), sizeof(fx) - 1);
    if (ImGui::InputText(ctx_, "##ContentInput", fx, sizeof(fx))) {
      sl.fx_name = fx;
      dirty_ = true;
    }
  } else {
    char path[1024] = {};
    strncpy_s(path, sl.path.c_str(), sizeof(path) - 1);
    if (ImGui::InputText(ctx_, "##ContentInput", path, sizeof(path))) {
      sl.path = path;
      dirty_ = true;
    }
  }
}

void SetupWindow::draw_editor_column() {
  auto& i18n = I18n::Instance();
  if (edit_.sectors.empty()) {
    if (ImGui::TextDisabled) ImGui::TextDisabled(ctx_, i18n.Tr("please_select_sector"));
    return;
  }
  selected_sector_ = std::clamp(selected_sector_, 0, static_cast<int>(edit_.sectors.size()) - 1);
  Sector& sec = edit_.sectors[selected_sector_];

  if (ImGui::BeginChild(ctx_, "##EditorGrid", 0, 160, 1, 0)) {
    draw_grid();
    ImGui::EndChild(ctx_);
  }
  if (ImGui::Spacing) ImGui::Spacing(ctx_);
  if (ImGui::Separator) ImGui::Separator(ctx_);

  if (selected_slot_ >= 0 && selected_slot_ < static_cast<int>(sec.slots.size()) &&
      sec.slots[selected_slot_].type != "empty") {
    draw_inspector();
  } else if (selected_slot_ >= 0) {
    if (ImGui::TextDisabled) ImGui::TextDisabled(ctx_, i18n.Tr("drag_hint_empty_slot"));
    if (ImGui::Text) ImGui::Text(ctx_, i18n.Tr("drag_hint_sub"));
  } else {
    if (ImGui::TextDisabled) ImGui::TextDisabled(ctx_, i18n.Tr("drag_hint_no_slot"));
  }

  if (ImGui::Spacing) ImGui::Spacing(ctx_);
  if (ImGui::Separator) ImGui::Separator(ctx_);
  draw_browser();
}

void SetupWindow::draw_browser() {
  browser_tab_seen_ = true;
  GetCatalog().TickBuild(300);
  auto& i18n = I18n::Instance();
  if (GetCatalog().IsBuilding() && ImGui::Text) {
    ImGui::Text(ctx_, "Building catalog...");
  }
  if (ImGui::BeginTabBar(ctx_, "##btabs")) {
    if (ImGui::BeginTabItem(ctx_, i18n.Tr("actions_tab"))) {
      if (browser_tab_prev_ >= 0 && browser_tab_prev_ != 0) {
        strncpy_s(search_actions_, search_fx_, sizeof(search_actions_) - 1);
        focus_search_actions_ = true;
      }
      browser_tab_ = 0;
      browser_tab_prev_ = 0;
      const auto& api = lee::Api();
      if (ImGui::Button(ctx_, i18n.Tr("action_list")) && api.Main_OnCommand) {
        api.Main_OnCommand(40605, 0);
      }
      if (ImGui::SameLine) ImGui::SameLine(ctx_);
      const bool can_run = selected_browser_action_id_ > 0;
      if (!can_run && ImGui::BeginDisabled) ImGui::BeginDisabled(ctx_);
      if (ImGui::PushStyleColor) {
        ImGui::PushStyleColor(ctx_, ImGui::Col_Button, RgbaToU32(46, 125, 50, 255));
      }
      if (ImGui::Button(ctx_, i18n.Tr("run")) && can_run) {
        Slot tmp;
        tmp.type = "action";
        tmp.command_id = selected_browser_action_id_;
        Execution::TriggerSlot(tmp);
      }
      if (ImGui::PopStyleColor) ImGui::PopStyleColor(ctx_, 1);
      if (!can_run && ImGui::EndDisabled) ImGui::EndDisabled(ctx_);
      if (ImGui::SameLine) ImGui::SameLine(ctx_);
      if (ImGui::SetNextItemWidth) ImGui::SetNextItemWidth(ctx_, -1);
      if (focus_search_actions_ && ImGui::SetKeyboardFocusHere) {
        ImGui::SetKeyboardFocusHere(ctx_, 0);
        focus_search_actions_ = false;
      }
      if (ImGui::InputText(ctx_, "##search_a", search_actions_, sizeof(search_actions_))) {
      }
      auto list = GetCatalog().FilterActions(search_actions_);
      if (ImGui::BeginChild(ctx_, "##alist", 0, 200, 0)) {
        for (const auto& a : list) {
          const std::string label =
              std::to_string(a.command_id) + ": " + a.name + "##a" + std::to_string(a.command_id);
          bool sel = (selected_browser_action_id_ == a.command_id);
          if (ImGui::Selectable(ctx_, label.c_str(), &sel, ImGui::SelectableFlags_AllowDoubleClick)) {
            selected_browser_action_id_ = a.command_id;
            if (ImGui::IsMouseDoubleClicked && ImGui::IsMouseDoubleClicked(ctx_, 0)) {
              Slot tmp;
              tmp.type = "action";
              tmp.command_id = a.command_id;
              Execution::TriggerSlot(tmp);
            } else if (selected_slot_ >= 0 &&
                       selected_slot_ <
                           static_cast<int>(edit_.sectors[selected_sector_].slots.size())) {
              auto& sl = edit_.sectors[selected_sector_].slots[selected_slot_];
              sl.type = "action";
              sl.command_id = a.command_id;
              sl.name = a.name;
              dirty_ = true;
            }
          }
          if (ImGui::BeginDragDropSource && ImGui::BeginDragDropSource(ctx_)) {
            const std::string payload =
                std::to_string(a.command_id) + "|" + a.name;
            if (ImGui::SetDragDropPayload) {
              ImGui::SetDragDropPayload(ctx_, "DND_ACTION", payload.c_str(),
                                        static_cast<int>(payload.size() + 1));
            }
            ImGui::Text(ctx_, a.name.c_str());
            ImGui::EndDragDropSource(ctx_);
          }
        }
        ImGui::EndChild(ctx_);
      }
      ImGui::EndTabItem(ctx_);
    }
    if (ImGui::BeginTabItem(ctx_, i18n.Tr("fx_tab"))) {
      if (browser_tab_prev_ >= 0 && browser_tab_prev_ != 1) {
        strncpy_s(search_fx_, search_actions_, sizeof(search_fx_) - 1);
        focus_search_fx_ = true;
      }
      browser_tab_ = 1;
      browser_tab_prev_ = 1;
      static const char* kFilters[] = {"All", "VST", "VST3", "JS", "AU", "CLAP", "LV2", "Chain",
                                       "Template"};
      for (int fi = 0; fi < 9; ++fi) {
        if (fi > 0 && ImGui::SameLine) ImGui::SameLine(ctx_);
        const bool on = (fx_filter_ == kFilters[fi]);
        if (ImGui::Button(ctx_, (std::string(kFilters[fi]) + "##ff" + std::to_string(fi)).c_str())) {
          fx_filter_ = kFilters[fi];
        }
        if (on && ImGui::IsItemHovered) {
          (void)on;
        }
      }
      if (ImGui::SetNextItemWidth) ImGui::SetNextItemWidth(ctx_, -1);
      if (focus_search_fx_ && ImGui::SetKeyboardFocusHere) {
        ImGui::SetKeyboardFocusHere(ctx_, 0);
        focus_search_fx_ = false;
      }
      if (ImGui::InputText(ctx_, "##search_f", search_fx_, sizeof(search_fx_))) {
      }
      auto list = GetCatalog().FilterFx(search_fx_, fx_filter_);
      if (ImGui::BeginChild(ctx_, "##flist", 0, 200, 0)) {
        for (const auto& f : list) {
          bool fx_sel = false;
          if (ImGui::Selectable(ctx_, (f.name + "##f" + f.original_name).c_str(), &fx_sel,
                                ImGui::SelectableFlags_None)) {
            if (selected_slot_ >= 0 &&
                selected_slot_ < static_cast<int>(edit_.sectors[selected_sector_].slots.size())) {
              auto& sl = edit_.sectors[selected_sector_].slots[selected_slot_];
              ApplyFxPayload(sl, (f.type + "|" + f.original_name).c_str());
              dirty_ = true;
            }
          }
          if (ImGui::BeginDragDropSource && ImGui::BeginDragDropSource(ctx_)) {
            std::string payload = f.type + "|" + f.original_name;
            if (f.type == "VST" || f.type == "VST3" || f.type == "JS" || f.type == "AU" ||
                f.type == "CLAP" || f.type == "LV2" || f.type == "Other") {
              payload = "fx|" + f.original_name;
            }
            if (ImGui::SetDragDropPayload) {
              ImGui::SetDragDropPayload(ctx_, "DND_FX", payload.c_str(),
                                        static_cast<int>(payload.size() + 1));
            }
            ImGui::Text(ctx_, f.name.c_str());
            ImGui::EndDragDropSource(ctx_);
          }
        }
        ImGui::EndChild(ctx_);
      }
      ImGui::EndTabItem(ctx_);
    }
    ImGui::EndTabBar(ctx_);
  }
}

void SetupWindow::draw_ui() {
  if (!ctx_ || !context_is_valid()) return;
  auto& i18n = I18n::Instance();
  int theme_colors = 0, theme_vars = 0;
  push_setup_theme(theme_colors, theme_vars);

  if (ImGui::SetNextWindowSize) {
    ImGui::SetNextWindowSize(ctx_, 800, 600, ImGui::Cond_FirstUseEver);
  }
  if (!ImGui::Begin(ctx_, i18n.Tr("window_title"), &open_,
                    ImGui::WindowFlags_NoCollapse)) {
    pop_setup_theme(theme_colors, theme_vars);
    if (!open_) close();
    return;
  }

  draw_action_bar();
  if (ImGui::Spacing) ImGui::Spacing(ctx_);
  if (ImGui::Separator) ImGui::Separator(ctx_);
  if (ImGui::Spacing) ImGui::Spacing(ctx_);

  if (ImGui::BeginChild(ctx_, "##LeftCol", 340, -1, 1, 0)) {
    draw_preview_column();
    ImGui::EndChild(ctx_);
  }
  if (ImGui::SameLine) ImGui::SameLine(ctx_, 0, 8);
  if (ImGui::BeginChild(ctx_, "##RightCol", 0, -1, 1, 0)) {
    draw_editor_column();
    ImGui::EndChild(ctx_);
  }

  if (!open_) {
    if (try_close_with_confirm()) close();
    else open_ = true;
  }
  ImGui::End(ctx_);
  pop_setup_theme(theme_colors, theme_vars);
}

void SetupWindow::tick() {
  if (!open_ || in_tick_) return;
  struct TickGuard {
    bool& flag;
    explicit TickGuard(bool& f) : flag(f) { flag = true; }
    ~TickGuard() { flag = false; }
  } guard(in_tick_);

  ensure_context();
  if (!ctx_ || !context_is_valid()) return;

  if (!native_warmed_ && lee::reaimgui::Ready()) {
    try {
      if (ImGui::SetNextWindowPos) ImGui::SetNextWindowPos(ctx_, -10000.0, -10000.0, ImGui::Cond_Always);
      if (ImGui::SetNextWindowSize) ImGui::SetNextWindowSize(ctx_, 64, 64, ImGui::Cond_Always);
      bool warm_open = true;
      if (ImGui::Begin(ctx_, "RadialMenu Setup##warm", &warm_open, ImGui::WindowFlags_NoInputs)) {
        if (ImGui::Dummy) ImGui::Dummy(ctx_, 1.0, 1.0);
        ImGui::End(ctx_);
      }
      native_warmed_ = true;
    } catch (...) {
    }
  }

  if (browser_tab_seen_) GetCatalog().TickBuild(300);
  try {
    draw_ui();
  } catch (...) {
    ensure_context();
  }
}

}  // namespace lee::radial_menu
