import Cocoa
import FinderSync

@objc(FinderSync)
class FinderSync: FIFinderSync {

    // Fixed integer tags that survive XPC serialization between Finder.app and FinderSync.appex
    private enum ActionTag: Int {
        case extractSubfolder = 101
        case extractHere      = 102
        case compressZip      = 201
        case compress7z       = 202
        case compressTarGz    = 203
        case compressTarXz    = 204
        case compressTarZst   = 205
        case openSettings     = 900
    }

    private var payloadsByTag: [Int: ArchiveTaskPayload] = [:]
    private var lastCapturedPaths: [String] = []
    private var lastCapturedDir: String?

    private lazy var cachedToolbarIcon: NSImage = {
        if let customImg = Bundle(for: FinderSync.self).image(forResource: "ToolbarIcon") {
            customImg.size = NSSize(width: 16, height: 16)
            customImg.isTemplate = false
            return customImg
        }
        let img = NSImage(systemSymbolName: "doc.zipper", accessibilityDescription: "轻压") ?? NSImage()
        img.size = NSSize(width: 16, height: 16)
        img.isTemplate = true
        return img
    }()

    override init() {
        super.init()
        refreshMonitoredDirectories()

        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(
            self,
            selector: #selector(volumesChanged(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(volumesChanged(_:)),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
    }

    @objc private func volumesChanged(_ notification: Notification) {
        refreshMonitoredDirectories()
    }

    private func refreshMonitoredDirectories() {
        var dirs = Set<URL>()
        dirs.insert(URL(fileURLWithPath: "/"))
        let home = FileManager.default.homeDirectoryForCurrentUser
        dirs.insert(home)

        let icloud = home.appendingPathComponent("Library/Mobile Documents")
        if FileManager.default.fileExists(atPath: icloud.path) {
            dirs.insert(icloud)
        }

        if let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) {
            for vol in mounted {
                dirs.insert(vol)
            }
        }

        FIFinderSyncController.default().directoryURLs = dirs
    }

    // MARK: - Toolbar Item Configuration

    override var toolbarItemName: String {
        return "轻压"
    }

    override var toolbarItemToolTip: String {
        return "轻压：选中文件快速压缩，选中压缩包快速解压"
    }

    override var toolbarItemImage: NSImage {
        return cachedToolbarIcon
    }

    // MARK: - Flat Single-Level Menu Construction (No Submenus)

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .toolbarItemMenu else {
            return nil
        }

        payloadsByTag.removeAll()

        let menu = NSMenu(title: "")
        menu.autoenablesItems = false

        let controller = FIFinderSyncController.default()
        let selectedURLs = controller.selectedItemURLs() ?? []
        let targetDirURL = controller.targetedURL()

        lastCapturedPaths = selectedURLs.map { $0.path }
        lastCapturedDir = targetDirURL?.path ?? selectedURLs.first?.deletingLastPathComponent().path

        if selectedURLs.isEmpty {
            buildFallbackFlatMenu(into: menu, dirPath: lastCapturedDir)
        } else {
            let allArchives = selectedURLs.allSatisfy { ArchiveDetector.isArchiveFile($0) }
            if allArchives {
                buildExtractFlatMenu(into: menu, archiveURLs: selectedURLs, dirPath: lastCapturedDir)
            } else {
                buildCompressFlatMenu(into: menu, selectedURLs: selectedURLs, dirPath: lastCapturedDir)
            }
        }

        menu.addItem(NSMenuItem.separator())
        let settingsPayload = ArchiveTaskPayload(action: .openSettings)
        menu.addItem(makeActionItem(
            title: "轻压设置…",
            tag: .openSettings,
            payload: settingsPayload
        ))

