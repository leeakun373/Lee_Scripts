#include "platform/win/OsFileDrag.h"

#include <objidl.h>
#include <shellapi.h>
#include <shlobj.h>

#include <cstring>
#include <new>
#include <utility>
#include <vector>

namespace {

constexpr DWORD kDropEffect = DROPEFFECT_COPY;

static UINT g_cfPreferredDropEffect = 0;
static UINT g_cfPerformedDropEffect = 0;

static void EnsureShellClipboardFormats() {
  if (g_cfPreferredDropEffect == 0) {
    g_cfPreferredDropEffect = RegisterClipboardFormat(CFSTR_PREFERREDDROPEFFECT);
  }
  if (g_cfPerformedDropEffect == 0) {
    g_cfPerformedDropEffect = RegisterClipboardFormat(CFSTR_PERFORMEDDROPEFFECT);
  }
}

struct OleInitScope {
  HRESULT hr = E_FAIL;
  bool shouldUninit = false;

  HRESULT tryInit() {
    hr = OleInitialize(nullptr);
    if (hr == S_OK) {
      shouldUninit = true;
      return S_OK;
    }
    if (hr == S_FALSE) {
      // Already initialized for this thread: OleUninitialize balances our call.
      shouldUninit = true;
      return S_OK;
    }
    // RPC_E_CHANGED_MODE: COM was initialized with a different concurrency model.
    // Do not call OleUninitialize; assume COM is usable for OLE drag/drop.
    if (hr == RPC_E_CHANGED_MODE) {
      shouldUninit = false;
      return S_OK;
    }
    return hr;
  }

  ~OleInitScope() {
    if (shouldUninit) {
      OleUninitialize();
    }
  }
};

class FmtEnumerator final : public IEnumFORMATETC {
 public:
  explicit FmtEnumerator(std::vector<FORMATETC> fmts) : ref_(1), fmts_(std::move(fmts)), index_(0) {}

