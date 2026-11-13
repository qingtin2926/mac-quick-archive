import Cocoa

final class MainWindowController: NSWindowController, NSWindowDelegate {

    static let shared = MainWindowController()

    private var extStatusLabel: NSTextField!
    private var toolbarStatusLabel: NSTextField!
    private var excludeJunkCheck: NSButton!
    private var smartUnwrapCheck: NSButton!
    private var selectInFinderCheck: NSButton!

    private init() {
        let rect = NSRect(x: 0, y: 0, width: 500, height: 420)
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "轻压 QuickArchive — 访达工具栏解压缩助手"
        win.center()
        win.isReleasedWhenClosed = false
        super.init(window: win)
        win.delegate = self
        setupUI(in: win)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndActivate() {
        NSApp.setActivationPolicy(.regular)
        refreshStatus()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Return to background agent mode without cluttering the Dock
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func setupUI(in win: NSWindow) {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 420))

        // Header Icon & Title
        let iconView = NSImageView(frame: NSRect(x: 28, y: 344, width: 52, height: 52))
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(iconView)

        let titleLbl = NSTextField(labelWithString: "轻压 QuickArchive")
        titleLbl.frame = NSRect(x: 92, y: 368, width: 380, height: 26)
        titleLbl.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        root.addSubview(titleLbl)

        let subLbl = NSTextField(labelWithString: "固定于访达窗口右上角：选中文件一键压缩，选中压缩包一键解压")
        subLbl.frame = NSRect(x: 92, y: 346, width: 385, height: 18)
        subLbl.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        subLbl.textColor = .secondaryLabelColor
        root.addSubview(subLbl)

        // Status Box
        let statusBox = NSBox(frame: NSRect(x: 28, y: 212, width: 444, height: 118))
        statusBox.title = "访达右上角工具栏集成状态"
        statusBox.titleFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        root.addSubview(statusBox)

        let boxContent = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 94))
        statusBox.contentView = boxContent

        extStatusLabel = NSTextField(labelWithString: "")
        extStatusLabel.frame = NSRect(x: 14, y: 60, width: 260, height: 20)
        extStatusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        boxContent.addSubview(extStatusLabel)

        let enableBtn = NSButton(title: "刷新并启用扩展", target: self, action: #selector(onEnableExtension))
        enableBtn.bezelStyle = .rounded
        enableBtn.frame = NSRect(x: 286, y: 55, width: 132, height: 28)
        boxContent.addSubview(enableBtn)

        toolbarStatusLabel = NSTextField(labelWithString: "")
        toolbarStatusLabel.frame = NSRect(x: 14, y: 20, width: 260, height: 20)
        toolbarStatusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        boxContent.addSubview(toolbarStatusLabel)

        let pinBtn = NSButton(title: "一键固定到访达右上角", target: self, action: #selector(onPinToolbar))
        pinBtn.bezelStyle = .rounded
        pinBtn.keyEquivalent = "\r"
        pinBtn.frame = NSRect(x: 266, y: 15, width: 152, height: 28)
        boxContent.addSubview(pinBtn)

        // Preferences Box
        let prefBox = NSBox(frame: NSRect(x: 28, y: 88, width: 444, height: 112))
        prefBox.title = "压缩与解压行为偏好"
        prefBox.titleFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        root.addSubview(prefBox)

        let prefContent = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 88))
        prefBox.contentView = prefContent

        excludeJunkCheck = NSButton(
            checkboxWithTitle: "压缩时自动过滤 .DS_Store 与 __MACOSX 隐藏元数据文件",
            target: self,
            action: #selector(onPrefChanged)
        )
        excludeJunkCheck.frame = NSRect(x: 14, y: 58, width: 400, height: 20)
        prefContent.addSubview(excludeJunkCheck)

        smartUnwrapCheck = NSButton(
            checkboxWithTitle: "解压到同名文件夹时智能防套娃（避免生成双层重复同名目录）",
            target: self,
            action: #selector(onPrefChanged)
        )
        smartUnwrapCheck.frame = NSRect(x: 14, y: 33, width: 400, height: 20)
        prefContent.addSubview(smartUnwrapCheck)

        selectInFinderCheck = NSButton(
            checkboxWithTitle: "完成后自动在当前访达窗口中高亮选中生成的文件或文件夹",
            target: self,
            action: #selector(onPrefChanged)
        )
        selectInFinderCheck.frame = NSRect(x: 14, y: 8, width: 400, height: 20)
        prefContent.addSubview(selectInFinderCheck)

        // Footer Hint
        let hintText = """
        提示：也可在任意访达窗口顶部工具栏空白处「右键 → 自定义工具栏…」，将「轻压」图标拖至右上角。
        支持压缩：ZIP、7Z、TAR.GZ、TAR.XZ、TAR.ZST  |  支持解压：ZIP、RAR、7Z、TAR.*、GZ、XZ、BZ2 等全主流格式（含加密包与防中文乱码）。
        """
        let hintLbl = NSTextField(wrappingLabelWithString: hintText)
        hintLbl.frame = NSRect(x: 30, y: 18, width: 440, height: 58)
        hintLbl.font = NSFont.systemFont(ofSize: 11.5)
        hintLbl.textColor = .secondaryLabelColor
        root.addSubview(hintLbl)

        win.contentView = root
        refreshStatus()
    }

    func refreshStatus() {
        let enabled = FinderBridge.isExtensionEnabled()
        extStatusLabel.stringValue = enabled ? "访达扩展状态：✅ 已启用" : "访达扩展状态：⚠️ 未启用"

        let pinned = FinderBridge.isPinnedInFinderToolbar()
        toolbarStatusLabel.stringValue = pinned ? "工具栏位置：✅ 已固定至访达右上角" : "工具栏位置：📌 待固定至访达右上角"

        excludeJunkCheck.state = ArchivePreferences.excludeMacJunk ? .on : .off
        smartUnwrapCheck.state = ArchivePreferences.smartUnwrapSubfolder ? .on : .off
        selectInFinderCheck.state = ArchivePreferences.selectResultInFinder ? .on : .off
    }

    @objc private func onEnableExtension() {
        FinderBridge.enableExtension()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.refreshStatus()
        }
    }

    @objc private func onPinToolbar() {
        FinderBridge.enableExtension()
        FinderBridge.pinToFinderToolbarRightCorner(restartFinder: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.refreshStatus()
            HUDPanelController.shared.showSuccess(
                title: "已固定到访达右上角",
                subtitle: "打开任意访达窗口即可在右上角看到「轻压」按钮"
            )
        }
    }

    @objc private func onPrefChanged() {
        ArchivePreferences.excludeMacJunk = (excludeJunkCheck.state == .on)
        ArchivePreferences.smartUnwrapSubfolder = (smartUnwrapCheck.state == .on)
        ArchivePreferences.selectResultInFinder = (selectInFinderCheck.state == .on)
    }
}
