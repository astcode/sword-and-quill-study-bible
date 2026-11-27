import Compression
import Foundation
import SherpaOnnxC
import SwiftUI

// MARK: - Neural Voice Packs (Fast Piper/VITS + Kokoro-82M Studio)

public enum NeuralPackID: String, CaseIterable, Identifiable, Sendable {
    case piperRyan = "piper-ryan-en"
    case piperLessac = "piper-lessac-en"
    case kokoro = "kokoro-en-v0_19"

    public var id: String { rawValue }

    public var isVits: Bool {
        switch self {
        case .piperRyan, .piperLessac: return true
        case .kokoro: return false
        }
    }

    public var title: String {
        switch self {
        case .piperRyan: return "Ryan · Fast Neural Narrator (US Male)"
        case .piperLessac: return "Lessac · Fast Neural Narrator (US Female)"
        case .kokoro: return "Kokoro-82M Studio Pack (11 Voices)"
        }
    }

    public var shortName: String {
        switch self {
        case .piperRyan: return "Ryan"
        case .piperLessac: return "Lessac"
        case .kokoro: return "Kokoro-82M"
        }
    }

    public var badgeText: String {
        switch self {
        case .piperRyan, .piperLessac: return "Fast · Instant"
        case .kokoro: return "11 Voices · M-Series"
        }
    }

    public var summary: String {
        switch self {
        case .piperRyan:
            return "Warm, rich American male narrator (Piper VITS). Instant zero-pause verse playback on all iPads, 100% offline."
        case .piperLessac:
            return "Clear, natural American female narrator (Piper VITS). Instant zero-pause verse playback on all iPads, 100% offline."
        case .kokoro:
            return "11 studio US & UK voices (Michael, George, Bella, Emma & more). Heavier 82M model — fastest on M1/M2/M4 iPads."
        }
    }

    public var approxDownloadSize: String {
        switch self {
        case .piperRyan, .piperLessac: return "~60 MB"
        case .kokoro: return "~95 MB"
        }
    }

    public var requiredFiles: [String] {
        if isVits {
            return ["model.onnx", "tokens.txt", "lexicon-en-us.txt"]
        }
        return ["model.int8.onnx", "voices.bin", "tokens.txt", "lexicon-en-us.txt"]
    }

    public var voiceIdentifierPrefix: String {
        switch self {
        case .piperRyan: return "piper:ryan"
        case .piperLessac: return "piper:lessac"
        case .kokoro: return "kokoro:"
        }
    }
}

// MARK: - Kokoro-82M Studio Neural Voice Definitions (11 Built-In Speakers)

public struct KokoroVoice: Identifiable, Hashable, Sendable {
    public let sid: Int32
    public let code: String
    public let displayName: String
    public let accent: String
    public let styleHint: String

    public var id: String { "kokoro:\(sid)" }
    public var fullLabel: String { "\(displayName) (\(accent))" }

    public static let allVoices: [KokoroVoice] = [
        KokoroVoice(sid: 6, code: "am_michael", displayName: "Michael", accent: "US Male", styleHint: "Warm & resonant"),
        KokoroVoice(sid: 9, code: "bm_george", displayName: "George", accent: "UK Male", styleHint: "Classic KJV narrator"),
        KokoroVoice(sid: 5, code: "am_adam", displayName: "Adam", accent: "US Male", styleHint: "Deep & steady"),
        KokoroVoice(sid: 10, code: "bm_lewis", displayName: "Lewis", accent: "UK Male", styleHint: "Clear & measured"),
        KokoroVoice(sid: 1, code: "af_bella", displayName: "Bella", accent: "US Female", styleHint: "Expressive & warm"),
        KokoroVoice(sid: 3, code: "af_sarah", displayName: "Sarah", accent: "US Female", styleHint: "Calm & natural"),
        KokoroVoice(sid: 7, code: "bf_emma", displayName: "Emma", accent: "UK Female", styleHint: "Crisp & gentle"),
        KokoroVoice(sid: 8, code: "bf_isabella", displayName: "Isabella", accent: "UK Female", styleHint: "Refined & clear"),
        KokoroVoice(sid: 2, code: "af_nicole", displayName: "Nicole", accent: "US Female", styleHint: "Soft & contemplative"),
        KokoroVoice(sid: 4, code: "af_sky", displayName: "Sky", accent: "US Female", styleHint: "Bright & clear"),
        KokoroVoice(sid: 0, code: "af", displayName: "Heart", accent: "US Female", styleHint: "Balanced studio"),
    ]

