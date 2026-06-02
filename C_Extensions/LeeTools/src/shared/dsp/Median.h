#pragma once

#include <vector>

namespace lee::dsp {

// 1-D sliding median over `in` with an odd `window` length (clamped to >= 1).
// Edges use clamped (replicated) indexing. Result has the same length as `in`.
void SlidingMedian(const std::vector<float>& in, int window, std::vector<float>& out);

// 1-D sliding minimum (used by FG/Ambient noise-floor estimation).
void SlidingMin(const std::vector<float>& in, int window, std::vector<float>& out);

}  // namespace lee::dsp
