#include "shared/dsp/Fft.h"

#define _USE_MATH_DEFINES
#include <cmath>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace lee::dsp {

bool IsPowerOfTwo(size_t n) {
  return n > 0 && (n & (n - 1)) == 0;
}

void Fft(std::vector<std::complex<float>>& a, bool inverse) {
  const size_t n = a.size();
  if (!IsPowerOfTwo(n)) return;

  // Bit-reversal permutation.
  for (size_t i = 1, j = 0; i < n; ++i) {
    size_t bit = n >> 1;
    for (; j & bit; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) std::swap(a[i], a[j]);
  }

  const double sign = inverse ? 1.0 : -1.0;
  for (size_t len = 2; len <= n; len <<= 1) {
    const double ang = sign * 2.0 * M_PI / static_cast<double>(len);
    const std::complex<float> wlen(static_cast<float>(std::cos(ang)),
                                   static_cast<float>(std::sin(ang)));
    for (size_t i = 0; i < n; i += len) {
      std::complex<float> w(1.0f, 0.0f);
      for (size_t k = 0; k < (len >> 1); ++k) {
        const std::complex<float> u = a[i + k];
        const std::complex<float> v = a[i + k + (len >> 1)] * w;
        a[i + k] = u + v;
        a[i + k + (len >> 1)] = u - v;
        w *= wlen;
      }
    }
  }
}

}  // namespace lee::dsp
