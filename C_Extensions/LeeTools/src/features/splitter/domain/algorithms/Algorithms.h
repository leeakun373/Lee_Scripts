#pragma once

#include "features/splitter/domain/AudioBuffer.h"
#include "features/splitter/domain/SplitMode.h"
#include "features/splitter/domain/SplitParams.h"

namespace lee::splitter::algo {

// Each function synthesises one layer (Layer1 or Layer2) of the input into
// `out` (same channel count / sample rate / frame count). Returns false if the
// algorithm cannot run on this input (e.g. Mid/Side on a mono buffer).

bool TransientSustain(const AudioBuffer& in, const SplitParams& p, Layer layer, AudioBuffer& out);
bool MidSide(const AudioBuffer& in, const SplitParams& p, Layer layer, AudioBuffer& out);
bool Hpss(const AudioBuffer& in, const SplitParams& p, Layer layer, AudioBuffer& out);
bool TonalNoise(const AudioBuffer& in, const SplitParams& p, Layer layer, AudioBuffer& out);
bool FgAmbient(const AudioBuffer& in, const SplitParams& p, Layer layer, AudioBuffer& out);

}  // namespace lee::splitter::algo
