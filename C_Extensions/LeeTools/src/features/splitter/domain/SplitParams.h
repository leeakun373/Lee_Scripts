#pragma once

#include "features/splitter/domain/SpecDefaults.h"

namespace lee::splitter {

// Aggregated parameters for all algorithms. UI knobs reset to these defaults on
// every window open (spec section 9: knob values are not persisted).
struct SplitParams {
  // Transient / Sustain.
  double trans_strength = defaults::kTransStrength;
  double trans_tail = defaults::kTransTail;
  bool show_advanced = false;
  double fast_attack_ms = defaults::kFastAttackMs;
  double slow_attack_ms = defaults::kSlowAttackMs;
  double release_ms = defaults::kReleaseMs;
  double smoothing_ms = defaults::kSmoothingMs;
  double sensitivity = defaults::kSensitivity;
  bool stereo_link = defaults::kStereoLink;

  // Mid / Side.
  double mid_gain_db = defaults::kMidGainDb;
  double side_gain_db = defaults::kSideGainDb;

  // HPSS.
  int harmonic_len = defaults::kHarmonicLen;
  int percussive_len = defaults::kPercussiveLen;
  double hpss_mask_power = defaults::kHpssMaskPower;

  // Tonal / Noise.
  int peak_width = defaults::kPeakWidth;
  double peak_threshold_db = defaults::kPeakThresholdDb;
  double tonal_mask_power = defaults::kTonalMaskPower;

  // Foreground / Ambient.
  double ambient_time_s = defaults::kAmbientTimeS;
  double fg_threshold_db = defaults::kFgThresholdDb;
  double fg_mask_power = defaults::kFgMaskPower;

  void reset() { *this = SplitParams{}; }

  // Spec 5.1: when Show Advanced is first enabled, derive the five advanced
  // params from the two Simple knobs as a starting point.
  void derive_advanced_from_simple() {
    const double s = trans_strength / 100.0;  // 0..1
    const double t = trans_tail / 100.0;      // 0..1
    fast_attack_ms = 2.0 + (0.5 - 2.0) * s;   // strength high -> faster
    slow_attack_ms = 15.0 + (40.0 - 15.0) * (1.0 - s);
    release_ms = 20.0 + (90.0 - 20.0) * t;
    smoothing_ms = 2.0 + (12.0 - 2.0) * t;
    sensitivity = 3.0 + (12.0 - 3.0) * s;
  }
};

}  // namespace lee::splitter
