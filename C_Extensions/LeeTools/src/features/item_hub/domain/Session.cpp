#include "features/item_hub/domain/Session.h"

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
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
  int tension = 0;
  bool selected = false;
};

struct EnvCache {
  void* envelope = nullptr;
  std::vector<EnvPoint> baseline;
};

struct SessionData {
  std::vector<ItemState> items;
  std::vector<EnvCache> envs;
  double relative[static_cast<int>(ParamId::Count)] = {};
  double envelope_vscale = 1.0;
  double envelope_voffset = 0.0;
  double envelope_tscale = 1.0;
  double envelope_smooth = 0.0;
  double item_gap = 0.0;
  double batch_trim = 1.0;
  int randomize_gen = 0;
};

namespace {

constexpr double kFineScale = 0.15;

double db_from_lin(double v) {
  return v > 0.0 ? 20.0 * std::log10(v) : -150.0;
}

double lin_from_db(double db) {
  return std::pow(10.0, db / 20.0);
}

double clampd(double v, double lo, double hi) {
  return std::max(lo, std::min(hi, v));
}

Session g_session;

bool envelope_visible(const lee::ApiTable& api, void* env) {
  if (!env || !api.GetEnvelopeInfo_Value) return true;
  return api.GetEnvelopeInfo_Value(env, "B_SHOW") > 0.5;
}

void capture_envelopes(const lee::ApiTable& api, void* take, std::vector<EnvCache>& out) {
  if (!take || !api.CountTakeEnvelopes || !api.GetTakeEnvelope || !api.CountEnvelopePoints ||
      !api.GetEnvelopePoint) {
    return;
  }
  const int n = api.CountTakeEnvelopes(take);
  for (int i = 0; i < n; ++i) {
    void* env = api.GetTakeEnvelope(take, i);
    if (!env || !envelope_visible(api, env)) continue;
    EnvCache cache;
    cache.envelope = env;
    const int pc = api.CountEnvelopePoints(env);
    for (int p = 0; p < pc; ++p) {
      EnvPoint pt;
      api.GetEnvelopePoint(env, p, &pt.time, &pt.value, &pt.shape, &pt.tension, &pt.selected);
      cache.baseline.push_back(pt);
    }
    if (!cache.baseline.empty()) out.push_back(std::move(cache));
  }
}

void read_item(ItemState& st, void* /*proj*/, void* item, const lee::ApiTable& api) {
  st.item = item;
  st.take = api.GetActiveTake ? api.GetActiveTake(item) : nullptr;
  if (api.GetMediaItemInfo_Value) {
    st.item_vol_db = db_from_lin(api.GetMediaItemInfo_Value(item, "D_VOL"));
    st.fade_in_ms = api.GetMediaItemInfo_Value(item, "D_FADEINLEN") * 1000.0;
    st.fade_out_ms = api.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") * 1000.0;
    st.fade_in_shape = api.GetMediaItemInfo_Value(item, "I_FADEINSHAPE");
    st.fade_out_shape = api.GetMediaItemInfo_Value(item, "I_FADEOUTSHAPE");
    st.pan100 = api.GetMediaItemInfo_Value(item, "D_PAN") * 100.0;
    st.reverse = api.GetMediaItemInfo_Value(item, "B_REVERSE");
    st.channel = api.GetMediaItemInfo_Value(item, "I_CHANMODE");
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

void refresh_position_displays(SessionData& data, bool multi, const lee::ApiTable& api) {
  if (multi || data.items.empty()) return;
  void* item = data.items.front().item;
  if (!item || !api.GetMediaItemInfo_Value) return;
  data.relative[static_cast<int>(ParamId::RightEdge)] =
      api.GetMediaItemInfo_Value(item, "D_LENGTH");
  void* take = data.items.front().take;
  if (take && api.GetMediaItemTakeInfo_Value) {
    data.relative[static_cast<int>(ParamId::TakeOffset)] =
        api.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS");
  }
}

void apply_envelope_transform(SessionData& data, const lee::ApiTable& api) {
  if (!api.SetEnvelopePoint) return;
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
    const int n = std::min(api.CountEnvelopePoints(cache.envelope), static_cast<int>(pts.size()));
    for (int p = 0; p < n; ++p) {
      const EnvPoint& pt = pts[static_cast<size_t>(p)];
      api.SetEnvelopePoint(cache.envelope, p, pt.time, pt.value, pt.shape, pt.tension, pt.selected);
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
      case ParamId::Rate:
        set_take("D_PLAYRATE", clampd(slot, def.min_v, def.max_v));
        break;
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
        set_item("I_FADEINSHAPE", std::round(slot));
        break;
      case ParamId::FadeOutShape:
        set_item("I_FADEOUTSHAPE", std::round(slot));
        break;
      case ParamId::Pan:
        set_item("D_PAN", clampd(rel(st.pan100), -100.0, 100.0) / 100.0);
        break;
      case ParamId::Reverse:
        set_item("B_REVERSE", slot > 0.5 ? 1.0 : 0.0);
        break;
      case ParamId::ChannelMode:
        set_item("I_CHANMODE", std::round(slot));
        break;
      case ParamId::LeftEdge: {
        const double trim = slot / 1000.0;
        set_take("D_STARTOFFS", st.take_offset + trim);
        set_item("D_LENGTH", std::max(0.001, st.length - trim));
        set_item("D_POSITION", st.position + trim);
        break;
      }
      case ParamId::RightEdge:
        set_item("D_LENGTH", clampd(rel(st.length), def.min_v, def.max_v));
        break;
      case ParamId::TakeOffset:
        set_take("D_STARTOFFS", rel(st.take_offset));
        break;
      case ParamId::SnapOffset:
        set_item("D_SNAPOFFSET", rel(st.snap_offset));
        break;
      case ParamId::PitchRand:
        set_take("D_PITCH", st.pitch + st.pitch_rand);
        break;
      case ParamId::RateRand:
        set_take("D_PLAYRATE", clampd(st.rate + st.rate_rand, 0.1, 4.0));
        break;
      case ParamId::VolRand:
        set_take("D_VOL", lin_from_db(st.take_vol_db + st.vol_rand));
        break;
      default:
        break;
    }
  }
  if (id == ParamId::LeftEdge) refresh_position_displays(data, multi, api);
  if (CategoryOf(id) == Category::Envelope) apply_envelope_transform(data, api);
  if (api.UpdateArrange) api.UpdateArrange();
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
  capture_selection(proj);
  multi_ = data_->items.size() >= 2;
  if (data_->items.empty()) {
    delete data_;
    data_ = nullptr;
    return false;
  }

  init_relative_slots(*data_, data_->items.front(), multi_);

  if (api.Undo_BeginBlock2) api.Undo_BeginBlock2(proj);
  undo_open_ = true;
  active_ = true;
  category_ = Category::GainPitch;
  return true;
}

void Session::capture_selection(void* proj) {
  const auto& api = lee::Api();
  data_->items.clear();
  data_->envs.clear();
  const int n = api.CountSelectedMediaItems(proj);
  for (int i = 0; i < n; ++i) {
    void* item = api.GetSelectedMediaItem(proj, i);
    if (!item) continue;
    if (api.ValidatePtr2 && !api.ValidatePtr2(proj, item, "MediaItem*")) continue;
    ItemState st;
    read_item(st, proj, item, api);
    data_->items.push_back(st);
    if (st.take) capture_envelopes(api, st.take, data_->envs);
  }
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
}

void Session::next_category(int delta) {
  int c = static_cast<int>(category_) + delta;
  while (c < 0) c += static_cast<int>(Category::Count);
  c %= static_cast<int>(Category::Count);
  category_ = static_cast<Category>(c);
}

bool Session::param_enabled(ParamId id) const {
  if (!active_ || !data_) return false;
  if (Def(id).multi_only && !multi_) return false;
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
    else if (id == ParamId::FadeIn || id == ParamId::FadeOut || id == ParamId::LeftEdge)
      std::snprintf(buf, buf_size, "%+.0f ms", v);
    else if (id == ParamId::Rate) std::snprintf(buf, buf_size, "%.4fx", v);
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
  if (id == ParamId::FadeIn || id == ParamId::FadeOut || id == ParamId::LeftEdge) {
    std::snprintf(buf, buf_size, "%.0f ms", v);
    return;
  }
  if (id == ParamId::RightEdge || id == ParamId::BatchTrim) {
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
  return (v - def.min_v) / std::max(1e-9, def.max_v - def.min_v);
}

void Session::adjust_param(ParamId id, double delta, bool fine) {
  if (!active_ || !data_ || !param_enabled(id)) return;
  const ParamDef& def = Def(id);
  const double scale = fine ? kFineScale : 1.0;
  double& slot = data_->relative[static_cast<int>(id)];

  if (def.kind == ParamKind::Discrete) {
    slot = clampd(slot + (delta > 0 ? 1.0 : -1.0), def.min_v, def.max_v);
  } else if (def.kind == ParamKind::Toggle) {
    slot = slot > 0.5 ? 0.0 : 1.0;
  } else {
    slot = clampd(slot + delta * (def.max_v - def.min_v) * 0.0025 * scale, def.min_v, def.max_v);
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

void Session::reset_param(ParamId id) {
  if (!active_ || !data_) return;
  const ParamDef& def = Def(id);
  data_->relative[static_cast<int>(id)] = multi_ && !def.absolute_in_multi ? 0.0 : def.default_v;
  if (CategoryOf(id) == Category::Envelope) {
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

void Session::tick(bool /*window_focused*/) {}

}  // namespace lee::item_hub
