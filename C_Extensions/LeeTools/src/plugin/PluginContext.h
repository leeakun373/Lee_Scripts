#pragma once

#include <string>

#include "reaper_plugin.h"

namespace lee {

bool InitPluginApi(reaper_plugin_info_t* rec);
void ShutdownPluginApi();

// Sets / gets the DLL's own HINSTANCE captured from REAPER_PLUGIN_ENTRYPOINT.
// We need this for Win32 RegisterClassEx so the class is automatically torn
// down when the DLL unloads.
void SetDllHInstance(REAPER_PLUGIN_HINSTANCE inst);
REAPER_PLUGIN_HINSTANCE GetDllHInstance();

reaper_plugin_info_t* GetPluginInfo();
const char* GetExtState(const char* section, const char* key);
void DebugLog(const wchar_t* msg);

// UTF-8 -> UTF-16 conversion helpers. IMPORTANT: when using MultiByteToWideChar
// with a null-terminated source (cbMultiByte=-1), the returned size *includes*
// the terminating NUL. The output buffer passed to the second call must be at
// least that many wchar_t -- not one fewer. Getting this wrong causes a one-wchar
// heap overflow that shows up as random REAPER crashes on longer paths/names.
std::wstring Utf8ToWide(const char* utf8);
std::wstring Utf8ToWide(const char* utf8, size_t byte_len);

// Bundle of cached REAPER API function pointers. Returned by Api(). All
// pointers may be nullptr if InitPluginApi() failed or the host is too old.
struct ApiTable {
  // Forward-declared opaque types from reaper_plugin_functions.h. We do not
  // pull that monster header into our normal sources; we just keep the
  // pointers and let users pass void* to them. The actual function signatures
  // below use void* for ReaProject / MediaItem / MediaItem_Take / PCM_source
  // to stay free of the implementation header dependency.

  // Selection / item / take introspection.
  int (*CountSelectedMediaItems)(void* proj) = nullptr;
  void* (*GetSelectedMediaItem)(void* proj, int selitem) = nullptr;
  void* (*GetActiveTake)(void* item) = nullptr;
  void (*SetActiveTake)(void* item, void* take) = nullptr;
  void* (*GetMediaItemTake_Source)(void* take) = nullptr;
  void (*GetMediaSourceFileName)(void* source, char* buf, int bufsz) = nullptr;
  bool (*GetSetMediaItemTakeInfo_String)(void* take, const char* parmname,
                                         char* str_need_big, bool set_new_value) = nullptr;
  bool (*GetSetMediaItemInfo_String)(void* item, const char* parmname,
                                     char* str_need_big, bool set_new_value) = nullptr;
  void* (*GetSetMediaItemInfo)(void* item, const char* parmname, void* set_new_value) = nullptr;
  const char* (*GetTakeName)(void* take) = nullptr;
  double (*GetMediaItemInfo_Value)(void* item, const char* parmname) = nullptr;
  double (*GetMediaItemTakeInfo_Value)(void* take, const char* parmname) = nullptr;
  bool (*SetMediaItemInfo_Value)(void* item, const char* parmname, double newvalue) = nullptr;
  bool (*SetMediaItemTakeInfo_Value)(void* take, const char* parmname, double newvalue) = nullptr;
  int (*CountMediaItems)(void* proj) = nullptr;
  void* (*GetMediaItem)(void* proj, int itemidx) = nullptr;
  // guidToString writes "{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}" (incl. braces)
  // plus a trailing NUL into the user buffer; needs at least 64 bytes to be
  // safe across REAPER versions.
  void (*guidToString)(const void* g, char* destNeed64) = nullptr;

  // Projects.
  void* (*EnumProjects)(int idx, char* projfn_out_opt, int projfn_out_opt_sz) = nullptr;
  int (*GetProjExtState)(void* proj, const char* extname, const char* key,
                         char* val_out_need_big, int val_out_need_big_sz) = nullptr;
  int (*SetProjExtState)(void* proj, const char* extname, const char* key, const char* value) = nullptr;
  void (*MarkProjectDirty)(void* proj) = nullptr;
  int (*GetProjectStateChangeCount)(void* proj) = nullptr;

