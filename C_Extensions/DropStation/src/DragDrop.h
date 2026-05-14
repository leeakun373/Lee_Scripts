#pragma once

#include <windows.h>

#include <string>

// Builds CF_HDROP (Unicode) in a moveable HGLOBAL. Returns nullptr on failure.
HGLOBAL CreateHDropFromPaths(const wchar_t* const* paths, size_t pathCount);

// Runs DoDragDrop for file copy. Returns HRESULT from DoDragDrop or earlier failure.
// Safe to call from the REAPER main/UI thread only (DoDragDrop runs a modal loop).
HRESULT RunOsFileDragDrop(HWND ownerGuess, HGLOBAL hDrop);
