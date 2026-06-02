#include "features/splitter/domain/AudioReader.h"

#include <algorithm>
#include <cmath>
#include <vector>

#include "plugin/PluginContext.h"

namespace lee::splitter {

namespace {
float peak_abs(const AudioBuffer& buf) {
  float p = 0.0f;
  for (float s : buf.samples) {
    p = std::max(p, std::fabs(s));
  }
  return p;
}
}  // namespace

bool ReadItemAudio(const ItemSnapshot& snap, AudioBuffer& out) {
  const auto& api = lee::Api();
  if (!snap.valid || !api.CreateTakeAudioAccessor || !api.GetAudioAccessorSamples ||
      !api.DestroyAudioAccessor) {
    return false;
  }

  const int sr = snap.source_sr;
  const int ch = snap.source_channels;
  if (sr <= 0 || ch <= 0) return false;

  const double region_seconds = snap.length * snap.playrate;
  if (region_seconds <= 0.0) return false;

  void* acc = api.CreateTakeAudioAccessor(snap.take);
  if (!acc) return false;

  double acc_start = 0.0;
  double acc_end = region_seconds;
  if (api.GetAudioAccessorStartTime && api.GetAudioAccessorEndTime) {
    acc_start = api.GetAudioAccessorStartTime(acc);
    acc_end = api.GetAudioAccessorEndTime(acc);
    if (acc_end <= acc_start) {
      api.DestroyAudioAccessor(acc);
      return false;
    }
  }

  const double readable_sec = std::min(region_seconds, acc_end - acc_start);
  const size_t total_frames = static_cast<size_t>(readable_sec * sr + 0.5);
  if (total_frames == 0) {
    api.DestroyAudioAccessor(acc);
    return false;
  }

  out.alloc(ch, sr, total_frames);

  const int block = 65536;
  std::vector<double> tmp(static_cast<size_t>(block) * static_cast<size_t>(ch));

  size_t done = 0;
  bool got_audio = false;
  bool had_error = false;

  while (done < total_frames) {
    const int want = static_cast<int>(
        (total_frames - done) < static_cast<size_t>(block) ? (total_frames - done) : block);
    // Item-relative timeline (see ReaTeam "Working with audio samples" template).
    const double t = acc_start + static_cast<double>(done) / static_cast<double>(sr);
    if (t >= acc_end) break;

    const int ok =
        api.GetAudioAccessorSamples(acc, sr, ch, t, want, tmp.data());
    // 0 = no audio (silence), 1 = audio, -1 = error
    if (ok < 0) {
      had_error = true;
      break;
    }
    if (ok > 0) got_audio = true;

    const size_t base = done * static_cast<size_t>(ch);
    const size_t count = static_cast<size_t>(want) * static_cast<size_t>(ch);
    for (size_t i = 0; i < count; ++i) {
      out.samples[base + i] = static_cast<float>(tmp[i]);
    }
    done += static_cast<size_t>(want);
  }

  api.DestroyAudioAccessor(acc);

  if (had_error) return false;
  if (!got_audio && peak_abs(out) < 1e-9f) return false;
  return true;
}

}  // namespace lee::splitter
