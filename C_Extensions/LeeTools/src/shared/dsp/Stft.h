#pragma once

#include <complex>
#include <vector>

namespace lee::dsp {

// Real-input STFT / iSTFT with a Hann window and overlap-add reconstruction.
// Frames are stored as the lower half-spectrum (bins = nfft/2 + 1). The
// inverse normalises by the accumulated analysis*synthesis window energy so
// that an all-ones mask reproduces the input (away from the zero-padded edges).
class Stft {
 public:
  using Spectrum = std::vector<std::vector<std::complex<float>>>;  // [frame][bin]

  Stft(int nfft, int hop);

  int nfft() const { return nfft_; }
  int hop() const { return hop_; }
  int bins() const { return nfft_ / 2 + 1; }

  // Forward transform of a mono signal.
  void forward(const float* x, size_t n, Spectrum& out) const;

  // Inverse transform back to `out_len` mono samples.
  void inverse(const Spectrum& frames, size_t out_len, std::vector<float>& out) const;

 private:
  int nfft_;
  int hop_;
  int pad_;  // front/back zero padding (== nfft_)
  std::vector<float> window_;
};

}  // namespace lee::dsp
