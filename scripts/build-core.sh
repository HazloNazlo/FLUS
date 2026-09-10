#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME:-/home/user/android-sdk}/ndk/27.0.12077973}"
case "$(uname -s)" in
 Linux) HOST=linux-x86_64 ;;
 Darwin) HOST=darwin-x86_64 ;;
 *) echo 'Run on Linux/macOS (or GitHub Actions)' >&2; exit 1 ;;
esac
export GOOS=android GOARCH=arm64 CGO_ENABLED=1
export CC="$NDK/toolchains/llvm/prebuilt/$HOST/bin/aarch64-linux-android26-clang"
export CXX="$NDK/toolchains/llvm/prebuilt/$HOST/bin/aarch64-linux-android26-clang++"
export CGO_LDFLAGS='-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384'
export GOTOOLCHAIN=local
command -v go >/dev/null || { echo 'Go 1.27.1 required in PATH'; exit 1; }
[[ -x "$CC" ]] || { echo 'Android NDK 27.0.12077973 missing'; exit 1; }
OUT="$ROOT/android/app/src/main/jniLibs/arm64-v8a/libopenflux.so"
mkdir -p "$(dirname "$OUT")"
cd "$ROOT/vendor"
go mod download
go mod verify
go build -mod=readonly -p 2 -trimpath -buildvcs=false -buildmode=pie \
  -ldflags="-s -w -checklinkname=0 -linkmode external -extldflags '-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384'" \
  -o "$OUT" .
chmod 755 "$OUT"
file "$OUT"
"$NDK/toolchains/llvm/prebuilt/$HOST/bin/llvm-readelf" -l "$OUT" | grep -E 'LOAD|interpreter'
