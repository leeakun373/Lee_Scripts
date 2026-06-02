#include "features/splitter/domain/WavWriter.h"

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <cstdio>

namespace lee::splitter {

namespace {
std::atomic<unsigned> g_counter{0};

void put_u32(FILE* f, uint32_t v) {
  unsigned char b[4] = {static_cast<unsigned char>(v & 0xFF),
                        static_cast<unsigned char>((v >> 8) & 0xFF),
                        static_cast<unsigned char>((v >> 16) & 0xFF),
                        static_cast<unsigned char>((v >> 24) & 0xFF)};
  std::fwrite(b, 1, 4, f);
}
void put_u16(FILE* f, uint16_t v) {
  unsigned char b[2] = {static_cast<unsigned char>(v & 0xFF),
                        static_cast<unsigned char>((v >> 8) & 0xFF)};
  std::fwrite(b, 1, 2, f);
}
}  // namespace

std::string TempDir() {
  char buf[MAX_PATH] = {0};
  DWORD n = ::GetTempPathA(MAX_PATH, buf);
  std::string dir = (n > 0) ? std::string(buf, n) : std::string(".\\");
  dir += "LeeSplitter\\";
  ::CreateDirectoryA(dir.c_str(), nullptr);
  return dir;
}

std::string MakeTempWavPath(const char* suffix) {
  const unsigned id = g_counter.fetch_add(1);
  const DWORD t = ::GetTickCount();
  char name[256];
  std::snprintf(name, sizeof(name), "%lu_%u_%s.wav", static_cast<unsigned long>(t), id,
                suffix ? suffix : "layer");
  return TempDir() + name;
}

bool WriteWav24(const std::string& path, const AudioBuffer& buf) {
  if (buf.channels <= 0 || buf.sample_rate <= 0) return false;

  FILE* f = nullptr;
  if (fopen_s(&f, path.c_str(), "wb") != 0 || !f) return false;

  const uint16_t channels = static_cast<uint16_t>(buf.channels);
  const uint32_t sr = static_cast<uint32_t>(buf.sample_rate);
  const uint16_t bits = 24;
  const uint16_t block_align = static_cast<uint16_t>(channels * (bits / 8));
  const uint32_t byte_rate = sr * block_align;
  const uint32_t data_bytes =
      static_cast<uint32_t>(buf.frames) * block_align;

  std::fwrite("RIFF", 1, 4, f);
  put_u32(f, 36 + data_bytes);
  std::fwrite("WAVE", 1, 4, f);
  std::fwrite("fmt ", 1, 4, f);
  put_u32(f, 16);
  put_u16(f, 1);  // PCM
  put_u16(f, channels);
  put_u32(f, sr);
  put_u32(f, byte_rate);
  put_u16(f, block_align);
  put_u16(f, bits);
  std::fwrite("data", 1, 4, f);
  put_u32(f, data_bytes);

  for (size_t i = 0; i < buf.samples.size(); ++i) {
    float s = buf.samples[i];
    if (s > 1.0f) s = 1.0f;
    if (s < -1.0f) s = -1.0f;
    int32_t v = static_cast<int32_t>(s * 8388607.0f);
    unsigned char b[3] = {static_cast<unsigned char>(v & 0xFF),
                          static_cast<unsigned char>((v >> 8) & 0xFF),
                          static_cast<unsigned char>((v >> 16) & 0xFF)};
    std::fwrite(b, 1, 3, f);
  }

  std::fclose(f);
  return true;
}

}  // namespace lee::splitter
