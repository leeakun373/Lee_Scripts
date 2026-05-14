#Requires -Version 5.0
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptDir
$IncludeDir = Join-Path $ProjectRoot "include"
$BuildDir = Join-Path $ProjectRoot "build"
$DeployDir = Join-Path $env:APPDATA "REAPER\UserPlugins"

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
        $url = "$base/$name"
        Write-Host ("Downloading " + $name + " ...") -ForegroundColor Yellow
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
}

function Find-BuiltDll {
    $candidates = @(
        (Join-Path $BuildDir "Release\reaper_dropstation.dll"),
        (Join-Path $BuildDir "reaper_dropstation.dll"),
        (Join-Path $BuildDir "bin\Release\reaper_dropstation.dll"),
        (Join-Path $BuildDir "bin\reaper_dropstation.dll")
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
    Write-Host "ERROR: reaper_dropstation.dll not found under build/." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null
$target = Join-Path $DeployDir "reaper_dropstation.dll"
Copy-Item -LiteralPath $dll -Destination $target -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "部署完成！请重启 REAPER，在 Action List 中搜索 Lee_StartOSDragDrop" -ForegroundColor Green
Write-Host (" DLL: " + $target) -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
