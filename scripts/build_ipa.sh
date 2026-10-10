#!/bin/bash
# xcodegen 生成工程 + xcodebuild 打 IPA（不 archive，绕 bitcode_strip，和百宝箱同法）
set -e
cd "$(dirname "$0")/.."

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

echo "==> 手动打包 IPA"
rm -rf dist pack_tmp && mkdir -p pack_tmp/Payload dist
cp -R "$APP" pack_tmp/Payload/
( cd pack_tmp && zip -qry "../dist/dsh助手_V1.ipa" Payload )
ls -la dist/dsh助手_V1.ipa