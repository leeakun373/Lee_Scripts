#pragma once

#include <windows.h>

// Windows CF_HDROP drag-out used by Drop Station list rows.
// Call from the REAPER main/UI thread only (DoDragDrop runs a modal loop).

HGLOBAL CreateHDropFromPaths(const wchar_t* const* paths, size_t pathCount);
HRESULT RunOsFileDragDrop(HWND ownerGuess, HGLOBAL hDrop);
