#!/bin/bash
# 交叉编译 Node.js (arm64) for iOS —— ninja 配方（2022 验证过的思路 + v22 官方 ios 支持）
# 关键：CC_host/CXX_host 给 mac 原生工具链；--ninja 让 CXXFLAGS 进入构建规则；
#       --without-snapshot 跳过 mksnapshot host 执行问题；GYP_DEFINES 显式声明 ios。
set -e
cd "$(dirname "$0")/.."
mkdir -p resources
WORK=build_tmp
LOG=/tmp/node_build.log

try_build() {
  local V="$1"
  rm -rf "$WORK"; mkdir -p "$WORK"; : > "$LOG"
  echo "===== 尝试 Node v$V（ninja 配方）====="
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  echo "SDK: $SDK"
  echo "==> 下载源码"
  (cd "$WORK" && curl -fsSL -o node.tar.gz "https://nodejs.org/dist/v$V/node-v$V.tar.gz" \
    && tar xzf node.tar.gz && mv "node-v$V" src)
  cd "$WORK/src"

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
  export CXXFLAGS="-std=c++17 -O -arch arm64 -isysroot $SDK -mios-version-min=15.0 -Wno-deprecated-declarations"
  export LDFLAGS="-O -arch arm64 -isysroot $SDK -mios-version-min=15.0"
  export CFLAGS_host="-O"
  export CXXFLAGS_host="-std=c++17 -O"
  export GYP_DEFINES="target_arch=arm64 v8_target_arch=arm64 ios_target_arch=arm64 host_os=mac OS=ios"

  echo "==> configure (ninja / dest-os=ios / without-snapshot / openssl-no-asm)"
  if ! ./configure --ninja --dest-cpu=arm64 --dest-os=ios \
        --without-snapshot --openssl-no-asm --with-intl=none \
        --cross-compiling --without-npm >>"$LOG" 2>&1; then
    echo "!! configure 失败，日志尾部："; tail -80 "$LOG"; return 1
  fi

  echo "==> ninja build node (可 10-20 分钟)"
  if ! ninja -C out/Release -w dupbuild=warn node >>"$LOG" 2>&1; then
    echo "!! ninja 失败，日志尾部："; tail -400 "$LOG"; return 1
  fi

  cd ../..
  if [ ! -x "$WORK/src/out/Release/node" ]; then
    echo "!! 未找到 node 产物"; return 1
  fi
  cp "$WORK/src/out/Release/node" resources/node
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