    public static let defaultVoice: KokoroVoice = allVoices[0]

    public static func fromIdentifier(_ id: String) -> KokoroVoice? {
        allVoices.first(where: { $0.id == id })
    }
}

// MARK: - Voice Pack Remote Manifest

private struct NeuralPackFileEntry: Codable, Sendable {
    let file: String
    let target: String
    let append: Bool
    let rawSize: Int
    let compressedSize: Int
}

private struct NeuralPackManifest: Codable, Sendable {
    let id: String
    let title: String
    let version: Int
    let totalDownloadBytes: Int
    let totalDiskBytes: Int
    let files: [NeuralPackFileEntry]
}

// MARK: - Engine Spec passed to background C synthesis thread

public struct NeuralEngineSpec: Hashable, Sendable {
    public let pack: NeuralPackID
    public let modelPath: String
    public let voicesPath: String
    public let tokensPath: String
    public let lexiconPath: String
}

// MARK: - Optional Downloadable Neural Voice Pack Manager

@MainActor
public final class KokoroVoiceManager: ObservableObject {
    public static let voicesBaseURL = URL(string: "https://swordandquillbible.com/modules/voices/")!

    @Published public private(set) var installedPacks: Set<NeuralPackID> = []
    @Published public private(set) var downloadingPack: NeuralPackID? = nil
    @Published public private(set) var downloadProgress: Double = 0.0
    @Published public private(set) var statusText: String? = nil
    @Published public private(set) var errorMessage: String? = nil

    public let voicesRootDir: URL
    public var onPackChanged: (() -> Void)? = nil
    private var downloadTask: Task<Void, Never>? = nil

