#include "features/splitter/domain/algorithms/Algorithms.h"

#include <cmath>
#include <complex>
#include <vector>

#include "features/splitter/domain/SpecDefaults.h"
#include "shared/dsp/Median.h"
#include "shared/dsp/Stft.h"

namespace lee::splitter::algo {

// Foreground/Ambient: estimate a long-window noise floor of per-frame energy,
// mark frames exceeding it by the threshold as foreground (spec 5.5).
bool FgAmbient(const AudioBuffer& in, const SplitParams& p, Layer layer, AudioBuffer& out) {
  if (in.empty()) return false;
  const int ch = in.channels;
  const size_t n = in.frames;
  const double sr = in.sample_rate;
  out.alloc(ch, in.sample_rate, n);

  dsp::Stft stft(defaults::kNfft, defaults::kHop);
  const int nbins = stft.bins();
  const bool want_fg = (layer == Layer::Layer1);
  const float power = static_cast<float>(p.fg_mask_power);
  const float thr = static_cast<float>(p.fg_threshold_db);

  // Window length in frames covering Ambient Time.
  const double frame_seconds = static_cast<double>(defaults::kHop) / sr;
  int win = static_cast<int>(p.ambient_time_s / frame_seconds);
  if (win < 1) win = 1;

  std::vector<float> chan;
  for (int c = 0; c < ch; ++c) {
    in.extract_channel(c, chan);
    dsp::Stft::Spectrum spec;
    stft.forward(chan.data(), n, spec);
    const size_t nframes = spec.size();
    if (nframes == 0) { out.set_channel(c, chan); continue; }

    // Per-frame energy (dB) and its long-window floor.
    std::vector<float> energy(nframes, 0.0f);
    for (size_t f = 0; f < nframes; ++f) {
      double e = 0.0;
      for (int b = 0; b < nbins; ++b) {
        const float a = std::abs(spec[f][static_cast<size_t>(b)]);
        e += static_cast<double>(a) * a;
      }
      energy[f] = static_cast<float>(10.0 * std::log10(e + 1e-12));
    }
    std::vector<float> floor_db;
    dsp::SlidingMin(energy, win, floor_db);

    std::vector<float> fg_mask(nframes, 0.0f);
    for (size_t f = 0; f < nframes; ++f) {
      const float excess = energy[f] - floor_db[f] - thr;
      float t = 1.0f / (1.0f + std::exp(-excess));
      t = std::pow(t, power);
      fg_mask[f] = t;
    }

    // Apply the (interpolated) frame mask to the spectrum, then iSTFT.
    for (size_t f = 0; f < nframes; ++f) {
      const float m = want_fg ? fg_mask[f] : (1.0f - fg_mask[f]);
      for (int b = 0; b < nbins; ++b) spec[f][static_cast<size_t>(b)] *= m;
    }

    std::vector<float> rec;
    stft.inverse(spec, n, rec);
    out.set_channel(c, rec);
  }
  return true;
}

}  // namespace lee::splitter::algo
