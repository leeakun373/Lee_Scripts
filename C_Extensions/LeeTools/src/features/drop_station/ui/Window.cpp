#include "features/drop_station/ui/Window.h"

#include <windows.h>
#include <shellapi.h>
#include <objidl.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

#include "reaper_imgui_functions.h"

#include "features/drop_station/domain/SliceReplicator.h"
#include "features/drop_station/domain/Store.h"
#include "platform/win/OsFileDrag.h"
#include "plugin/PluginContext.h"
#include "shared/reaper/ReaImGuiApi.h"
#include "shared/ui/LeeUiTheme.h"

namespace lee::dropstation {

namespace {

std::wstring basename_of(const std::wstring& path) {
  for (size_t i = path.size(); i > 0; --i) {
    wchar_t c = path[i - 1];
    if (c == L'\\' || c == L'/') {
      return path.substr(i);
    }
  }
  return path;
}

std::string to_utf8(const std::wstring& w) {
  if (w.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()),
                              nullptr, 0, nullptr, nullptr);
  if (n <= 0) return {};
  std::string out(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()),
                      out.data(), n, nullptr, nullptr);
  return out;
}

void reveal_in_explorer(const std::wstring& path) {
  if (path.empty()) return;
  std::wstring arg = L"/select,\"" + path + L"\"";
  ShellExecuteW(nullptr, L"open", L"explorer.exe", arg.c_str(), nullptr, SW_SHOWNORMAL);
}

// "1:23.456" formatter for slice time ranges. Choose seconds-only formatting
// for sub-minute slices to avoid wasting label width on leading zeros.
std::string format_time(double seconds) {
  if (seconds < 0) seconds = 0.0;
  char buf[32];
  if (seconds < 60.0) {
    std::snprintf(buf, sizeof(buf), "%.2fs", seconds);
  } else {
    int total = static_cast<int>(seconds);
    int m = total / 60;
    double s = seconds - 60.0 * m;
    std::snprintf(buf, sizeof(buf), "%d:%05.2f", m, s);
  }
  return buf;
}

// Compose "<basename> [start - end]" for slices, plain "<basename>" for whole
// sources. Anything > 0 length with non-zero offset OR < whole source length
// is considered a slice.
std::wstring make_display_label(const std::wstring& take_name,
                                const std::wstring& basename,
                                double take_offset,
                                double length) {
  std::wstring base = !take_name.empty() ? take_name : basename;
  if (length <= 0.0) {
    return base;
  }
  std::string range = "  [" + format_time(take_offset) + " - "
                    + format_time(take_offset + length) + "]";
  return base + lee::Utf8ToWide(range.c_str());
}

void separator_text(ImGui_Context* ctx, const char* label) {
  if (ImGui::SeparatorText) {
    ImGui::SeparatorText(ctx, label);
  } else {
    ImGui::Separator(ctx);
    ImGui::Text(ctx, label);
    ImGui::Separator(ctx);
  }
}

void help_marker(ImGui_Context* ctx, const char* text) {
  ImGui::SameLine(ctx);
  ImGui::TextDisabled(ctx, "(?)");
  if (ImGui::IsItemHovered(ctx) && ImGui::BeginTooltip(ctx)) {
    if (ImGui::PushTextWrapPos) ImGui::PushTextWrapPos(ctx, 320.0);
    ImGui::Text(ctx, text);
    if (ImGui::PopTextWrapPos) ImGui::PopTextWrapPos(ctx);
    ImGui::EndTooltip(ctx);
  }
}

// Selection / drag-gesture state. Lives at module scope because the window is
// a singleton and we do not need per-instance bookkeeping.
struct UiState {
  std::vector<bool> selected;
  int last_clicked_idx = -1;
  bool drag_press_on_row = false;
  int drag_press_row_idx = -1;
  double drag_press_x = 0.0;
  double drag_press_y = 0.0;
  bool drag_in_progress = false;

  void ensure_size(size_t n) {
    if (selected.size() != n) selected.assign(n, false);
  }
  std::vector<size_t> selected_indices() const {
    std::vector<size_t> r;
    for (size_t i = 0; i < selected.size(); ++i) {
      if (selected[i]) r.push_back(i);
    }
    return r;
  }
  void clear_selection() {
    std::fill(selected.begin(), selected.end(), false);
  }
};