        return menu
    }

    private func buildExtractFlatMenu(into menu: NSMenu, archiveURLs: [URL], dirPath: String?) {
        let paths = archiveURLs.map { $0.path }

        let subfolderTitle: String
        if archiveURLs.count == 1 {
            let baseName = ArchiveDetector.archiveBaseName(for: archiveURLs[0])
            subfolderTitle = "解压到同名文件夹 “\(baseName)/”"
        } else {
            subfolderTitle = "分别解压到各自同名文件夹 (\(archiveURLs.count) 个)"
        }

        let subPayload = ArchiveTaskPayload(
            action: .extract,
            extractMode: .toSubfolder,
            itemPaths: paths,
            targetDirPath: dirPath
        )
        menu.addItem(makeActionItem(
            title: subfolderTitle,
            tag: .extractSubfolder,
            payload: subPayload
        ))

        let hereTitle = archiveURLs.count == 1 ? "直接解压到当前目录" : "全部直接解压到当前目录"
        let herePayload = ArchiveTaskPayload(
            action: .extract,
            extractMode: .toCurrentDir,
            itemPaths: paths,
            targetDirPath: dirPath
        )
        menu.addItem(makeActionItem(
            title: hereTitle,
            tag: .extractHere,
            payload: herePayload
        ))
    }

    private func buildCompressFlatMenu(into menu: NSMenu, selectedURLs: [URL], dirPath: String?) {
        let paths = selectedURLs.map { $0.path }

        let specs: [(CompressFormat, ActionTag, String)] = [
            (.zip,      .compressZip,    "压缩为 ZIP (.zip)"),
            (.sevenZip, .compress7z,     "压缩为 7Z (.7z)"),
            (.tarGz,    .compressTarGz,  "压缩为 TAR.GZ (.tar.gz)"),
            (.tarXz,    .compressTarXz,  "压缩为 TAR.XZ (.tar.xz)"),
            (.tarZst,   .compressTarZst, "压缩为 TAR.ZST (.tar.zst)")
        ]

        for (fmt, tag, title) in specs {
            let payload = ArchiveTaskPayload(
                action: .compress,
                compressFormat: fmt,
                itemPaths: paths,
                targetDirPath: dirPath
            )
            menu.addItem(makeActionItem(title: title, tag: tag, payload: payload))
        }
    }

    private func buildFallbackFlatMenu(into menu: NSMenu, dirPath: String?) {
        let info = NSMenuItem(title: "请先选中文件或压缩包（也可直接点击下方自动识别）", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeActionItem(
            title: "解压到同名文件夹",
            tag: .extractSubfolder,
            payload: ArchiveTaskPayload(action: .extract, extractMode: .toSubfolder, targetDirPath: dirPath, useFinderFallbackSelection: true)
        ))
        menu.addItem(makeActionItem(
            title: "直接解压到当前目录",
            tag: .extractHere,
            payload: ArchiveTaskPayload(action: .extract, extractMode: .toCurrentDir, targetDirPath: dirPath, useFinderFallbackSelection: true)
        ))

        menu.addItem(NSMenuItem.separator())
        let specs: [(CompressFormat, ActionTag, String)] = [
            (.zip,      .compressZip,   "压缩为 ZIP (.zip)"),
            (.sevenZip, .compress7z,    "压缩为 7Z (.7z)"),
            (.tarGz,    .compressTarGz, "压缩为 TAR.GZ (.tar.gz)"),
            (.tarXz,    .compressTarXz, "压缩为 TAR.XZ (.tar.xz)")
        ]
        for (fmt, tag, title) in specs {
            menu.addItem(makeActionItem(
                title: title,
                tag: tag,
                payload: ArchiveTaskPayload(action: .compress, compressFormat: fmt, targetDirPath: dirPath, useFinderFallbackSelection: true)
            ))
        }
    }

    private func makeActionItem(title: String, tag: ActionTag, payload: ArchiveTaskPayload) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(onMenuItemClicked(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tag.rawValue
        item.isEnabled = true
        payloadsByTag[tag.rawValue] = payload
        return item
    }

    // MARK: - XPC-Safe Action Handler

    @objc func onMenuItemClicked(_ sender: NSMenuItem) {
        let rawTag = sender.tag
        let payload: ArchiveTaskPayload

        if let cached = payloadsByTag[rawTag] {
            payload = cached
        } else if let reconstructed = reconstructPayload(forTag: rawTag) {
            payload = reconstructed
        } else {
            return
        }

        guard let url = payload.toURL() else { return }

        let opened = NSWorkspace.shared.open(url)
        if !opened {
            let hostAppURL = Bundle(for: FinderSync.self).bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.open([url], withApplicationAt: hostAppURL, configuration: config, completionHandler: nil)
        }
    }

    private func reconstructPayload(forTag rawTag: Int) -> ArchiveTaskPayload? {
        guard let tag = ActionTag(rawValue: rawTag) else { return nil }
        let livePaths = (FIFinderSyncController.default().selectedItemURLs() ?? []).map { $0.path }
        let paths = livePaths.isEmpty ? lastCapturedPaths : livePaths
        let dir = FIFinderSyncController.default().targetedURL()?.path ?? lastCapturedDir
        let fallback = paths.isEmpty

        switch tag {
        case .extractSubfolder:
            return ArchiveTaskPayload(action: .extract, extractMode: .toSubfolder, itemPaths: paths, targetDirPath: dir, useFinderFallbackSelection: fallback)
        case .extractHere:
            return ArchiveTaskPayload(action: .extract, extractMode: .toCurrentDir, itemPaths: paths, targetDirPath: dir, useFinderFallbackSelection: fallback)
        case .compressZip:
            return ArchiveTaskPayload(action: .compress, compressFormat: .zip, itemPaths: paths, targetDirPath: dir, useFinderFallbackSelection: fallback)
        case .compress7z:
            return ArchiveTaskPayload(action: .compress, compressFormat: .sevenZip, itemPaths: paths, targetDirPath: dir, useFinderFallbackSelection: fallback)
        case .compressTarGz:
            return ArchiveTaskPayload(action: .compress, compressFormat: .tarGz, itemPaths: paths, targetDirPath: dir, useFinderFallbackSelection: fallback)
        case .compressTarXz:
            return ArchiveTaskPayload(action: .compress, compressFormat: .tarXz, itemPaths: paths, targetDirPath: dir, useFinderFallbackSelection: fallback)
        case .compressTarZst:
            return ArchiveTaskPayload(action: .compress, compressFormat: .tarZst, itemPaths: paths, targetDirPath: dir, useFinderFallbackSelection: fallback)
        case .openSettings:
            return ArchiveTaskPayload(action: .openSettings)
        }
    }
}
