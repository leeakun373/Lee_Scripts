#include "domain/Execution.h"

#include <vector>

#include "plugin/PluginContext.h"

namespace lee::radial_menu {
namespace {

int g_last_valid_context = -1;

void* CurrentProj() {
  const auto& api = lee::Api();
  if (!api.EnumProjects) return nullptr;
  return api.EnumProjects(-1, nullptr, 0);
}

bool AddFxTrack(void* track, const char* fx, bool show) {
  const auto& api = lee::Api();
  if (!api.TrackFX_AddByName || !track) return false;
  const int idx = api.TrackFX_AddByName(track, fx, false, -1);
  if (idx >= 0 && show && api.TrackFX_Show) api.TrackFX_Show(track, idx, 3);
  return idx >= 0;
}

bool AddFxItem(void* item, const char* fx, bool show) {
  const auto& api = lee::Api();
  if (!api.GetActiveTake || !api.TakeFX_AddByName || !item) return false;
  void* take = api.GetActiveTake(item);
  if (!take) return false;
  const int idx = api.TakeFX_AddByName(take, fx, -1);
  if (idx >= 0 && show && api.TakeFX_Show) api.TakeFX_Show(take, idx, 3);
  return idx >= 0;
}

enum class CtxKind { None, Item, Track };

struct ContextResult {
  CtxKind kind = CtxKind::None;
  std::vector<void*> objects;
  bool show_window = false;
};

ContextResult DetectContext(void* proj) {
  ContextResult r;
  const auto& api = lee::Api();
  if (!api.CountSelectedMediaItems || !api.GetSelectedMediaItem) return r;

  std::vector<void*> items;
  const int ic = api.CountSelectedMediaItems(proj);
  for (int i = 0; i < ic; ++i) {
    void* item = api.GetSelectedMediaItem(proj, i);
    if (item && api.GetActiveTake && api.GetActiveTake(item)) items.push_back(item);
  }

  std::vector<void*> tracks;
  if (api.CountSelectedTracks && api.GetSelectedTrack) {
    const int tc = api.CountSelectedTracks(proj);
    for (int i = 0; i < tc; ++i) tracks.push_back(api.GetSelectedTrack(proj, i));
  }

  if (items.empty() && tracks.empty()) return r;

  if (!items.empty() && tracks.empty()) {
    r.kind = CtxKind::Item;
    r.objects = items;
    r.show_window = items.size() == 1;
    return r;
  }
  if (!tracks.empty() && items.empty()) {
    r.kind = CtxKind::Track;
    r.objects = tracks;
    r.show_window = tracks.size() == 1;
    return r;
  }

  if (g_last_valid_context == 0) {
    r.kind = CtxKind::Track;
    r.objects = tracks;
    r.show_window = tracks.size() == 1;
    return r;
  }
  if (g_last_valid_context == 1) {
    r.kind = CtxKind::Item;
    r.objects = items;
    r.show_window = items.size() == 1;
    return r;
  }

  if (api.GetCursorContext) {
    const int cc = api.GetCursorContext();
    if (cc == 0) {
      r.kind = CtxKind::Track;
      r.objects = tracks;
      r.show_window = tracks.size() == 1;
      return r;
    }
    if (cc == 1) {
      r.kind = CtxKind::Item;
      r.objects = items;
      r.show_window = items.size() == 1;
      return r;
    }
  }

  r.kind = CtxKind::Item;
  r.objects = items;
  r.show_window = items.size() == 1;
  return r;
}

void RunFxChain(const Slot& slot, void* proj) {
  std::string fx;
  if (slot.type == "fx") fx = slot.fx_name;
  else if (slot.type == "chain") fx = slot.path;
  if (fx.empty()) return;

  ContextResult ctx = DetectContext(proj);
  const auto& api = lee::Api();

  if (ctx.kind == CtxKind::Item) {
    for (size_t i = 0; i < ctx.objects.size(); ++i) {
      const bool show = ctx.show_window && (i + 1 == ctx.objects.size());
      AddFxItem(ctx.objects[i], fx.c_str(), show);
    }
    return;
  }
  if (ctx.kind == CtxKind::Track) {
    for (size_t i = 0; i < ctx.objects.size(); ++i) {
      const bool show = ctx.show_window && (i + 1 == ctx.objects.size());
      AddFxTrack(ctx.objects[i], fx.c_str(), show);
    }
    return;
  }

  if (api.InsertTrackAtIndex && api.CountTracks && api.GetTrack) {
    const int idx = api.CountTracks(proj);
    api.InsertTrackAtIndex(idx, true);
    void* tr = api.GetTrack(proj, idx);
    if (tr) AddFxTrack(tr, fx.c_str(), true);
  }
}

}  // namespace

void Execution::SetLastValidContext(int ctx) {
  g_last_valid_context = ctx;
}

void Execution::TriggerSlot(const Slot& slot, void* proj) {
  if (!proj) proj = CurrentProj();
  const auto& api = lee::Api();

  if (slot.type == "action") {
    int cmd = slot.command_id;
    if (cmd <= 0 && !slot.command_name.empty() && api.NamedCommandLookup) {
      cmd = api.NamedCommandLookup(slot.command_name.c_str());
    }
    if (api.Main_OnCommand && cmd > 0) {
      api.Main_OnCommand(cmd, 0);
    }
    return;
  }

  if (slot.type == "fx" || slot.type == "chain") {
    RunFxChain(slot, proj);
    return;
  }

  if (slot.type == "template" && api.Main_openProject && !slot.path.empty()) {
    std::string cmd = "template:" + slot.path;
    api.Main_openProject(cmd.c_str());
  }
}

void Execution::HandleDrop(const Slot& slot, int screen_x, int screen_y, void* proj) {
  if (!proj) proj = CurrentProj();
  const auto& api = lee::Api();

  if (slot.type == "fx" || slot.type == "chain") {
    const std::string fx = slot.type == "fx" ? slot.fx_name : slot.path;
    if (fx.empty()) return;

    if (api.GetItemFromPoint) {
      void* item = api.GetItemFromPoint(screen_x, screen_y, true);
      if (item) {
        AddFxItem(item, fx.c_str(), true);
        return;
      }
    }
    if (api.GetTrackFromPoint) {
      void* tr = api.GetTrackFromPoint(screen_x, screen_y, nullptr);
      if (tr) {
        AddFxTrack(tr, fx.c_str(), true);
        return;
      }
    }
    if (api.InsertTrackAtIndex && api.CountTracks && api.GetTrack) {
      const int idx = api.CountTracks(proj);
      api.InsertTrackAtIndex(idx, true);
      void* tr = api.GetTrack(proj, idx);
      if (tr) AddFxTrack(tr, fx.c_str(), true);
    }
    return;
  }

  if (slot.type == "template" && api.Main_openProject && !slot.path.empty()) {
    std::string cmd = "template:" + slot.path;
    api.Main_openProject(cmd.c_str());
  }
}

}  // namespace lee::radial_menu
