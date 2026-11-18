#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$ROOT_DIR/rust"
APP_DIR="$ROOT_DIR/app"
DIST_DIR="$ROOT_DIR/dist"

export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
export PATH="${FLUTTER_HOME:+$FLUTTER_HOME/bin:}${JAVA_HOME:+$JAVA_HOME/bin:}$ANDROID_HOME/platform-tools:${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"

for tool in cargo rustup flutter java; do
  command -v "$tool" >/dev/null || { echo "Required tool not found: $tool" >&2; exit 1; }
done
rustup target add aarch64-linux-android x86_64-linux-android

NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
if [[ ! -d "$NDK_BIN" ]]; then
  echo "Android NDK toolchain not found at $NDK_BIN" >&2
  exit 1
fi

export CC_aarch64_linux_android="$NDK_BIN/aarch64-linux-android24-clang"
export AR_aarch64_linux_android="$NDK_BIN/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK_BIN/aarch64-linux-android24-clang"

export CC_x86_64_linux_android="$NDK_BIN/x86_64-linux-android24-clang"
export AR_x86_64_linux_android="$NDK_BIN/llvm-ar"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$NDK_BIN/x86_64-linux-android24-clang"

echo "[1/3] Building Rust core for Android (arm64-v8a & x86_64)..."
(cd "$RUST_DIR" && cargo build --locked --release --target aarch64-linux-android --target x86_64-linux-android)

JNI_DIR="$APP_DIR/android/app/src/main/jniLibs"
mkdir -p "$JNI_DIR/arm64-v8a" "$JNI_DIR/x86_64"
cp "$RUST_DIR/target/aarch64-linux-android/release/libstyleloom_core.so" "$JNI_DIR/arm64-v8a/libstyleloom_core.so"
cp "$RUST_DIR/target/x86_64-linux-android/release/libstyleloom_core.so" "$JNI_DIR/x86_64/libstyleloom_core.so"

echo "[2/3] Building Android Release APK..."
(cd "$APP_DIR" && flutter pub get && flutter build apk --release --target-platform android-arm64,android-x64)

echo "[3/3] Copying APK to dist/..."
mkdir -p "$DIST_DIR"
cp "$APP_DIR/build/app/outputs/flutter-apk/app-release.apk" "$DIST_DIR/StyleLoom-android-release.apk"
ls -lh "$DIST_DIR/StyleLoom-android-release.apk"
