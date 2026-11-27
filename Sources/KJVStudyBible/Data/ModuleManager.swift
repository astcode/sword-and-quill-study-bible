import Compression
import Foundation
import SwiftUI

// MARK: - Modular Library Models (.sqmod)

public struct StudyModuleManifest: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let kind: String // "commentary", "bible", "dictionary", "devotional"
    public let title: String
    public let shortTitle: String
    public let abbr: String
    public let author: String
    public let description: String
    public let copyright: String
    public let version: Int
    public let entryCount: Int
    public let mqlRawSize: Int?
    public let pagesRawSize: Int?
    public let starter: Bool?
    public let downloadBytes: Int?
    public let downloadURL: String?

    public var formattedDownloadSize: String {
        let bytes = Double(downloadBytes ?? ((mqlRawSize ?? 0) + (pagesRawSize ?? 0)))
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", bytes / 1_048_576.0)
        }
        return String(format: "%.0f KB", max(1, bytes / 1024.0))
    }
}

public struct StudyModuleCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let updatedAt: String
    public let modules: [StudyModuleManifest]
}

public struct CommentaryEntry: Identifiable, Hashable, Sendable {
    public let id: Int
    public let bookId: Int
    public let chapterFrom: Int
    public let verseFrom: Int
    public let chapterTo: Int
    public let verseTo: Int
    public let body: String

    public var verseRangeLabel: String {
        if verseFrom == 0 && verseTo == 0 {
            return "Chapter Overview"
        }
        if chapterTo > chapterFrom {
            return "\(chapterFrom):\(verseFrom)–\(chapterTo):\(verseTo)"
        }
        if verseTo > verseFrom {
            return "vv. \(verseFrom)–\(verseTo)"
        }
        return "v. \(verseFrom)"
    }

    public func covers(verse: Int) -> Bool {
        if verseFrom == 0 && verseTo == 0 { return false }
        if chapterTo > chapterFrom { return verse >= verseFrom }
        return verse >= verseFrom && verse <= max(verseFrom, verseTo)
    }
}

// MARK: - Zero-Dependency SQM1 Binary Package Codec (Apple Compression ZLIB)

public enum SQModError: LocalizedError {
    case invalidMagic
    case truncatedData
    case invalidManifest
    case decompressionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidMagic: return "Not a valid Sword & Quill (.sqmod) module file."
        case .truncatedData: return "Module file appears incomplete or corrupted."
        case .invalidManifest: return "Could not read module metadata."
        case .decompressionFailed: return "Could not decompress module database."
        }
    }
}

public enum SQModCodec {
    public static func unpack(sqmodData: Data, into destinationDir: URL) throws -> StudyModuleManifest {
        guard sqmodData.count >= 12 else { throw SQModError.truncatedData }
        let magic = String(data: sqmodData.subdata(in: 0..<4), encoding: .ascii)
        guard magic == "SQM1" else { throw SQModError.invalidMagic }

        var offset = 4
        func readU32() throws -> Int {
            guard offset + 4 <= sqmodData.count else { throw SQModError.truncatedData }
            let v: UInt32 = sqmodData.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
            }
            offset += 4
            return Int(v)
        }

        let manifestLen = try readU32()
        guard offset + manifestLen <= sqmodData.count else { throw SQModError.truncatedData }
        let manifestData = sqmodData.subdata(in: offset..<(offset + manifestLen))
        offset += manifestLen

        guard let manifest = try? JSONDecoder().decode(StudyModuleManifest.self, from: manifestData) else {
            throw SQModError.invalidManifest
        }

        let mqlRawLen = try readU32()
        let mqlCompLen = try readU32()
        guard offset + mqlCompLen <= sqmodData.count else { throw SQModError.truncatedData }
        let mqlComp = sqmodData.subdata(in: offset..<(offset + mqlCompLen))
        offset += mqlCompLen

        let pagesRawLen = try readU32()
        let pagesCompLen = try readU32()
        guard offset + pagesCompLen <= sqmodData.count else { throw SQModError.truncatedData }
        let pagesComp = sqmodData.subdata(in: offset..<(offset + pagesCompLen))

        let mqlData = try inflateRaw(mqlComp, expectedSize: mqlRawLen)
        let pagesData: Data? = (pagesRawLen > 0 && pagesCompLen > 0)
            ? try inflateRaw(pagesComp, expectedSize: pagesRawLen)
            : nil

        let fm = FileManager.default
        let modDir = destinationDir.appendingPathComponent(manifest.id, isDirectory: true)
        try? fm.removeItem(at: modDir)
        try fm.createDirectory(at: modDir, withIntermediateDirectories: true)

