#!/bin/zsh
# 建置 Release 版 Flione.app 並打包成 dmg（未公證）。公開版分成 Apple Silicon 與 Intel 兩包。
# 這是測試版：本機有 repo 的 .secrets 時自動登入（DEV_LOGIN）。要給別人的正式版用 FLIONE_PUBLIC=1 建置。
# 用法：FLIONE_PUBLIC=1 scripts/build-release.sh   輸出：dist/Flione-<版本>-AppleSilicon.dmg、dist/Flione-<版本>-Intel.dmg
#   另有不含版本的 dist/Flione-AppleSilicon.dmg、dist/Flione-Intel.dmg：發版時一起上傳，官網用
#   releases/latest/download/Flione-AppleSilicon.dmg 固定連到最新版（D58）。發版：gh release create v<版本> dist/*.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
CONDITIONS=()
# 公開版用 ad-hoc 簽章：開發者憑證的名稱含 Apple ID，簽進 app 裡任何人都看得到；反正都未經公證，開啟流程相同
[[ "${FLIONE_PUBLIC:-${FINIFY_PUBLIC:-0}}" == 1 ]] && CONDITIONS=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=) || CONDITIONS=(SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEV_LOGIN')
xcodebuild -project Flione.xcodeproj -scheme Flione -configuration Release \
  -derivedDataPath build-release "${CONDITIONS[@]}" build | grep -E "error:|BUILD" || true

APP=build-release/Build/Products/Release/Flione.app
[[ -d "$APP" ]] || { echo "建置失敗：找不到 $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
rm -rf dist && mkdir -p dist

# dmg：Flione.app 旁邊放「應用程式」的捷徑，打開後直接拖進去
make_dmg() {  # make_dmg <app 路徑> <dmg 檔名>
  local stage=$(mktemp -d)
  cp -R "$1" "$stage/"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "Flione $VERSION" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "dist/$2" >/dev/null
  rm -rf "$stage"
}

if [[ "${FLIONE_PUBLIC:-${FINIFY_PUBLIC:-0}}" == 1 ]]; then
  # 公開版分兩包：Apple Silicon 與 Intel 各一個，每包只有自己的架構，大小約減半（D46）
  for pair in "arm64:AppleSilicon" "x86_64:Intel"; do
    arch=${pair%%:*}; label=${pair##*:}
    mkdir -p "dist/$label"
    cp -R "$APP" "dist/$label/"
    BIN="dist/$label/Flione.app/Contents/MacOS/Flione"
    lipo "$BIN" -thin "$arch" -output "$BIN.thin" && mv "$BIN.thin" "$BIN"
    # 拆架構後原本的簽章失效，重新 ad-hoc 簽章（保留 hardened runtime）
    codesign --force --sign - --options runtime "dist/$label/Flione.app" 2>/dev/null
    make_dmg "dist/$label/Flione.app" "Flione-$VERSION-$label.dmg"
    cp "dist/Flione-$VERSION-$label.dmg" "dist/Flione-$label.dmg"
  done
  echo "完成：dist/Flione-$VERSION-AppleSilicon.dmg、dist/Flione-$VERSION-Intel.dmg（與不含版本的同一份）"
else
  cp -R "$APP" dist/
  make_dmg dist/Flione.app "Flione-$VERSION.dmg"
  echo "完成：dist/Flione.app、dist/Flione-$VERSION.dmg"
fi
echo "未經 Apple 公證；在其他 Mac 第一次開啟前先執行 xattr -dr com.apple.quarantine /Applications/Flione.app，或到「系統設定 → 隱私權與安全性」按「強制打開」。"
