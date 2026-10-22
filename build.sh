#!/bin/zsh
# 编译并打包成 build/ClipLine.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=.build/release/ClipLine
APP=build/ClipLine.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipLine"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# 用 App 自己的绘图代码渲染图标
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
"$BIN" --render-icon build/icon_1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null
echo "✓ 已生成 $APP"

# ./build.sh install：装进「应用程序」并设为开机启动
if [[ "${1:-}" == "install" ]]; then
  pkill -x ClipLine 2>/dev/null || true
  sleep 0.3
  rm -rf /Applications/ClipLine.app
  ditto "$APP" /Applications/ClipLine.app
  rm -rf "$APP"
  /Applications/ClipLine.app/Contents/MacOS/ClipLine --enable-login-item
  open /Applications/ClipLine.app
  echo "✓ 已安装到 /Applications/ClipLine.app"
fi