UiState& ui() {
  static UiState s;
  return s;
}

}  // namespace

Window& GetWindow() {
  static Window w;
  return w;
}

Window::~Window() {
  destroy();
}

// ---------------------------------------------------------------------------
// AddSelected: collect source paths of REAPER's currently selected items.
// ---------------------------------------------------------------------------
int AddSelectedItemsToModel(Model& model) {
  const auto& api = lee::Api();
  if (!api.CountSelectedMediaItems || !api.GetSelectedMediaItem ||
      !api.GetActiveTake || !api.GetMediaItemTake_Source ||
      !api.GetMediaSourceFileName) {
    OutputDebugStringA("[Lee] AddSelected: missing core API\n");
    return 0;
  }
  void* proj = nullptr;
  if (api.EnumProjects) proj = api.EnumProjects(-1, nullptr, 0);

  const int n = api.CountSelectedMediaItems(proj);
  OutputDebugStringA("[Lee] AddSelected: begin\n");
  int added = 0;
  for (int i = 0; i < n; ++i) {
    void* item = api.GetSelectedMediaItem(proj, i);
    if (!item) continue;
    // Hard validation. REAPER's ValidatePtr2 catches dangling MediaItem
    // pointers (which can otherwise crash the API in obscure project states,
    // e.g. just after a SWS action or item deletion).
    if (api.ValidatePtr2 && !api.ValidatePtr2(proj, item, "MediaItem*")) {
      OutputDebugStringA("[Lee] AddSelected: item failed ValidatePtr2\n");
      continue;
    }

    void* take = api.GetActiveTake(item);
    if (!take) continue;
    if (api.ValidatePtr2 && !api.ValidatePtr2(proj, take, "MediaItem_Take*")) {
      OutputDebugStringA("[Lee] AddSelected: take failed ValidatePtr2\n");
      continue;
    }

    void* src = api.GetMediaItemTake_Source(take);
    if (!src) continue;

    char buf[4096] = {0};
    api.GetMediaSourceFileName(src, buf, static_cast<int>(sizeof(buf)));
    if (buf[0] == '\0') continue;

    const std::wstring wpath = lee::Utf8ToWide(buf);
    if (wpath.empty()) continue;

    DropEntry entry;
    entry.path = wpath;

    // Capture the slice snapshot. Each call is independently optional so a
    // host missing one of the *_Value getters still gives us at least the
    // path. Defaults from DropEntry already match "no slicing".
    if (api.GetMediaItemInfo_Value) {
      entry.length      = api.GetMediaItemInfo_Value(item, "D_LENGTH");
      entry.fade_in     = api.GetMediaItemInfo_Value(item, "D_FADEINLEN");
      entry.fade_out    = api.GetMediaItemInfo_Value(item, "D_FADEOUTLEN");
      entry.item_volume = api.GetMediaItemInfo_Value(item, "D_VOL");
    }
    if (api.GetMediaItemTakeInfo_Value) {
      entry.take_offset = api.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS");
      entry.take_volume = api.GetMediaItemTakeInfo_Value(take, "D_VOL");
      entry.playrate    = api.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE");
    }

    // GUID -- used by Model::add as the preferred dedup key. Read the binary
    // GUID via GetSetMediaItemInfo (never the _String variant with a stack
    // buffer -- REAPER may realloc that pointer on get).
    if (api.GetSetMediaItemInfo && api.guidToString) {
      const void* guid = api.GetSetMediaItemInfo(item, "GUID", nullptr);
      if (guid) {
        char gbuf[64] = {0};
        api.guidToString(guid, gbuf);
        if (gbuf[0] != '\0') {
          entry.item_guid.assign(gbuf);
        }
      }
    }

    // Display name: prefer GetTakeName (returns a stable const char*), else
    // fall back to the source basename. Append the time range so abc-style
    // slices are easy to tell apart in the list.
    std::wstring take_name;
    if (api.GetTakeName) {
      const char* name = api.GetTakeName(take);
      if (name && name[0] != '\0') {
        take_name = lee::Utf8ToWide(name);
      }
    }
    entry.label = make_display_label(take_name, basename_of(wpath),
                                     entry.take_offset, entry.length);

    if (model.add(entry)) {
      ++added;
    }
  }
  char done[64];
  std::snprintf(done, sizeof(done), "[Lee] AddSelected: end, added=%d\n", added);
  OutputDebugStringA(done);
  return added;
}

