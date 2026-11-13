import Foundation
import AppKit

enum ArchiveError: LocalizedError {
    case emptySelection
    case passwordRequired
    case wrongPassword
    case toolMissing(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "未选中任何文件或文件夹，请先在访达中选中目标项。"
        case .passwordRequired:
            return "该压缩包受密码保护，需要输入密码。"
        case .wrongPassword:
            return "解压密码不正确，请重新输入。"
        case .toolMissing(let tool):
            return "未找到所需的命令行组件：\(tool)"
        case .commandFailed(let detail):
            return detail
        }
    }
}

struct ArchivePreferences {
    private static let excludeMacJunkKey = "ExcludeMacJunkFiles"
    private static let selectResultInFinderKey = "SelectResultInFinder"
    private static let smartUnwrapSubfolderKey = "SmartUnwrapSubfolder"

    static var excludeMacJunk: Bool {
        get {
            if UserDefaults.standard.object(forKey: excludeMacJunkKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: excludeMacJunkKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: excludeMacJunkKey) }
    }

    static var selectResultInFinder: Bool {
        get {
            if UserDefaults.standard.object(forKey: selectResultInFinderKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: selectResultInFinderKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: selectResultInFinderKey) }
    }

    static var smartUnwrapSubfolder: Bool {
        get {
            if UserDefaults.standard.object(forKey: smartUnwrapSubfolderKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: smartUnwrapSubfolderKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: smartUnwrapSubfolderKey) }
    }
}

final class ArchiveEngine {

    static let shared = ArchiveEngine()

    private let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    private func findExecutable(_ name: String) -> String? {
        let fm = FileManager.default
        for dir in searchPaths {
            let full = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: full) {
                return full
            }
        }
        return nil
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd = currentDirectory {
            process.currentDirectoryURL = cwd
        }

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths.joined(separator: ":")
        env["COPYFILE_DISABLE"] = ArchivePreferences.excludeMacJunk ? "1" : "0"
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.wait()
        process.waitUntilExit()

        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        let combined = [outStr, errStr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return (process.terminationStatus, combined)
    }

    // MARK: - Compression

