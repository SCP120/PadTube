#!/bin/bash
# OpenSSL as static libraries (from PadTerm's scripts/build_deps.sh, without libssh2) into third_party/prefix/:
#   ios-armv7    iOS 6.0 and later, theos iPhoneOS9.3-armv7 SDK (scripts/make_ios_sdk.sh)
#   ios-arm64    iOS 7.0 and later, theos iPhoneOS16.5 SDK (D48)
#   macos-arm64  the host tests
# PT_HOST_ONLY=1: only macos-arm64 (CI has no iOS SDK). A prefix that has libssl.a is kept; delete it to rebuild.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TP="$ROOT/third_party"
SRC="$TP/src/openssl"
W="$ROOT/build/deps"
JOBS="$(sysctl -n hw.ncpu)"
VER=3.5.9
# SHA-256 published by the project: openssl-3.5.9.tar.gz.sha256 on the GitHub release page.
SHA=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
URL="https://github.com/openssl/openssl/releases/download/openssl-$VER/openssl-$VER.tar.gz"
CLANG="$(xcrun --find clang)"

mkdir -p "$SRC" "$W"
TGZ="$SRC/openssl-$VER.tar.gz"
if [ ! -f "$TGZ" ] || [ "$(shasum -a 256 "$TGZ" | cut -d' ' -f1)" != "$SHA" ]; then curl -fL --retry 3 -o "$TGZ" "$URL"; fi
[ "$(shasum -a 256 "$TGZ" | cut -d' ' -f1)" = "$SHA" ] || { echo "SHA-256 mismatch: $TGZ" >&2; exit 1; }

build() { # name configure-target cflags [extra options]
  local name=$1 conf=$2 cflags=$3; shift 3
  local prefix="$TP/prefix/$name" b="$W/openssl-$name"
  if [ -f "$prefix/lib/libssl.a" ]; then echo "kept: $prefix"; return; fi
  rm -rf "$b" "$prefix"; mkdir -p "$b/src" "$prefix"
  tar -xzf "$TGZ" -C "$b/src"
  [ -z "${PATCH:-}" ] || patch -s -p1 -d "$b/src/openssl-$VER" < "$PATCH"
  ( cd "$b"
    CC="$CLANG" CFLAGS="$cflags" perl "$b/src/openssl-$VER/Configure" "$conf" \
      no-shared no-tests no-apps no-docs no-engine no-dso no-async no-ui-console ${1+"$@"} \
      --prefix=/padtube --openssldir=/padtube/ssl --libdir=lib >/dev/null
    # A shipped binary must not name this machine's folders: OpenSSL records its paths and its compiler flags.
    make crypto/buildinf.h >/dev/null
    printf '%s\n' '#define PLATFORM "platform: padtube"' '#define DATE "built on: release"' \
      'static const char compiler_flags[] = "compiler: clang";' > crypto/buildinf.h
    make -j"$JOBS" build_libs >/dev/null
    make DESTDIR="$b/stage" install_dev >/dev/null
    ditto "$b/stage/padtube" "$prefix" )
  echo "built: $prefix"
}

MAC_SDK="$(xcrun --sdk macosx --show-sdk-path)"
build macos-arm64 darwin64-arm64-cc "-isysroot $MAC_SDK"
[ -n "${PT_HOST_ONLY:-}" ] && exit 0

SDK7="$HOME/theos/sdks/iPhoneOS9.3-armv7.sdk"; SDK64="$HOME/theos/sdks/iPhoneOS16.5.sdk"
[ -d "$SDK7" ] && [ -d "$SDK64" ] || { echo "missing theos SDKs: see README, Build" >&2; exit 1; }
# armv7 (D65): -mno-thumb (ld-27037 writes code pointers without the Thumb bit), so the ARMv7 assembly builds its ARM
# variants. The patch (from the PadWeb project, see NOTICE) makes the ios32 perlasm output assemble with current clang:
# a data cell for OPENSSL_armcap_P, and poly1305 label offsets as data. -DBROKEN_CLANG_ATOMICS: else clang calls
# ___atomic_is_lock_free, which no iOS 6 library exports.
PATCH="$ROOT/scripts/patches/openssl-$VER-ios-armv7-asm.patch" \
  build ios-armv7 ios-xcrun "-mno-thumb -isysroot $SDK7 -miphoneos-version-min=6.0 -DBROKEN_CLANG_ATOMICS"
# gates: no Thumb code, and the assembly is in (grep -c, not grep -q: with pipefail, nm's SIGPIPE would fail the gate)
A7="$TP/prefix/ios-armv7/lib"
thumb=$(nm -m "$A7/libcrypto.a" "$A7/libssl.a" 2>/dev/null | grep -c '\[Thumb\]' || true)
[ "$thumb" = 0 ] || { echo "ios-armv7: $thumb Thumb symbols" >&2; exit 1; }
for s in _sha256_block_data_order _ossl_bsaes_ctr32_encrypt_blocks _gcm_ghash_neon _ChaCha20_ctr32 _poly1305_blocks \
         _bn_mul_mont _ecp_nistz256_mul_mont; do
  [ "$(nm "$A7/libcrypto.a" 2>/dev/null | grep -c " T $s\$" || true)" -ge 1 ] || { echo "ios-armv7: no $s (an old no-asm prefix? delete it to rebuild)" >&2; exit 1; }
done
build ios-arm64 ios64-xcrun "-arch arm64 -isysroot $SDK64 -miphoneos-version-min=7.0"
