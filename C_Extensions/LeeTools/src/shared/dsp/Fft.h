#pragma once

#include <complex>
#include <vector>

namespace lee::dsp {

// In-place iterative radix-2 Cooley-Tukey FFT. `data.size()` must be a power
// of two. `inverse=true` computes the inverse transform (without 1/N scaling;
// caller divides by N if needed).
void Fft(std::vector<std::complex<float>>& data, bool inverse);

// Returns true if n is a power of two and > 0.
bool IsPowerOfTwo(size_t n);

}  // namespace lee::dsp
