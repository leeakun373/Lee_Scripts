#pragma once

#include <cmath>

namespace lee::dsp {

// Soft (Wiener-style) mask: a^p / (a^p + b^p). p controls sharpness; higher p
// approaches a hard binary mask. Returns a value in [0, 1].
inline float WienerMask(float a, float b, float power) {
  if (a < 0.0f) a = 0.0f;
  if (b < 0.0f) b = 0.0f;
  const float ap = std::pow(a, power);
  const float bp = std::pow(b, power);
  const float denom = ap + bp + 1e-12f;
  return ap / denom;
}

}  // namespace lee::dsp
