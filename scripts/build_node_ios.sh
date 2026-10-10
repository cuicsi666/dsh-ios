#!/bin/bash
# 交叉编译 Node.js (arm64) for iOS，产物落到 resources/node
# 优先从源码交叉编译 v22；失败则回退 nodejs-mobile 预构建 iOS node。
set -e
cd "$(dirname "$0")/.."
mkdir -p resources
NODE_V=${NODE_V:-22.22.0}
WORK=build_tmp
rm -rf "$WORK"
mkdir -p "$WORK"

echo "==> SDK 检查"
xcrun --sdk iphoneos --show-sdk-path >/dev/null
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

try_source_build() {
  echo "==> 下载 Node v$NODE_V 源码"
  (cd "$WORK" && curl -fsSL -o node.tar.gz "https://nodejs.org/dist/v$NODE_V/node-v$NODE_V.tar.gz" \
     && tar xzf node.tar.gz && mv "node-v$NODE_V" src)
  cd "$WORK/src"
  local CC="$(xcrun --sdk iphoneos --find clang)"
  local CXX="$(xcrun --sdk iphoneos --find clang++)"
  export CC="$CC -arch arm64 -isysroot $SDK -mios-version-min=15.0"
  export CXX="$CXX -arch arm64 -isysroot $SDK -mios-version-min=15.0"
  export CPP="$CC -E"
  export AR=$(command -v ar)
  export STRIP=$(xcrun --sdk iphoneos --find strip)
  export LDFLAGS="-arch arm64 -isysroot $SDK -mios-version-min=15.0"
  echo "==> configure dest-os=ios dest-cpu=arm64"
  ./configure --without-npm \
    --dest-cpu=arm64 --dest-os=ios \
    --prefix=/node --with-intl=none \
    --cross-compiling >>/tmp/node_build.log 2>&1 || return 1
  echo "==> make (可较慢)"
  make -j8 >>/tmp/node_build.log 2>&1 || return 1
  make install >>/tmp/node_build.log 2>&1 || return 1
  cd ../..
  if [ -x "$WORK/src/out/Release/node" ]; then
    cp "$WORK/src/out/Release/node" resources/node
  elif [ -f /node/bin/node ]; then
    cp /node/bin/node resources/node
  else
    return 1
  fi
  return 0
}

try_nodejs_mobile() {
  echo "==> 回退：拉 nodejs-mobile 预构建 iOS node"
  local rel="$(curl -fsSL https://api.github.com/repos/janeasystems/nodejs-mobile/releases/latest \
     | python3 -c "import json,sys;print(json.load(sys.stdin)['tag_name'])")"
  echo "    release: $rel"
  curl -fsSL -o nm.tgz "https://github.com/janeasystems/nodejs-mobile/releases/download/$rel/nodejs-mobile-v${rel#v}-ios-xcframework.tgz" \
    || curl -fsSL -o nm.tgz "https://github.com/janeasystems/nodejs-mobile/releases/download/$rel/nodejs-mobile-v${rel#v}-ios-macos.tgz"
  tar tzf nm.tgz | head
}

if try_source_build; then
  echo "==> Node for iOS 源码编译成功"
else
  echo "==> 源码编译失败，尝试 nodejs-mobile"
  try_nodejs_mobile
fi

chmod +x resources/node 2>/dev/null || true
echo "==> 签名 node 二进制 (ad-hoc)"
codesign --force -s - resources/node 2>/dev/null || true
ls -la resources/node
file resources/node