#include "features/splitter/domain/TrackWriter.h"

#include <vector>

#include "features/splitter/domain/WavWriter.h"
#include "plugin/PluginContext.h"

namespace lee::splitter {
namespace {

void build_source_peaks(void* src) {
  const auto& api = lee::Api();
  if (!src || !api.PCM_Source_BuildPeaks) return;
  if (!api.PCM_Source_BuildPeaks(src, 0)) return;
  while (api.PCM_Source_BuildPeaks(src, 1) > 0) {
  }
  api.PCM_Source_BuildPeaks(src, 2);
}

}  // namespace

void* TrackWriter::ensure_track(const ItemSnapshot& snap, const char* suffix) {
  const auto& api = lee::Api();
  const std::string suf = suffix ? suffix : "Layer";

  int offset = 0;
  for (const auto& r : records_) {
    if (r.src_track == snap.track) {
      if (r.suffix == suf) return r.out_track;
      ++offset;
    }
  }

  if (!api.GetMediaTrackInfo_Value || !api.InsertTrackAtIndex || !api.GetTrack) {
    return nullptr;
  }

  const int live_ip = static_cast<int>(api.GetMediaTrackInfo_Value(snap.track, "IP_TRACKNUMBER"));
  const int insert_idx = (live_ip > 0 ? live_ip : 1) + offset;
  api.InsertTrackAtIndex(insert_idx, true);

  void* out_track = api.GetTrack(proj_, insert_idx);
  if (out_track && api.GetSetMediaTrackInfo_String) {
    std::string name = snap.source_track_name + "_" + suf;
    std::vector<char> buf(name.begin(), name.end());
    buf.push_back('\0');
    api.GetSetMediaTrackInfo_String(out_track, "P_NAME", buf.data(), true);
  }

  records_.push_back({snap.track, suf, out_track});
  return out_track;
}

bool TrackWriter::Write(const ItemSnapshot& snap, const AudioBuffer& layer, const char* suffix) {
  const auto& api = lee::Api();
  if (!api.PCM_Source_CreateFromFile || !api.AddMediaItemToTrack || !api.AddTakeToMediaItem ||
      !api.SetMediaItemTake_Source || !api.SetMediaItemInfo_Value ||
      !api.SetMediaItemTakeInfo_Value) {
    return false;
  }

  const std::string path = MakeTempWavPath(suffix);
  if (!WriteWav24(path, layer)) return false;

  void* track = ensure_track(snap, suffix);
  if (!track) return false;

  void* src = api.PCM_Source_CreateFromFile(path.c_str());
  if (!src) return false;

  void* item = api.AddMediaItemToTrack(track);
  if (!item) return false;
  void* take = api.AddTakeToMediaItem(item);
  if (!take) return false;

  api.SetMediaItemTake_Source(take, src);

  double src_seconds = 0.0;
  if (layer.sample_rate > 0 && layer.frames > 0) {
    src_seconds = static_cast<double>(layer.frames) / static_cast<double>(layer.sample_rate);
  }
  if (api.GetMediaSourceLength) {
    bool length_is_qn = false;
    const double media_len = api.GetMediaSourceLength(src, &length_is_qn);
    if (media_len > 0.0 && !length_is_qn) src_seconds = media_len;
  }

  double playrate = snap.playrate;
  if (playrate <= 0.0) playrate = 1.0;

  double item_length = snap.length;
  if (src_seconds > 0.0) {
    item_length = src_seconds / playrate;
  }
  if (item_length <= 0.0) item_length = 0.001;

  api.SetMediaItemInfo_Value(item, "D_POSITION", snap.position);
  api.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0.0);
  api.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", playrate);
  api.SetMediaItemInfo_Value(item, "D_LENGTH", item_length);
  api.SetMediaItemInfo_Value(item, "D_VOL", snap.item_vol);
  api.SetMediaItemInfo_Value(item, "D_FADEINLEN", snap.fadein_len);
  api.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", snap.fadeout_len);
  api.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", snap.fadein_len_auto);
  api.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", snap.fadeout_len_auto);
  api.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", static_cast<double>(snap.fadein_shape));
  api.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", static_cast<double>(snap.fadeout_shape));
  api.SetMediaItemInfo_Value(item, "D_FADEINDIR", snap.fadein_dir);
  api.SetMediaItemInfo_Value(item, "D_FADEOUTDIR", snap.fadeout_dir);
  api.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0.0);

  api.SetMediaItemTakeInfo_Value(take, "D_VOL", snap.take_vol);
  api.SetMediaItemTakeInfo_Value(take, "D_PAN", snap.take_pan);
  api.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", static_cast<double>(snap.chanmode));

  build_source_peaks(src);

  if (api.UpdateItemInProject) api.UpdateItemInProject(item);
  return true;
}

}  // namespace lee::splitter