// ---------------------------------------------------------------------------
// OS file drag-out (CF_HDROP, multi-file). See dropstation/OsFileDrag.cpp.
// ---------------------------------------------------------------------------
void Window::start_os_drag(const std::vector<DropEntry>& slice_entries,
                            bool arm_replicate) {
  if (slice_entries.empty()) return;

  // Pull out the raw source paths in the same order as the slice list so that
  // the replicator's FIFO matching aligns with the items REAPER creates.
  std::vector<const wchar_t*> raw;
  raw.reserve(slice_entries.size());
  for (const auto& e : slice_entries) {
    if (!e.path.empty()) raw.push_back(e.path.c_str());
  }
  if (raw.empty()) return;

  HGLOBAL hdrop = ::CreateHDropFromPaths(raw.data(), raw.size());
  if (!hdrop) {
    lee::DebugLog(L"DropStation: CreateHDropFromPaths failed");
    return;
  }
  HWND owner = nullptr;
  if (const auto& api = lee::Api(); api.GetMainHwnd) {
    owner = api.GetMainHwnd();
  }

  // Arm the replicator BEFORE DoDragDrop, so we have a clean snapshot of
  // pre-existing item GUIDs. If the drop ends up landing outside REAPER no
  // new matching items appear and the replicator quietly times out after
  // ~5 seconds.
  if (arm_replicate && current_proj_) {
    GetReplicator().Begin(current_proj_, slice_entries);
  }

  HRESULT hr = ::RunOsFileDragDrop(owner, hdrop);
  if (arm_replicate) {
    if (FAILED(hr) || hr == DRAGDROP_S_CANCEL) {
      GetReplicator().Cancel();
    } else {
      GetReplicator().FlushAfterDrop();
    }
  } else if (FAILED(hr)) {
    lee::DebugLog(L"DropStation: RunOsFileDragDrop failed");
  }
}

// ---------------------------------------------------------------------------
// Context lifecycle.
// ---------------------------------------------------------------------------
bool Window::ensure_context() {
  if (ctx_) return true;
  if (!lee::reaimgui::Ready()) {
    return false;
  }
  try {
    ctx_ = ImGui::CreateContext("Lee Drop Station");
  } catch (const ImGui_Error&) {
    lee::DebugLog(L"DropStation: ImGui_CreateContext threw");
    ctx_ = nullptr;
    return false;
  }
  if (!ctx_) {
    return false;
  }
  lee::ui::EnsureFonts(ctx_, theme_fonts_);
  load_settings();
  if (const auto& api = lee::Api(); api.EnumProjects) {
    current_proj_ = api.EnumProjects(-1, nullptr, 0);
    if (current_proj_) {
      Store::Load(current_proj_, model_);
    }
  }
  return true;
}

void Window::load_settings() {
  if (settings_loaded_) return;
  // Stored as the literal strings "1" / "0" in the REAPER global ext state.
  // Default true on first use.
  const char* v = lee::GetExtState("Lee_DropStation", "replicate");
  if (v && (v[0] == '0')) {
    replicate_enabled_ = false;
  } else {
    replicate_enabled_ = true;
  }
  settings_loaded_ = true;
}

void Window::save_settings() {
  const auto& api = lee::Api();
  if (!api.SetExtState) return;
  api.SetExtState("Lee_DropStation", "replicate", replicate_enabled_ ? "1" : "0", true);
}

bool Window::show() {
  if (!ensure_context()) {
    return false;
  }
  open_ = true;
  return true;
}

void Window::hide() {
  open_ = false;
}

void Window::toggle() {
  if (open_) {
    hide();
  } else {
    show();
  }
}

