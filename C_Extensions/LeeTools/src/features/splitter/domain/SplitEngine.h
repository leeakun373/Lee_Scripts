#pragma once

#include "features/splitter/domain/AudioBuffer.h"
#include "features/splitter/domain/SplitMode.h"
#include "features/splitter/domain/SplitParams.h"

namespace lee::splitter {

// Pure DSP: synthesise one layer of `in` for the given mode. Thread-safe (no
// REAPER calls). Returns false if the algorithm cannot run on this input.
bool ProduceLayer(const AudioBuffer& in, AlgoMode mode, const SplitParams& params,
                  Layer layer, AudioBuffer& out);

}  // namespace lee::splitter
