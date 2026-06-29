#pragma once

#include <chrono>
#include <cstdio>
#include <cstring>

#include <windows.h>

namespace lee::radial_menu::dbg {

// #region agent log
inline void Log(const char* hypothesis_id, const char* location, const char* message,
                const char* data_json = "{}") {
  const auto ts = std::chrono::duration_cast<std::chrono::milliseconds>(
                      std::chrono::system_clock::now().time_since_epoch())
                      .count();
  char line[640];
  snprintf(line, sizeof(line),
           "{\"sessionId\":\"7d1a96\",\"hypothesisId\":\"%s\",\"location\":\"%s\","
           "\"message\":\"%s\",\"data\":%s,\"timestamp\":%lld}\n",
           hypothesis_id, location, message, data_json, static_cast<long long>(ts));
  OutputDebugStringA("[RadialMenu] ");
  OutputDebugStringA(line);

  const char* paths[2] = {
      "C:\\Users\\DELL\\AppData\\Roaming\\REAPER\\Scripts\\Lee_Scripts\\debug-7d1a96.log",
      nullptr};
  char appdata_path[MAX_PATH] = {};
  if (const char* appdata = std::getenv("APPDATA"); appdata && appdata[0]) {
    snprintf(appdata_path, sizeof(appdata_path), "%s\\REAPER\\debug-7d1a96.log", appdata);
    paths[1] = appdata_path;
  }

  for (const char* path : paths) {
    if (!path || !path[0]) continue;
    FILE* f = nullptr;
    if (fopen_s(&f, path, "a") != 0 || !f) continue;
    fputs(line, f);
    fflush(f);
    fclose(f);
  }
}
// #endregion

}  // namespace lee::radial_menu::dbg
