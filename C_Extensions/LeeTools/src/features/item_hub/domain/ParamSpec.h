#pragma once

namespace lee::item_hub {

enum class Category : int {
  GainPitch = 0,
  FadePan = 1,
  Position = 2,
  Envelope = 3,
  Randomize = 4,
  Count = 5,
};

enum class ParamKind { Continuous, Toggle, Discrete };

enum class ParamId : int {
  ItemVol = 0,
  TakeVol,
  Pitch,
  Rate,
  PreservePitch,
  FadeIn,
  FadeOut,
  FadeInShape,
  FadeOutShape,
  Pan,
  Reverse,
  ChannelMode,
  LeftEdge,
  RightEdge,
  TakeOffset,
  SnapOffset,
  ItemGap,
  BatchTrim,
  VScale,
  VOffset,
  TScale,
  Smooth,
  PitchRand,
  RateRand,
  VolRand,
  Count,
};

struct ParamDef {
  ParamId id;
  Category category;
  ParamKind kind;
  const char* label;
  double min_v;
  double max_v;
  double default_v;
  bool absolute_in_multi;
  bool multi_only;
  int discrete_count;
};

Category CategoryOf(ParamId id);
const ParamDef& Def(ParamId id);
int ParamCountInCategory(Category cat);
ParamId ParamAt(Category cat, int index);

constexpr const char* kCategoryLabels[] = {
    "Gain & Pitch", "Fade & Pan", "Position", "Envelope", "Randomize",
};

constexpr const char* kFadeShapeLabels[] = {
    "Linear", "Fast Start", "Fast End", "S-Curve", "Rev S-Curve", "Sharp", "Smooth",
};

constexpr const char* kChannelModeLabels[] = {
    "Normal", "Rev Stereo", "Mono (DM)", "Left", "Right",
};

}  // namespace lee::item_hub