        try manifestData.write(to: modDir.appendingPathComponent("manifest.json"), options: .atomic)
        try mqlData.write(to: modDir.appendingPathComponent("\(manifest.id).mql"), options: .atomic)
        if let pagesData {
            try pagesData.write(to: modDir.appendingPathComponent("\(manifest.id).mql.pages"), options: .atomic)
        }
        return manifest
    }

    private static func inflateRaw(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        let dstSize = max(expectedSize + 64, 1024)
        var out = Data(count: dstSize)
        let decodedCount: Int = out.withUnsafeMutableBytes { dstPtr in
            compressed.withUnsafeBytes { srcPtr in
                guard let dstBase = dstPtr.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase, dstSize,
                    srcBase, compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount > 0 else { throw SQModError.decompressionFailed }
        out.count = decodedCount
        return out
    }
}

// MARK: - Modular Library Manager (e-Sword–Style Add/Remove/Toggle)

@MainActor
public final class ModuleManager: ObservableObject {
    public static let catalogURL = URL(string: "https://swordandquillbible.com/modules/catalog.json")!

    @Published public private(set) var installedModules: [StudyModuleManifest] = []
    @Published public private(set) var enabledModuleIds: Set<String> = []
    @Published public private(set) var remoteCatalog: [StudyModuleManifest] = []
    @Published public private(set) var isLoadingCatalog: Bool = false
    @Published public private(set) var catalogError: String? = nil
    @Published public private(set) var downloadingModuleIds: Set<String> = []
    @Published public var statusMessage: String? = nil

    private let modulesRootDir: URL
    private var openHandles: [String: MagQLite] = [:]
    private let enabledKey = "sq_enabled_module_ids"
    private let removedStartersKey = "sq_removed_starter_ids"

    private static let moduleConfig = MagQLiteConfig(
        durability: "off",
        pagedStorage: true,
        bufferPoolPages: 64,
        autoCheckpointFrames: 0
    )

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modulesRootDir = appSupport.appendingPathComponent("KJVStudyBible/Modules", isDirectory: true)
        try? FileManager.default.createDirectory(at: modulesRootDir, withIntermediateDirectories: true)

        if let saved = UserDefaults.standard.array(forKey: enabledKey) as? [String] {
            self.enabledModuleIds = Set(saved)
        }
        installBundledStartersIfNeeded()
        reloadInstalledModules()
    }

    public var enabledCommentaries: [StudyModuleManifest] {
        installedModules.filter { $0.kind == "commentary" && enabledModuleIds.contains($0.id) }
    }

    public var hasEnabledCommentaries: Bool {
        !enabledCommentaries.isEmpty
    }

    public func isInstalled(_ id: String) -> Bool {
        installedModules.contains(where: { $0.id == id })
    }

    public func isEnabled(_ id: String) -> Bool {
        enabledModuleIds.contains(id)
    }

    public func diskSizeBytes(for id: String) -> Int64 {
        let dir = modulesRootDir.appendingPathComponent(id, isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(0) { sum, url in
            let sz = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(sz)
        }
    }

    public func formattedDiskSize(for id: String) -> String {
        let bytes = Double(diskSizeBytes(for: id))
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", bytes / 1_048_576.0)
        }
        return String(format: "%.0f KB", max(1, bytes / 1024.0))
    }

    // MARK: - Bundled Starters

    private func installBundledStartersIfNeeded() {
        let removedStarters = Set(UserDefaults.standard.array(forKey: removedStartersKey) as? [String] ?? [])
        let starterNames = ["kjv-notes", "scofield-1917"]

        for name in starterNames {
            if removedStarters.contains(name) { continue }
            let targetDir = modulesRootDir.appendingPathComponent(name, isDirectory: true)
            if FileManager.default.fileExists(atPath: targetDir.appendingPathComponent("manifest.json").path) {
                continue
            }
            guard let url = Bundle.module.url(forResource: name, withExtension: "sqmod", subdirectory: "StarterModules")
                    ?? Bundle.module.url(forResource: name, withExtension: "sqmod"),
                  let data = try? Data(contentsOf: url),
                  let manifest = try? SQModCodec.unpack(sqmodData: data, into: modulesRootDir) else {
                continue
            }
            enabledModuleIds.insert(manifest.id)
        }
        persistEnabledIds()
    }

    public func reloadInstalledModules() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: modulesRootDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            installedModules = []
            return
        }
        var found: [StudyModuleManifest] = []
        for dir in dirs {
            let mURL = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: mURL),
                  let manifest = try? JSONDecoder().decode(StudyModuleManifest.self, from: data) else {
                continue
            }
            found.append(manifest)
        }
        found.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        installedModules = found
    }

    // MARK: - Enable / Disable / Remove

    public func setEnabled(_ id: String, enabled: Bool) {
        if enabled {
            enabledModuleIds.insert(id)
        } else {
            enabledModuleIds.remove(id)
            openHandles[id]?.close()
            openHandles.removeValue(forKey: id)
        }
        persistEnabledIds()
    }

    public func removeModule(_ id: String) {
        openHandles[id]?.close()
        openHandles.removeValue(forKey: id)
        enabledModuleIds.remove(id)
        persistEnabledIds()

        let modDir = modulesRootDir.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.removeItem(at: modDir)

        // Remember if user explicitly removed a starter so we don't re-install it next launch
        var removed = Set(UserDefaults.standard.array(forKey: removedStartersKey) as? [String] ?? [])
        removed.insert(id)
        UserDefaults.standard.set(Array(removed), forKey: removedStartersKey)

        reloadInstalledModules()
        statusMessage = "Removed module and freed storage."
    }

    private func persistEnabledIds() {
        UserDefaults.standard.set(Array(enabledModuleIds), forKey: enabledKey)
    }

    // MARK: - Remote Catalog & Download

    public func fetchCatalog() async {
        isLoadingCatalog = true
        catalogError = nil
        defer { isLoadingCatalog = false }

        do {
            var req = URLRequest(url: Self.catalogURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                catalogError = "Library catalog unavailable (HTTP \(http.statusCode))."
                return
            }
            let decoded = try JSONDecoder().decode(StudyModuleCatalog.self, from: data)
            remoteCatalog = decoded.modules
        } catch {
            catalogError = "Offline — connect to Wi-Fi to browse downloadable classics. Installed modules always work 100% offline."
        }
    }

    public func downloadAndInstall(_ remote: StudyModuleManifest) async {
        guard let urlStr = remote.downloadURL, let url = URL(string: urlStr) else {
            statusMessage = "Missing download URL for \(remote.title)."
            return
        }
        guard !downloadingModuleIds.contains(remote.id) else { return }
        downloadingModuleIds.insert(remote.id)
        defer { downloadingModuleIds.remove(remote.id) }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                statusMessage = "Download failed (HTTP \(http.statusCode))."
                return
            }
            let rootDir = self.modulesRootDir
            let manifest = try await Task.detached(priority: .userInitiated) {
                try SQModCodec.unpack(sqmodData: data, into: rootDir)
            }.value

            openHandles[manifest.id]?.close()
            openHandles.removeValue(forKey: manifest.id)

            var removed = Set(UserDefaults.standard.array(forKey: removedStartersKey) as? [String] ?? [])
            removed.remove(manifest.id)
            UserDefaults.standard.set(Array(removed), forKey: removedStartersKey)

            enabledModuleIds.insert(manifest.id)
            persistEnabledIds()
            reloadInstalledModules()
            statusMessage = "Installed \(manifest.title) — ready offline!"
        } catch {
            statusMessage = "Could not install \(remote.shortTitle): \(error.localizedDescription)"
        }
    }

    public func importLocalSQMod(url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let manifest = try SQModCodec.unpack(sqmodData: data, into: modulesRootDir)
            openHandles[manifest.id]?.close()
            openHandles.removeValue(forKey: manifest.id)
            enabledModuleIds.insert(manifest.id)
            persistEnabledIds()
            reloadInstalledModules()
            statusMessage = "Imported \(manifest.title)!"
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sub-Millisecond MagQLite Commentary Queries

    private func databaseHandle(for moduleId: String) -> MagQLite? {
        if let existing = openHandles[moduleId] {
            return existing
        }
        let mqlPath = modulesRootDir
            .appendingPathComponent(moduleId, isDirectory: true)
            .appendingPathComponent("\(moduleId).mql").path
        guard FileManager.default.fileExists(atPath: mqlPath),
              let db = try? MagQLite(path: mqlPath, config: Self.moduleConfig) else {
            return nil
        }
        openHandles[moduleId] = db
        return db
    }

    public func commentaryEntries(moduleId: String, bookId: Int, chapter: Int) -> [CommentaryEntry] {
        guard let db = databaseHandle(for: moduleId) else { return [] }
        let bcKey = Int64(bookId * 1000 + chapter)
        guard let res = try? db.queryParams(
            "SELECT id, book_id, chapter_from, verse_from, chapter_to, verse_to, body FROM commentary_entries WHERE bc_key = ? ORDER BY verse_from, id;",
            params: [.int(bcKey)]
        ) else {
            return []
        }
        return res.rows.compactMap { row in
            guard let id = row.int(at: 0),
                  let b = row.int(at: 1),
                  let cf = row.int(at: 2),
                  let vf = row.int(at: 3),
                  let ct = row.int(at: 4),
                  let vt = row.int(at: 5),
                  let body = row.string(at: 6) else { return nil }
            return CommentaryEntry(
                id: Int(id),
                bookId: Int(b),
                chapterFrom: Int(cf),
                verseFrom: Int(vf),
                chapterTo: Int(ct),
                verseTo: Int(vt),
                body: body
            )
        }
    }
}
