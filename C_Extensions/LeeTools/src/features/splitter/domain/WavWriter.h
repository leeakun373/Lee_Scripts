#pragma once

#include <string>

#include "features/splitter/domain/AudioBuffer.h"

namespace lee::splitter {

// Returns (creating if needed) "%TEMP%/LeeSplitter" with a trailing separator.
std::string TempDir();

// Builds a unique wav path inside TempDir() using the given suffix label.
std::string MakeTempWavPath(const char* suffix);

// Writes an interleaved buffer as a 24-bit PCM WAV file. Returns false on error.
bool WriteWav24(const std::string& path, const AudioBuffer& buf);

}  // namespace lee::splitter
