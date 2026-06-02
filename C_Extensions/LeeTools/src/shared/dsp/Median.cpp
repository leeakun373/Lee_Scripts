#include "shared/dsp/Median.h"

#include <algorithm>

namespace lee::dsp {

namespace {

int clamp_index(int i, int n) {
  if (i < 0) return 0;
  if (i >= n) return n - 1;
  return i;
}

}  // namespace

void SlidingMedian(const std::vector<float>& in, int window, std::vector<float>& out) {
  const int n = static_cast<int>(in.size());
  out.assign(static_cast<size_t>(n), 0.0f);
  if (n == 0) return;
  if (window < 1) window = 1;
  if ((window & 1) == 0) window += 1;  // force odd
  const int half = window / 2;

  std::vector<float> w(static_cast<size_t>(window));
  for (int i = 0; i < n; ++i) {
    for (int k = -half; k <= half; ++k) {
      w[static_cast<size_t>(k + half)] = in[static_cast<size_t>(clamp_index(i + k, n))];
    }
    std::nth_element(w.begin(), w.begin() + half, w.end());
    out[static_cast<size_t>(i)] = w[static_cast<size_t>(half)];
  }
}

void SlidingMin(const std::vector<float>& in, int window, std::vector<float>& out) {
  const int n = static_cast<int>(in.size());
  out.assign(static_cast<size_t>(n), 0.0f);
  if (n == 0) return;
  if (window < 1) window = 1;
  const int half = window / 2;

  for (int i = 0; i < n; ++i) {
    float m = in[static_cast<size_t>(i)];
    for (int k = -half; k <= half; ++k) {
      const float v = in[static_cast<size_t>(clamp_index(i + k, n))];
      if (v < m) m = v;
    }
    out[static_cast<size_t>(i)] = m;
  }
}

}  // namespace lee::dsp
