#pragma once

#include <cstddef>
#include <vector>

namespace lee::splitter {

// Interleaved float audio. samples.size() == frames * channels.
struct AudioBuffer {
  int channels = 0;
  int sample_rate = 0;
  size_t frames = 0;
  std::vector<float> samples;  // interleaved

  void alloc(int ch, int sr, size_t fr) {
    channels = ch;
    sample_rate = sr;
    frames = fr;
    samples.assign(fr * static_cast<size_t>(ch), 0.0f);
  }

  bool empty() const { return frames == 0 || channels == 0; }

  // Copy one channel out to a planar buffer.
  void extract_channel(int ch, std::vector<float>& out) const {
    out.assign(frames, 0.0f);
    if (ch < 0 || ch >= channels) return;
    for (size_t i = 0; i < frames; ++i) {
      out[i] = samples[i * static_cast<size_t>(channels) + static_cast<size_t>(ch)];
    }
  }

  // Write one planar channel back.
  void set_channel(int ch, const std::vector<float>& in) {
    if (ch < 0 || ch >= channels) return;
    const size_t n = (in.size() < frames) ? in.size() : frames;
    for (size_t i = 0; i < n; ++i) {
      samples[i * static_cast<size_t>(channels) + static_cast<size_t>(ch)] = in[i];
    }
  }
};

}  // namespace lee::splitter
