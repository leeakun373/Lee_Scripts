#include "shared/dsp/Stft.h"

#define _USE_MATH_DEFINES
#include <cmath>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#include "shared/dsp/Fft.h"

namespace lee::dsp {

Stft::Stft(int nfft, int hop) : nfft_(nfft), hop_(hop), pad_(nfft) {
  window_.resize(static_cast<size_t>(nfft_));
  for (int i = 0; i < nfft_; ++i) {
    window_[static_cast<size_t>(i)] =
        0.5f - 0.5f * static_cast<float>(std::cos(2.0 * M_PI * i / (nfft_ - 1)));
  }
}

void Stft::forward(const float* x, size_t n, Spectrum& out) const {
  out.clear();
  if (!x || n == 0) return;

  // Zero-pad front and back so real samples sit in the interior.
  const size_t padded_len = n + static_cast<size_t>(2 * pad_);
  std::vector<float> padded(padded_len, 0.0f);
  for (size_t i = 0; i < n; ++i) {
    padded[static_cast<size_t>(pad_) + i] = x[i];
  }

  const int nbins = bins();
  const size_t frame_count =
      padded_len >= static_cast<size_t>(nfft_)
          ? 1 + (padded_len - static_cast<size_t>(nfft_)) / static_cast<size_t>(hop_)
          : 1;
  out.reserve(frame_count);

  std::vector<std::complex<float>> buf(static_cast<size_t>(nfft_));
  for (size_t f = 0; f < frame_count; ++f) {
    const size_t start = f * static_cast<size_t>(hop_);
    for (int i = 0; i < nfft_; ++i) {
      const size_t idx = start + static_cast<size_t>(i);
      const float s = (idx < padded_len) ? padded[idx] : 0.0f;
      buf[static_cast<size_t>(i)] =
          std::complex<float>(s * window_[static_cast<size_t>(i)], 0.0f);
    }
    Fft(buf, /*inverse=*/false);
    std::vector<std::complex<float>> frame(static_cast<size_t>(nbins));
    for (int b = 0; b < nbins; ++b) {
      frame[static_cast<size_t>(b)] = buf[static_cast<size_t>(b)];
    }
    out.push_back(std::move(frame));
  }
}

void Stft::inverse(const Spectrum& frames, size_t out_len, std::vector<float>& out) const {
  out.assign(out_len, 0.0f);
  if (frames.empty() || out_len == 0) return;

  const size_t padded_len = out_len + static_cast<size_t>(2 * pad_);
  std::vector<float> acc(padded_len, 0.0f);
  std::vector<float> denom(padded_len, 0.0f);

  const int nbins = bins();
  std::vector<std::complex<float>> buf(static_cast<size_t>(nfft_));

  for (size_t f = 0; f < frames.size(); ++f) {
    const auto& frame = frames[f];
    if (static_cast<int>(frame.size()) < nbins) continue;

    // Rebuild the full spectrum via conjugate symmetry.
    for (int b = 0; b < nbins; ++b) {
      buf[static_cast<size_t>(b)] = frame[static_cast<size_t>(b)];
    }
    for (int b = 1; b < nfft_ - nbins + 1; ++b) {
      buf[static_cast<size_t>(nfft_ - b)] = std::conj(frame[static_cast<size_t>(b)]);
    }

    Fft(buf, /*inverse=*/true);
    const float inv_n = 1.0f / static_cast<float>(nfft_);

    const size_t start = f * static_cast<size_t>(hop_);
    for (int i = 0; i < nfft_; ++i) {
      const size_t idx = start + static_cast<size_t>(i);
      if (idx >= padded_len) break;
      const float w = window_[static_cast<size_t>(i)];
      const float sample = buf[static_cast<size_t>(i)].real() * inv_n * w;
      acc[idx] += sample;
      denom[idx] += w * w;
    }
  }

  for (size_t i = 0; i < out_len; ++i) {
    const size_t idx = static_cast<size_t>(pad_) + i;
    const float d = denom[idx];
    out[i] = (d > 1e-8f) ? acc[idx] / d : 0.0f;
  }
}

}  // namespace lee::dsp