    func compress(items: [URL], format: CompressFormat, preferredDir: URL?) throws -> URL {
        let validItems = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validItems.isEmpty else {
            throw ArchiveError.emptySelection
        }

        let fm = FileManager.default
        let outDir = resolveCommonParentDirectory(for: validItems, fallback: preferredDir)

        // Determine archive base name
        let baseName: String
        if validItems.count == 1 {
            let single = validItems[0]
            var isDir: ObjCBool = false
            fm.fileExists(atPath: single.path, isDirectory: &isDir)
            if isDir.boolValue {
                // Keep full directory name without stripping dots like "v1.2"
                baseName = single.lastPathComponent
            } else {
                baseName = ArchiveDetector.archiveBaseName(for: single)
            }
        } else {
            let dirName = outDir.lastPathComponent
            if dirName.isEmpty || dirName == "/" || dirName == "Desktop" {
                baseName = "归档"
            } else {
                baseName = dirName
            }
        }

        let finalURL = ArchiveDetector.uniqueDestinationURL(
            in: outDir,
            baseName: baseName,
            ext: format.fileExtension
        )

        let tempArchiveName = ".quickarchive_tmp_\(UUID().uuidString.prefix(8)).\(format.fileExtension)"
        let tempArchiveURL = outDir.appendingPathComponent(tempArchiveName)
        defer {
            if fm.fileExists(atPath: tempArchiveURL.path) {
                try? fm.removeItem(at: tempArchiveURL)
            }
        }

        // Compute relative paths from outDir
        let outDirPrefix = outDir.standardizedFileURL.path.hasSuffix("/")
            ? outDir.standardizedFileURL.path
            : outDir.standardizedFileURL.path + "/"

        let relativePaths: [String] = validItems.map { url in
            let stdPath = url.standardizedFileURL.path
            if stdPath.hasPrefix(outDirPrefix) {
                return String(stdPath.dropFirst(outDirPrefix.count))
            }
            return url.lastPathComponent
        }

        let excludeJunk = ArchivePreferences.excludeMacJunk

        switch format {
        case .zip:
            guard let zipBin = findExecutable("zip") else {
                throw ArchiveError.toolMissing("zip")
            }
            var args = ["-r", "-y", "-q", "-b", NSTemporaryDirectory(), tempArchiveURL.path] + relativePaths
            if excludeJunk {
                args += ["-x", "*.DS_Store", "*/.DS_Store", ".DS_Store", "__MACOSX/*", "*/._*", "._*"]
            }
            let res = try runProcess(executable: zipBin, arguments: args, currentDirectory: outDir)
            guard res.exitCode == 0, fm.fileExists(atPath: tempArchiveURL.path) else {
                throw ArchiveError.commandFailed("ZIP 压缩失败：\(res.output)")
            }

        case .sevenZip:
            guard let sevenBin = findExecutable("7zz") ?? findExecutable("7z") else {
                throw ArchiveError.toolMissing("7zz (请通过 brew install sevenzip 安装)")
            }
            var args = ["a", "-t7z", "-mx=5", "-y"]
            if excludeJunk {
                args += ["-xr!.DS_Store", "-xr!._*", "-xr!__MACOSX"]
            }
            args += [tempArchiveURL.path, "--"] + relativePaths
            let res = try runProcess(executable: sevenBin, arguments: args, currentDirectory: outDir)
            guard res.exitCode == 0, fm.fileExists(atPath: tempArchiveURL.path) else {
                throw ArchiveError.commandFailed("7Z 压缩失败：\(res.output)")
            }

        case .tarGz:
            guard let tarBin = findExecutable("tar") else {
                throw ArchiveError.toolMissing("tar")
            }
            var args: [String] = []
            if excludeJunk {
                args += ["--exclude=.DS_Store", "--exclude=._*", "--exclude=__MACOSX"]
            }
            args += ["-czf", tempArchiveURL.path, "--"] + relativePaths
            let res = try runProcess(executable: tarBin, arguments: args, currentDirectory: outDir)
            guard res.exitCode == 0, fm.fileExists(atPath: tempArchiveURL.path) else {
                throw ArchiveError.commandFailed("TAR.GZ 压缩失败：\(res.output)")
            }

        case .tarXz:
            guard let tarBin = findExecutable("tar"),
                  let xzBin = findExecutable("xz") else {
                throw ArchiveError.toolMissing("tar / xz")
            }
            var args: [String] = ["--use-compress-program=\(xzBin)"]
            if excludeJunk {
                args += ["--exclude=.DS_Store", "--exclude=._*", "--exclude=__MACOSX"]
            }
            args += ["-cf", tempArchiveURL.path, "--"] + relativePaths
            let res = try runProcess(executable: tarBin, arguments: args, currentDirectory: outDir)
            guard res.exitCode == 0, fm.fileExists(atPath: tempArchiveURL.path) else {
                throw ArchiveError.commandFailed("TAR.XZ 压缩失败：\(res.output)")
            }

        case .tarZst:
            guard let tarBin = findExecutable("tar"),
                  let zstdBin = findExecutable("zstd") else {
                throw ArchiveError.toolMissing("tar / zstd")
            }
            var args: [String] = ["--use-compress-program=\(zstdBin)"]
            if excludeJunk {
                args += ["--exclude=.DS_Store", "--exclude=._*", "--exclude=__MACOSX"]
            }
            args += ["-cf", tempArchiveURL.path, "--"] + relativePaths
            let res = try runProcess(executable: tarBin, arguments: args, currentDirectory: outDir)
            guard res.exitCode == 0, fm.fileExists(atPath: tempArchiveURL.path) else {
                throw ArchiveError.commandFailed("TAR.ZST 压缩失败：\(res.output)")
            }
        }

        // Re-check final destination collision right before atomic move
        let safeFinalURL = fm.fileExists(atPath: finalURL.path)
            ? ArchiveDetector.uniqueDestinationURL(in: outDir, baseName: baseName, ext: format.fileExtension)
            : finalURL

        try fm.moveItem(at: tempArchiveURL, to: safeFinalURL)
        return safeFinalURL
    }

    // MARK: - Extraction

