#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="QuickArchive.app"
STAGED_APP="$BUILD_DIR/$APP_NAME"
INSTALL_APP="/Applications/$APP_NAME"
APPEX_REL="Contents/PlugIns/QuickArchiveFinderSync.appex"

echo "==> [1/6] 准备构建目录..."
rm -rf "$BUILD_DIR"
mkdir -p "$STAGED_APP/Contents/MacOS"
mkdir -p "$STAGED_APP/Contents/Resources"
mkdir -p "$STAGED_APP/$APPEX_REL/Contents/MacOS"
mkdir -p "$STAGED_APP/$APPEX_REL/Contents/Resources"

echo "==> [2/6] 生成高清应用图标与访达工具栏矢量模板图标..."
ICONSET_TMP="$BUILD_DIR/AppIcon.iconset"
swift "$PROJECT_DIR/HostApp/IconGenerator.swift" "$ICONSET_TMP" "$STAGED_APP/$APPEX_REL/Contents/Resources"
iconutil -c icns "$ICONSET_TMP" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_TMP"

cp "$PROJECT_DIR/HostApp/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$PROJECT_DIR/FinderExtension/Info.plist" "$STAGED_APP/$APPEX_REL/Contents/Info.plist"

echo "==> [3/6] 编译访达工具栏扩展 (QuickArchiveFinderSync.appex)..."
swiftc -O -swift-version 5 \
    -parse-as-library \
    -application-extension \
    -framework Cocoa \
    -framework FinderSync \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$PROJECT_DIR/Shared/ArchiveTypes.swift" \
    "$PROJECT_DIR/FinderExtension/FinderSync.swift" \
    -o "$STAGED_APP/$APPEX_REL/Contents/MacOS/QuickArchiveFinderSync"

echo "==> [4/6] 编译轻压主程序 (QuickArchive.app)..."
swiftc -O -swift-version 5 \
    -parse-as-library \
    -framework Cocoa \
    "$PROJECT_DIR/Shared/ArchiveTypes.swift" \
    "$PROJECT_DIR/HostApp/ArchiveEngine.swift" \
    "$PROJECT_DIR/HostApp/HUDPanelController.swift" \
    "$PROJECT_DIR/HostApp/MainWindowController.swift" \
    "$PROJECT_DIR/HostApp/AppDelegate.swift" \
    -o "$STAGED_APP/Contents/MacOS/QuickArchive"

echo "==> [5/6] 执行代码签名与部署到 /Applications..."
codesign --force --sign - \
    --entitlements "$PROJECT_DIR/FinderExtension/FinderExtension.entitlements" \
    "$STAGED_APP/$APPEX_REL"
codesign --force --sign - "$STAGED_APP"

# 卸载旧实例后再覆盖安装
killall QuickArchive 2>/dev/null || true
killall QuickArchiveFinderSync 2>/dev/null || true
if [ -d "$INSTALL_APP" ]; then
    pluginkit -r "$INSTALL_APP/$APPEX_REL" 2>/dev/null || true
    rm -rf "$INSTALL_APP"
fi

cp -R "$STAGED_APP" "$INSTALL_APP"
xattr -cr "$INSTALL_APP" 2>/dev/null || true

echo "==> [6/6] 注册 URL 协议、启用访达扩展并固定到访达窗口右上角..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f -R -trusted "$INSTALL_APP"

pluginkit -a "$INSTALL_APP/$APPEX_REL"
pluginkit -e use -i com.antigravity.quickarchive.findersync

# 先停止 Finder 再写入偏好设置，防止 Finder 退出时用内存旧配置覆盖新布局
killall Finder 2>/dev/null || true
sleep 0.6

# 将工具栏按钮固定到访达右上角（搜索框左侧，并用单个弹性空白替代固定宽度空白防止溢出成二级菜单或闪烁）
swift - << 'EOF'
import Foundation

let domain = "com.apple.finder" as CFString
let key = "NSToolbar Configuration Browser" as CFString
let extID = "com.antigravity.quickarchive.findersync"

var config = (CFPreferencesCopyAppValue(key, domain) as? [String: Any]) ?? [:]
var items = (config["TB Item Identifiers"] as? [String]) ?? [
    "com.apple.finder.BACK",
    "com.apple.finder.SWCH",
    "com.apple.finder.ARNG",
    "com.apple.finder.SHAR",
    "com.apple.finder.LABL",
    "com.apple.finder.ACTN",
    "com.apple.finder.SRCH"
]

items.removeAll {
    $0 == "com.local.probe.findersync" ||
    $0 == "NSToolbarSpaceItem" ||
    $0 == "NSToolbarFlexibleSpaceItem" ||
    $0 == extID
}

let rightAnchorIndex = items.firstIndex(where: {
    $0.contains("findersync") || $0 == "com.apple.finder.SRCH"
}) ?? items.endIndex
items.insert("NSToolbarFlexibleSpaceItem", at: rightAnchorIndex)

if let idx = items.lastIndex(of: "com.apple.finder.SRCH") {
    items.insert(extID, at: idx)
} else {
    items.append(extID)
}
config["TB Item Identifiers"] = items
config["TB Is Shown"] = 1
CFPreferencesSetAppValue(key, config as CFDictionary, domain)
CFPreferencesAppSynchronize(domain)
EOF

# 确保 Finder 重新拉起以应用最新工具栏布局
open -g -a Finder
sleep 1.8

echo ""
echo "✅ 构建与安装完成！"
echo "   应用路径: $INSTALL_APP"
pluginkit -m -v -i com.antigravity.quickarchive.findersync || true
