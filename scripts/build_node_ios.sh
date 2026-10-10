#!/bin/bash
# 交叉编译 Node.js (arm64) for iOS，产物落到 resources/node
# 优先 v22（可配 NODE_V），失败自动回退 NODE_V_FALLBACK（默认 v20.19.0，老 node_crypto 无 ncrypto 坑）
set -e
cd "$(dirname "$0")/.."
mkdir -p resources
WORK=build_tmp
LOG=/tmp/node_build.log

try_build() {
  local V="$1"
  rm -rf "$WORK"; mkdir -p "$WORK"; : > "$LOG"
  echo "===== 尝试 Node v$V ====="
  echo "==> SDK 检查"
  xcrun --sdk iphoneos --show-sdk-path >/dev/null
  local SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  echo "==> 下载 Node v$V 源码"
  (cd "$WORK" && curl -fsSL -o node.tar.gz "https://nodejs.org/dist/v$V/node-v$V.tar.gz" \
    && tar xzf node.tar.gz && mv "node-v$V" src)
  cd "$WORK/src"
  local CC_BIN=$(xcrun --sdk iphoneos --find clang)
  local CXX_BIN=$(xcrun --sdk iphoneos --find clang++)
  local ARCH_FLAGS="-arch arm64 -isysroot $SDK -mios-version-min=15.0"
  export CC="$CC_BIN $ARCH_FLAGS"
  export CXX="$CXX_BIN $ARCH_FLAGS"
  export CPP="$CC_BIN $ARCH_FLAGS -E"
  export CFLAGS="$ARCH_FLAGS -Wno-deprecated-declarations -Wno-deprecated"
  export CXXFLAGS="-std=c++20 -Wno-deprecated-declarations -Wno-deprecated"
  export AR=$(command -v ar)
  export STRIP=$(xcrun --sdk iphoneos --find strip)
  export LDFLAGS="$ARCH_FLAGS"
  echo "==> configure dest-os=ios dest-cpu=arm64 (--openssl-no-asm)"
  if ! ./configure --without-npm --dest-cpu=arm64 --dest-os=ios \
        --prefix=/node --with-intl=none --cross-compiling \
        --openssl-no-asm >>"$LOG" 2>&1; then
    echo "!! configure 失败，日志尾部："; tail -100 "$LOG"; return 1
  fi
  echo "==> make node (仅主程序)"
  if ! make -j8 node >>"$LOG" 2>&1; then
    echo "!! make 失败，日志尾部："; tail -400 "$LOG"; return 1
  fi
  cd ../..
  local BIN=""
  [ -x "$WORK/src/out/Release/node" ] && BIN="$WORK/src/out/Release/node"
  [ -z "$BIN" ] && [ -f /node/bin/node ] && BIN=/node/bin/node
  if [ -z "$BIN" ]; then echo "!! 未找到 node 产物"; return 1; fi
  cp "$BIN" resources/node
  chmod +x resources/node
  echo "==> ✅ Node v$V 编译成功"
  ls -la resources/node
  file resources/node
  return 0
}

NODE_V=${NODE_V:-22.23.3}
if ! try_build "$NODE_V"; then
  FALLBACK=${NODE_V_FALLBACK:-20.19.0}
  echo "===== v$NODE_V 失败，自动回退 v$FALLBACK ====="
  if ! try_build "$FALLBACK"; then
    echo "!! v$FALLBACK 也失败，放弃"
    exit 1
  fi
fi

echo "==> 签名 node 二进制 (ad-hoc)"
codesign --force -s - resources/node 2>/dev/null || true