#include "domain/I18n.h"

#include <unordered_map>

#include "plugin/PluginContext.h"

namespace lee::radial_menu {

I18n& I18n::Instance() {
  static I18n i;
  return i;
}

void I18n::LoadFromExtState() {
  const char* v = lee::GetExtState("RadialMenu", "Language");
  if (v && v[0] == 'e') lang_ = Lang::En;
  else lang_ = Lang::Zh;
}

void I18n::SetLang(Lang l) {
  lang_ = l;
  const auto& api = lee::Api();
  if (api.SetExtState) {
    api.SetExtState("RadialMenu", "Language", l == Lang::En ? "en" : "zh", false);
  }
}

const char* I18n::Tr(const char* key) const {
  static const std::unordered_map<std::string, std::pair<const char*, const char*>> tbl = {
      {"window_title", {"RadialMenu 设置", "RadialMenu Setup"}},
      {"save", {"保存", "Save"}},
      {"discard", {"丢弃", "Discard"}},
      {"preset", {"预设", "Preset"}},
      {"preview", {"预览", "Preview"}},
      {"browser", {"浏览器", "Browser"}},
      {"grid", {"网格", "Grid"}},
      {"inspector", {"属性", "Inspector"}},
      {"language", {"语言", "Language"}},
      {"hover_to_open", {"悬停打开子菜单", "Hover to open submenu"}},
      {"new_preset", {"新建预设", "New preset"}},
      {"rename", {"重命名", "Rename"}},
      {"delete", {"删除", "Delete"}},
      {"open_radial", {"打开轮盘", "Open radial menu"}},
      {"setup", {"设置", "Setup"}},
      {"pin", {"固定", "Pin"}},
      {"management", {"管理模式", "Management"}},
      {"global_settings", {"全局设置", "Global settings"}},
      {"sector_count", {"扇区数量", "Sector count"}},
      {"outer_radius", {"外半径", "Outer radius"}},
      {"inner_radius", {"内半径", "Inner radius"}},
      {"wheel_size", {"轮盘尺寸", "Wheel size"}},
      {"current_sector_name", {"当前扇区名称", "Sector name"}},
      {"please_select_sector", {"请在预览中点击扇区", "Click a sector in preview"}},
      {"select_sector_hint",
       {"请从左侧预览中选择一个扇区进行编辑", "Select a sector from the preview on the left"}},
      {"clear_sector", {"清除扇区内容", "Clear sector slots"}},
      {"drag_hint_no_slot", {"选择一个插槽以编辑", "Select a slot to edit"}},
      {"drag_hint_empty_slot", {"从下方浏览器拖入 Action 或 FX", "Drag Action or FX from browser below"}},
      {"drag_hint_sub", {"或点击网格中的空插槽", "Or click an empty slot in the grid"}},
      {"slot_n", {"插槽", "Slot"}},
      {"clear_slot", {"清除", "Clear"}},
      {"delete_slot", {"删除", "Delete"}},
      {"display_name", {"显示名称", "Display name"}},
      {"search", {"搜索", "Search"}},
      {"actions_tab", {"Actions", "Actions"}},
      {"fx_tab", {"FX", "FX"}},
      {"empty_slot", {"Empty", "Empty"}},
      {"confirm", {"确认", "Confirm"}},
      {"confirm_discard_changes",
       {"确定丢弃所有未保存的更改？", "Discard all unsaved changes?"}},
      {"confirm_close_unsaved", {"有未保存的更改，确定关闭？", "Unsaved changes. Close anyway?"}},
      {"confirm_reset", {"重置为默认配置？", "Reset to default configuration?"}},
      {"confirm_delete_preset", {"确定删除此预设？", "Delete this preset?"}},
      {"reset", {"重置", "Reset"}},
      {"run", {"运行", "Run"}},
      {"action_list", {"Action 列表", "Action List"}},
      {"submenu_size", {"子菜单尺寸", "Submenu size"}},
      {"submenu_width", {"窗口宽度", "Window width"}},
      {"submenu_height", {"窗口高度", "Window height"}},
      {"slot_width", {"按钮宽度", "Button width"}},
      {"slot_height", {"按钮高度", "Button height"}},
      {"submenu_gap", {"按钮间距", "Button gap"}},
      {"submenu_padding", {"内边距", "Padding"}},
      {"enable_ui_animation", {"启用界面动画", "Enable UI animation"}},
      {"duration_open", {"展开时长", "Open duration"}},
      {"enable_sector_expansion", {"启用扇区膨胀", "Sector expansion"}},
      {"hover_expansion_pixels", {"膨胀幅度", "Expansion pixels"}},
      {"hover_animation_speed", {"膨胀速度", "Expansion speed"}},
      {"new_preset_name", {"预设名称", "Preset name"}},
      {"preset_blank", {"空白", "Blank"}},
      {"preset_duplicate", {"复制当前", "Duplicate current"}},
      {"add_slot", {"+", "+"}},
      {"preview_scaled", {"预览已缩放", "Preview scaled"}},
      {"saved_ok", {"已保存", "Saved"}},
  };
  const auto it = tbl.find(key ? key : "");
  if (it == tbl.end()) return key;
  return lang_ == Lang::En ? it->second.second : it->second.first;
}

}  // namespace lee::radial_menu
