#include "plugin/PluginContext.h"

#include <windows.h>

#include <string>
#include <vector>

namespace lee {
namespace {

reaper_plugin_info_t* g_rec = nullptr;
REAPER_PLUGIN_HINSTANCE g_dll_hinst = nullptr;
using GetExtStateFn = const char* (*)(const char* section, const char* key);
GetExtStateFn g_getExtState = nullptr;
ApiTable g_api;

template <typename Fn>
void LoadFn(reaper_plugin_info_t* rec, const char* name, Fn*& slot) {
  void* p = rec->GetFunc(name);
  slot = reinterpret_cast<Fn*>(p);
}

void LoadApiTable(reaper_plugin_info_t* rec) {
  LoadFn(rec, "CountSelectedMediaItems",         g_api.CountSelectedMediaItems);
  LoadFn(rec, "GetSelectedMediaItem",            g_api.GetSelectedMediaItem);
  LoadFn(rec, "GetActiveTake",                   g_api.GetActiveTake);
  LoadFn(rec, "GetMediaItemTake_Source",         g_api.GetMediaItemTake_Source);
  LoadFn(rec, "GetMediaSourceFileName",          g_api.GetMediaSourceFileName);
  LoadFn(rec, "GetSetMediaItemTakeInfo_String",  g_api.GetSetMediaItemTakeInfo_String);
  LoadFn(rec, "GetSetMediaItemInfo_String",      g_api.GetSetMediaItemInfo_String);
  LoadFn(rec, "GetSetMediaItemInfo",              g_api.GetSetMediaItemInfo);
  LoadFn(rec, "GetTakeName",                      g_api.GetTakeName);
  LoadFn(rec, "GetMediaItemInfo_Value",          g_api.GetMediaItemInfo_Value);
  LoadFn(rec, "GetMediaItemTakeInfo_Value",      g_api.GetMediaItemTakeInfo_Value);
  LoadFn(rec, "SetMediaItemInfo_Value",          g_api.SetMediaItemInfo_Value);
  LoadFn(rec, "SetMediaItemTakeInfo_Value",      g_api.SetMediaItemTakeInfo_Value);
  LoadFn(rec, "CountMediaItems",                 g_api.CountMediaItems);
  LoadFn(rec, "GetMediaItem",                    g_api.GetMediaItem);
  LoadFn(rec, "guidToString",                    g_api.guidToString);

  LoadFn(rec, "EnumProjects",                    g_api.EnumProjects);
  LoadFn(rec, "GetProjExtState",                 g_api.GetProjExtState);
  LoadFn(rec, "SetProjExtState",                 g_api.SetProjExtState);
  LoadFn(rec, "MarkProjectDirty",                g_api.MarkProjectDirty);
  LoadFn(rec, "GetProjectStateChangeCount",      g_api.GetProjectStateChangeCount);

  LoadFn(rec, "Main_OnCommand",                  g_api.Main_OnCommand);
  LoadFn(rec, "NamedCommandLookup",              g_api.NamedCommandLookup);
  LoadFn(rec, "Undo_BeginBlock2",                g_api.Undo_BeginBlock2);
  LoadFn(rec, "Undo_EndBlock2",                  g_api.Undo_EndBlock2);
  LoadFn(rec, "ValidatePtr2",                    g_api.ValidatePtr2);
  LoadFn(rec, "UpdateArrange",                   g_api.UpdateArrange);
  LoadFn(rec, "PreventUIRefresh",                g_api.PreventUIRefresh);
  LoadFn(rec, "GetMainHwnd",                     g_api.GetMainHwnd);
  LoadFn(rec, "SetExtState",                     g_api.SetExtState);
  LoadFn(rec, "GetMediaItemTrack",               g_api.GetMediaItemTrack);
  LoadFn(rec, "CountTakeEnvelopes",              g_api.CountTakeEnvelopes);
  LoadFn(rec, "GetTakeEnvelope",                 g_api.GetTakeEnvelope);
  LoadFn(rec, "GetEnvelopeInfo_Value",           g_api.GetEnvelopeInfo_Value);
  LoadFn(rec, "SetEnvelopeInfo_Value",           g_api.SetEnvelopeInfo_Value);
  LoadFn(rec, "CountEnvelopePoints",             g_api.CountEnvelopePoints);
  LoadFn(rec, "GetEnvelopePoint",               g_api.GetEnvelopePoint);
  LoadFn(rec, "SetEnvelopePoint",                g_api.SetEnvelopePoint);
  LoadFn(rec, "InsertEnvelopePoint",             g_api.InsertEnvelopePoint);
  LoadFn(rec, "GetEnvelopeScalingMode",          g_api.GetEnvelopeScalingMode);
}

}  // namespace

bool InitPluginApi(reaper_plugin_info_t* rec) {
  g_rec = rec;
  if (!rec || !rec->GetFunc) {
    return false;
  }
  *reinterpret_cast<void**>(&g_getExtState) = rec->GetFunc("GetExtState");
  LoadApiTable(rec);
  return g_getExtState != nullptr;
}

void ShutdownPluginApi() {
  g_getExtState = nullptr;
  g_api = ApiTable{};
  g_rec = nullptr;
  g_dll_hinst = nullptr;
}

reaper_plugin_info_t* GetPluginInfo() {
  return g_rec;
}

void SetDllHInstance(REAPER_PLUGIN_HINSTANCE inst) {
  g_dll_hinst = inst;
}

REAPER_PLUGIN_HINSTANCE GetDllHInstance() {
  return g_dll_hinst;
}

const char* GetExtState(const char* section, const char* key) {
  return g_getExtState ? g_getExtState(section, key) : nullptr;
}

const ApiTable& Api() {
  return g_api;
}

void DebugLog(const wchar_t* msg) {
  OutputDebugStringW(L"[reaper_lee_tools] ");
  OutputDebugStringW(msg);
  OutputDebugStringW(L"\n");
}

std::wstring Utf8ToWide(const char* utf8) {
  if (!utf8 || utf8[0] == '\0') {
    return {};
  }
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
  if (n <= 1) {
    return {};
  }
  std::vector<wchar_t> buf(static_cast<size_t>(n));
  if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, buf.data(), n) <= 0) {
    return {};
  }
  return std::wstring(buf.data(), static_cast<size_t>(n - 1));
}

std::wstring Utf8ToWide(const char* utf8, size_t byte_len) {
  if (!utf8 || byte_len == 0) {
    return {};
  }
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8, static_cast<int>(byte_len), nullptr, 0);
  if (n <= 0) {
    return {};
  }
  std::wstring out(static_cast<size_t>(n), L'\0');
  if (MultiByteToWideChar(CP_UTF8, 0, utf8, static_cast<int>(byte_len), out.data(), n) <= 0) {
    return {};
  }
  return out;
}

}  // namespace lee
