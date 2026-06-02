#include "shared/dsp/Envelope.h"

#include <cmath>

namespace lee::dsp {

namespace {

double coef_from_ms(double ms, double sr) {
  if (ms <= 0.0 || sr <= 0.0) return 0.0;
  return std::exp(-1.0 / (ms * 0.001 * sr));
}

}  // namespace

void EnvelopeFollow(const std::vector<float>& in, double sample_rate, double attack_ms,
                    double release_ms, std::vector<float>& out) {
  const size_t n = in.size();
  out.assign(n, 0.0f);
  if (n == 0) return;

  const float atk = static_cast<float>(coef_from_ms(attack_ms, sample_rate));
  const float rel = static_cast<float>(coef_from_ms(release_ms, sample_rate));

  float env = 0.0f;
  for (size_t i = 0; i < n; ++i) {
    const float x = std::fabs(in[i]);
    if (x > env) {
      env = atk * env + (1.0f - atk) * x;
    } else {
      env = rel * env + (1.0f - rel) * x;
    }
    out[i] = env;
  }
}

void MovingAverage(const std::vector<float>& in, int window, std::vector<float>& out) {
  const int n = static_cast<int>(in.size());
  out.assign(static_cast<size_t>(n), 0.0f);
  if (n == 0) return;
  if (window < 1) window = 1;
  const int half = window / 2;

  // Prefix sums for an O(n) box filter.
  std::vector<double> prefix(static_cast<size_t>(n) + 1, 0.0);
  for (int i = 0; i < n; ++i) {
    prefix[static_cast<size_t>(i + 1)] = prefix[static_cast<size_t>(i)] + in[static_cast<size_t>(i)];
  }
  for (int i = 0; i < n; ++i) {
    int lo = i - half;
    int hi = i + half;
    if (lo < 0) lo = 0;
    if (hi > n - 1) hi = n - 1;
    const double sum = prefix[static_cast<size_t>(hi + 1)] - prefix[static_cast<size_t>(lo)];
    out[static_cast<size_t>(i)] = static_cast<float>(sum / (hi - lo + 1));
  }
}

}  // namespace lee::dsp
