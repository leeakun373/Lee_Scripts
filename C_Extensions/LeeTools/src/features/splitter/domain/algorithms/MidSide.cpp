#include "features/splitter/domain/algorithms/Algorithms.h"

#include <cmath>
#include <vector>

namespace lee::splitter::algo {

namespace {
float db2lin(double db) { return static_cast<float>(std::pow(10.0, db / 20.0)); }
}  // namespace

// Mid/Side is only meaningful on stereo input (spec 5.2).
bool MidSide(const AudioBuffer& in, const SplitParams& p, Layer layer, AudioBuffer& out) {
  if (in.empty() || in.channels < 2) return false;
  const int ch = in.channels;
  const size_t n = in.frames;
  out.alloc(ch, in.sample_rate, n);

  const bool want_mid = (layer == Layer::Layer1);
  const float g = want_mid ? db2lin(p.mid_gain_db) : db2lin(p.side_gain_db);

  for (size_t i = 0; i < n; ++i) {
    const size_t base = i * static_cast<size_t>(ch);
    const float l = in.samples[base + 0];
    const float r = in.samples[base + 1];
    const float mid = 0.5f * (l + r);
    const float side = 0.5f * (l - r);
    if (want_mid) {
      const float v = mid * g;
      out.samples[base + 0] = v;
      out.samples[base + 1] = v;
    } else {
      const float v = side * g;
      out.samples[base + 0] = v;
      out.samples[base + 1] = -v;
    }
    // Pass through any extra channels unchanged-ish (rare).
    for (int c = 2; c < ch; ++c) {
      out.samples[base + static_cast<size_t>(c)] = in.samples[base + static_cast<size_t>(c)] * g;
    }
  }
  return true;
}

}  // namespace lee::splitter::algo
