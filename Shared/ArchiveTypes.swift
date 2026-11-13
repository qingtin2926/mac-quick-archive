import Foundation

public enum CompressFormat: String, CaseIterable {
    case zip = "zip"
    case sevenZip = "7z"
    case tarGz = "tar.gz"
    case tarXz = "tar.xz"
    case tarZst = "tar.zst"

    public var fileExtension: String {
        return self.rawValue
    }

    public var menuTitle: String {
        switch self {
        case .zip:
            return "压缩为 ZIP (.zip)  — 兼容性最佳"
        case .sevenZip:
            return "压缩为 7Z (.7z)    — 高压缩率"
        case .tarGz:
            return "压缩为 TAR.GZ (.tar.gz)"
        case .tarXz:
            return "压缩为 TAR.XZ (.tar.xz)"
        case .tarZst:
            return "压缩为 TAR.ZST (.tar.zst)"
        }
    }

    public var shortLabel: String {
        return self.rawValue.uppercased()
    }
}

public enum ExtractMode: String {
    case toSubfolder = "subfolder"
    case toCurrentDir = "here"
}

public enum ArchiveActionType: String {
    case compress = "compress"
    case extract = "extract"
    case openSettings = "settings"
}

public struct ArchiveTaskPayload {
    public let action: ArchiveActionType
    public let compressFormat: CompressFormat?
    public let extractMode: ExtractMode?
    public let itemPaths: [String]
    public let targetDirPath: String?
    public let useFinderFallbackSelection: Bool

    public init(
        action: ArchiveActionType,
        compressFormat: CompressFormat? = nil,
        extractMode: ExtractMode? = nil,
        itemPaths: [String] = [],
        targetDirPath: String? = nil,
        useFinderFallbackSelection: Bool = false
    ) {
        self.action = action
        self.compressFormat = compressFormat
        self.extractMode = extractMode
        self.itemPaths = itemPaths
        self.targetDirPath = targetDirPath
        self.useFinderFallbackSelection = useFinderFallbackSelection
    }

    public func toURL() -> URL? {
        var components = URLComponents()
        components.scheme = "quickarchive"
        components.host = "run"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "action", value: action.rawValue)
        ]
        if let fmt = compressFormat {
            queryItems.append(URLQueryItem(name: "format", value: fmt.rawValue))
        }
        if let mode = extractMode {
            queryItems.append(URLQueryItem(name: "mode", value: mode.rawValue))
        }
        if let dir = targetDirPath {
            queryItems.append(URLQueryItem(name: "dir", value: dir))
        }
        if useFinderFallbackSelection {
            queryItems.append(URLQueryItem(name: "fallback", value: "1"))
        }
        for path in itemPaths {
            queryItems.append(URLQueryItem(name: "item", value: path))
        }
        components.queryItems = queryItems
        return components.url
    }

    public static func fromURL(_ url: URL) -> ArchiveTaskPayload? {
        guard url.scheme?.lowercased() == "quickarchive",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        func firstValue(_ name: String) -> String? {
            return items.first(where: { $0.name == name })?.value
        }
        guard let actionStr = firstValue("action"),
              let action = ArchiveActionType(rawValue: actionStr) else {
            return nil
        }
        let fmt = firstValue("format").flatMap { CompressFormat(rawValue: $0) }
        let mode = firstValue("mode").flatMap { ExtractMode(rawValue: $0) }
        let dir = firstValue("dir")
        let fallback = firstValue("fallback") == "1"
        let paths = items.filter { $0.name == "item" }.compactMap { $0.value }

        return ArchiveTaskPayload(
            action: action,
            compressFormat: fmt,
            extractMode: mode,
            itemPaths: paths,
            targetDirPath: dir,
            useFinderFallbackSelection: fallback
        )
    }
}

public enum ArchiveDetector {
    /// Compound multi-part or double extensions (ordered longest/most specific first)
    private static let compoundSuffixes: [String] = [
        ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tar.lz", ".tar.lzma", ".tar.z",
        ".7z.001", ".zip.001", ".tar.001"
    ]

    /// Single-part archive extensions
    private static let singleExtensions: Set<String> = [
        "zip", "7z", "rar", "tar",
        "tgz", "txz", "tbz", "tbz2", "tzst",
        "gz", "bz2", "xz", "zst", "lzma",
        "cab", "iso", "arj", "lzh", "lha", "xar", "cpio", "cbz", "cbr"
    ]

    /// Check whether a URL points to a supported archive file (and not a directory)
    public static func isArchiveFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return false
        }
        let name = url.lastPathComponent.lowercased()

        // Check compound suffixes
        for suffix in compoundSuffixes {
            if name.hasSuffix(suffix) && name.count > suffix.count {
                return true
            }
        }

        // Check multi-part RAR like xxx.part1.rar / xxx.part01.rar
        if let _ = name.range(of: #"^.+(\.part\d+\.rar|\.r\d{2})$"#, options: .regularExpression) {
            return true
        }

        let ext = url.pathExtension.lowercased()
        return singleExtensions.contains(ext)
    }

    /// Extract clean base name without archive suffix (e.g. "backup.tar.gz" -> "backup", "data.part01.rar" -> "data")
    public static func archiveBaseName(for url: URL) -> String {
        let fileName = url.lastPathComponent
        let lower = fileName.lowercased()

        for suffix in compoundSuffixes {
            if lower.hasSuffix(suffix) && fileName.count > suffix.count {
                return String(fileName.dropLast(suffix.count))
            }
        }

        if let range = lower.range(of: #"\.part\d+\.rar$"#, options: .regularExpression) {
            let dist = lower.distance(from: range.lowerBound, to: lower.endIndex)
            if fileName.count > dist {
                return String(fileName.dropLast(dist))
            }
        }

        let ext = url.pathExtension
        if !ext.isEmpty && fileName.count > ext.count + 1 {
            return String(fileName.dropLast(ext.count + 1))
        }
        return fileName
    }

    /// Generate a non-colliding file/folder URL in the given directory (e.g. "Report.zip", "Report 2.zip")
    public static func uniqueDestinationURL(in directory: URL, baseName: String, ext: String? = nil) -> URL {
        let fm = FileManager.default
        let cleanBase = baseName.isEmpty ? "归档" : baseName

        func makeURL(index: Int) -> URL {
            let suffixNum = index == 1 ? "" : " \(index)"
            if let ext = ext, !ext.isEmpty {
                return directory.appendingPathComponent("\(cleanBase)\(suffixNum).\(ext)")
            } else {
                return directory.appendingPathComponent("\(cleanBase)\(suffixNum)")
            }
        }

        var attempt = 1
        var candidate = makeURL(index: attempt)
        while fm.fileExists(atPath: candidate.path) {
            attempt += 1
            candidate = makeURL(index: attempt)
        }
        return candidate
    }
}