    func extract(
        archiveURL: URL,
        mode: ExtractMode,
        password: String? = nil
    ) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: archiveURL.path) else {
            throw ArchiveError.commandFailed("找不到压缩包：\(archiveURL.lastPathComponent)")
        }

        let outDir = archiveURL.deletingLastPathComponent()
        let tempDir = outDir.appendingPathComponent(".quickarchive_ext_\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            if fm.fileExists(atPath: tempDir.path) {
                try? fm.removeItem(at: tempDir)
            }
        }

        try unpackIntoDirectory(archiveURL: archiveURL, tempDir: tempDir, password: password)

        // Clean cross-platform metadata folders like __MACOSX inside staging dir
        let macosxFolder = tempDir.appendingPathComponent("__MACOSX")
        if fm.fileExists(atPath: macosxFolder.path) {
            try? fm.removeItem(at: macosxFolder)
        }
        let dsStore = tempDir.appendingPathComponent(".DS_Store")
        if fm.fileExists(atPath: dsStore.path) {
            try? fm.removeItem(at: dsStore)
        }

        let topItems = (try? fm.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []

        switch mode {
        case .toSubfolder:
            let baseName = ArchiveDetector.archiveBaseName(for: archiveURL)
            let destFolder = ArchiveDetector.uniqueDestinationURL(in: outDir, baseName: baseName, ext: nil)

            // Smart unwrap: if archive already contains a single root folder, move it directly as destFolder
            if ArchivePreferences.smartUnwrapSubfolder, topItems.count == 1 {
                let singleItem = topItems[0]
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: singleItem.path, isDirectory: &isDir), isDir.boolValue {
                    try fm.moveItem(at: singleItem, to: destFolder)
                    return [destFolder]
                }
            }

            try fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
            for item in topItems {
                let target = destFolder.appendingPathComponent(item.lastPathComponent)
                try fm.moveItem(at: item, to: target)
            }
            return [destFolder]

        case .toCurrentDir:
            var movedURLs: [URL] = []
            for item in topItems {
                let directCandidate = outDir.appendingPathComponent(item.lastPathComponent)
                let finalItemURL: URL
                if fm.fileExists(atPath: directCandidate.path) {
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: item.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        finalItemURL = ArchiveDetector.uniqueDestinationURL(
                            in: outDir,
                            baseName: item.lastPathComponent,
                            ext: nil
                        )
                    } else {
                        let ext = item.pathExtension
                        let stem = ext.isEmpty
                            ? item.lastPathComponent
                            : String(item.lastPathComponent.dropLast(ext.count + 1))
                        finalItemURL = ArchiveDetector.uniqueDestinationURL(
                            in: outDir,
                            baseName: stem,
                            ext: ext.isEmpty ? nil : ext
                        )
                    }
                } else {
                    finalItemURL = directCandidate
                }
                try fm.moveItem(at: item, to: finalItemURL)
                movedURLs.append(finalItemURL)
            }
            return movedURLs
        }
    }

    private func unpackIntoDirectory(archiveURL: URL, tempDir: URL, password: String?) throws {
        let lowerName = archiveURL.lastPathComponent.lowercased()

        // 1. Handle .tar.zst / .tzst explicitly
        if lowerName.hasSuffix(".tar.zst") || lowerName.hasSuffix(".tzst") {
            guard let tarBin = findExecutable("tar"),
                  let zstdBin = findExecutable("zstd") else {
                throw ArchiveError.toolMissing("tar / zstd")
            }
            let res = try runProcess(
                executable: tarBin,
                arguments: ["--use-compress-program=\(zstdBin)", "-xf", archiveURL.path, "-C", tempDir.path]
            )
            guard res.exitCode == 0 else {
                throw ArchiveError.commandFailed("解压 TAR.ZST 失败：\(res.output)")
            }
            return
        }

        // 2. Handle standalone .zst
        if lowerName.hasSuffix(".zst") {
            guard let zstdBin = findExecutable("zstd") else {
                throw ArchiveError.toolMissing("zstd")
            }
            let outFile = tempDir.appendingPathComponent(ArchiveDetector.archiveBaseName(for: archiveURL))
            let res = try runProcess(
                executable: zstdBin,
                arguments: ["-d", "-q", archiveURL.path, "-o", outFile.path]
            )
            guard res.exitCode == 0 else {
                throw ArchiveError.commandFailed("解压 ZST 失败：\(res.output)")
            }
            return
        }

        // 3. Handle .7z / .7z.001 primarily with 7zz (fastest & full 7z feature set)
        if lowerName.hasSuffix(".7z") || lowerName.hasSuffix(".7z.001") {
            if let sevenBin = findExecutable("7zz") ?? findExecutable("7z") {
                let pwdArg = "-p\(password ?? "")"
                let res = try runProcess(
                    executable: sevenBin,
                    arguments: ["x", "-y", pwdArg, "-o\(tempDir.path)", "--", archiveURL.path]
                )
                if res.exitCode == 0 {
                    return
                }
                if isPasswordErrorOutput(res.output) {
                    throw (password == nil) ? ArchiveError.passwordRequired : ArchiveError.wrongPassword
                }
                throw ArchiveError.commandFailed("解压 7Z 失败：\(res.output)")
            }
        }

        // 4. Primary universal extractor: unar (auto-detects GBK/Shift-JIS/UTF-8, supports RAR5/ZIP/TAR.*/GZ/BZ2/XZ)
        let isTarCompound = lowerName.contains(".tar.") ||
            lowerName.hasSuffix(".tgz") ||
            lowerName.hasSuffix(".txz") ||
            lowerName.hasSuffix(".tbz") ||
            lowerName.hasSuffix(".tbz2")

        if let unarBin = findExecutable("unar") {
            var args = ["-q", "-o", tempDir.path, "-D", "-f", "-nq"]
            if !isTarCompound {
                args.append("-nr") // Prevent unpacking nested archives inside zip/rar
            }
            if let pwd = password {
                args += ["-p", pwd]
            }
            args += ["--", archiveURL.path]

            let res = try runProcess(executable: unarBin, arguments: args)
            if res.exitCode == 0 {
                return
            }
            if isPasswordErrorOutput(res.output) {
                throw (password == nil) ? ArchiveError.passwordRequired : ArchiveError.wrongPassword
            }

            // Fallback to 7zz if unar couldn't handle a newer zip/rar compression method
            if let sevenBin = findExecutable("7zz") ?? findExecutable("7z") {
                // Clean partial files before retry
                if let partials = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
                    for p in partials { try? FileManager.default.removeItem(at: p) }
                }
                let pwdArg = "-p\(password ?? "")"
                let res7z = try runProcess(
                    executable: sevenBin,
                    arguments: ["x", "-y", pwdArg, "-o\(tempDir.path)", "--", archiveURL.path]
                )
                if res7z.exitCode == 0 {
                    return
                }
                if isPasswordErrorOutput(res7z.output) {
                    throw (password == nil) ? ArchiveError.passwordRequired : ArchiveError.wrongPassword
                }
            }

            throw ArchiveError.commandFailed("解压失败（\(archiveURL.lastPathComponent)）：\(res.output)")
        }

        // 5. Fallback if unar is not present: 7zz or system tar/unzip
        if let sevenBin = findExecutable("7zz") ?? findExecutable("7z") {
            let pwdArg = "-p\(password ?? "")"
            let res = try runProcess(
                executable: sevenBin,
                arguments: ["x", "-y", pwdArg, "-o\(tempDir.path)", "--", archiveURL.path]
            )
            if res.exitCode == 0 {
                return
            }
            if isPasswordErrorOutput(res.output) {
                throw (password == nil) ? ArchiveError.passwordRequired : ArchiveError.wrongPassword
            }
            throw ArchiveError.commandFailed("解压失败：\(res.output)")
        }

        throw ArchiveError.toolMissing("unar / 7zz")
    }

    private func isPasswordErrorOutput(_ output: String) -> Bool {
        let lower = output.lowercased()
        let keywords = [
            "requires a password",
            "wrong password",
            "password required",
            "encrypted",
            "data error in encrypted file",
            "headers error"
        ]
        return keywords.contains { lower.contains($0) }
    }

    private func resolveCommonParentDirectory(for urls: [URL], fallback: URL?) -> URL {
        guard let first = urls.first else {
            return fallback ?? FileManager.default.homeDirectoryForCurrentUser
        }
        let firstParent = first.standardizedFileURL.deletingLastPathComponent()
        let allSameParent = urls.allSatisfy {
            $0.standardizedFileURL.deletingLastPathComponent().path == firstParent.path
        }
        if allSameParent {
            return firstParent
        }
        if let fb = fallback, FileManager.default.fileExists(atPath: fb.path) {
            return fb
        }
        return firstParent
    }
}

