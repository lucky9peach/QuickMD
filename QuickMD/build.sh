#!/bin/bash
# QuickMD 一键编译打包
set -e
cd "$(dirname "$0")"
APP="QuickMD.app"
rm -rf "$APP" build
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 Swift（-O 优化）…"
swiftc -O -whole-module-optimization Sources/QuickMD.swift -o "build/QuickMD" 2>&1 | grep -v "warning:" || true
cp build/QuickMD "$APP/Contents/MacOS/QuickMD"

echo "==> 复制资源…"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/template.html Resources/app.css Resources/marked.min.js "$APP/Contents/Resources/"

echo "==> 生成图标…"
if swift makeicon.swift "build/QuickMD.iconset" && iconutil -c icns "build/QuickMD.iconset" -o "$APP/Contents/Resources/AppIcon.icns"; then
  cp "$APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/DocIcon.icns"
  echo "    图标 OK"
else
  echo "    图标生成失败，用系统默认图标（不影响使用）"
fi

echo "==> 签名…"
codesign --force --deep --sign - "$APP"

echo "==> 注册到 LaunchServices…"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP" || true

echo "==> 安装到 /Applications…"
rm -rf /Applications/QuickMD.app
cp -R "$APP" /Applications/QuickMD.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/QuickMD.app || true

echo ""
echo "✅ 完成：$PWD/$APP + /Applications/QuickMD.app"
ls -lh "$APP/Contents/MacOS/QuickMD"
