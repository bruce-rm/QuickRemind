#!/usr/bin/env bash
# 在 Mac 上生成「未签名 IPA」。用法：
#   chmod +x build_ipa.sh && ./build_ipa.sh
# 产出的 QuickRemind-unsigned.ipa 可用 Sideloadly / AltStore 重签后安装到 iPhone。
# 若要正式签名，请用 Xcode 的 Product > Archive > Distribute App，或参考 README 的签名说明。

set -euo pipefail
cd "$(dirname "$0")"

echo "==> 清理旧产物"
rm -rf build staging QuickRemind-unsigned.ipa

echo "==> 构建 Release-iphoneos（无签名）"
xcodebuild \
  -project QuickRemind.xcodeproj \
  -scheme QuickRemind \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_ENTITLEMENTS=QuickRemind/QuickRemind.unsigned.entitlements \
  build

echo "==> 打包 IPA"
APP=$(find build/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' -type d | head -1)
if [ -z "$APP" ]; then
  echo "构建产物中未找到 .app"
  exit 1
fi
ROOT="$PWD"
mkdir -p staging/Payload
cp -R "$APP" staging/Payload/
(cd staging && zip -qry "$ROOT/QuickRemind-unsigned.ipa" Payload)

echo "==> 完成"
ls -lh QuickRemind-unsigned.ipa