    public var isDownloading: Bool { downloadingPack != nil }
    public var hasAnyNeuralVoice: Bool { !installedPacks.isEmpty }
    public var isInstalled: Bool { installedPacks.contains(.kokoro) }

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.voicesRootDir = appSupport.appendingPathComponent("KJVStudyBible/Voices", isDirectory: true)
        refreshInstallState()
    }

    public func packDir(for pack: NeuralPackID) -> URL {
        voicesRootDir.appendingPathComponent(pack.rawValue, isDirectory: true)
    }

    public func isInstalled(_ pack: NeuralPackID) -> Bool {
        installedPacks.contains(pack)
    }

    public func engineSpec(for pack: NeuralPackID) -> NeuralEngineSpec {
        let dir = packDir(for: pack)
        return NeuralEngineSpec(
            pack: pack,
            modelPath: dir.appendingPathComponent(pack.isVits ? "model.onnx" : "model.int8.onnx").path,
            voicesPath: pack.isVits ? "" : dir.appendingPathComponent("voices.bin").path,
            tokensPath: dir.appendingPathComponent("tokens.txt").path,
            lexiconPath: dir.appendingPathComponent("lexicon-en-us.txt").path
        )
    }

    /// Best installed neural pack for instant playback (prefers fast Piper VITS if installed).
    public var preferredInstalledPack: NeuralPackID? {
        if installedPacks.contains(.piperRyan) { return .piperRyan }
        if installedPacks.contains(.piperLessac) { return .piperLessac }
        if installedPacks.contains(.kokoro) { return .kokoro }
        return nil
    }

    public func refreshInstallState() {
        let fm = FileManager.default
        var found: Set<NeuralPackID> = []
        for pack in NeuralPackID.allCases {
            let dir = packDir(for: pack)
            let ok = pack.requiredFiles.allSatisfy { name in
                let p = dir.appendingPathComponent(name).path
                guard fm.fileExists(atPath: p),
                      let attrs = try? fm.attributesOfItem(atPath: p),
                      let sz = attrs[.size] as? Int64 else { return false }
                return sz > 100
            }
            if ok { found.insert(pack) }
        }
        installedPacks = found
    }

    public func formattedDiskSize(for pack: NeuralPackID) -> String {
        let fm = FileManager.default
        let dir = packDir(for: pack)
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 MB"
        }
        let total = items.reduce(Int64(0)) { sum, url in
            let sz = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(sz)
        }
        return String(format: "%.0f MB", Double(total) / 1_048_576.0)
    }

    public func startDownload(_ pack: NeuralPackID) {
        guard downloadingPack == nil else { return }
        downloadingPack = pack
        downloadProgress = 0.0
        errorMessage = nil
        statusText = "Fetching \(pack.shortName) manifest…"

        downloadTask = Task { [weak self] in
            guard let self else { return }
            await self.performDownload(pack)
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingPack = nil
        downloadProgress = 0.0
        statusText = nil
    }

    public func removeVoicePack(_ pack: NeuralPackID) {
        if downloadingPack == pack { cancelDownload() }
        try? FileManager.default.removeItem(at: packDir(for: pack))
        refreshInstallState()
        onPackChanged?()
        statusText = "\(pack.shortName) removed."
    }

    private func performDownload(_ pack: NeuralPackID) async {
        let fm = FileManager.default
        let destDir = packDir(for: pack)
        let stagingDir = voicesRootDir.appendingPathComponent("\(pack.rawValue)-staging", isDirectory: true)
        let packBaseURL = Self.voicesBaseURL.appendingPathComponent(pack.rawValue, isDirectory: true)

        do {
            var mComps = URLComponents(url: packBaseURL.appendingPathComponent("manifest.json"), resolvingAgainstBaseURL: false)
            mComps?.queryItems = [URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))")]
            let manifestURL = mComps?.url ?? packBaseURL.appendingPathComponent("manifest.json")
            var manifestReq = URLRequest(url: manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            manifestReq.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (manifestData, manifestResp) = try await URLSession.shared.data(for: manifestReq)
            if let http = manifestResp as? HTTPURLResponse, http.statusCode != 200 {
                throw NSError(domain: "NeuralVoice", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Voice pack server returned HTTP \(http.statusCode)."
                ])
            }
            let manifest = try JSONDecoder().decode(NeuralPackManifest.self, from: manifestData)

            try? fm.removeItem(at: stagingDir)
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            let totalBytes = max(1, Double(manifest.totalDownloadBytes))
            var completedBytes: Double = 0

            for (index, entry) in manifest.files.enumerated() {
                try Task.checkCancellation()
                statusText = "Downloading \(pack.shortName) (\(index + 1)/\(manifest.files.count))…"

                var comps = URLComponents(url: packBaseURL.appendingPathComponent(entry.file), resolvingAgainstBaseURL: false)
                comps?.queryItems = [URLQueryItem(name: "v", value: "\(manifest.version)")]
                let fileURL = comps?.url ?? packBaseURL.appendingPathComponent(entry.file)
                let fileReq = URLRequest(url: fileURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
                let (tempURL, resp) = try await URLSession.shared.download(for: fileReq)
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    throw NSError(domain: "NeuralVoice", code: http.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to download \(entry.file) (HTTP \(http.statusCode))."
                    ])
                }

                statusText = "Unpacking \(pack.shortName) (\(index + 1)/\(manifest.files.count))…"
                let targetURL = stagingDir.appendingPathComponent(entry.target)
                let rawSize = entry.rawSize
                let shouldAppend = entry.append

                try await Task.detached(priority: .userInitiated) {
                    let compressed = try Data(contentsOf: tempURL, options: .mappedIfSafe)
                    let inflated = try Self.inflateRawZlib(compressed, expectedSize: rawSize)
                    if shouldAppend && FileManager.default.fileExists(atPath: targetURL.path) {
                        let handle = try FileHandle(forWritingTo: targetURL)
                        try handle.seekToEnd()
                        try handle.write(contentsOf: inflated)
                        try handle.close()
                    } else {
                        try inflated.write(to: targetURL, options: .atomic)
                    }
                    try? FileManager.default.removeItem(at: tempURL)
                }.value

                completedBytes += Double(entry.compressedSize)
                downloadProgress = min(0.99, completedBytes / totalBytes)
            }

            try Task.checkCancellation()
            try? fm.removeItem(at: destDir)
            try fm.createDirectory(at: voicesRootDir, withIntermediateDirectories: true)
            try fm.moveItem(at: stagingDir, to: destDir)

            downloadProgress = 1.0
            downloadingPack = nil
            refreshInstallState()
            onPackChanged?()
            statusText = isInstalled(pack) ? "\(pack.shortName) installed (100% offline)." : nil
        } catch is CancellationError {
            try? fm.removeItem(at: stagingDir)
            downloadingPack = nil
            downloadProgress = 0.0
            statusText = nil
        } catch {
            try? fm.removeItem(at: stagingDir)
            downloadingPack = nil
            downloadProgress = 0.0
            statusText = nil
            errorMessage = error.localizedDescription
        }
    }

    nonisolated private static func inflateRawZlib(_ compressed: Data, expectedSize: Int) throws -> Data {
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
        guard decodedCount > 0 else {
            throw NSError(domain: "NeuralVoice", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to decompress neural voice asset."
            ])
        }
        out.count = decodedCount
        return out
    }
}

