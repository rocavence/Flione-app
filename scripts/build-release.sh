#!/bin/zsh
# 建置 Release 版 Flione.app 並打包成 zip（本機簽章，未公證）。
# 這是測試版：本機有 repo 的 .secrets 時自動登入（DEV_LOGIN）。要給別人的正式版用 FINIFY_PUBLIC=1 建置。
# 用法：scripts/build-release.sh   輸出：dist/Flione.app、dist/Flione-<版本>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
CONDITIONS=()
[[ "${FINIFY_PUBLIC:-0}" == 1 ]] || CONDITIONS=(SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEV_LOGIN')
xcodebuild -project Finify.xcodeproj -scheme Finify -configuration Release \
  -derivedDataPath build-release "${CONDITIONS[@]}" build | grep -E "error:|BUILD" || true

APP=build-release/Build/Products/Release/Flione.app
[[ -d "$APP" ]] || { echo "建置失敗：找不到 $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
rm -rf dist && mkdir -p dist
cp -R "$APP" dist/
ditto -c -k --keepParent dist/Flione.app "dist/Flione-$VERSION.zip"
echo "完成：dist/Flione.app、dist/Flione-$VERSION.zip"
echo "未經 Apple 公證；在其他 Mac 第一次開啟時需在 Finder 按右鍵 → 打開。"
