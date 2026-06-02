#pragma once

#include <vector>

namespace lee::dsp {

// One-pole attack/release envelope follower over the absolute value of `in`.
// attack_ms / release_ms are time constants; sample_rate in Hz. Output has the
// same length as input.
void EnvelopeFollow(const std::vector<float>& in, double sample_rate,
                    double attack_ms, double release_ms, std::vector<float>& out);

// Simple centred moving-average smoothing of `in` over `window` samples.
void MovingAverage(const std::vector<float>& in, int window, std::vector<float>& out);

}  // namespace lee::dsp
