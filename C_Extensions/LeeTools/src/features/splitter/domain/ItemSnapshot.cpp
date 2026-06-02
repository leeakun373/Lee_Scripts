#include "features/splitter/domain/ItemSnapshot.h"

#include "plugin/PluginContext.h"

namespace lee::splitter {

bool CaptureItemSnapshot(void* item, ItemSnapshot& out) {
  out = ItemSnapshot{};
  const auto& api = lee::Api();
  if (!item || !api.GetActiveTake || !api.GetMediaItemTake_Source) return false;

  void* take = api.GetActiveTake(item);
  if (!take) return false;
  if (api.TakeIsMIDI && api.TakeIsMIDI(take)) return false;

  void* source = api.GetMediaItemTake_Source(take);
  if (!source) return false;

  out.item = item;
  out.take = take;
  out.source = source;
  out.track = api.GetMediaItemTrack ? api.GetMediaItemTrack(item) : nullptr;

  if (out.track && api.GetMediaTrackInfo_Value) {
    const double tn = api.GetMediaTrackInfo_Value(out.track, "IP_TRACKNUMBER");
    out.source_track_index = (tn > 0.0) ? static_cast<int>(tn) - 1 : 0;
  }
  if (out.track && api.GetSetMediaTrackInfo_String) {
    char buf[512] = {0};
    if (api.GetSetMediaTrackInfo_String(out.track, "P_NAME", buf, false) && buf[0]) {
      out.source_track_name = buf;
    }
  }
  if (out.source_track_name.empty()) {
    out.source_track_name = "Track " + std::to_string(out.source_track_index + 1);
  }

  if (api.GetMediaItemInfo_Value) {
    out.position = api.GetMediaItemInfo_Value(item, "D_POSITION");
    out.length = api.GetMediaItemInfo_Value(item, "D_LENGTH");
    out.item_vol = api.GetMediaItemInfo_Value(item, "D_VOL");
    out.fadein_len = api.GetMediaItemInfo_Value(item, "D_FADEINLEN");
    out.fadeout_len = api.GetMediaItemInfo_Value(item, "D_FADEOUTLEN");
    out.fadein_len_auto = api.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO");
    out.fadeout_len_auto = api.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO");
    out.fadein_shape = static_cast<int>(api.GetMediaItemInfo_Value(item, "C_FADEINSHAPE"));
    out.fadeout_shape = static_cast<int>(api.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE"));
    out.fadein_dir = api.GetMediaItemInfo_Value(item, "D_FADEINDIR");
    out.fadeout_dir = api.GetMediaItemInfo_Value(item, "D_FADEOUTDIR");
  }

  if (api.GetMediaItemTakeInfo_Value) {
    out.take_offset = api.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS");
    out.playrate = api.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE");
    out.take_vol = api.GetMediaItemTakeInfo_Value(take, "D_VOL");
    out.take_pan = api.GetMediaItemTakeInfo_Value(take, "D_PAN");
    out.chanmode = static_cast<int>(api.GetMediaItemTakeInfo_Value(take, "I_CHANMODE"));
  }
  if (out.playrate <= 0.0) out.playrate = 1.0;

  if (api.GetMediaSourceSampleRate) out.source_sr = api.GetMediaSourceSampleRate(source);
  if (api.GetMediaSourceNumChannels) out.source_channels = api.GetMediaSourceNumChannels(source);
  if (out.source_sr <= 0) out.source_sr = 48000;
  if (out.source_channels <= 0) out.source_channels = 1;

  out.valid = true;
  return true;
}

}  // namespace lee::splitter
