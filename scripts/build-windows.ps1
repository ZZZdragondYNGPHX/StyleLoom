$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$RustDir = Join-Path $RootDir "rust"
$AppDir  = Join-Path $RootDir "app"
$DistDir = Join-Path $RootDir "dist\StyleLoom-windows-x64"

Write-Host "[1/3] Building Rust core (styleloom_core.dll)..." -ForegroundColor Cyan
Push-Location $RustDir
try {
    cargo build --locked --release
    if ($LASTEXITCODE -ne 0) { throw "Rust build failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
}

Write-Host "[2/3] Building Flutter Windows Release..." -ForegroundColor Cyan
Push-Location $AppDir
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "Flutter dependency resolution failed ($LASTEXITCODE)" }
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Flutter Windows build failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
}

Write-Host "[3/3] Staging portable Windows bundle to $DistDir..." -ForegroundColor Cyan
$BuildOut = Join-Path $AppDir "build\windows\x64\runner\Release"
if (-not (Test-Path $BuildOut)) {
    $BuildOut = Join-Path $AppDir "build\windows\runner\Release"
}
if (Test-Path $DistDir) {
    Remove-Item -Recurse -Force $DistDir
}
New-Item -ItemType Directory -Path $DistDir | Out-Null
Copy-Item -Recurse -Force (Join-Path $BuildOut "*") $DistDir

$DllPath = Join-Path $RustDir "target\release\styleloom_core.dll"
if (-not (Test-Path (Join-Path $DistDir "styleloom_core.dll")) -and (Test-Path $DllPath)) {
    Copy-Item -Force $DllPath $DistDir
}

Write-Host "Build complete! Launch: $(Join-Path $DistDir 'styleloom_app.exe')" -ForegroundColor Green
Compress-Archive -Path (Join-Path $DistDir "*") -DestinationPath (Join-Path $RootDir "dist\StyleLoom-windows-x64.zip") -Force
