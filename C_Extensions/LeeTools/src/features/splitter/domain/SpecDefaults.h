#pragma once

namespace lee::splitter::defaults {

// Global STFT settings (spec section 4).
constexpr int kNfft = 2048;
constexpr int kHop = 512;

// Transient / Sustain (Simple).
constexpr double kTransStrength = 50.0;  // 0..100 %
constexpr double kTransTail = 15.0;      // 0..100 %
// Transient / Sustain (Advanced).
constexpr double kFastAttackMs = 1.0;   // 0.5..5
constexpr double kSlowAttackMs = 20.0;  // 10..50
constexpr double kReleaseMs = 40.0;     // 10..100
constexpr double kSmoothingMs = 5.0;    // 1..20
constexpr double kSensitivity = 5.0;    // 1..15
constexpr bool kStereoLink = true;

// Mid / Side.
constexpr double kMidGainDb = 0.0;   // -12..+12
constexpr double kSideGainDb = 0.0;  // -12..+12

// HPSS.
constexpr int kHarmonicLen = 17;    // 3..31 odd
constexpr int kPercussiveLen = 17;  // 3..31 odd
constexpr double kHpssMaskPower = 2.0;  // 1..8

// Tonal / Noise.
constexpr int kPeakWidth = 9;            // 3..31 odd bins
constexpr double kPeakThresholdDb = 6.0; // 0..30
constexpr double kTonalMaskPower = 4.0;  // 1..8

// Foreground / Ambient.
constexpr double kAmbientTimeS = 2.0;    // 0.5..10
constexpr double kFgThresholdDb = 6.0;   // 0..30
constexpr double kFgMaskPower = 4.0;     // 1..8

}  // namespace lee::splitter::defaults