  // Commands / undo / pointer validation.
  void (*Main_OnCommand)(int command, int flag) = nullptr;
  int (*NamedCommandLookup)(const char* command_name) = nullptr;
  void (*Undo_BeginBlock2)(void* proj) = nullptr;
  void (*Undo_EndBlock2)(void* proj, const char* descchange, int extraflags) = nullptr;
  bool (*ValidatePtr2)(void* proj, void* pointer, const char* ctypename) = nullptr;
  void (*UpdateArrange)() = nullptr;
  void (*PreventUIRefresh)(int prevent_count) = nullptr;
  HWND (*GetMainHwnd)() = nullptr;
  void (*SetExtState)(const char* section, const char* key, const char* value, bool persist) = nullptr;

  // Item Hub: envelopes + tracks
  void* (*GetMediaItemTrack)(void* item) = nullptr;
  int (*CountTakeEnvelopes)(void* take) = nullptr;
  void* (*GetTakeEnvelope)(void* take, int idx) = nullptr;
  void* (*GetTakeEnvelopeByName)(void* take, const char* envname) = nullptr;
  double (*GetEnvelopeInfo_Value)(void* envelope, const char* parmname) = nullptr;
  bool (*SetEnvelopeInfo_Value)(void* envelope, const char* parmname, double value) = nullptr;
  int (*CountAutomationItems)(void* envelope) = nullptr;
  int (*CountEnvelopePoints)(void* envelope) = nullptr;
  int (*CountEnvelopePointsEx)(void* envelope, int autoitem_idx) = nullptr;
  bool (*GetEnvelopePoint)(void* envelope, int ptidx, double* timeOut, double* valueOut,
                           int* shapeOut, double* tensionOut, bool* selectedOut) = nullptr;
  bool (*GetEnvelopePointEx)(void* envelope, int autoitem_idx, int ptidx, double* timeOut,
                             double* valueOut, int* shapeOut, double* tensionOut,
                             bool* selectedOut) = nullptr;
  bool (*SetEnvelopePoint)(void* envelope, int ptidx, double* timeInOptional,
                           double* valueInOptional, int* shapeInOptional,
                           double* tensionInOptional, bool* selectedInOptional,
                           bool* noSortInOptional) = nullptr;
  bool (*SetEnvelopePointEx)(void* envelope, int autoitem_idx, int ptidx,
                             double* timeInOptional, double* valueInOptional,
                             int* shapeInOptional, double* tensionInOptional,
                             bool* selectedInOptional, bool* noSortInOptional) = nullptr;
  bool (*InsertEnvelopePoint)(void* envelope, double time, double value, int shape, int tension,
                              bool selected, bool* noSortInOut) = nullptr;
  int (*GetEnvelopeScalingMode)(void* envelope) = nullptr;

  // Item Hub: PCM source / reverse (native + optional SWS)
  void* (*GetSetMediaItemTakeInfo)(void* take, const char* parmname, void* set_new_value) = nullptr;
  void (*GetMediaSourceType)(void* source, char* typebuf, int typebuf_sz) = nullptr;
  double (*GetMediaSourceLength)(void* source, bool* lengthIsQNOut) = nullptr;
  void* (*GetMediaSourceParent)(void* source) = nullptr;
  bool (*PCM_Source_GetSectionInfo)(void* src, double* offsOut, double* lenOut, bool* revOut) =
      nullptr;
  void* (*PCM_Source_CreateFromType)(const char* sourcetype) = nullptr;
  void (*PCM_Source_Destroy)(void* src) = nullptr;
  bool (*BR_GetMediaSourceProperties)(void* take, bool* sectionOut, double* startOut,
                                      double* lengthOut, double* fadeOut, bool* reverseOut) =
      nullptr;
  bool (*BR_SetMediaSourceProperties)(void* take, bool section, double start, double length,
                                      double fade, bool reverse) = nullptr;
  bool (*CF_PCM_Source_SetSectionInfo)(void* section, void* source, double offset, double length,
                                       bool reverse, double* fadeInOptional) = nullptr;
};

// Returns the cached function pointer table. Always non-null; individual
// members may still be nullptr if a given REAPER build did not expose them.
const ApiTable& Api();

}  // namespace lee