void Window::destroy() {
  GetReplicator().Cancel();
  if (ctx_) {
    lee::ui::DestroyFonts(ctx_, theme_fonts_);
  }
  ctx_ = nullptr;
  open_ = false;
  current_proj_ = nullptr;
}

void Window::poll_project_switch() {
  const auto& api = lee::Api();
  if (!api.EnumProjects) return;
  void* proj = api.EnumProjects(-1, nullptr, 0);
  if (proj != current_proj_) {
    if (current_proj_) {
      Store::Save(current_proj_, model_);
    }
    current_proj_ = proj;
    model_.reset({});
    if (current_proj_) {
      Store::Load(current_proj_, model_);
    }
  }
}

// ---------------------------------------------------------------------------
// Main tick: called by REAPER's timer hook. ReaImGui handles its own message
// pump / present so we just describe the frame here.
// ---------------------------------------------------------------------------
void Window::tick() {
  // The slice replicator must keep ticking even when the Drop Station window
  // is hidden, otherwise a drop completed in the brief moment between the
  // user closing the window and REAPER instantiating the new item would
  // never get its slice properties patched. Tick it unconditionally first.
  GetReplicator().Tick();

  if (!open_ || !ctx_) return;
  if (!lee::reaimgui::Ready()) {
    open_ = false;
    return;
  }
  poll_project_switch();

  // ReaImGui throws if the context was invalidated (e.g. the user closed the
  // window via OS chrome and ReaImGui auto-destroyed the context). Treat any
  // exception during a frame as "window gone" and clean up locally.
  try {
    draw_ui();
  } catch (const ImGui_Error& e) {
    lee::DebugLog(L"DropStation: frame raised ImGui_Error, closing");
    OutputDebugStringA(e.what());
    OutputDebugStringA("\n");
    ctx_ = nullptr;
    open_ = false;
  } catch (...) {
    ctx_ = nullptr;
    open_ = false;
  }
}

