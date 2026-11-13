import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var handledURLOnLaunch = false
    private var activeTaskCount = 0
    private var idleExitTimer: DispatchWorkItem?
    private let taskQueue = DispatchQueue(label: "com.antigravity.quickarchive.worker", qos: .userInitiated)

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        // Ensure FinderSync extension is registered whenever HostApp launches
        if !FinderBridge.isExtensionEnabled() {
            FinderBridge.enableExtension()
        }

        // If user launched app directly (not via quickarchive:// URL), open settings window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self = self else { return }
            if !self.handledURLOnLaunch {
                MainWindowController.shared.showAndActivate()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.showAndActivate()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handledURLOnLaunch = true
        cancelIdleExit()

        for url in urls {
            guard let payload = ArchiveTaskPayload.fromURL(url) else { continue }
            dispatchPayload(payload)
        }
    }

    // MARK: - Task Dispatch

    private func dispatchPayload(_ payload: ArchiveTaskPayload) {
        if payload.action == .openSettings {
            DispatchQueue.main.async {
                MainWindowController.shared.showAndActivate()
            }
            return
        }

        incrementActiveTask()

        taskQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.decrementActiveTask() }

            var targetURLs = payload.itemPaths.map { URL(fileURLWithPath: $0) }
            if payload.useFinderFallbackSelection || targetURLs.isEmpty {
                let fallback = FinderBridge.getSelectedURLs()
                if !fallback.isEmpty {
                    targetURLs = fallback
                }
            }

            let preferredDir = payload.targetDirPath.map { URL(fileURLWithPath: $0) }

            switch payload.action {
            case .compress:
                let fmt = payload.compressFormat ?? .zip
                self.performCompression(items: targetURLs, format: fmt, preferredDir: preferredDir)

            case .extract:
                let mode = payload.extractMode ?? .toSubfolder
                self.performExtraction(items: targetURLs, mode: mode)

            case .openSettings:
                break
            }
        }
    }

    private func performCompression(items: [URL], format: CompressFormat, preferredDir: URL?) {
        guard !items.isEmpty else {
            showErrorAlert(message: "未检测到选中的文件或文件夹", info: "请先在访达窗口中点击选中要压缩的文件或文件夹，再点击右上角「轻压」按钮。")
            return
        }

        let subtitle = items.count == 1
            ? items[0].lastPathComponent
            : "共 \(items.count) 个项目"

        HUDPanelController.shared.showProgress(
            title: "正在压缩为 \(format.shortLabel)…",
            subtitle: subtitle
        )

        do {
            let outputArchive = try ArchiveEngine.shared.compress(
                items: items,
                format: format,
                preferredDir: preferredDir
            )
            HUDPanelController.shared.showSuccess(
                title: "已压缩至当前目录",
                subtitle: outputArchive.lastPathComponent
            )
            FinderBridge.selectItemsInFinder([outputArchive])
        } catch {
            HUDPanelController.shared.hideImmediately()
            showErrorAlert(message: "压缩失败", info: error.localizedDescription)
        }
    }

    private func performExtraction(items: [URL], mode: ExtractMode) {
        let archives = items.filter { ArchiveDetector.isArchiveFile($0) }
        guard !archives.isEmpty else {
            showErrorAlert(message: "选中的不是受支持的压缩包", info: "请选中 .zip / .rar / .7z / .tar.gz / .tar.xz 等压缩文件后再执行解压。")
            return
        }

        var allCreatedURLs: [URL] = []

        for (index, archiveURL) in archives.enumerated() {
            let progressTitle = archives.count == 1
                ? "正在解压…"
                : "正在解压 (\(index + 1)/\(archives.count))…"
            HUDPanelController.shared.showProgress(
                title: progressTitle,
                subtitle: archiveURL.lastPathComponent
            )

            var currentPassword: String? = nil
            var finishedArchive = false

            while !finishedArchive {
                do {
                    let created = try ArchiveEngine.shared.extract(
                        archiveURL: archiveURL,
                        mode: mode,
                        password: currentPassword
                    )
                    allCreatedURLs.append(contentsOf: created)
                    finishedArchive = true
                } catch ArchiveError.passwordRequired {
                    HUDPanelController.shared.hideImmediately()
                    if let pwd = promptForPassword(archiveName: archiveURL.lastPathComponent, isRetry: false) {
                        currentPassword = pwd
                        HUDPanelController.shared.showProgress(
                            title: progressTitle,
                            subtitle: archiveURL.lastPathComponent
                        )
                    } else {
                        // User cancelled password dialog
                        return
                    }
                } catch ArchiveError.wrongPassword {
                    HUDPanelController.shared.hideImmediately()
                    if let pwd = promptForPassword(archiveName: archiveURL.lastPathComponent, isRetry: true) {
                        currentPassword = pwd
                        HUDPanelController.shared.showProgress(
                            title: progressTitle,
                            subtitle: archiveURL.lastPathComponent
                        )
                    } else {
                        return
                    }
                } catch {
                    HUDPanelController.shared.hideImmediately()
                    showErrorAlert(message: "解压失败：\(archiveURL.lastPathComponent)", info: error.localizedDescription)
                    return
                }
            }
        }

        let summarySubtitle: String
        if allCreatedURLs.count == 1 {
            summarySubtitle = allCreatedURLs[0].lastPathComponent
        } else {
            summarySubtitle = "已释放 \(allCreatedURLs.count) 个项目到当前目录"
        }

        HUDPanelController.shared.showSuccess(
            title: mode == .toSubfolder ? "已解压到同名文件夹" : "已解压到当前目录",
            subtitle: summarySubtitle
        )
        FinderBridge.selectItemsInFinder(allCreatedURLs)
    }

    // MARK: - Password & Error Dialogs

    private func promptForPassword(archiveName: String, isRetry: Bool) -> String? {
        var result: String? = nil
        let sem = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = isRetry ? "密码错误，请重试" : "需要解压密码"
            alert.informativeText = "压缩包「\(archiveName)」已加密，请输入密码："
            alert.addButton(withTitle: "解压")
            alert.addButton(withTitle: "取消")

            let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            input.placeholderString = "输入压缩包密码"
            alert.accessoryView = input
            alert.window.initialFirstResponder = input

            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                result = input.stringValue
            }
            sem.signal()
        }

        sem.wait()
        return result
    }

    private func showErrorAlert(message: String, info: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = message
            alert.informativeText = info
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    // MARK: - Idle Lifecycle Management

    private func incrementActiveTask() {
        DispatchQueue.main.async {
            self.activeTaskCount += 1
            self.cancelIdleExit()
        }
    }

    private func decrementActiveTask() {
        DispatchQueue.main.async {
            self.activeTaskCount = max(0, self.activeTaskCount - 1)
            self.scheduleIdleExitIfNeeded()
        }
    }

    private func cancelIdleExit() {
        idleExitTimer?.cancel()
        idleExitTimer = nil
    }

    private func scheduleIdleExitIfNeeded() {
        cancelIdleExit()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let settingsVisible = MainWindowController.shared.window?.isVisible ?? false
            if self.activeTaskCount == 0 && !settingsVisible {
                NSApp.terminate(nil)
            }
        }
        idleExitTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: work)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于轻压 QuickArchive", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "退出轻压", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
