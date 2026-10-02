#!/bin/zsh
# 建置 Release 版 Finify.app 並打包成 zip（本機簽章，未公證）。
# 用法：scripts/build-release.sh   輸出：dist/Finify.app、dist/Finify-<版本>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Finify.xcodeproj -scheme Finify -configuration Release \
  -derivedDataPath build-release build | grep -E "error:|BUILD" || true

APP=build-release/Build/Products/Release/Finify.app
[[ -d "$APP" ]] || { echo "建置失敗：找不到 $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
rm -rf dist && mkdir -p dist
cp -R "$APP" dist/
ditto -c -k --keepParent dist/Finify.app "dist/Finify-$VERSION.zip"
echo "完成：dist/Finify.app、dist/Finify-$VERSION.zip"
echo "未經 Apple 公證；在其他 Mac 第一次開啟時需在 Finder 按右鍵 → 打開。"
