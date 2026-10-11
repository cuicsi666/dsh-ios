#!/bin/bash
# xcodegen 生成工程 + xcodebuild 打 .app（无签名），然后把 dsh/node 注入 .app，手动 zip IPA
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild (iphoneos, 无签名)"
xcodebuild -project DashHarness.xcodeproj -scheme DashHarness -configuration Release \
  -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build

APP="$(find build -name "*.app" -type d | head -1)"
echo "==> app: $APP"
test -n "$APP"

echo "==> 注入 dsh / node 资源（避免 Xcode 资源同名冲突）"
mkdir -p "$APP/dsh" "$APP/node"
cp -R "$ROOT/resources/dsh/." "$APP/dsh/"
cp "$ROOT/resources/node" "$APP/node/node"
chmod +x "$APP/node/node"
du -sh "$APP"

echo "==> 手动打包 IPA"
rm -rf dist pack_tmp && mkdir -p pack_tmp/Payload dist
cp -R "$APP" pack_tmp/Payload/
( cd pack_tmp && zip -qry "../dist/dsh助手_V1.ipa" Payload )
ls -la dist/dsh助手_V1.ipa