// MARK: - Thread-Safe On-Device Neural Synthesis Engine (Piper VITS + Kokoro-82M via SherpaOnnxC)

public struct KokoroSynthesizedAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Int32
}

public final class KokoroSpeechEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.aaron.KJVStudyBible.neuraltts", qos: .userInitiated)
    private var ttsPtr: OpaquePointer? = nil
    private var loadedSpec: NeuralEngineSpec? = nil

    public init() {}

    deinit {
        if let ptr = ttsPtr {
            SherpaOnnxDestroyOfflineTts(ptr)
            ttsPtr = nil
        }
    }

    public func prewarm(spec: NeuralEngineSpec) {
        queue.async { [weak self] in
            guard let self else { return }
            self.ensureLoaded(spec: spec)
        }
    }

    public func unload() {
        queue.async { [weak self] in
            guard let self else { return }
            if let ptr = self.ttsPtr {
                SherpaOnnxDestroyOfflineTts(ptr)
                self.ttsPtr = nil
                self.loadedSpec = nil
            }
        }
    }

    public func synthesize(
        text: String,
        speakerId: Int32,
        speed: Float,
        spec: NeuralEngineSpec
    ) async -> KokoroSynthesizedAudio? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                self.ensureLoaded(spec: spec)
                guard let tts = self.ttsPtr else {
                    continuation.resume(returning: nil)
                    return
                }

                let cleaned = Self.normalizeText(text)
                guard !cleaned.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                var genConfig = SherpaOnnxGenerationConfig()
                genConfig.sid = spec.pack.isVits ? 0 : speakerId
                genConfig.speed = max(0.5, min(2.0, speed))
                genConfig.silence_scale = 0.20

                let audioPtr = cleaned.withCString { cText in
                    withUnsafePointer(to: &genConfig) { cfgPtr in
                        SherpaOnnxOfflineTtsGenerateWithConfig(tts, cText, cfgPtr, nil, nil)
                    }
                }

                guard let audio = audioPtr else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

                let count = Int(audio.pointee.n)
                let rate = audio.pointee.sample_rate
                guard count > 0, let rawSamples = audio.pointee.samples else {
                    continuation.resume(returning: nil)
                    return
                }

                let samples = Array(UnsafeBufferPointer(start: rawSamples, count: count))
                continuation.resume(returning: KokoroSynthesizedAudio(samples: samples, sampleRate: rate))
            }
        }
    }

    private func ensureLoaded(spec: NeuralEngineSpec) {
        if ttsPtr != nil && loadedSpec == spec { return }
        if let existing = ttsPtr {
            SherpaOnnxDestroyOfflineTts(existing)
            ttsPtr = nil
            loadedSpec = nil
        }
        ttsPtr = Self.createTts(spec: spec)
        loadedSpec = ttsPtr != nil ? spec : nil
    }

    private static func createTts(spec: NeuralEngineSpec) -> OpaquePointer? {
        var config = SherpaOnnxOfflineTtsConfig()
        config.model.num_threads = 4
        config.model.debug = 0
        config.max_num_sentences = 1
        config.silence_scale = 0.20

        if spec.pack.isVits {
            config.model.vits.noise_scale = 0.667
            config.model.vits.noise_scale_w = 0.8
            config.model.vits.length_scale = 1.0
            return spec.modelPath.withCString { cModel in
                spec.tokensPath.withCString { cTokens in
                    spec.lexiconPath.withCString { cLexicon in
                        "cpu".withCString { cProvider in
                            config.model.provider = cProvider
                            config.model.vits.model = cModel
                            config.model.vits.tokens = cTokens
                            config.model.vits.lexicon = cLexicon
                            return withUnsafePointer(to: &config) { cfgPtr in
                                SherpaOnnxCreateOfflineTts(cfgPtr)
                            }
                        }
                    }
                }
            }
        } else {
            config.model.kokoro.length_scale = 1.0
            return spec.modelPath.withCString { cModel in
                spec.voicesPath.withCString { cVoices in
                    spec.tokensPath.withCString { cTokens in
                        spec.lexiconPath.withCString { cLexicon in
                            "cpu".withCString { cProvider in
                                config.model.provider = cProvider
                                config.model.kokoro.model = cModel
                                config.model.kokoro.voices = cVoices
                                config.model.kokoro.tokens = cTokens
                                config.model.kokoro.lexicon = cLexicon
                                return withUnsafePointer(to: &config) { cfgPtr in
                                    SherpaOnnxCreateOfflineTts(cfgPtr)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "¶", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
