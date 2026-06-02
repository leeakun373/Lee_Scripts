#include "features/splitter/domain/algorithms/Algorithms.h"

#include <cmath>
#include <complex>
#include <vector>

#include "features/splitter/domain/SpecDefaults.h"
#include "shared/dsp/Median.h"
#include "shared/dsp/Stft.h"

namespace lee::splitter::algo {

// Tonal/Noise: per-frame, decide whether each bin sits above the local noise
// floor (median over a frequency neighbourhood) by more than the threshold.
bool TonalNoise(const AudioBuffer& in, const SplitParams& p, Layer layer, AudioBuffer& out) {
  if (in.empty()) return false;
  const int ch = in.channels;
  const size_t n = in.frames;
  out.alloc(ch, in.sample_rate, n);

  dsp::Stft stft(defaults::kNfft, defaults::kHop);
  const int nbins = stft.bins();
  const bool want_tonal = (layer == Layer::Layer1);
  const float power = static_cast<float>(p.tonal_mask_power);
  const float thr = static_cast<float>(p.peak_threshold_db);

  std::vector<float> chan, mag, floor;
  for (int c = 0; c < ch; ++c) {
    in.extract_channel(c, chan);
    dsp::Stft::Spectrum spec;
    stft.forward(chan.data(), n, spec);
    const size_t nframes = spec.size();
    if (nframes == 0) { out.set_channel(c, chan); continue; }

    mag.assign(static_cast<size_t>(nbins), 0.0f);
    for (size_t f = 0; f < nframes; ++f) {
      for (int b = 0; b < nbins; ++b) mag[static_cast<size_t>(b)] = std::abs(spec[f][static_cast<size_t>(b)]);
      dsp::SlidingMedian(mag, p.peak_width, floor);
      for (int b = 0; b < nbins; ++b) {
        const float m = mag[static_cast<size_t>(b)];
        const float fl = floor[static_cast<size_t>(b)];
        const float excess_db = 20.0f * std::log10((m + 1e-9f) / (fl + 1e-9f));
        // Soft tonal probability: sigmoid of (excess - threshold), sharpened.
        float t = 1.0f / (1.0f + std::exp(-(excess_db - thr)));
        t = std::pow(t, power);
        const float mask = want_tonal ? t : (1.0f - t);
        spec[f][static_cast<size_t>(b)] *= mask;
      }
    }

    std::vector<float> rec;
    stft.inverse(spec, n, rec);
    out.set_channel(c, rec);
  }
  return true;
}

}  // namespace lee::splitter::algo