// ---------------------------------------------------------------------------
// One ImGui frame. Mirrors the layout of the original DX11 version but uses
// ReaImGui's API surface (note: sizes are doubles, optional flags can be
// omitted entirely thanks to the binding's default-argument support).
// ---------------------------------------------------------------------------
void Window::draw_ui() {
  const lee::ui::FrameTheme frame = lee::ui::BeginFrame(ctx_, theme_fonts_);

  ImGui::SetNextWindowSize(ctx_, 540.0, 520.0, /*Cond_FirstUseEver*/ 4);

  bool stay_open = true;
  unsigned int prev_revision = model_.revision();
  bool save_now = false;

  if (!ImGui::Begin(ctx_, "Lee Drop Station", &stay_open)) {
    ImGui::End(ctx_);
    lee::ui::EndFrame(ctx_, frame);
    if (!stay_open) open_ = false;
    return;
  }

  // Header (Toolbox Demo_UI pattern)
  if (theme_fonts_.heading && ImGui::PushFont) {
    ImGui::PushFont(ctx_, theme_fonts_.heading, 22.0);
    ImGui::Text(ctx_, "Drop Station");
    ImGui::PopFont(ctx_);
  } else {
    ImGui::Text(ctx_, "Drop Station");
  }
  if (ImGui::PushStyleColor) {
    ImGui::PushStyleColor(ctx_, ImGui::Col_Text, lee::ui::kSemanticTextDim);
    ImGui::Text(ctx_,
                "Slice clipboard -- add items, drag back into REAPER or out to Explorer.");
    ImGui::PopStyleColor(ctx_, 1);
  }

  separator_text(ctx_, "Actions");
  if (ImGui::Button(ctx_, "Add Selected")) {
    if (AddSelectedItemsToModel(model_) > 0) save_now = true;
  }
  ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "Clear")) {
    if (!model_.entries().empty()) { model_.clear(); save_now = true; }
  }
  ImGui::SameLine(ctx_);
  if (ImGui::Button(ctx_, "Sort")) {
    model_.sort_by_label();
    save_now = true;
  }

  {
    bool was = replicate_enabled_;
    if (ImGui::Checkbox(ctx_, "Replicate slice in REAPER", &replicate_enabled_)) {
      if (was != replicate_enabled_) save_settings();
    }
    help_marker(ctx_,
                "When you drop a slice back into a REAPER project, automatically "
                "restore the original take offset, length, fade-in/out, item/take "
                "volume and play rate. Drops outside REAPER still receive the raw "
                "source file for now.");
  }

  separator_text(ctx_, "Items");

  {
    char hint[160];
    std::snprintf(hint, sizeof(hint),
                  "%d item(s)  |  press and drag rows out  |  right-click menu",
                  static_cast<int>(model_.entries().size()));
    ImGui::TextDisabled(ctx_, hint);
  }

  const auto& entries = model_.entries();
  ui().ensure_size(entries.size());

  const int child_flags = ImGui::ChildFlags_Borders;
  if (ImGui::BeginChild(ctx_, "##list", 0.0, 0.0, child_flags)) {
    if (entries.empty()) {
      ImGui::TextDisabled(ctx_, "No items yet.");
      ImGui::TextDisabled(ctx_, "Select media items in the arrange, then Add Selected.");
    }

    int delete_request = -1;
    bool remove_selected_request = false;

    for (int i = 0; i < static_cast<int>(entries.size()); ++i) {
      ImGui::PushID(ctx_, std::to_string(i).c_str());

      const auto& e = entries[i];
      std::string label_u8 = to_utf8(e.label);
      if (label_u8.empty()) label_u8 = to_utf8(basename_of(e.path));

      bool selected = ui().selected[i];
      const int sel_flags = ImGui::SelectableFlags_AllowDoubleClick;
      if (ImGui::Selectable(ctx_, label_u8.c_str(), &selected, sel_flags)) {
        const int mods = ImGui::GetKeyMods ? ImGui::GetKeyMods(ctx_) : 0;
        const bool shift = (mods & ImGui::Mod_Shift) != 0;
        const bool ctrl  = (mods & ImGui::Mod_Ctrl)  != 0;
        if (shift && ui().last_clicked_idx >= 0) {
          int a = ui().last_clicked_idx, b = i;
          if (a > b) std::swap(a, b);
          if (!ctrl) ui().clear_selection();
          for (int k = a; k <= b && k < static_cast<int>(ui().selected.size()); ++k) {
            ui().selected[k] = true;
          }
        } else if (ctrl) {
          ui().selected[i] = !ui().selected[i];
          ui().last_clicked_idx = i;
        } else {
          ui().clear_selection();
          ui().selected[i] = true;
          ui().last_clicked_idx = i;
        }
        if (ImGui::IsMouseDoubleClicked && ImGui::IsMouseDoubleClicked(ctx_, ImGui::MouseButton_Left)) {
          reveal_in_explorer(e.path);
        }
      }

      // Press on a row: select it (unless Ctrl/Shift multi-select) so drag-out
      // works on the first press-and-move without a separate click.
      if (ImGui::IsItemActive(ctx_) &&
          ImGui::IsMouseClicked(ctx_, ImGui::MouseButton_Left)) {
        const int mods = ImGui::GetKeyMods ? ImGui::GetKeyMods(ctx_) : 0;
        const bool shift = (mods & ImGui::Mod_Shift) != 0;
        const bool ctrl  = (mods & ImGui::Mod_Ctrl)  != 0;
        if (!ctrl && !shift && !ui().selected[i]) {
          ui().clear_selection();
          ui().selected[i] = true;
          ui().last_clicked_idx = i;
        }
        ui().drag_press_on_row = true;
        ui().drag_press_row_idx = i;
        double mx = 0.0, my = 0.0;
        if (ImGui::GetMousePos) ImGui::GetMousePos(ctx_, &mx, &my);
        ui().drag_press_x = mx;
        ui().drag_press_y = my;
      }

      if (ImGui::IsItemHovered(ctx_)) {
        if (ImGui::BeginTooltip(ctx_)) {
          ImGui::Text(ctx_, to_utf8(e.path).c_str());
          // Linear gains are stored 1.0 = unity; convert to dB on display so
          // it lines up with what users see in REAPER's item properties.
          auto db_from_lin = [](double v) {
            return v > 0.0 ? 20.0 * std::log10(v) : -150.0;
          };
          char meta[256];
          std::snprintf(meta, sizeof(meta),
                        "slice: %s -> %s   length: %s\n"
                        "fade in: %s   fade out: %s\n"
                        "item vol: %.2f dB   take vol: %.2f dB   rate: %.4fx",
                        format_time(e.take_offset).c_str(),
                        format_time(e.take_offset + e.length).c_str(),
                        format_time(e.length).c_str(),
                        format_time(e.fade_in).c_str(),
                        format_time(e.fade_out).c_str(),
                        db_from_lin(e.item_volume),
                        db_from_lin(e.take_volume),
                        e.playrate);
          ImGui::TextDisabled(ctx_, meta);
          ImGui::EndTooltip(ctx_);
        }
      }

      if (ImGui::BeginPopupContextItem(ctx_)) {
        if (!ui().selected[i]) {
          ui().clear_selection();
          ui().selected[i] = true;
          ui().last_clicked_idx = i;
        }
        if (ImGui::MenuItem(ctx_, "Reveal in Explorer")) reveal_in_explorer(e.path);
        if (ImGui::MenuItem(ctx_, "Copy Path")) {
          if (ImGui::SetClipboardText) ImGui::SetClipboardText(ctx_, to_utf8(e.path).c_str());
        }
        ImGui::Separator(ctx_);
        if (ImGui::MenuItem(ctx_, "Remove")) delete_request = i;
        if (ImGui::MenuItem(ctx_, "Remove Selected")) remove_selected_request = true;
        ImGui::EndPopup(ctx_);
      }

      ImGui::PopID(ctx_);
    }

    // Drag-out detection. Press-and-move > 5px on a row -> RunOsFileDragDrop.
    if (!ui().drag_in_progress && ui().drag_press_on_row &&
        ImGui::IsMouseDown(ctx_, ImGui::MouseButton_Left)) {
      double mx = 0.0, my = 0.0;
      if (ImGui::GetMousePos) ImGui::GetMousePos(ctx_, &mx, &my);
      const double dx = mx - ui().drag_press_x;
      const double dy = my - ui().drag_press_y;
      if (dx * dx + dy * dy > 25.0) {
        auto idxs = ui().selected_indices();
        if (idxs.empty() && ui().drag_press_row_idx >= 0 &&
            ui().drag_press_row_idx < static_cast<int>(entries.size())) {
          idxs.push_back(static_cast<size_t>(ui().drag_press_row_idx));
        }
        if (!idxs.empty()) {
          // Carry the full DropEntry rather than only paths -- the replicator
          // needs the slice metadata (offset / length / fades / vols / rate).
          std::vector<DropEntry> slice_entries;
          slice_entries.reserve(idxs.size());
          for (size_t k : idxs) {
            if (k < entries.size()) slice_entries.push_back(entries[k]);
          }
          if (!slice_entries.empty()) {
            ui().drag_in_progress = true;
            ui().drag_press_on_row = false;
            start_os_drag(slice_entries, replicate_enabled_);
            ui().drag_in_progress = false;
          }
        }
      }
    }
    if (!ImGui::IsMouseDown(ctx_, ImGui::MouseButton_Left)) {
      ui().drag_press_on_row = false;
      ui().drag_press_row_idx = -1;
    }

    if (delete_request >= 0) {
      model_.remove_at(static_cast<size_t>(delete_request));
      save_now = true;
    } else if (remove_selected_request) {
      auto idxs = ui().selected_indices();
      if (!idxs.empty()) {
        model_.remove_indices(idxs);
        save_now = true;
        ui().clear_selection();
        ui().last_clicked_idx = -1;
      }
    }
  }
  ImGui::EndChild(ctx_);

  ImGui::End(ctx_);

  if (!stay_open) open_ = false;

  if (save_now || model_.revision() != prev_revision) {
    if (current_proj_) Store::Save(current_proj_, model_);
  }

  lee::ui::EndFrame(ctx_, frame);
}

}  // namespace lee::dropstation
