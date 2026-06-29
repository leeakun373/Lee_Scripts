#pragma once

#include <filesystem>
#include <string>
#include <vector>

#include "shared/ui/LeeUiTheme.h"

class ImGui_Context;

namespace lee::projectexplorer {

struct FileEntry {
  std::filesystem::path path;
  std::wstring name;
  bool is_dir = false;
  bool is_parent = false;
  bool is_audio = false;
  bool is_project = false;
};

class Window {
 public:
  Window() = default;
  ~Window();

  Window(const Window&) = delete;
  Window& operator=(const Window&) = delete;

  bool is_open() const { return open_; }

  bool show();
  void hide();
  void toggle();
  void destroy();
  void tick();

  bool open_current_project_folder_external();

 private:
  bool open_ = false;
  ImGui_Context* ctx_ = nullptr;
  void* current_proj_ = nullptr;  // ReaProject*, last focused project tab.
  std::string current_project_file_;

  std::filesystem::path current_path_;
  std::vector<FileEntry> entries_;
  int selected_index_ = -1;
  bool show_hidden_ = false;
  std::string status_;
  bool drag_press_on_row_ = false;
  int drag_press_row_idx_ = -1;
  double drag_press_x_ = 0.0;
  double drag_press_y_ = 0.0;
  bool drag_in_progress_ = false;

  lee::ui::ThemeFonts theme_fonts_;

  bool ensure_context();
  void invalidate_context();
  void poll_project_switch();
  void draw_ui();
  void load_current_project_folder();
  bool load_directory(const std::filesystem::path& dir);
  void navigate_up();
  void open_entry(const FileEntry& entry);
  void start_os_drag(const FileEntry& entry);
};

Window& GetWindow();

}  // namespace lee::projectexplorer
