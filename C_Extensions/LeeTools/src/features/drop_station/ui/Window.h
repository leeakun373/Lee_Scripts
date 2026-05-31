#pragma once

#include <string>
#include <vector>

#include "features/drop_station/domain/Model.h"
#include "shared/ui/LeeUiTheme.h"

class ImGui_Context;

namespace lee::dropstation {

// Drop Station window driven by the ReaImGui extension. We do not create our
// own HWND, DX swap chain or font atlas -- ReaImGui owns all of that. The
// window only needs to:
//   - hold an ImGui_Context*
//   - reload the project-scoped entry list on project switch
//   - drive one ImGui frame per REAPER timer tick while open
//   - hand multi-selection paths to RunOsFileDragDrop on drag-out
class Window {
 public:
  Window() = default;
  ~Window();

  Window(const Window&) = delete;
  Window& operator=(const Window&) = delete;

  bool is_open() const { return open_; }

  // Shows the window. Idempotent. Returns false if ReaImGui isn't usable
  // (extension missing); the caller can surface this to the user.
  bool show();

  void hide();
  void toggle();

  // Called every REAPER timer tick (~33Hz). Builds the next ImGui frame; if
  // the user closed the window via the title-bar X we destroy our context.
  void tick();

  // Releases the ImGui context. Idempotent. Safe to call on plugin unload.
  void destroy();

  Model& model() { return model_; }

  // Builds a CF_HDROP from the slice entries' source paths and runs the modal
  // OS drag. If `arm_replicate` is true, the slice replicator is armed against
  // the active project so any items REAPER creates within the next few seconds
  // get their offset/length/fade/vol patched to match the original slices.
  void start_os_drag(const std::vector<DropEntry>& slice_entries,
                     bool arm_replicate);

 private:
  bool open_ = false;
  ImGui_Context* ctx_ = nullptr;
  Model model_;
  void* current_proj_ = nullptr;  // ReaProject*, last seen for switch detection

  lee::ui::ThemeFonts theme_fonts_;

  // UI/persistent settings. Backed by REAPER's GetExtState/SetExtState so the
  // preference survives across REAPER sessions and projects.
  bool replicate_enabled_ = true;
  bool settings_loaded_ = false;

  bool ensure_context();
  void poll_project_switch();
  void draw_ui();

  void load_settings();
  void save_settings();
};

// Singleton accessor used by the action handlers / timer.
Window& GetWindow();

// Standalone helper for the Lee_DropStation_AddSelected hotkey path.
// Reads REAPER's selected items, resolves each take's source path, and appends
// unique entries to the model. Returns the number of newly added entries.
int AddSelectedItemsToModel(Model& model);

}  // namespace lee::dropstation
