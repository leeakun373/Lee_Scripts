#include "features/project_explorer/ui/Window.h"

#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <system_error>

#include "reaper_imgui_functions.h"

#include "platform/win/OsFileDrag.h"
#include "plugin/PluginContext.h"
#include "shared/reaper/ReaImGuiApi.h"

namespace lee::projectexplorer {
namespace {

constexpr int kTextDim = static_cast<int>(0xA1A1AAFFu);
constexpr int kTextFolder = static_cast<int>(0x42A5F5FFu);
constexpr int kTextAudio = static_cast<int>(0x0F766EFFu);
constexpr int kTextProject = static_cast<int>(0xFFA726FFu);
constexpr int kTextFile = static_cast<int>(0xE4E4E7FFu);

std::string wide_to_utf8(const std::wstring& w) {
  if (w.empty()) return {};
  const int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()),
                                    nullptr, 0, nullptr, nullptr);
  if (n <= 0) return {};
  std::string out(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), out.data(), n,
                      nullptr, nullptr);
  return out;
}

std::string path_to_utf8(const std::filesystem::path& p) {
  return wide_to_utf8(p.wstring());
}

std::wstring lower_w(std::wstring s) {
  std::transform(s.begin(), s.end(), s.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
  return s;
}

std::string shorten_utf8(const std::filesystem::path& p, size_t max_chars) {
  std::string s = path_to_utf8(p);
  if (s.size() <= max_chars) return s;
  if (max_chars <= 3) return "...";
  return "..." + s.substr(s.size() - (max_chars - 3));
}

bool is_hidden_name(const std::wstring& name) {
  return !name.empty() && name[0] == L'.';
}

bool is_hidden_file(const std::filesystem::path& p) {
  DWORD attrs = GetFileAttributesW(p.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_HIDDEN) != 0;
}

bool has_extension(const std::filesystem::path& p, const wchar_t* const* exts, size_t count) {
  const std::wstring ext = lower_w(p.extension().wstring());
  for (size_t i = 0; i < count; ++i) {
    if (ext == exts[i]) return true;
  }
  return false;
}

bool is_audio_file(const std::filesystem::path& p) {
  static const wchar_t* const kExts[] = {
      L".wav", L".mp3", L".flac", L".aac", L".ogg", L".m4a", L".wma",
      L".aiff", L".aif", L".opus", L".wv", L".ape", L".dsd", L".dsf", L".dff"};
  return has_extension(p, kExts, std::size(kExts));
}

bool is_project_file(const std::filesystem::path& p) {
  static const wchar_t* const kExts[] = {L".rpp", L".rpp-bak"};
  return has_extension(p, kExts, std::size(kExts));
}

std::string type_label(const FileEntry& e) {
  if (e.is_parent) return "上级目录";
  if (e.is_dir) return "文件夹";
  if (e.is_audio) {
    std::string ext = path_to_utf8(e.path.extension());
    if (!ext.empty() && ext[0] == '.') ext.erase(ext.begin());
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    return ext.empty() ? "音频" : ext + " 音频";
  }
  if (e.is_project) return "REAPER 工程";
  std::string ext = path_to_utf8(e.path.extension());
  if (!ext.empty() && ext[0] == '.') ext.erase(ext.begin());
  std::transform(ext.begin(), ext.end(), ext.begin(),
                 [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
  return ext.empty() ? "文件" : ext;
}

int text_color(const FileEntry& e) {
  if (e.is_parent || e.is_project) return kTextProject;
  if (e.is_dir) return kTextFolder;
  if (e.is_audio) return kTextAudio;
  return kTextFile;
}

std::string row_prefix(const FileEntry& e) {
  if (e.is_parent) return "[上级] ";
  if (e.is_dir) return "[文件夹] ";
  if (e.is_audio) return "[音频] ";
  if (e.is_project) return "[工程] ";
  return "";
}

void shell_open_path(const std::filesystem::path& p) {
  if (p.empty()) return;
  ShellExecuteW(nullptr, L"open", p.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

struct ProjectLocation {
  void* proj = nullptr;
  std::string project_file_utf8;
  std::filesystem::path folder;
};

ProjectLocation current_project_location() {
  ProjectLocation loc;
  const auto& api = lee::Api();
  char project_file[4096] = {0};
  if (api.EnumProjects) {
    loc.proj = api.EnumProjects(-1, project_file, static_cast<int>(sizeof(project_file)));
    loc.project_file_utf8 = project_file;
  }

  if (project_file[0] != '\0') {
    std::filesystem::path project_path(lee::Utf8ToWide(project_file));
    loc.folder = project_path.parent_path();
    return loc;
  }

  char folder[4096] = {0};
  if (api.GetProjectPathEx && loc.proj) {
    api.GetProjectPathEx(loc.proj, folder, static_cast<int>(sizeof(folder)));
  }
  if (folder[0] == '\0' && api.GetProjectPath) {
    api.GetProjectPath(folder, static_cast<int>(sizeof(folder)));
  }
  if (folder[0] != '\0') {
    loc.folder = std::filesystem::path(lee::Utf8ToWide(folder));
  }
  return loc;
}

void warn_reaimgui_missing() {
  HWND owner = nullptr;
  if (const auto& api = lee::Api(); api.GetMainHwnd) owner = api.GetMainHwnd();
  ::MessageBoxW(owner,
                L"Project File Explorer 需要 ReaImGui 扩展。\n\n"
                L"请在 ReaPack 中安装 cfillion/ReaImGui，重启 REAPER 后再试。",
                L"Lee Project File Explorer",
                MB_OK | MB_ICONINFORMATION);
}

}  // namespace

Window& GetWindow() {
  static Window w;
  return w;
}

Window::~Window() {
  destroy();
}

bool Window::ensure_context() {
  if (ctx_) return true;
  if (!lee::reaimgui::Ready()) return false;
  try {
    ctx_ = ImGui::CreateContext("Project File Explorer");
  } catch (...) {
    ctx_ = nullptr;
    return false;
  }
  if (!ctx_) return false;
  lee::ui::EnsureFonts(ctx_, theme_fonts_);
  load_current_project_folder();
  return true;
}

bool Window::show() {
  if (!ensure_context()) return false;
  open_ = true;
  load_current_project_folder();
  return true;
}

void Window::hide() {
  open_ = false;
  invalidate_context();
}

void Window::toggle() {
  if (open_) {
    hide();
  } else if (!show()) {
    warn_reaimgui_missing();
  }
}

void Window::destroy() {
  invalidate_context();
  open_ = false;
  current_proj_ = nullptr;
  current_project_file_.clear();
  entries_.clear();
  selected_index_ = -1;
}

void Window::invalidate_context() {
  if (ctx_) lee::ui::DestroyFonts(ctx_, theme_fonts_);
  ctx_ = nullptr;
  theme_fonts_ = {};
  drag_press_on_row_ = false;
  drag_press_row_idx_ = -1;
  drag_in_progress_ = false;
}

void Window::tick() {
  if (!open_ || !ctx_) return;
  if (!lee::reaimgui::Ready()) {
    hide();
    return;
  }
  poll_project_switch();
  try {
    draw_ui();
  } catch (...) {
    open_ = false;
    invalidate_context();
  }
}

void Window::poll_project_switch() {
  ProjectLocation loc = current_project_location();
  if (loc.proj != current_proj_ || loc.project_file_utf8 != current_project_file_) {
    load_current_project_folder();
  }
}

void Window::load_current_project_folder() {
  ProjectLocation loc = current_project_location();
  current_proj_ = loc.proj;
  current_project_file_ = loc.project_file_utf8;
  if (loc.folder.empty()) {
    entries_.clear();
    current_path_.clear();
    selected_index_ = -1;
    status_ = "工程未保存，无法打开工程目录";
    return;
  }
  load_directory(loc.folder);
}

bool Window::load_directory(const std::filesystem::path& dir) {
  std::error_code ec;
  if (dir.empty() || !std::filesystem::exists(dir, ec) || !std::filesystem::is_directory(dir, ec)) {
    entries_.clear();
    selected_index_ = -1;
    status_ = "路径无效或无法访问";
    return false;
  }

  std::vector<FileEntry> folders;
  std::vector<FileEntry> files;

  const auto parent = dir.parent_path();
  if (!parent.empty() && parent != dir) {
    folders.push_back({parent, L"..", true, true, false, false});
  }

  for (const auto& de : std::filesystem::directory_iterator(dir, ec)) {
    if (ec) break;
    const auto p = de.path();
    const std::wstring name = p.filename().wstring();
    if (!show_hidden_ && (is_hidden_name(name) || is_hidden_file(p))) continue;

    FileEntry entry;
    entry.path = p;
    entry.name = name;
    entry.is_dir = de.is_directory(ec);
    entry.is_audio = !entry.is_dir && is_audio_file(p);
    entry.is_project = !entry.is_dir && is_project_file(p);
    if (entry.is_dir) {
      folders.push_back(std::move(entry));
    } else {
      files.push_back(std::move(entry));
    }
  }

  auto by_name = [](const FileEntry& a, const FileEntry& b) {
    if (a.is_parent != b.is_parent) return a.is_parent;
    return lower_w(a.name) < lower_w(b.name);
  };
  std::sort(folders.begin(), folders.end(), by_name);
  std::sort(files.begin(), files.end(), by_name);

  entries_.clear();
  entries_.reserve(folders.size() + files.size());
  entries_.insert(entries_.end(), folders.begin(), folders.end());
  entries_.insert(entries_.end(), files.begin(), files.end());
  current_path_ = dir;
  selected_index_ = -1;
  drag_press_on_row_ = false;
  drag_press_row_idx_ = -1;
  status_.clear();
  return true;
}

void Window::navigate_up() {
  if (current_path_.empty()) return;
  const auto parent = current_path_.parent_path();
  if (!parent.empty() && parent != current_path_) load_directory(parent);
}

bool Window::open_current_project_folder_external() {
  ProjectLocation loc = current_project_location();
  if (loc.folder.empty()) {
    const auto& api = lee::Api();
    if (api.ShowMessageBox) {
      api.ShowMessageBox("工程未保存，无法打开工程目录", "Lee Project File Explorer", 0);
    }
    return false;
  }
  shell_open_path(loc.folder);
  return true;
}

void Window::open_entry(const FileEntry& entry) {
  if (entry.is_dir) {
    load_directory(entry.path);
    return;
  }

  const auto& api = lee::Api();
  const std::string path_u8 = path_to_utf8(entry.path);
  if (entry.is_project && api.Main_openProject) {
    api.Main_openProject(path_u8.c_str());
    return;
  }

  if (entry.is_audio && api.InsertMedia) {
    void* proj = api.EnumProjects ? api.EnumProjects(-1, nullptr, 0) : nullptr;
    if (api.GetSelectedTrack && api.CountTracks && api.GetTrack && api.InsertTrackAtIndex &&
        api.SetOnlyTrackSelected) {
      void* track = api.GetSelectedTrack(proj, 0);
      if (!track) {
        if (api.CountTracks(proj) == 0) {
          api.InsertTrackAtIndex(0, true);
          if (api.TrackList_AdjustWindows) api.TrackList_AdjustWindows(false);
        }
        track = api.GetTrack(proj, 0);
        if (track) api.SetOnlyTrackSelected(track);
      }
    }

    api.InsertMedia(path_u8.c_str(), 0);
    if (api.GetSelectedMediaItem && api.GetMediaItemInfo_Value && api.SetEditCurPos) {
      void* item = api.GetSelectedMediaItem(proj, 0);
      if (item) {
        const double pos = api.GetMediaItemInfo_Value(item, "D_POSITION");
        const double len = api.GetMediaItemInfo_Value(item, "D_LENGTH");
        api.SetEditCurPos(pos + len, false, false);
      }
    }
    return;
  }

  shell_open_path(entry.path);
}

void Window::start_os_drag(const FileEntry& entry) {
  if (entry.is_dir || entry.path.empty()) return;
  const wchar_t* raw[] = {entry.path.c_str()};
  HGLOBAL hdrop = ::CreateHDropFromPaths(raw, 1);
  if (!hdrop) return;
  HWND owner = nullptr;
  if (const auto& api = lee::Api(); api.GetMainHwnd) owner = api.GetMainHwnd();
  HRESULT hr = ::RunOsFileDragDrop(owner, hdrop);
  if (FAILED(hr)) lee::DebugLog(L"ProjectExplorer: RunOsFileDragDrop failed");
}

void Window::draw_ui() {
  const lee::ui::FrameTheme frame = lee::ui::BeginFrame(ctx_, theme_fonts_);
  ImGui::SetNextWindowSize(ctx_, 700.0, 600.0, 4);

  bool stay_open = true;
  if (!ImGui::Begin(ctx_, "Project File Explorer", &stay_open)) {
    lee::ui::EndFrame(ctx_, frame);
    if (!stay_open) hide();
    return;
  }

  bool activate_entry = false;
  FileEntry entry_to_activate;

  ImGui::Text(ctx_, "路径:");
  ImGui::SameLine(ctx_);
  const std::string path_display = current_path_.empty() ? "未选择路径" : shorten_utf8(current_path_, 92);
  ImGui::TextWrapped(ctx_, path_display.c_str());
  if (!status_.empty()) {
    ImGui::TextColored(ctx_, kTextProject, status_.c_str());
  }
  ImGui::Separator(ctx_);

  if (ImGui::Button(ctx_, "工程文件夹")) load_current_project_folder();
  ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "打开工程目录")) open_current_project_folder_external();
  ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "上级")) navigate_up();
  ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "刷新")) {
    if (current_path_.empty()) load_current_project_folder();
    else load_directory(current_path_);
  }
  ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "外部打开") && !current_path_.empty()) shell_open_path(current_path_);
  ImGui::SameLine(ctx_);
  bool hidden = show_hidden_;
  if (ImGui::Checkbox(ctx_, "显示隐藏文件", &hidden)) {
    show_hidden_ = hidden;
    if (!current_path_.empty()) load_directory(current_path_);
  }

  ImGui::Separator(ctx_);

  if (ImGui::BeginChild(ctx_, "##project_file_list", 0.0, -52.0, ImGui::ChildFlags_Borders)) {
    if (ImGui::BeginTable(ctx_, "##project_files", 3,
                          ImGui::TableFlags_RowBg |
                              ImGui::TableFlags_Borders |
                              ImGui::TableFlags_Resizable |
                              ImGui::TableFlags_ScrollY)) {
      ImGui::TableSetupColumn(ctx_, "名称", ImGui::TableColumnFlags_WidthStretch);
      ImGui::TableSetupColumn(ctx_, "类型", ImGui::TableColumnFlags_WidthFixed, 120.0);
      ImGui::TableSetupColumn(ctx_, "路径", ImGui::TableColumnFlags_WidthFixed, 260.0);
      ImGui::TableHeadersRow(ctx_);

      if (entries_.empty()) {
        ImGui::TableNextRow(ctx_);
        ImGui::TableNextColumn(ctx_);
        ImGui::TextColored(ctx_, kTextDim, current_path_.empty() ? "没有可显示的工程目录" : "文件夹为空");
      }

      for (int i = 0; i < static_cast<int>(entries_.size()); ++i) {
        const FileEntry& e = entries_[i];
        ImGui::PushID(ctx_, std::to_string(i).c_str());
        ImGui::TableNextRow(ctx_);

        ImGui::TableNextColumn(ctx_);
        std::string label = row_prefix(e) + wide_to_utf8(e.name);
        bool selected = selected_index_ == i;
        const bool row_color_pushed = ImGui::PushStyleColor && ImGui::PopStyleColor;
        if (row_color_pushed) ImGui::PushStyleColor(ctx_, ImGui::Col_Text, text_color(e));
        if (ImGui::Selectable(ctx_, label.c_str(), &selected,
                              ImGui::SelectableFlags_SpanAllColumns |
                                  ImGui::SelectableFlags_AllowDoubleClick)) {
          selected_index_ = i;
          if (ImGui::IsMouseDoubleClicked &&
              ImGui::IsMouseDoubleClicked(ctx_, ImGui::MouseButton_Left)) {
            entry_to_activate = e;
            activate_entry = true;
          }
        }
        if (row_color_pushed) ImGui::PopStyleColor(ctx_, 1);

        if (!e.is_dir && ImGui::IsItemActive(ctx_) &&
            ImGui::IsMouseClicked(ctx_, ImGui::MouseButton_Left)) {
          selected_index_ = i;
          drag_press_on_row_ = true;
          drag_press_row_idx_ = i;
          if (ImGui::GetMousePos) ImGui::GetMousePos(ctx_, &drag_press_x_, &drag_press_y_);
        }

        if (ImGui::IsItemHovered(ctx_) && ImGui::BeginTooltip(ctx_)) {
          ImGui::Text(ctx_, path_to_utf8(e.path).c_str());
          if (!e.is_dir) ImGui::TextDisabled(ctx_, "拖动到 REAPER 编排区可导入文件");
          ImGui::EndTooltip(ctx_);
        }

        ImGui::TableNextColumn(ctx_);
        ImGui::TextColored(ctx_, e.is_audio ? kTextAudio : (e.is_project ? kTextProject : kTextDim),
                           type_label(e).c_str());

        ImGui::TableNextColumn(ctx_);
        ImGui::TextColored(ctx_, kTextDim, shorten_utf8(e.path, 52).c_str());

        ImGui::PopID(ctx_);
      }
      ImGui::EndTable(ctx_);
    }
  }
  ImGui::EndChild(ctx_);

  // Directory navigation rebuilds entries_. Defer it until the table loop no
  // longer holds references into that vector.
  if (activate_entry) open_entry(entry_to_activate);

  if (!drag_in_progress_ && drag_press_on_row_ &&
      ImGui::IsMouseDown(ctx_, ImGui::MouseButton_Left)) {
    double mx = 0.0, my = 0.0;
    if (ImGui::GetMousePos) ImGui::GetMousePos(ctx_, &mx, &my);
    const double dx = mx - drag_press_x_;
    const double dy = my - drag_press_y_;
    if (dx * dx + dy * dy > 25.0 && drag_press_row_idx_ >= 0 &&
        drag_press_row_idx_ < static_cast<int>(entries_.size())) {
      drag_in_progress_ = true;
      drag_press_on_row_ = false;
      start_os_drag(entries_[drag_press_row_idx_]);
      drag_in_progress_ = false;
    }
  }
  if (!ImGui::IsMouseDown(ctx_, ImGui::MouseButton_Left)) {
    drag_press_on_row_ = false;
    drag_press_row_idx_ = -1;
  }

  ImGui::Separator(ctx_);
  if (selected_index_ >= 0 && selected_index_ < static_cast<int>(entries_.size())) {
    const FileEntry& e = entries_[selected_index_];
    ImGui::TextColored(ctx_, kTextDim, "选中:");
    ImGui::SameLine(ctx_);
    ImGui::Text(ctx_, wide_to_utf8(e.name).c_str());
    if (!e.is_dir) {
      ImGui::SameLine(ctx_, 0.0, 16.0);
      if (ImGui::Button(ctx_, e.is_project ? "打开工程" : (e.is_audio ? "插入到轨道" : "外部打开"))) {
        open_entry(e);
      }
    }
  } else {
    char footer[160];
    std::snprintf(footer, sizeof(footer),
                  "双击打开，拖动文件到 REAPER 可导入 | 当前共 %d 项",
                  static_cast<int>(entries_.size()));
    ImGui::TextColored(ctx_, kTextDim, footer);
  }

  ImGui::End(ctx_);
  lee::ui::EndFrame(ctx_, frame);
  if (!stay_open) hide();
}

}  // namespace lee::projectexplorer
