#include "features/splitter/domain/SplitEngine.h"

#include "features/splitter/domain/algorithms/Algorithms.h"

namespace lee::splitter {

bool ProduceLayer(const AudioBuffer& in, AlgoMode mode, const SplitParams& params, Layer layer,
                  AudioBuffer& out) {
  switch (mode) {
    case AlgoMode::TransientSustain: return algo::TransientSustain(in, params, layer, out);
    case AlgoMode::MidSide:          return algo::MidSide(in, params, layer, out);
    case AlgoMode::Hpss:             return algo::Hpss(in, params, layer, out);
    case AlgoMode::TonalNoise:       return algo::TonalNoise(in, params, layer, out);
    case AlgoMode::FgAmbient:        return algo::FgAmbient(in, params, layer, out);
    default:                         return false;
  }
}

}  // namespace lee::splitter