// MARK: - Finder Scripting Bridge Helper

enum FinderBridge {
    /// Query current selection in Finder via AppleScript (fallback for virtual folders)
    static func getSelectedURLs() -> [URL] {
        let scriptSrc = """
        tell application "Finder"
            set theSelection to selection
            set pathList to {}
            repeat with anItem in theSelection
                try
                    set end of pathList to POSIX path of (anItem as alias)
                end try
            end repeat
            return pathList
        end tell
        """
        guard let script = NSAppleScript(source: scriptSrc) else { return [] }
        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        guard errorDict == nil else { return [] }

        var urls: [URL] = []
        let count = descriptor.numberOfItems
        if count > 0 {
            for idx in 1...count {
                if let path = descriptor.atIndex(idx)?.stringValue, !path.isEmpty {
                    urls.append(URL(fileURLWithPath: path))
                }
            }
        }
        return urls
    }

    /// Highlight newly created archive or extracted items in the active Finder window without stealing focus
    static func selectItemsInFinder(_ urls: [URL]) {
        guard !urls.isEmpty, ArchivePreferences.selectResultInFinder else { return }
        let posixLiterals = urls.map { url -> String in
            let escaped = url.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "(POSIX file \"\(escaped)\")"
        }.joined(separator: ", ")

        let scriptSrc = """
        tell application "Finder"
            try
                select {\(posixLiterals)}
            end try
        end tell
        """
        DispatchQueue.global(qos: .utility).async {
            if let script = NSAppleScript(source: scriptSrc) {
                var err: NSDictionary?
                _ = script.executeAndReturnError(&err)
            }
        }
    }

