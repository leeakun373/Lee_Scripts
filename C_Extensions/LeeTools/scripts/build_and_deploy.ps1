#Requires -Version 5.0
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptDir
$IncludeDir = Join-Path $ProjectRoot "include"
$ThirdPartyDir = Join-Path $ProjectRoot "third_party"
$ReaImGuiDir = Join-Path $ThirdPartyDir "reaimgui"
$BuildDir = Join-Path $ProjectRoot "build"
$DeployDir = Join-Path $env:APPDATA "REAPER\UserPlugins"

# Pin the ReaImGui API header version. The runtime ReaImGui DLL may be newer
# (forward-compatible API). Bump cautiously if upstream changes signatures.
$ReaImGuiVersion = "v0.10.0.5"

Write-Host ("Project root: " + $ProjectRoot) -ForegroundColor Cyan

function Test-CMake {
    $cmake = Get-Command cmake -ErrorAction SilentlyContinue
    if (-not $cmake) {
        Write-Host "ERROR: cmake not found. Install CMake and add it to PATH." -ForegroundColor Red
        exit 1
    }
    Write-Host ("CMake: " + $cmake.Source) -ForegroundColor Green
}

function Ensure-ReaperHeaders {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Force -Path $IncludeDir | Out-Null
    $base = "https://raw.githubusercontent.com/justinfrankel/reaper-sdk/main/sdk"
    $names = @("reaper_plugin.h", "reaper_plugin_functions.h")
    foreach ($name in $names) {
        $dest = Join-Path $IncludeDir $name
        if (Test-Path -LiteralPath $dest) { continue }
        $url = "$base/$name"
        Write-Host ("Downloading " + $name + " ...") -ForegroundColor Yellow
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
}

function Ensure-ReaImGuiHeader {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Force -Path $ReaImGuiDir | Out-Null
    $dest = Join-Path $ReaImGuiDir "reaper_imgui_functions.h"
    if (Test-Path -LiteralPath $dest) {
        Write-Host ("ReaImGui header already present: " + $dest) -ForegroundColor Green
        return
    }
    $url = "https://github.com/cfillion/reaimgui/releases/download/$ReaImGuiVersion/reaper_imgui_functions.h"
    Write-Host ("Downloading reaper_imgui_functions.h (" + $ReaImGuiVersion + ") ...") -ForegroundColor Yellow
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    if (-not (Test-Path -LiteralPath $dest)) {
        throw "Failed to download reaper_imgui_functions.h"
    }
    Write-Host ("ReaImGui header ready: " + $dest) -ForegroundColor Green
}

function Find-BuiltDll {
    $candidates = @(
        (Join-Path $BuildDir "Release\reaper_lee_tools.dll"),
        (Join-Path $BuildDir "reaper_lee_tools.dll"),
        (Join-Path $BuildDir "bin\Release\reaper_lee_tools.dll"),
        (Join-Path $BuildDir "bin\reaper_lee_tools.dll")
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) {
            return $p
        }
    }
    return $null
}

Test-CMake
Ensure-ReaperHeaders
Ensure-ReaImGuiHeader

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
Push-Location $BuildDir
try {
    cmake $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw "cmake configure failed (exit $LASTEXITCODE)" }
    cmake --build . --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw "cmake build failed (exit $LASTEXITCODE)" }
}
finally {
    Pop-Location
}

$dll = Find-BuiltDll
if (-not $dll) {
    Write-Host "ERROR: reaper_lee_tools.dll not found under build/." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null
$target = Join-Path $DeployDir "reaper_lee_tools.dll"
Copy-Item -LiteralPath $dll -Destination $target -Force

# Drop the legacy Drop Station extension so both DLLs do not coexist.
$legacyDll = Join-Path $DeployDir "reaper_dropstation.dll"
if (Test-Path -LiteralPath $legacyDll) {
    Remove-Item -LiteralPath $legacyDll -Force
    Write-Host ("Removed legacy: " + $legacyDll) -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Deployed reaper_lee_tools.dll" -ForegroundColor Green
Write-Host (" DLL: " + $target) -ForegroundColor Green
Write-Host "Requires: ReaImGui extension (install via ReaPack)" -ForegroundColor Yellow
Write-Host "Restart REAPER and look for Lee_* actions in the Action List." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