  // IUnknown
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) override {
    if (!ppvObject) {
      return E_POINTER;
    }
    *ppvObject = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IEnumFORMATETC)) {
      *ppvObject = static_cast<IEnumFORMATETC*>(this);
      AddRef();
      return S_OK;
    }
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return static_cast<ULONG>(InterlockedIncrement(&ref_)); }

  ULONG STDMETHODCALLTYPE Release() override {
    const LONG n = InterlockedDecrement(&ref_);
    if (n == 0) {
      delete this;
    }
    return static_cast<ULONG>(n);
  }

  // IEnumFORMATETC
  HRESULT STDMETHODCALLTYPE Next(ULONG celt, FORMATETC* rgelt, ULONG* pceltFetched) override {
    if (!rgelt) {
      return E_POINTER;
    }
    if (celt != 1 && !pceltFetched) {
      return E_INVALIDARG;
    }
    ULONG fetched = 0;
    while (fetched < celt && static_cast<size_t>(index_) < fmts_.size()) {
      rgelt[fetched] = fmts_[static_cast<size_t>(index_)];
      ++fetched;
      ++index_;
    }
    if (pceltFetched) {
      *pceltFetched = fetched;
    }
    return fetched == celt ? S_OK : S_FALSE;
  }

  HRESULT STDMETHODCALLTYPE Skip(ULONG celt) override {
    index_ += static_cast<int>(celt);
    if (static_cast<size_t>(index_) > fmts_.size()) {
      index_ = static_cast<int>(fmts_.size());
      return S_FALSE;
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Reset() override {
    index_ = 0;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Clone(IEnumFORMATETC** ppenum) override {
    if (!ppenum) {
      return E_POINTER;
    }
    auto* e = new (std::nothrow) FmtEnumerator(fmts_);
    if (!e) {
      return E_OUTOFMEMORY;
    }
    e->index_ = index_;
    *ppenum = e;
    return S_OK;
  }

 private:
  LONG ref_;
  std::vector<FORMATETC> fmts_;
  int index_;
};

class FileDragObject final : public IDataObject, public IDropSource {
 public:
  explicit FileDragObject(HGLOBAL ownedHDrop) : ref_(1), hdrop_(ownedHDrop) {
    EnsureShellClipboardFormats();
    ZeroMemory(&feHdrop_, sizeof(feHdrop_));
    feHdrop_.cfFormat = CF_HDROP;
    feHdrop_.ptd = nullptr;
    feHdrop_.dwAspect = DVASPECT_CONTENT;
    feHdrop_.lindex = -1;
    feHdrop_.tymed = TYMED_HGLOBAL;

    ZeroMemory(&fePreferred_, sizeof(fePreferred_));
    fePreferred_.cfFormat = static_cast<CLIPFORMAT>(g_cfPreferredDropEffect);
    fePreferred_.ptd = nullptr;
    fePreferred_.dwAspect = DVASPECT_CONTENT;
    fePreferred_.lindex = -1;
    fePreferred_.tymed = TYMED_HGLOBAL;
  }

  FileDragObject(const FileDragObject&) = delete;
  FileDragObject& operator=(const FileDragObject&) = delete;

  // IUnknown
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppvObject) override {
    if (!ppvObject) {
      return E_POINTER;
    }
    *ppvObject = nullptr;
    if (IsEqualIID(riid, IID_IUnknown)) {
      *ppvObject = static_cast<IUnknown*>(static_cast<IDataObject*>(this));
    } else if (IsEqualIID(riid, IID_IDataObject)) {
      *ppvObject = static_cast<IDataObject*>(this);
    } else if (IsEqualIID(riid, IID_IDropSource)) {
      *ppvObject = static_cast<IDropSource*>(this);
    } else {
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return static_cast<ULONG>(InterlockedIncrement(&ref_)); }

  ULONG STDMETHODCALLTYPE Release() override {
    const LONG n = InterlockedDecrement(&ref_);
    if (n == 0) {
      delete this;
    }
    return static_cast<ULONG>(n);
  }

  // IDataObject
  HRESULT STDMETHODCALLTYPE GetData(FORMATETC* pformatetcIn, STGMEDIUM* pmedium) override {
    if (!pformatetcIn || !pmedium) {
      return E_POINTER;
    }
    ZeroMemory(pmedium, sizeof(*pmedium));

    if (pformatetcIn->dwAspect != DVASPECT_CONTENT) {
      return DV_E_DVASPECT;
    }
    if (pformatetcIn->lindex != -1) {
      return DV_E_LINDEX;
    }

    if (pformatetcIn->cfFormat == static_cast<CLIPFORMAT>(g_cfPreferredDropEffect) &&
        (pformatetcIn->tymed & TYMED_HGLOBAL)) {
      HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
      if (!h) {
        return E_OUTOFMEMORY;
      }
      void* p = GlobalLock(h);
      if (!p) {
        GlobalFree(h);
        return E_OUTOFMEMORY;
      }
      *static_cast<DWORD*>(p) = kDropEffect;
      GlobalUnlock(h);
      pmedium->tymed = TYMED_HGLOBAL;
      pmedium->hGlobal = h;
      pmedium->pUnkForRelease = nullptr;
      return S_OK;
    }

    if (pformatetcIn->cfFormat != CF_HDROP || !(pformatetcIn->tymed & TYMED_HGLOBAL)) {
      return DV_E_FORMATETC;
    }
    const SIZE_T bytes = GlobalSize(hdrop_);
    if (bytes == 0) {
      return STG_E_MEDIUMFULL;
    }
    void* src = GlobalLock(hdrop_);
    if (!src) {
      return E_OUTOFMEMORY;
    }
    HGLOBAL dup = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (!dup) {
      GlobalUnlock(hdrop_);
      return E_OUTOFMEMORY;
    }
    void* dst = GlobalLock(dup);
    if (!dst) {
      GlobalFree(dup);
      GlobalUnlock(hdrop_);
      return E_OUTOFMEMORY;
    }
    memcpy(dst, src, bytes);
    GlobalUnlock(dup);
    GlobalUnlock(hdrop_);
    pmedium->tymed = TYMED_HGLOBAL;
    pmedium->hGlobal = dup;
    pmedium->pUnkForRelease = nullptr;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override { return DV_E_FORMATETC; }

  HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* pformatetc) override {
    if (!pformatetc) {
      return E_POINTER;
    }
    if (pformatetc->dwAspect != DVASPECT_CONTENT || pformatetc->lindex != -1) {
      return DV_E_FORMATETC;
    }
    if (pformatetc->cfFormat == static_cast<CLIPFORMAT>(g_cfPreferredDropEffect) &&
        (pformatetc->tymed & TYMED_HGLOBAL)) {
      return S_OK;
    }
    if (pformatetc->cfFormat == CF_HDROP && (pformatetc->tymed & TYMED_HGLOBAL)) {
      return S_OK;
    }
    return DV_E_FORMATETC;
  }

  HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*, FORMATETC* pformatetcOut) override {
    if (pformatetcOut) {
      pformatetcOut->ptd = nullptr;
    }
    return E_NOTIMPL;
  }

  HRESULT STDMETHODCALLTYPE SetData(FORMATETC* pformatetc, STGMEDIUM* pmedium, BOOL fRelease) override {
    if (!pformatetc) {
      return E_POINTER;
    }
    // Targets often write "Performed DropEffect" back; accept so negotiation completes.
    if (pformatetc->cfFormat == static_cast<CLIPFORMAT>(g_cfPerformedDropEffect)) {
      if (pmedium && fRelease) {
        ReleaseStgMedium(pmedium);
      }
      return S_OK;
    }
    return DV_E_FORMATETC;
  }

  HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD dwDirection, IEnumFORMATETC** ppenumFormatEtc) override {
    if (!ppenumFormatEtc) {
      return E_POINTER;
    }
    *ppenumFormatEtc = nullptr;
    if (dwDirection == DATADIR_GET) {
      std::vector<FORMATETC> fmts;
      fmts.push_back(feHdrop_);
      fmts.push_back(fePreferred_);
      auto* e = new (std::nothrow) FmtEnumerator(std::move(fmts));
      if (!e) {
        return E_OUTOFMEMORY;
      }
      *ppenumFormatEtc = e;
      return S_OK;
    }
    return E_NOTIMPL;
  }

  HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override { return OLE_E_ADVISENOTSUPPORTED; }

  HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override { return OLE_E_ADVISENOTSUPPORTED; }

  HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override { return OLE_E_ADVISENOTSUPPORTED; }

  // IDropSource
  HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL fEscapePressed, DWORD grfKeyState) override {
    if (fEscapePressed) {
      return DRAGDROP_S_CANCEL;
    }
    // Must signal drop when LMB goes up; otherwise OLE keeps "dragging" and targets never receive the file.
    if ((grfKeyState & MK_LBUTTON) == 0) {
      return DRAGDROP_S_DROP;
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override { return DRAGDROP_S_USEDEFAULTCURSORS; }

 private:
  ~FileDragObject() {
    if (hdrop_) {
      GlobalFree(hdrop_);
      hdrop_ = nullptr;
    }
  }

  LONG ref_;
  HGLOBAL hdrop_;
  FORMATETC feHdrop_;
  FORMATETC fePreferred_;
};

}  // namespace

