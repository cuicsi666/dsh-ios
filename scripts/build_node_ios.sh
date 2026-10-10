#!/bin/bash
# 交叉编译 Node.js (arm64) for iOS，产物落到 resources/node
set -e
cd "$(dirname "$0")/.."
mkdir -p resources
WORK=build_tmp
rm -rf "$WORK"
mkdir -p "$WORK"
LOG=/tmp/node_build.log
: > "$LOG"

if [ -z "${NODE_V:-}" ]; then
  NODE_V=$(curl -sL https://nodejs.org/dist/latest-v22.x/ \
    | grep -oE 'node-v22\.[0-9]+\.[0-9]+\.tar\.gz' | sort -uV | tail -1 \
    | sed 's/node-v//;s/\.tar\.gz//')
fi
echo "==> 使用 Node v$NODE_V"

echo "==> SDK 检查"
xcrun --sdk iphoneos --show-sdk-path >/dev/null
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

echo "==> 下载 Node v$NODE_V 源码"
(cd "$WORK" && curl -fsSL -o node.tar.gz "https://nodejs.org/dist/v$NODE_V/node-v$NODE_V.tar.gz" \
  && tar xzf node.tar.gz && mv "node-v$NODE_V" src)

cd "$WORK/src"
CC_BIN=$(xcrun --sdk iphoneos --find clang)
CXX_BIN=$(xcrun --sdk iphoneos --find clang++)
CCFLAGS="-arch arm64 -isysroot $SDK -mios-version-min=15.0"
export CC="$CC_BIN $CCFLAGS"
export CXX="$CXX_BIN $CCFLAGS"
export CPP="$CC_BIN $CCFLAGS -E"
export AR=$(command -v ar)
export STRIP=$(xcrun --sdk iphoneos --find strip)
export LDFLAGS="-arch arm64 -isysroot $SDK -mios-version-min=15.0"

echo "==> configure dest-os=ios dest-cpu=arm64"
if ! ./configure --without-npm --dest-cpu=arm64 --dest-os=ios \
      --prefix=/node --with-intl=none --cross-compiling \
      --openssl-no-asm \
      >>"$LOG" 2>&1; then
  echo "!! configure 失败，日志尾部："; tail -60 "$LOG"; exit 1
fi

echo "==> make (可能 10-20 分钟)"
if ! make -j8 >>"$LOG" 2>&1; then
  echo "!! make 失败，日志尾部："; tail -80 "$LOG"; exit 1
fi

cd ../..
if [ -x "$WORK/src/out/Release/node" ]; then
  cp "$WORK/src/out/Release/node" resources/node
elif [ -f /node/bin/node ]; then
  cp /node/bin/node resources/node
else
  echo "!! 未找到 node 产物"; exit 1
fi

chmod +x resources/node
echo "==> 签名 node 二进制 (ad-hoc)"
codesign --force -s - resources/node 2>/dev/null || true
ls -la resources/node
file resources/node