    /// Check if our FinderSync extension is currently enabled in pluginkit
    static func isExtensionEnabled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        proc.arguments = ["-m", "-i", "com.antigravity.quickarchive.findersync"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let str = String(data: data, encoding: .utf8) ?? ""
            return str.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+")
        } catch {
            return false
        }
    }

    /// Enable and register our FinderSync extension
    static func enableExtension() {
        let appexPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/QuickArchiveFinderSync.appex")
            .path
        _ = try? runSimple("/usr/bin/pluginkit", ["-a", appexPath])
        _ = try? runSimple("/usr/bin/pluginkit", ["-e", "use", "-i", "com.antigravity.quickarchive.findersync"])
    }

    /// Automatically pin our toolbar item to the top-right corner of Finder's toolbar (right next to Search)
    @discardableResult
    static func pinToFinderToolbarRightCorner(restartFinder: Bool = true) -> Bool {
        let extID = "com.antigravity.quickarchive.findersync"
        let domain = "com.apple.finder" as CFString
        let key = "NSToolbar Configuration Browser" as CFString

        var config = (CFPreferencesCopyAppValue(key, domain) as? [String: Any]) ?? [:]
        var items = (config["TB Item Identifiers"] as? [String]) ?? [
            "com.apple.finder.BACK",
            "com.apple.finder.SWCH",
            "NSToolbarSpaceItem",
            "com.apple.finder.ARNG",
            "com.apple.finder.SHAR",
            "com.apple.finder.LABL",
            "com.apple.finder.ACTN",
            "NSToolbarSpaceItem",
            "com.apple.finder.SRCH"
        ]

        // Remove stale probes and rigid NSToolbarSpaceItem spacers that cause overflow/oscillation
        items.removeAll {
            $0 == "com.local.probe.findersync" ||
            $0 == "NSToolbarSpaceItem" ||
            $0 == "NSToolbarFlexibleSpaceItem" ||
            $0 == extID
        }

        // Insert a single 0-min-width flexible space before right-aligned extension/search items
        let rightAnchorIndex = items.firstIndex(where: {
            $0.contains("findersync") || $0 == "com.apple.finder.SRCH"
        }) ?? items.endIndex
        items.insert("NSToolbarFlexibleSpaceItem", at: rightAnchorIndex)

        if let searchIdx = items.lastIndex(of: "com.apple.finder.SRCH") {
            items.insert(extID, at: searchIdx)
        } else {
            items.append(extID)
        }
        config["TB Item Identifiers"] = items
        config["TB Is Shown"] = 1
        CFPreferencesSetAppValue(key, config as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)

        if restartFinder {
            _ = try? runSimple("/usr/bin/killall", ["Finder"])
        }
        return true
    }

    static func isPinnedInFinderToolbar() -> Bool {
        let domain = "com.apple.finder" as CFString
        let key = "NSToolbar Configuration Browser" as CFString
        guard let config = CFPreferencesCopyAppValue(key, domain) as? [String: Any],
              let items = config["TB Item Identifiers"] as? [String] else {
            return false
        }
        return items.contains("com.antigravity.quickarchive.findersync")
    }

    private static func runSimple(_ bin: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
    }
}
