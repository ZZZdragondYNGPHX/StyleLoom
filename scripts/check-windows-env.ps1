$ErrorActionPreference = "Stop"

function Require-Command($Name, $Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Error "Missing '$Name'. $Hint"
    }
}

Require-Command "cargo" "Install Rust (msvc toolchain) via https://rustup.rs"
Require-Command "rustc" "Install Rust (msvc toolchain) via https://rustup.rs"
Require-Command "flutter" "Install Flutter Windows SDK and add flutter\bin to PATH"

$RustHost = (rustc -vV | Select-String "host:").ToString()
Write-Host "Rust: $RustHost"

$FlutterDoctor = flutter doctor -v | Out-String
if ($FlutterDoctor -notmatch "Visual Studio") {
    Write-Warning "Flutter doctor did not report Visual Studio Desktop C++ workload. If Windows build fails, install 'Desktop development with C++' in Visual Studio Installer."
} else {
    Write-Host "Visual Studio C++ toolchain detected." -ForegroundColor Green
}
