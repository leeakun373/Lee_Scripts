#include "features/item_hub/domain/Session.h"

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "plugin/PluginContext.h"

namespace lee::item_hub {

struct ItemState {
  void* item = nullptr;
  void* take = nullptr;
  double item_vol_db = 0.0;
  double take_vol_db = 0.0;
  double pitch = 0.0;
  double rate = 1.0;
  double preserve = 1.0;
  double fade_in_ms = 0.0;
  double fade_out_ms = 0.0;
  double fade_in_shape = 0.0;
  double fade_out_shape = 0.0;
  double pan100 = 0.0;
  double reverse = 0.0;
  double channel = 0.0;
  double position = 0.0;
  double length = 0.0;
  double take_offset = 0.0;
  double snap_offset = 0.0;
  double pitch_rand = 0.0;
  double rate_rand = 0.0;
  double vol_rand = 0.0;
  uint32_t rand_seed = 1;
};

struct EnvPoint {
  double time = 0.0;
  double value = 0.0;
  int shape = 0;
  double tension = 0.0;
  bool selected = false;
};

struct EnvCache {
  void* envelope = nullptr;
  int autoitem_idx = -1;
  std::vector<EnvPoint> baseline;
};

struct PendingReverseApply {
  void* item = nullptr;
  void* take = nullptr;
  bool want = false;
};

struct SessionData {
  void* proj = nullptr;
  std::vector<ItemState> items;
  std::vector<EnvCache> envs;
  std::vector<PendingReverseApply> pending_reverse;
  double relative[static_cast<int>(ParamId::Count)] = {};
  double envelope_vscale = 1.0;
  double envelope_voffset = 0.0;
  double envelope_tscale = 1.0;
  double envelope_smooth = 0.0;
  double item_gap = 0.0;
  double batch_trim = 1.0;
  int randomize_gen = 0;
  bool envelopes_captured = false;
};

namespace {

constexpr double kFineScale = 0.15;
constexpr int kCmdToggleTakeReverse = 41051;
constexpr double kMaxPositionSeconds = 30.0;

bool deselect_all_items(void* proj, const lee::ApiTable& api) {
  if (!proj || !api.CountMediaItems || !api.GetMediaItem || !api.SetMediaItemInfo_Value) {
    return false;
  }
  const int n = api.CountMediaItems(proj);
  for (int i = 0; i < n; ++i) {
    void* it = api.GetMediaItem(proj, i);
    if (it) api.SetMediaItemInfo_Value(it, "B_UISEL", 0.0);
  }
  return true;
}

void restore_hub_selection(SessionData& data, const lee::ApiTable& api) {
  if (!data.proj || !api.SetMediaItemInfo_Value) return;
  deselect_all_items(data.proj, api);
  for (const ItemState& st : data.items) {
    if (st.item) api.SetMediaItemInfo_Value(st.item, "B_UISEL", 1.0);
  }
}

double db_from_lin(double v) {
  return v > 0.0 ? 20.0 * std::log10(v) : -150.0;
}

double lin_from_db(double db) {
  return std::pow(10.0, db / 20.0);
}

double clampd(double v, double lo, double hi) {
  return std::max(lo, std::min(hi, v));
}

double item_target_rate(const SessionData& data, const ItemState& st) {
  if (std::abs(st.rate_rand) > 1e-9) {
    return clampd(st.rate + st.rate_rand, 0.1, 4.0);
  }
  return clampd(data.relative[static_cast<int>(ParamId::Rate)], 0.1, 4.0);
}

double item_timeline_length(const ItemState& st, double target_rate) {
  const double base_rate = st.rate > 0.0 ? st.rate : 1.0;
  return std::max(0.001, st.length * base_rate / target_rate);
}

double item_intended_length(const SessionData& data, const ItemState& st, bool multi) {
  const ParamDef& right_def = Def(ParamId::RightEdge);
  const double right_slot = data.relative[static_cast<int>(ParamId::RightEdge)];
  const double rate_len = item_timeline_length(st, item_target_rate(data, st));

  if (multi) {
    return clampd(rate_len + right_slot, right_def.min_v, right_def.max_v);
  }
  return clampd(right_slot, right_def.min_v, right_def.max_v);
}

void apply_left_edge_item(const SessionData& data, const ItemState& st, void* item, void* take,
                          double trim_s, bool multi, const lee::ApiTable& api) {
  if (!item || !api.SetMediaItemInfo_Value) return;
  const double target_rate = item_target_rate(data, st);
  const double intended_len = item_intended_length(data, st, multi);
  trim_s = clampd(trim_s, 0.0, std::max(0.0, intended_len - 0.001));

  if (take && api.SetMediaItemTakeInfo_Value) {
    api.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", st.take_offset + trim_s * target_rate);
  }
  api.SetMediaItemInfo_Value(item, "D_LENGTH", std::max(0.001, intended_len - trim_s));
  api.SetMediaItemInfo_Value(item, "D_POSITION", st.position + trim_s);
  if (st.snap_offset > 0.0) {
    api.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", st.snap_offset + trim_s);
  }
}

void param_limits(const SessionData& data, bool multi, ParamId id, double& min_v, double& max_v) {
  const ParamDef& def = Def(id);
  min_v = def.min_v;
  max_v = def.max_v;

  switch (id) {
    case ParamId::LeftEdge: {
      if (data.items.empty()) break;
      max_v = kMaxPositionSeconds;
      for (const ItemState& st : data.items) {
        const double intended = item_intended_length(data, st, multi);
        max_v = std::min(max_v, std::max(0.0, intended - 0.001));
      }
      break;
    }
    case ParamId::SnapOffset: {
      if (data.items.empty()) break;
      double cap = kMaxPositionSeconds;
      for (const ItemState& st : data.items) {
        cap = std::min(cap, std::max(0.001, st.length));
      }
      if (multi) {
        min_v = -cap;
      }
      max_v = cap;
      break;
    }
    default:
      break;
  }
}

Session g_session;

bool take_supports_reverse(void* take, const lee::ApiTable& api) {
  if (!take || !api.GetMediaItemTake_Source || !api.GetMediaSourceType) return false;
  void* src = api.GetMediaItemTake_Source(take);
  if (!src) return false;
  char type[64] = {};
  api.GetMediaSourceType(src, type, sizeof(type));
  return std::strcmp(type, "MIDI") != 0;
}

bool reverse_apis_available(const lee::ApiTable& api) {
  return api.Main_OnCommand && api.SetMediaItemInfo_Value && api.CountMediaItems &&
         api.GetMediaItem;
}

bool read_take_reverse(void* take, const lee::ApiTable& api) {
  if (!take_supports_reverse(take, api)) return false;
  if (!api.GetMediaItemTake_Source || !api.PCM_Source_GetSectionInfo) return false;

  void* src = api.GetMediaItemTake_Source(take);
  if (!src) return false;

  char type[64] = {};
  api.GetMediaSourceType(src, type, sizeof(type));
  if (std::strcmp(type, "SECTION") != 0) return false;

  double offs = 0.0;
  double len = 0.0;
  bool reverse = false;
  if (api.PCM_Source_GetSectionInfo(src, &offs, &len, &reverse)) return reverse;
  return false;
}

bool set_take_reverse_action(void* proj, void* take, void* item, bool want_reverse,
                             const lee::ApiTable& api) {
  if (!proj || !take || !item || !api.Main_OnCommand || !api.SetMediaItemInfo_Value) {
    return false;
  }
  if (api.ValidatePtr2) {
    if (!api.ValidatePtr2(proj, item, "MediaItem*")) return false;
    if (!api.ValidatePtr2(proj, take, "MediaItem_Take*")) return false;
  }
  if (read_take_reverse(take, api) == want_reverse) return true;

  if (api.PreventUIRefresh) api.PreventUIRefresh(1);
  if (api.SetActiveTake) api.SetActiveTake(item, take);
  if (!deselect_all_items(proj, api)) {
    if (api.PreventUIRefresh) api.PreventUIRefresh(-1);
    return false;
  }
  api.SetMediaItemInfo_Value(item, "B_UISEL", 1.0);
  api.Main_OnCommand(kCmdToggleTakeReverse, 0);
  if (api.PreventUIRefresh) api.PreventUIRefresh(-1);
  return true;
}

bool set_take_reverse(void* proj, void* take, void* item, bool want_reverse,
                      const lee::ApiTable& api) {
  if (!take_supports_reverse(take, api)) return false;
  return set_take_reverse_action(proj, take, item, want_reverse, api);
}

bool envelope_visible(const lee::ApiTable& api, void* env) {
  if (!env || !api.GetEnvelopeInfo_Value) return true;
  return api.GetEnvelopeInfo_Value(env, "B_SHOW") > 0.5;
}

int count_envelope_lane_points(const lee::ApiTable& api, void* env, int autoitem_idx) {
  if (!env) return 0;
  if (api.CountEnvelopePointsEx) return api.CountEnvelopePointsEx(env, autoitem_idx);
  if (autoitem_idx < 0 && api.CountEnvelopePoints) return api.CountEnvelopePoints(env);
  return 0;
}

void capture_envelope_lane(const lee::ApiTable& api, void* env, int autoitem_idx,
                           std::vector<EnvCache>& out) {
  const int pc = count_envelope_lane_points(api, env, autoitem_idx);
  if (pc <= 0) return;

  EnvCache cache;
  cache.envelope = env;
  cache.autoitem_idx = autoitem_idx;
  cache.baseline.reserve(static_cast<size_t>(pc));
  for (int p = 0; p < pc; ++p) {
    EnvPoint pt;
    bool ok = false;
    if (api.GetEnvelopePointEx) {
      ok = api.GetEnvelopePointEx(env, autoitem_idx, p, &pt.time, &pt.value, &pt.shape,
                                  &pt.tension, &pt.selected);
    } else if (autoitem_idx < 0 && api.GetEnvelopePoint) {
      ok = api.GetEnvelopePoint(env, p, &pt.time, &pt.value, &pt.shape, &pt.tension,
                                &pt.selected);
    }
    if (ok) cache.baseline.push_back(pt);
  }
  if (!cache.baseline.empty()) out.push_back(std::move(cache));
}

void capture_take_envelope(const lee::ApiTable& api, void* env, std::vector<EnvCache>& out,
                           int& auto_items_out, int& lanes_out) {
  if (!env) return;
  const size_t before = out.size();
  capture_envelope_lane(api, env, -1, out);
  auto_items_out = 0;
  if (api.CountAutomationItems) {
    auto_items_out = api.CountAutomationItems(env);
    for (int ai = 0; ai < auto_items_out; ++ai) {
      capture_envelope_lane(api, env, ai, out);
    }
  }
  lanes_out = static_cast<int>(out.size() - before);
}

void capture_envelopes(const lee::ApiTable& api, void* take, std::vector<EnvCache>& out) {
  if (!take || !api.CountTakeEnvelopes || !api.GetTakeEnvelope) return;
  if (!api.GetEnvelopePoint && !api.GetEnvelopePointEx) return;

  std::vector<void*> processed;
  auto already_processed = [&](void* env) {
    for (void* e : processed) {
      if (e == env) return true;
    }
    return false;
  };
  auto process_env = [&](void* env) {
    if (!env || already_processed(env)) return;
    processed.push_back(env);
    int auto_items = 0;
    int lanes = 0;
    capture_take_envelope(api, env, out, auto_items, lanes);
    (void)auto_items;
    (void)lanes;
  };

  static const char* kTakeEnvNames[] = {"Volume", "Pan", "Pitch", "Mute"};
  if (api.GetTakeEnvelopeByName) {
    for (const char* name : kTakeEnvNames) {
      process_env(api.GetTakeEnvelopeByName(take, name));
    }
  }

  const int n = api.CountTakeEnvelopes(take);
  for (int i = 0; i < n; ++i) {
    process_env(api.GetTakeEnvelope(take, i));
  }

}

void read_item(ItemState& st, void* /*proj*/, void* item, const lee::ApiTable& api) {
  st.item = item;
  st.take = api.GetActiveTake ? api.GetActiveTake(item) : nullptr;
  if (api.GetMediaItemInfo_Value) {
    st.item_vol_db = db_from_lin(api.GetMediaItemInfo_Value(item, "D_VOL"));
    st.fade_in_ms = api.GetMediaItemInfo_Value(item, "D_FADEINLEN") * 1000.0;
    st.fade_out_ms = api.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") * 1000.0;
    st.fade_in_shape = api.GetMediaItemInfo_Value(item, "C_FADEINSHAPE");
    st.fade_out_shape = api.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE");
    st.position = api.GetMediaItemInfo_Value(item, "D_POSITION");
    st.length = api.GetMediaItemInfo_Value(item, "D_LENGTH");
    st.snap_offset = api.GetMediaItemInfo_Value(item, "D_SNAPOFFSET");
  }
  if (st.take && api.GetMediaItemTakeInfo_Value) {
    st.take_vol_db = db_from_lin(api.GetMediaItemTakeInfo_Value(st.take, "D_VOL"));
    st.pitch = api.GetMediaItemTakeInfo_Value(st.take, "D_PITCH");
    st.rate = api.GetMediaItemTakeInfo_Value(st.take, "D_PLAYRATE");
    st.preserve = api.GetMediaItemTakeInfo_Value(st.take, "B_PPITCH");
    st.take_offset = api.GetMediaItemTakeInfo_Value(st.take, "D_STARTOFFS");
    st.pan100 = api.GetMediaItemTakeInfo_Value(st.take, "D_PAN") * 100.0;
    st.reverse = read_take_reverse(st.take, api) ? 1.0 : 0.0;
    st.channel = api.GetMediaItemTakeInfo_Value(st.take, "I_CHANMODE");
  }
  st.rand_seed = static_cast<uint32_t>(std::rand()) | 1u;
}

double rand_unit(uint32_t& seed) {
  seed = seed * 1664525u + 1013904223u;
  return static_cast<double>(seed & 0xFFFF) / 65535.0;
}

void init_relative_slots(SessionData& data, const ItemState& ref, bool multi) {
  data.relative[static_cast<int>(ParamId::ItemVol)] = ref.item_vol_db;
  data.relative[static_cast<int>(ParamId::TakeVol)] = ref.take_vol_db;
  data.relative[static_cast<int>(ParamId::Pitch)] = multi ? 0.0 : ref.pitch;
  data.relative[static_cast<int>(ParamId::Rate)] = ref.rate;
  data.relative[static_cast<int>(ParamId::PreservePitch)] = ref.preserve;
  data.relative[static_cast<int>(ParamId::FadeIn)] = multi ? 0.0 : ref.fade_in_ms;
  data.relative[static_cast<int>(ParamId::FadeOut)] = multi ? 0.0 : ref.fade_out_ms;
  data.relative[static_cast<int>(ParamId::FadeInShape)] = ref.fade_in_shape;
  data.relative[static_cast<int>(ParamId::FadeOutShape)] = ref.fade_out_shape;
  data.relative[static_cast<int>(ParamId::Pan)] = multi ? 0.0 : ref.pan100;
  data.relative[static_cast<int>(ParamId::Reverse)] = ref.reverse;
  data.relative[static_cast<int>(ParamId::ChannelMode)] = ref.channel;
  data.relative[static_cast<int>(ParamId::LeftEdge)] = 0.0;
  data.relative[static_cast<int>(ParamId::RightEdge)] = multi ? 0.0 : ref.length;
  data.relative[static_cast<int>(ParamId::TakeOffset)] = multi ? 0.0 : ref.take_offset;
  data.relative[static_cast<int>(ParamId::SnapOffset)] = multi ? 0.0 : ref.snap_offset;
  data.relative[static_cast<int>(ParamId::ItemGap)] = 0.0;
  data.relative[static_cast<int>(ParamId::BatchTrim)] = 1.0;
  data.relative[static_cast<int>(ParamId::VScale)] = 1.0;
  data.relative[static_cast<int>(ParamId::VOffset)] = 0.0;
  data.relative[static_cast<int>(ParamId::TScale)] = 1.0;
  data.relative[static_cast<int>(ParamId::Smooth)] = 0.0;
  data.relative[static_cast<int>(ParamId::PitchRand)] = 0.0;
  data.relative[static_cast<int>(ParamId::RateRand)] = 0.0;
  data.relative[static_cast<int>(ParamId::VolRand)] = 0.0;
}

void refresh_position_displays(SessionData& data, bool multi, const lee::ApiTable& api,
                               bool sync_right_edge = true) {
  if (multi || data.items.empty()) return;
  void* item = data.items.front().item;
  if (!item || !api.GetMediaItemInfo_Value) return;
  if (sync_right_edge) {
    data.relative[static_cast<int>(ParamId::RightEdge)] =
        api.GetMediaItemInfo_Value(item, "D_LENGTH");
  }
  data.relative[static_cast<int>(ParamId::SnapOffset)] =
      api.GetMediaItemInfo_Value(item, "D_SNAPOFFSET");
  void* take = data.items.front().take;
  if (take && api.GetMediaItemTakeInfo_Value) {
    data.relative[static_cast<int>(ParamId::TakeOffset)] =
        api.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS");
  }
}

void apply_playrate_resampled(const ItemState& baseline, void* item, void* take, double new_rate,
                              const lee::ApiTable& api) {
  new_rate = clampd(new_rate, 0.1, 4.0);
  const double old_rate = baseline.rate > 0.0 ? baseline.rate : 1.0;
  const double new_len = std::max(0.001, baseline.length * old_rate / new_rate);
  if (take && api.SetMediaItemTakeInfo_Value) {
    api.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", new_rate);
  }
  if (item && api.SetMediaItemInfo_Value) {
    api.SetMediaItemInfo_Value(item, "D_LENGTH", new_len);
  }
}

void apply_rate_with_geometry(SessionData& data, ItemState& st, void* item, void* take,
                              double new_rate, bool multi, const lee::ApiTable& api) {
  apply_playrate_resampled(st, item, take, new_rate, api);
  if (!multi) {
    data.relative[static_cast<int>(ParamId::RightEdge)] = item_timeline_length(st, new_rate);
  }
  apply_left_edge_item(data, st, item, take, data.relative[static_cast<int>(ParamId::LeftEdge)],
                       multi, api);
}

void write_envelope_lane_point(const lee::ApiTable& api, const EnvCache& cache, int ptidx,
                               const EnvPoint& pt) {
  double time = pt.time;
  double value = pt.value;
  double tension = pt.tension;
  int shape = pt.shape;
  bool selected = pt.selected;
  if (cache.autoitem_idx >= 0 && api.SetEnvelopePointEx) {
    api.SetEnvelopePointEx(cache.envelope, cache.autoitem_idx, ptidx, &time, &value, &shape,
                           &tension, &selected, nullptr);
  } else if (api.SetEnvelopePoint) {
    api.SetEnvelopePoint(cache.envelope, ptidx, &time, &value, &shape, &tension, &selected,
                         nullptr);
  }
}

void apply_envelope_transform(SessionData& data, const lee::ApiTable& api) {
  if (!api.SetEnvelopePoint && !api.SetEnvelopePointEx) return;
  for (const EnvCache& cache : data.envs) {
    if (!cache.envelope || cache.baseline.empty()) continue;
    std::vector<EnvPoint> pts = cache.baseline;
    if (data.envelope_tscale != 1.0) {
      for (auto& pt : pts) pt.time *= data.envelope_tscale;
    }
    double vmin = pts.front().value, vmax = pts.front().value;
    for (const auto& pt : pts) {
      vmin = std::min(vmin, pt.value);
      vmax = std::max(vmax, pt.value);
    }
    const double center = (vmin + vmax) * 0.5;
    const double range = std::max(1e-9, vmax - vmin);
    for (auto& pt : pts) {
      double v = center + (pt.value - center) * data.envelope_vscale;
      v += data.envelope_voffset * range;
      pt.value = v;
    }
    const int passes = static_cast<int>(data.envelope_smooth / 20.0);
    for (int pass = 0; pass < passes && pts.size() > 2; ++pass) {
      std::vector<EnvPoint> sm = pts;
      for (size_t i = 1; i + 1 < pts.size(); ++i) {
        sm[i].value = (pts[i - 1].value + pts[i].value + pts[i + 1].value) / 3.0;
      }
      pts.swap(sm);
    }
    const int n = std::min(count_envelope_lane_points(api, cache.envelope, cache.autoitem_idx),
                           static_cast<int>(pts.size()));
    for (int p = 0; p < n; ++p) {
      write_envelope_lane_point(api, cache, p, pts[static_cast<size_t>(p)]);
    }
  }
}

void apply_to_items(SessionData& data, bool multi, ParamId id, const lee::ApiTable& api) {
  const ParamDef& def = Def(id);
  const double slot = data.relative[static_cast<int>(id)];

  for (ItemState& st : data.items) {
    if (!st.item) continue;
    void* item = st.item;
    void* take = st.take;

    auto set_item = [&](const char* key, double v) {
      if (api.SetMediaItemInfo_Value) api.SetMediaItemInfo_Value(item, key, v);
    };
    auto set_take = [&](const char* key, double v) {
      if (take && api.SetMediaItemTakeInfo_Value) api.SetMediaItemTakeInfo_Value(take, key, v);
    };

    const auto rel = [&](double baseline) { return multi && !def.absolute_in_multi ? baseline + slot : slot; };

    switch (id) {
      case ParamId::ItemVol:
        set_item("D_VOL", lin_from_db(rel(st.item_vol_db)));
        break;
      case ParamId::TakeVol:
        set_take("D_VOL", lin_from_db(rel(st.take_vol_db)));
        break;
      case ParamId::Pitch:
        set_take("D_PITCH", rel(st.pitch));
        break;
      case ParamId::Rate: {
        const double new_rate = clampd(slot, def.min_v, def.max_v);
        apply_rate_with_geometry(data, st, item, take, new_rate, multi, api);
        break;
      }
      case ParamId::PreservePitch:
        set_take("B_PPITCH", slot > 0.5 ? 1.0 : 0.0);
        break;
      case ParamId::FadeIn:
        set_item("D_FADEINLEN", rel(st.fade_in_ms) / 1000.0);
        break;
      case ParamId::FadeOut:
        set_item("D_FADEOUTLEN", rel(st.fade_out_ms) / 1000.0);
        break;
      case ParamId::FadeInShape:
        set_item("C_FADEINSHAPE", std::round(slot));
        break;
      case ParamId::FadeOutShape:
        set_item("C_FADEOUTSHAPE", std::round(slot));
        break;
      case ParamId::Pan:
        set_take("D_PAN", clampd(rel(st.pan100), -100.0, 100.0) / 100.0);
        break;
      case ParamId::Reverse: {
        PendingReverseApply pending;
        pending.item = item;
        pending.take = take;
        pending.want = slot > 0.5;
        data.pending_reverse.push_back(pending);
        break;
      }
      case ParamId::ChannelMode:
        set_take("I_CHANMODE", std::round(slot));
        break;
      case ParamId::LeftEdge:
        apply_left_edge_item(data, st, item, take, slot, multi, api);
        break;
      case ParamId::RightEdge:
        set_item("D_LENGTH", clampd(rel(st.length), def.min_v, def.max_v));
        break;
      case ParamId::TakeOffset:
        set_take("D_STARTOFFS", rel(st.take_offset));
        break;
      case ParamId::SnapOffset:
        set_item("D_SNAPOFFSET", clampd(rel(st.snap_offset), 0.0, st.length));
        break;
      case ParamId::PitchRand:
        set_take("D_PITCH", st.pitch + st.pitch_rand);
        break;
      case ParamId::RateRand: {
        const double new_rate = clampd(st.rate + st.rate_rand, 0.1, 4.0);
        apply_rate_with_geometry(data, st, item, take, new_rate, multi, api);
        break;
      }
      case ParamId::VolRand:
        set_take("D_VOL", lin_from_db(st.take_vol_db + st.vol_rand));
        break;
      default:
        break;
    }
  }
  if (id == ParamId::LeftEdge) refresh_position_displays(data, multi, api, false);
  if (id == ParamId::Rate || id == ParamId::RateRand) refresh_position_displays(data, multi, api, true);
  if (CategoryOf(id) == Category::Envelope) apply_envelope_transform(data, api);
  if (api.UpdateArrange) api.UpdateArrange();
}

double wheel_value_step(ParamId id) {
  switch (id) {
    case ParamId::ItemVol:
    case ParamId::TakeVol:
      return 1.0;
    case ParamId::Rate:
      return 0.1;
    case ParamId::LeftEdge:
    case ParamId::RightEdge:
      return 0.01;
    default:
      return 0.0;
  }
}

}  // namespace

Session& GetSession() {
  return g_session;
}

bool Session::begin(void* proj) {
  if (active_) end();
  const auto& api = lee::Api();
  if (!api.CountSelectedMediaItems || !api.GetSelectedMediaItem) return false;

  data_ = new SessionData();
  proj_ = proj;
  data_->proj = proj;
  capture_selection(proj);
  multi_ = data_->items.size() >= 2;
  if (data_->items.empty()) {
    delete data_;
    data_ = nullptr;
    return false;
  }

  init_relative_slots(*data_, data_->items.front(), multi_);

  undo_open_ = false;
  active_ = true;
  category_ = Category::GainPitch;
  return true;
}

void Session::capture_selection(void* proj) {
  const auto& api = lee::Api();
  data_->items.clear();
  data_->envs.clear();
  data_->envelopes_captured = false;
  const int n = api.CountSelectedMediaItems(proj);
  for (int i = 0; i < n; ++i) {
    void* item = api.GetSelectedMediaItem(proj, i);
    if (!item) continue;
    if (api.ValidatePtr2 && !api.ValidatePtr2(proj, item, "MediaItem*")) continue;
    ItemState st;
    read_item(st, proj, item, api);
    data_->items.push_back(st);
  }
}

void Session::ensure_envelopes_captured() {
  if (!data_) return;
  if (data_->envelopes_captured && !data_->envs.empty()) return;
  const auto& api = lee::Api();
  data_->envs.clear();
  for (const ItemState& st : data_->items) {
    if (st.take) capture_envelopes(api, st.take, data_->envs);
  }
  data_->envelopes_captured = true;
}

void Session::ensure_undo() {
  if (undo_open_ || !active_ || !proj_) return;
  const auto& api = lee::Api();
  if (api.Undo_BeginBlock2) api.Undo_BeginBlock2(proj_);
  undo_open_ = true;
}

void Session::end() {
  if (!active_) return;
  const auto& api = lee::Api();
  if (undo_open_ && api.Undo_EndBlock2) {
    api.Undo_EndBlock2(proj_, "Lee: Item Hub adjust parameters", -1);
  }
  undo_open_ = false;
  active_ = false;
  delete data_;
  data_ = nullptr;
  proj_ = nullptr;
}

void Session::set_category(Category c) {
  if (c >= Category::Count) return;
  category_ = c;
  if (c == Category::Envelope) ensure_envelopes_captured();
}

void Session::next_category(int delta) {
  int c = static_cast<int>(category_) + delta;
  while (c < 0) c += static_cast<int>(Category::Count);
  c %= static_cast<int>(Category::Count);
  category_ = static_cast<Category>(c);
  if (category_ == Category::Envelope) ensure_envelopes_captured();
}

bool Session::param_enabled(ParamId id) const {
  if (!active_ || !data_) return false;
  if (Def(id).multi_only && !multi_) return false;
  if (id == ParamId::Reverse) {
    const lee::ApiTable& api = lee::Api();
    if (!reverse_apis_available(api)) return false;
    for (const ItemState& st : data_->items) {
      if (take_supports_reverse(st.take, api)) return true;
    }
    return false;
  }
  return true;
}

void Session::format_value(ParamId id, char* buf, size_t buf_size) const {
  if (!buf || buf_size == 0 || !active_ || !data_) return;
  const ParamDef& def = Def(id);
  const double v = data_->relative[static_cast<int>(id)];

  if (def.kind == ParamKind::Toggle) {
    std::snprintf(buf, buf_size, "%s", v > 0.5 ? "ON" : "OFF");
    return;
  }
  if (def.kind == ParamKind::Discrete) {
    const int idx = static_cast<int>(std::round(clampd(v, def.min_v, def.max_v)));
    if (id == ParamId::FadeInShape || id == ParamId::FadeOutShape) {
      std::snprintf(buf, buf_size, "%s", kFadeShapeLabels[std::max(0, std::min(6, idx))]);
    } else if (id == ParamId::ChannelMode) {
      std::snprintf(buf, buf_size, "%s", kChannelModeLabels[std::max(0, std::min(4, idx))]);
    } else {
      std::snprintf(buf, buf_size, "%d", idx);
    }
    return;
  }
  if (multi_ && !def.absolute_in_multi) {
    if (id == ParamId::Pitch) std::snprintf(buf, buf_size, "%+.1f st", v);
    else if (id == ParamId::Pan) std::snprintf(buf, buf_size, "%+.0f", v);
    else if (id == ParamId::FadeIn || id == ParamId::FadeOut)
      std::snprintf(buf, buf_size, "%+.0f ms", v);
    else if (id == ParamId::LeftEdge || id == ParamId::RightEdge || id == ParamId::ItemGap)
      std::snprintf(buf, buf_size, "%+.3f s", v);
    else if (id == ParamId::TakeOffset || id == ParamId::SnapOffset)
      std::snprintf(buf, buf_size, "%+.3f s", v);
    else if (id == ParamId::Rate || id == ParamId::RateRand) std::snprintf(buf, buf_size, "%.4fx", v);
    else std::snprintf(buf, buf_size, "%+.2f dB", v);
    return;
  }
  if (id == ParamId::Pan) {
    if (std::abs(v) < 0.5) std::snprintf(buf, buf_size, "C");
    else std::snprintf(buf, buf_size, "%s%.0f", v < 0 ? "L" : "R", std::abs(v));
    return;
  }
  if (id == ParamId::Rate || id == ParamId::VScale || id == ParamId::TScale) {
    std::snprintf(buf, buf_size, "%.4fx", v);
    return;
  }
  if (id == ParamId::RateRand) {
    std::snprintf(buf, buf_size, "%.2f x", v);
    return;
  }
  if (id == ParamId::FadeIn || id == ParamId::FadeOut) {
    std::snprintf(buf, buf_size, "%.0f ms", v);
    return;
  }
  if (id == ParamId::LeftEdge || id == ParamId::RightEdge || id == ParamId::BatchTrim) {
    std::snprintf(buf, buf_size, "%.3f s", v);
    return;
  }
  if (id == ParamId::TakeOffset || id == ParamId::SnapOffset || id == ParamId::ItemGap) {
    std::snprintf(buf, buf_size, "%.3f s", v);
    return;
  }
  if (id == ParamId::Smooth) {
    std::snprintf(buf, buf_size, "%.0f %%", v);
    return;
  }
  if (id == ParamId::Pitch || id == ParamId::PitchRand) {
    std::snprintf(buf, buf_size, "%.1f st", v);
    return;
  }
  std::snprintf(buf, buf_size, "%.2f dB", v);
}

double Session::normalized_value(ParamId id) const {
  if (!active_ || !data_) return 0.0;
  const ParamDef& def = Def(id);
  const double v = data_->relative[static_cast<int>(id)];
  double min_v = def.min_v;
  double max_v = def.max_v;
  param_limits(*data_, multi_, id, min_v, max_v);
  return (v - min_v) / std::max(1e-9, max_v - min_v);
}

void Session::adjust_param(ParamId id, double delta, bool fine) {
  if (!active_ || !data_ || !param_enabled(id)) return;
  ensure_undo();
  if (CategoryOf(id) == Category::Envelope) ensure_envelopes_captured();
  const ParamDef& def = Def(id);
  const double scale = fine ? kFineScale : 1.0;
  double& slot = data_->relative[static_cast<int>(id)];

  if (def.kind == ParamKind::Discrete) {
    slot = clampd(std::round(slot) + (delta > 0 ? 1.0 : -1.0), def.min_v, def.max_v);
  } else if (def.kind == ParamKind::Toggle) {
    slot = slot > 0.5 ? 0.0 : 1.0;
  } else {
    double min_v = def.min_v;
    double max_v = def.max_v;
    param_limits(*data_, multi_, id, min_v, max_v);
    slot = clampd(slot + delta * (max_v - min_v) * 0.0025 * scale, min_v, max_v);
  }

  if (CategoryOf(id) == Category::Envelope) {
    switch (id) {
      case ParamId::VScale: data_->envelope_vscale = slot; break;
      case ParamId::VOffset: data_->envelope_voffset = slot; break;
      case ParamId::TScale: data_->envelope_tscale = slot; break;
      case ParamId::Smooth: data_->envelope_smooth = slot; break;
      default: break;
    }
  }
  if (CategoryOf(id) == Category::Randomize) apply_randomize(id);
  else if (id == ParamId::ItemGap) {
    data_->item_gap = slot;
    apply_item_gap();
  } else if (id == ParamId::BatchTrim) {
    data_->batch_trim = slot;
    apply_batch_trim(slot);
  } else {
    apply_to_items(*data_, multi_, id, lee::Api());
  }
}

void Session::wheel_param(ParamId id, double notches, bool fine) {
  if (!active_ || !data_ || !param_enabled(id) || notches == 0.0) return;
  const ParamDef& def = Def(id);
  if (def.kind == ParamKind::Toggle) {
    click_param(id);
    return;
  }
  if (CategoryOf(id) == Category::Envelope) ensure_envelopes_captured();

  const double step = wheel_value_step(id);
  if (step > 0.0) {
    ensure_undo();
    const double scale = fine ? kFineScale : 1.0;
    double min_v = def.min_v;
    double max_v = def.max_v;
    param_limits(*data_, multi_, id, min_v, max_v);
    double& slot = data_->relative[static_cast<int>(id)];
    slot = clampd(slot + notches * step * scale, min_v, max_v);
    if (CategoryOf(id) == Category::Envelope) {
      switch (id) {
        case ParamId::VScale: data_->envelope_vscale = slot; break;
        case ParamId::VOffset: data_->envelope_voffset = slot; break;
        case ParamId::TScale: data_->envelope_tscale = slot; break;
        case ParamId::Smooth: data_->envelope_smooth = slot; break;
        default: break;
      }
    }
    apply_to_items(*data_, multi_, id, lee::Api());
    return;
  }

  // One wheel notch ≈ 10 px of horizontal drag.
  adjust_param(id, notches * 10.0, fine);
}

void Session::reset_param(ParamId id) {
  if (!active_ || !data_) return;
  ensure_undo();
  const ParamDef& def = Def(id);
  data_->relative[static_cast<int>(id)] = multi_ && !def.absolute_in_multi ? 0.0 : def.default_v;
  if (CategoryOf(id) == Category::Envelope) {
    ensure_envelopes_captured();
    data_->envelope_vscale = 1.0;
    data_->envelope_voffset = 0.0;
    data_->envelope_tscale = 1.0;
    data_->envelope_smooth = 0.0;
    apply_envelope_transform(*data_, lee::Api());
  } else if (CategoryOf(id) == Category::Randomize) {
    apply_randomize(id);
  } else if (id == ParamId::ItemGap) {
    apply_item_gap();
  } else if (id == ParamId::BatchTrim) {
    apply_batch_trim(data_->batch_trim);
  } else {
    apply_to_items(*data_, multi_, id, lee::Api());
  }
}

void Session::click_param(ParamId id) {
  if (!active_ || !data_ || Def(id).kind != ParamKind::Toggle) return;
  adjust_param(id, 0.0, false);
}

void Session::on_param_drag_start(ParamId id) {
  if (!active_ || !data_ || CategoryOf(id) != Category::Randomize) return;
  ++data_->randomize_gen;
  for (ItemState& st : data_->items) {
    st.rand_seed = static_cast<uint32_t>(std::rand()) ^ static_cast<uint32_t>(data_->randomize_gen);
    if (st.rand_seed == 0) st.rand_seed = 1;
  }
  apply_randomize(id);
}

void Session::apply_randomize(ParamId id) {
  if (!data_) return;
  const double coeff = data_->relative[static_cast<int>(id)];
  for (ItemState& st : data_->items) {
    uint32_t seed = st.rand_seed;
    const double r = rand_unit(seed) * 2.0 - 1.0;
    switch (id) {
      case ParamId::PitchRand: st.pitch_rand = r * coeff; break;
      case ParamId::RateRand: st.rate_rand = r * coeff; break;
      case ParamId::VolRand: st.vol_rand = r * coeff; break;
      default: break;
    }
  }
  apply_to_items(*data_, multi_, id, lee::Api());
}

void Session::apply_item_gap() {
  if (!data_ || !multi_) return;
  const auto& api = lee::Api();
  std::sort(data_->items.begin(), data_->items.end(),
            [](const ItemState& a, const ItemState& b) { return a.position < b.position; });
  double cursor = data_->items.front().position;
  for (ItemState& st : data_->items) {
    if (api.SetMediaItemInfo_Value) api.SetMediaItemInfo_Value(st.item, "D_POSITION", cursor);
    cursor += st.length + data_->item_gap;
  }
  if (api.UpdateArrange) api.UpdateArrange();
}

void Session::apply_batch_trim(double target_len) {
  if (!data_ || !multi_) return;
  const auto& api = lee::Api();
  for (ItemState& st : data_->items) {
    if (api.SetMediaItemInfo_Value) {
      api.SetMediaItemInfo_Value(st.item, "D_LENGTH", clampd(target_len, 0.001, 3600.0));
    }
  }
  if (api.UpdateArrange) api.UpdateArrange();
}

void Session::flush_deferred_reverse_applies() {
  if (!active_ || !data_ || data_->pending_reverse.empty()) return;
  const auto& api = lee::Api();
  for (const PendingReverseApply& pending : data_->pending_reverse) {
    set_take_reverse(data_->proj, pending.take, pending.item, pending.want, api);
  }
  restore_hub_selection(*data_, api);
  data_->pending_reverse.clear();
  if (api.UpdateArrange) api.UpdateArrange();
}

void Session::tick(bool /*window_focused*/) {}

}  // namespace lee::item_hub
