#include "reaper_plugin.h"
#include "DragDrop.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <cwctype>
#include <string>

#include <objbase.h>
#include <shellapi.h>
#include <windows.h>

namespace {

constexpr const char kExtSection[] = "Toolbox_DropStation";
constexpr const char kPathKey[] = "Toolbox_DropStation_ExportPath";

using GetExtStateFn = const char* (*)(const char* section, const char* key);

reaper_plugin_info_t* g_rec = nullptr;
int (*g_register)(const char* name, void* infostruct) = nullptr;
GetExtStateFn g_getExtState = nullptr;

int g_actionCommandId = 0;

gaccel_register_t g_gaccel{};
bool (*g_hookCommand)(int command, int flag) = nullptr;
bool g_gaccel_registered = false;
bool g_hook_registered = false;

bool Utf8ToWide(const char* utf8, std::wstring& out) {
  out.clear();
  if (!utf8) {
    return false;
  }
  const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, nullptr, 0);
  if (n <= 0) {
    return false;
  }
  out.resize(static_cast<size_t>(n - 1));
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, out.data(), n) <= 0) {
    out.clear();
    return false;
  }
  return true;
}

bool PathLooksLikeWav(const std::wstring& p) {
  if (p.size() < 5) {
    return false;
  }
  std::wstring tail = p.substr(p.size() - 4);
  std::transform(tail.begin(), tail.end(), tail.begin(), [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
  return tail == L".wav";
}

bool FileExistsUtf16(const std::wstring& p) {
  const DWORD a = GetFileAttributesW(p.c_str());
  return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

void DebugLog(const wchar_t* msg) {
  OutputDebugStringW(L"[reaper_dropstation] ");
  OutputDebugStringW(msg);
  OutputDebugStringW(L"\n");
}

void HandleStartOsDragDrop() {
  if (!g_getExtState) {
    DebugLog(L"GetExtState unavailable");
    return;
  }
  const char* pathUtf8 = g_getExtState(kExtSection, kPathKey);
  if (!pathUtf8 || pathUtf8[0] == '\0') {
    DebugLog(L"ExtState empty: Toolbox_DropStation / Toolbox_DropStation_ExportPath");
    return;
  }

  std::wstring wpath;
  if (!Utf8ToWide(pathUtf8, wpath)) {
    DebugLog(L"Invalid UTF-8 path in ExtState");
    return;
  }
  if (!PathLooksLikeWav(wpath)) {
    DebugLog(L"Path is not a .wav file (extension check)");
    return;
  }
  if (!FileExistsUtf16(wpath)) {
    DebugLog(L"File does not exist on disk");
    return;
  }

  const wchar_t* one = wpath.c_str();
  HGLOBAL hdrop = CreateHDropFromPaths(&one, 1);
  if (!hdrop) {
    DebugLog(L"CreateHDropFromPaths failed");
    return;
  }

  HWND owner = g_rec ? g_rec->hwnd_main : nullptr;
  const HRESULT hr = RunOsFileDragDrop(owner, hdrop);
  if (FAILED(hr)) {
    DebugLog(L"RunOsFileDragDrop failed");
  }
}

bool HookCommand(int command, int flag) {
  UNREFERENCED_PARAMETER(flag);
  if (g_actionCommandId != 0 && command == g_actionCommandId) {
    HandleStartOsDragDrop();
    return true;
  }
  return false;
}

bool LoadApi(reaper_plugin_info_t* rec) {
  g_rec = rec;
  g_register = rec->Register;
  if (!rec->GetFunc) {
    return false;
  }
  *reinterpret_cast<void**>(&g_getExtState) = rec->GetFunc("GetExtState");
  return g_getExtState != nullptr;
}

void UnregisterAll() {
  if (g_register) {
    if (g_hook_registered && g_hookCommand) {
      g_register("-hookcommand", reinterpret_cast<void*>(g_hookCommand));
    }
    if (g_gaccel_registered) {
      g_register("-gaccel", &g_gaccel);
    }
  }
  g_hook_registered = false;
  g_gaccel_registered = false;
  g_hookCommand = nullptr;
  ZeroMemory(&g_gaccel, sizeof(g_gaccel));
  g_actionCommandId = 0;
  g_register = nullptr;
  g_getExtState = nullptr;
  g_rec = nullptr;
}

}  // namespace

extern "C" REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE hInst,
                                                                 reaper_plugin_info_t* rec) {
  UNREFERENCED_PARAMETER(hInst);
  if (!rec) {
    UnregisterAll();
    return 0;
  }

  if (rec->caller_version != REAPER_PLUGIN_VERSION) {
    return 0;
  }

  if (!LoadApi(rec)) {
    return 0;
  }

  g_hookCommand = &HookCommand;
  g_actionCommandId = g_register("command_id", reinterpret_cast<void*>(const_cast<char*>("Lee_StartOSDragDrop")));
  if (!g_actionCommandId) {
    UnregisterAll();
    return 0;
  }

  ZeroMemory(&g_gaccel, sizeof(g_gaccel));
  g_gaccel.desc = "Lee: Start OS Drag & Drop for File Path";
  g_gaccel.accel.fVirt = 0;
  g_gaccel.accel.key = 0;
  g_gaccel.accel.cmd = static_cast<WORD>(g_actionCommandId);

  if (!g_register("gaccel", &g_gaccel)) {
    UnregisterAll();
    return 0;
  }
  g_gaccel_registered = true;

  if (!g_register("hookcommand", reinterpret_cast<void*>(g_hookCommand))) {
    UnregisterAll();
    return 0;
  }
  g_hook_registered = true;

  return 1;
}
