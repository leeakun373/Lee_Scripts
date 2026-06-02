#include "features/splitter/domain/algorithms/Algorithms.h"

#include <complex>
#include <vector>

#include "features/splitter/domain/SpecDefaults.h"
#include "shared/dsp/Median.h"
#include "shared/dsp/Stft.h"
#include "shared/dsp/Wiener.h"

namespace lee::splitter::algo {

bool Hpss(const AudioBuffer& in, const SplitParams& p, Layer layer, AudioBuffer& out) {
  if (in.empty()) return false;
  const int ch = in.channels;
  const size_t n = in.frames;
  out.alloc(ch, in.sample_rate, n);

  dsp::Stft stft(defaults::kNfft, defaults::kHop);
  const int nbins = stft.bins();
  const bool want_harmonic = (layer == Layer::Layer1);
  const float power = static_cast<float>(p.hpss_mask_power);

  std::vector<float> chan;
  for (int c = 0; c < ch; ++c) {
    in.extract_channel(c, chan);

    dsp::Stft::Spectrum spec;
    stft.forward(chan.data(), n, spec);
    const size_t nframes = spec.size();
    if (nframes == 0) {
      out.set_channel(c, chan);
      continue;
    }

    // Magnitude matrix.
    std::vector<std::vector<float>> mag(nframes, std::vector<float>(static_cast<size_t>(nbins)));
    for (size_t f = 0; f < nframes; ++f) {
      for (int b = 0; b < nbins; ++b) {
        mag[f][static_cast<size_t>(b)] = std::abs(spec[f][static_cast<size_t>(b)]);
      }
    }

    // Harmonic: median over time (per bin). Percussive: median over freq (per frame).
    std::vector<std::vector<float>> H(nframes, std::vector<float>(static_cast<size_t>(nbins)));
    std::vector<std::vector<float>> P(nframes, std::vector<float>(static_cast<size_t>(nbins)));

    std::vector<float> col(nframes), colmed;
    for (int b = 0; b < nbins; ++b) {
      for (size_t f = 0; f < nframes; ++f) col[f] = mag[f][static_cast<size_t>(b)];
      dsp::SlidingMedian(col, p.harmonic_len, colmed);
      for (size_t f = 0; f < nframes; ++f) H[f][static_cast<size_t>(b)] = colmed[f];
    }
    std::vector<float> rowmed;
    for (size_t f = 0; f < nframes; ++f) {
      dsp::SlidingMedian(mag[f], p.percussive_len, rowmed);
      P[f] = rowmed;
    }

    // Wiener mask + apply.
    for (size_t f = 0; f < nframes; ++f) {
      for (int b = 0; b < nbins; ++b) {
        const float mh = dsp::WienerMask(H[f][static_cast<size_t>(b)], P[f][static_cast<size_t>(b)], power);
        const float m = want_harmonic ? mh : (1.0f - mh);
        spec[f][static_cast<size_t>(b)] *= m;
      }
    }

    std::vector<float> rec;
    stft.inverse(spec, n, rec);
    out.set_channel(c, rec);
  }
  return true;
}

}  // namespace lee::splitter::algo
