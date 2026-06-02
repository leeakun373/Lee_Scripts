#pragma once

#include "features/splitter/domain/AudioBuffer.h"
#include "features/splitter/domain/ItemSnapshot.h"

namespace lee::splitter {

// Reads the audio the item plays (length * playrate seconds of source media)
// via CreateTakeAudioAccessor. starttime_sec is item-relative (0 = item start),
// not D_STARTOFFS — the accessor maps that internally. Main thread only.
// Returns false on failure.
bool ReadItemAudio(const ItemSnapshot& snap, AudioBuffer& out);

}  // namespace lee::splitter
