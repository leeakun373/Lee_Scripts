#include "features/item_hub/domain/ParamSpec.h"

namespace lee::item_hub {
namespace {

constexpr ParamDef kDefs[] = {
    {ParamId::ItemVol, Category::GainPitch, ParamKind::Continuous, "Item Vol", -150.0, 12.0, 0.0,
     true, false, 0},
    {ParamId::TakeVol, Category::GainPitch, ParamKind::Continuous, "Take Vol", -150.0, 12.0, 0.0,
     true, false, 0},
    {ParamId::Pitch, Category::GainPitch, ParamKind::Continuous, "Pitch", -24.0, 24.0, 0.0, false,
     false, 0},
    {ParamId::Rate, Category::GainPitch, ParamKind::Continuous, "Rate", 0.1, 4.0, 1.0, true, false,
     0},
    {ParamId::PreservePitch, Category::GainPitch, ParamKind::Toggle, "Preserve Pitch", 0.0, 1.0,
     0.0, true, false, 0},
    {ParamId::FadeIn, Category::FadePan, ParamKind::Continuous, "Fade In", 0.0, 5000.0, 0.0, false,
     false, 0},
    {ParamId::FadeOut, Category::FadePan, ParamKind::Continuous, "Fade Out", 0.0, 5000.0, 0.0,
     false, false, 0},
    {ParamId::FadeInShape, Category::FadePan, ParamKind::Discrete, "FadeIn Shape", 0.0, 6.0, 0.0,
     true, false, 7},
    {ParamId::FadeOutShape, Category::FadePan, ParamKind::Discrete, "FadeOut Shape", 0.0, 6.0, 0.0,
     true, false, 7},
    {ParamId::Pan, Category::FadePan, ParamKind::Continuous, "Pan", -100.0, 100.0, 0.0, false,
     false, 0},
    {ParamId::Reverse, Category::FadePan, ParamKind::Toggle, "Reverse", 0.0, 1.0, 0.0, true,
     false, 0},
    {ParamId::ChannelMode, Category::FadePan, ParamKind::Discrete, "Channel Mode", 0.0, 4.0, 0.0,
     true, false, 5},
    {ParamId::LeftEdge, Category::Position, ParamKind::Continuous, "Left Edge", 0.0, 30.0, 0.0,
     false, false, 0},
    {ParamId::RightEdge, Category::Position, ParamKind::Continuous, "Right Edge", 0.001, 30.0,
     1.0, false, false, 0},
    {ParamId::TakeOffset, Category::Position, ParamKind::Continuous, "Take Offset", -10.0, 10.0,
     0.0, false, false, 0},
    {ParamId::SnapOffset, Category::Position, ParamKind::Continuous, "Snap Offset", 0.0, 30.0,
     0.0, false, false, 0},
    {ParamId::ItemGap, Category::Position, ParamKind::Continuous, "Item Gap", -1.0, 5.0, 0.0,
     false, true, 0},
    {ParamId::BatchTrim, Category::Position, ParamKind::Continuous, "Batch Trim", 0.1, 30.0, 1.0,
     false, true, 0},
    {ParamId::VScale, Category::Envelope, ParamKind::Continuous, "V-Scale", 0.1, 4.0, 1.0, false,
     false, 0},
    {ParamId::VOffset, Category::Envelope, ParamKind::Continuous, "V-Offset", -1.0, 1.0, 0.0,
     false, false, 0},
    {ParamId::TScale, Category::Envelope, ParamKind::Continuous, "T-Scale", 0.1, 4.0, 1.0, false,
     false, 0},
    {ParamId::Smooth, Category::Envelope, ParamKind::Continuous, "Smooth", 0.0, 100.0, 0.0, false,
     false, 0},
    {ParamId::PitchRand, Category::Randomize, ParamKind::Continuous, "Pitch Rand", 0.0, 12.0, 0.0,
     false, false, 0},
    {ParamId::RateRand, Category::Randomize, ParamKind::Continuous, "Rate Rand", 0.0, 1.0, 0.0,
     false, false, 0},
    {ParamId::VolRand, Category::Randomize, ParamKind::Continuous, "Vol Rand", 0.0, 12.0, 0.0,
     false, false, 0},
};

static_assert(sizeof(kDefs) / sizeof(kDefs[0]) == static_cast<size_t>(ParamId::Count), "param table");

}  // namespace

Category CategoryOf(ParamId id) {
  const int i = static_cast<int>(id);
  if (i < 0 || i >= static_cast<int>(ParamId::Count)) return Category::GainPitch;
  return kDefs[i].category;
}

const ParamDef& Def(ParamId id) {
  return kDefs[static_cast<int>(id)];
}

int ParamCountInCategory(Category cat) {
  int n = 0;
  for (const auto& d : kDefs) {
    if (d.category == cat) ++n;
  }
  return n;
}

ParamId ParamAt(Category cat, int index) {
  int n = 0;
  for (const auto& d : kDefs) {
    if (d.category != cat) continue;
    if (n == index) return d.id;
    ++n;
  }
  return ParamId::ItemVol;
}

}  // namespace lee::item_hub