HGLOBAL CreateHDropFromPaths(const wchar_t* const* paths, size_t pathCount) {
  if (!paths || pathCount == 0) {
    return nullptr;
  }
  SIZE_T listBytes = sizeof(wchar_t);  // final extra null
  for (size_t i = 0; i < pathCount; ++i) {
    if (!paths[i]) {
      return nullptr;
    }
    const SIZE_T n = wcslen(paths[i]);
    if (n == 0) {
      return nullptr;
    }
    listBytes += (n + 1) * sizeof(wchar_t);
  }
  const SIZE_T total = sizeof(DROPFILES) + listBytes;
  if (total < sizeof(DROPFILES)) {
    return nullptr;
  }
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, total);
  if (!h) {
    return nullptr;
  }
  void* p = GlobalLock(h);
  if (!p) {
    GlobalFree(h);
    return nullptr;
  }
  auto* df = static_cast<DROPFILES*>(p);
  df->pFiles = sizeof(DROPFILES);
  df->pt.x = 0;
  df->pt.y = 0;
  df->fNC = FALSE;
  df->fWide = TRUE;
  wchar_t* dest = reinterpret_cast<wchar_t*>(reinterpret_cast<unsigned char*>(df) + df->pFiles);
  wchar_t* end = reinterpret_cast<wchar_t*>(reinterpret_cast<unsigned char*>(df) + total);
  for (size_t i = 0; i < pathCount; ++i) {
    const errno_t e = wcscpy_s(dest, static_cast<size_t>(end - dest), paths[i]);
    if (e != 0) {
      GlobalUnlock(h);
      GlobalFree(h);
      return nullptr;
    }
    dest += wcslen(paths[i]) + 1;
  }
  *dest = L'\0';
  GlobalUnlock(h);
  return h;
}

HRESULT RunOsFileDragDrop(HWND ownerGuess, HGLOBAL hDrop) {
  UNREFERENCED_PARAMETER(ownerGuess);
  if (!hDrop) {
    return E_INVALIDARG;
  }

  OleInitScope ole;
  HRESULT hr = ole.tryInit();
  if (FAILED(hr)) {
    GlobalFree(hDrop);
    return hr;
  }

  FileDragObject* obj = new (std::nothrow) FileDragObject(hDrop);
  if (!obj) {
    GlobalFree(hDrop);
    return E_OUTOFMEMORY;
  }

  IDataObject* data = nullptr;
  IDropSource* src = nullptr;
  hr = obj->QueryInterface(IID_IDataObject, reinterpret_cast<void**>(&data));
  if (FAILED(hr)) {
    obj->Release();
    return hr;
  }
  hr = obj->QueryInterface(IID_IDropSource, reinterpret_cast<void**>(&src));
  if (FAILED(hr)) {
    data->Release();
    return hr;
  }
  obj->Release();

  DWORD effect = kDropEffect;
  hr = DoDragDrop(data, src, kDropEffect, &effect);

  src->Release();
  data->Release();
  return hr;
}
