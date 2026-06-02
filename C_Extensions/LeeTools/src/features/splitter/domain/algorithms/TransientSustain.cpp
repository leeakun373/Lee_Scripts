#include "features/splitter/domain/algorithms/Algorithms.h"

#include <algorithm>
#include <cmath>
#include <vector>

#include "shared/dsp/Envelope.h"

namespace lee::splitter::algo {

bool TransientSustain(const AudioBuffer& in, const SplitParams& p, Layer layer, AudioBuffer& out) {
  if (in.empty()) return false;
  const int ch = in.channels;
  const size_t n = in.frames;
  const double sr = in.sample_rate;
  out.alloc(ch, in.sample_rate, n);

  // Detection signal: when Stereo Link, use the per-sample max across channels
  // so all channels share one mask (avoids stereo image drift).
  std::vector<float> link_det;
  if (p.stereo_link && ch > 1) {
    link_det.assign(n, 0.0f);
    for (size_t i = 0; i < n; ++i) {
      float m = 0.0f;
      for (int c = 0; c < ch; ++c) {
        m = std::max(m, std::fabs(in.samples[i * static_cast<size_t>(ch) + static_cast<size_t>(c)]));
      }
      link_det[i] = m;
    }
  }

  std::vector<float> chan, det, fast, slow, mask, mask_s;
  std::vector<float> shared_mask;

  const double strength = p.trans_strength / 50.0;  // 1.0 at the 50% default
  const double tail = p.trans_tail / 100.0;         // 0..1
  // Tail lengthens the mask release: longer release keeps more of the decay.
  const double mask_release_ms = p.release_ms * (0.5 + 1.5 * tail);
  const int smooth_win = std::max(1, static_cast<int>(p.smoothing_ms * 0.001 * sr));

  for (int c = 0; c < ch; ++c) {
    in.extract_channel(c, chan);
    const std::vector<float>& d = (p.stereo_link && ch > 1) ? link_det : chan;

    if (!(p.stereo_link && ch > 1) || c == 0 || shared_mask.empty()) {
      dsp::EnvelopeFollow(d, sr, p.fast_attack_ms, p.release_ms, fast);
      dsp::EnvelopeFollow(d, sr, p.slow_attack_ms, mask_release_ms, slow);
      mask.assign(n, 0.0f);
      for (size_t i = 0; i < n; ++i) {
        const float r = fast[i] / (slow[i] + 1e-9f);
        float m = static_cast<float>((r - 1.0f) * p.sensitivity * strength);
        if (m < 0.0f) m = 0.0f;
        if (m > 1.0f) m = 1.0f;
        mask[i] = m;
      }
      dsp::MovingAverage(mask, smooth_win, mask_s);
      if (p.stereo_link && ch > 1) shared_mask = mask_s;
    }

    const std::vector<float>& mfinal = (p.stereo_link && ch > 1) ? shared_mask : mask_s;
    std::vector<float> result(n, 0.0f);
    const bool want_transient = (layer == Layer::Layer1);
    for (size_t i = 0; i < n; ++i) {
      const float m = mfinal[i];
      result[i] = chan[i] * (want_transient ? m : (1.0f - m));
    }
    out.set_channel(c, result);
  }
  return true;
}

}  // namespace lee::splitter::algo
