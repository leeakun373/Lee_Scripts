#pragma once

namespace lee::splitter {

// The five algorithm families (Algorithm mode).
enum class AlgoMode {
  TransientSustain = 0,
  MidSide,
  Hpss,
  TonalNoise,
  FgAmbient,
  Count
};

// Which of the two output layers to synthesise.
enum class Layer { Layer1 = 0, Layer2 = 1 };

// Quick-mode one-click presets (spec section 4).
enum class QuickPreset {
  Punch = 0,  // Transient
  Body,       // Sustain
  Drone,      // HPSS harmonic
  Rhythm,     // HPSS percussive
  Center,     // Mid
  Width,      // Side
  Tonal,      // Tonal
  Noise,      // Noise
  Event,      // Foreground
  Bed,        // Ambient
  Count
};

inline const char* AlgoModeKey(AlgoMode m) {
  switch (m) {
    case AlgoMode::TransientSustain: return "transus";
    case AlgoMode::MidSide:          return "midside";
    case AlgoMode::Hpss:             return "hpss";
    case AlgoMode::TonalNoise:       return "tonalnoise";
    case AlgoMode::FgAmbient:        return "fgamb";
    default:                         return "transus";
  }
}

inline AlgoMode AlgoModeFromKey(const char* key) {
  if (!key) return AlgoMode::TransientSustain;
  const char* keys[] = {"transus", "midside", "hpss", "tonalnoise", "fgamb"};
  for (int i = 0; i < 5; ++i) {
    const char* k = keys[i];
    bool eq = true;
    for (int j = 0;; ++j) {
      if (k[j] != key[j]) { eq = false; break; }
      if (k[j] == '\0') break;
    }
    if (eq) return static_cast<AlgoMode>(i);
  }
  return AlgoMode::TransientSustain;
}

inline const char* AlgoModeLabel(AlgoMode m) {
  switch (m) {
    case AlgoMode::TransientSustain: return "Transient / Sustain";
    case AlgoMode::MidSide:          return "Mid / Side";
    case AlgoMode::Hpss:             return "Harmonic / Percussive";
    case AlgoMode::TonalNoise:       return "Tonal / Noise";
    case AlgoMode::FgAmbient:        return "Foreground / Ambient";
    default:                         return "Transient / Sustain";
  }
}

// Layer display names per mode (for preview buttons and track suffixes).
inline const char* LayerName(AlgoMode m, Layer l) {
  const bool first = (l == Layer::Layer1);
  switch (m) {
    case AlgoMode::TransientSustain: return first ? "Transient" : "Sustain";
    case AlgoMode::MidSide:          return first ? "Mid" : "Side";
    case AlgoMode::Hpss:             return first ? "Harmonic" : "Percussive";
    case AlgoMode::TonalNoise:       return first ? "Tonal" : "Noise";
    case AlgoMode::FgAmbient:        return first ? "Foreground" : "Ambient";
    default:                         return first ? "Layer 1" : "Layer 2";
  }
}

struct QuickInfo {
  const char* label;
  AlgoMode mode;
  Layer layer;
  const char* suffix;
  bool needs_stereo;
};

inline QuickInfo QuickPresetInfo(QuickPreset p) {
  switch (p) {
    case QuickPreset::Punch:  return {"Punch",  AlgoMode::TransientSustain, Layer::Layer1, "Punch",  false};
    case QuickPreset::Body:   return {"Body",   AlgoMode::TransientSustain, Layer::Layer2, "Body",   false};
    case QuickPreset::Drone:  return {"Drone",  AlgoMode::Hpss,             Layer::Layer1, "Drone",  false};
    case QuickPreset::Rhythm: return {"Rhythm", AlgoMode::Hpss,             Layer::Layer2, "Rhythm", false};
    case QuickPreset::Center: return {"Center", AlgoMode::MidSide,          Layer::Layer1, "Center", true};
    case QuickPreset::Width:  return {"Width",  AlgoMode::MidSide,          Layer::Layer2, "Width",  true};
    case QuickPreset::Tonal:  return {"Tonal",  AlgoMode::TonalNoise,       Layer::Layer1, "Tonal",  false};
    case QuickPreset::Noise:  return {"Noise",  AlgoMode::TonalNoise,       Layer::Layer2, "Noise",  false};
    case QuickPreset::Event:  return {"Event",  AlgoMode::FgAmbient,        Layer::Layer1, "Event",  false};
    case QuickPreset::Bed:    return {"Bed",    AlgoMode::FgAmbient,        Layer::Layer2, "Bed",    false};
    default:                  return {"Punch",  AlgoMode::TransientSustain, Layer::Layer1, "Punch",  false};
  }
}

}  // namespace lee::splitter
