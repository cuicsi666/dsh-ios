#!/bin/bash
# 交叉编译 Node.js (arm64) for iOS —— ninja 配方
# 主版本 v20.19.0（已实测 4255/4255 全量编译成功）；v22.23.3 作回退（host 工具需 C++20）
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
mkdir -p resources
WORK=build_tmp
LOG=/tmp/node_build.log

try_build() {
  local V="$1"
  rm -rf "$ROOT/$WORK"; mkdir -p "$ROOT/$WORK"; : > "$LOG"
  echo "===== 尝试 Node v$V（ninja 配方）====="
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  echo "SDK: $SDK"
  echo "==> 下载源码"
  (cd "$ROOT/$WORK" && curl -fsSL -o node.tar.gz "https://nodejs.org/dist/v$V/node-v$V.tar.gz" \
    && tar xzf node.tar.gz && mv "node-v$V" src)
  cd "$ROOT/$WORK/src"

  echo "==> iOS 补丁：cares 关 HAVE_SYS_RANDOM_H（iOS 无 sys/random.h，走 arc4random_buf）"
  sed -i '' 's/#define HAVE_SYS_RANDOM_H 1/\/\* #undef HAVE_SYS_RANDOM_H \*\//' deps/cares/config/darwin/ares_config.h \
    && grep -n "SYS_RANDOM" deps/cares/config/darwin/ares_config.h || true

  echo "==> iOS 补丁：zlib fdopen 宏与 _stdio.h 碰撞 → 头文件末尾追加 undef fdopen"
  for f in deps/zlib/zutil.h deps/v8/third_party/zlib/zutil.h \
           deps/zlib/gzguts.h deps/v8/third_party/zlib/gzguts.h \
           deps/v8/third_party/zlib/zconf.h deps/zlib/zconf.h; do
    [ -f "$f" ] && printf '\n#ifdef fdopen\n#undef fdopen\n#endif\n' >> "$f"
  done

  echo "==> iOS 补丁：crypto_context.cc 排除 macOS 专属 kSecTrustSettings 段"
  python3 -c "
p='src/crypto/crypto_context.cc'
s=open(p,encoding='utf-8').read()

old1='#ifdef __APPLE__\nTrustStatus IsTrustDictionaryTrustedForPolicy'
new1='#if defined(__APPLE__) && !defined(__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__)\nTrustStatus IsTrustDictionaryTrustedForPolicy'
assert old1 in s, '补丁1 未命中'
s=s.replace(old1,new1)

old2='''#ifdef __APPLE__
  ReadMacOSKeychainCertificates(&system_store_certs);
#endif
#ifdef _WIN32
  ReadWindowsCertificates(&system_store_certs);
#endif
#if !defined(__APPLE__) && !defined(_WIN32)
  GetOpenSSLSystemCertificates(&system_store_certs);
#endif'''
new2='''#if defined(__APPLE__) && !defined(__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__)
  ReadMacOSKeychainCertificates(&system_store_certs);
#elif !defined(_WIN32)
  GetOpenSSLSystemCertificates(&system_store_certs);
#endif'''
assert old2 in s, '补丁2 未命中'
s=s.replace(old2,new2)

open(p,'w',encoding='utf-8').write(s)
print('  crypto_context.cc ✅ (两块补丁)')
"

  echo "==> 设置工具链"
  export CC="$(xcrun -sdk iphoneos -find clang)"
  export CXX="$(xcrun -sdk iphoneos -find clang++)"
  export AR="$(xcrun -sdk iphoneos -find ar 2>/dev/null || command -v ar)"
  export LD="$(xcrun -sdk iphoneos -find ld 2>/dev/null || true)"
  export STRIP="$(xcrun -sdk iphoneos -find strip)"
  export RANLIB="$(xcrun -sdk iphoneos -find ranlib 2>/dev/null || command -v ranlib)"
  export CC_host="$(command -v clang)"
  export CXX_host="$(command -v clang++)"

  export CFLAGS="-O -arch arm64 -isysroot $SDK -mios-version-min=15.0 -Wno-deprecated-declarations"
  export CXXFLAGS="-std=c++20 -O -arch arm64 -isysroot $SDK -mios-version-min=15.0 -Wno-deprecated-declarations"
  export LDFLAGS="-O -arch arm64 -isysroot $SDK -mios-version-min=15.0"
  export CFLAGS_host="-O"
  export CXXFLAGS_host="-std=c++20 -O -Wno-deprecated-declarations"
  export GYP_DEFINES="target_arch=arm64 v8_target_arch=arm64 ios_target_arch=arm64 host_os=mac OS=ios"

  echo "==> configure (ninja / dest-os=ios / openssl-no-asm / intl=none)"
  if ! ./configure --ninja --dest-cpu=arm64 --dest-os=ios \
        --openssl-no-asm --with-intl=none \
        --cross-compiling --without-npm >>"$LOG" 2>&1; then
    echo "!! configure 失败，日志尾部："; tail -80 "$LOG"; return 1
  fi

  echo "==> ninja build node (可 30-90 分钟)"
  if ! ninja -C out/Release -w dupbuild=warn node >>"$LOG" 2>&1; then
    echo "!! ninja 失败，日志尾部："; tail -200 "$LOG"; return 1
  fi

  local BUILT="$ROOT/$WORK/src/out/Release/node"
  cd "$ROOT"
  echo "==> 检查产物: $BUILT"
  ls -la "$BUILT" || return 1
  if [ ! -x "$BUILT" ]; then echo "!! node 产物不可执行"; return 1; fi
  cp -f "$BUILT" "$ROOT/resources/node"
  chmod +x "$ROOT/resources/node"
  echo "==> ✅ Node v$V 编译成功"
  ls -la "$ROOT/resources/node"
  file "$ROOT/resources/node"
  return 0
}

NODE_V=${NODE_V:-20.19.0}
if ! try_build "$NODE_V"; then
  FALLBACK=${NODE_V_FALLBACK:-22.23.3}
  echo "===== v$NODE_V 失败，自动回退 v$FALLBACK ====="
  if ! try_build "$FALLBACK"; then
    echo "!! v$FALLBACK 也失败，放弃"
    exit 1
  fi
fi

echo "==> 签名 node 二进制 (ad-hoc)"
codesign --force -s - "$ROOT/resources/node" 2>/dev/null || true