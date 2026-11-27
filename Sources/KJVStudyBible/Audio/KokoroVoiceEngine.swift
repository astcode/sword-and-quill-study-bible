import Compression
import Foundation
import SherpaOnnxC
import SwiftUI

// MARK: - Kokoro-82M Studio Neural Voice Definitions (11 Built-In Speakers)

public struct KokoroVoice: Identifiable, Hashable, Sendable {
    public let sid: Int32
    public let code: String
    public let displayName: String
    public let accent: String
    public let styleHint: String

    public var id: String { "kokoro:\(sid)" }
    public var fullLabel: String { "\(displayName) (\(accent))" }

    /// All 11 English studio voices in `kokoro-int8-en-v0_19`.
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

    public static let defaultVoice: KokoroVoice = allVoices[0] // Michael

    public static func fromIdentifier(_ id: String) -> KokoroVoice? {
        allVoices.first(where: { $0.id == id })
    }
}

// MARK: - Voice Pack Remote Manifest

private struct KokoroPackFileEntry: Codable, Sendable {
    let file: String
    let target: String
    let append: Bool
    let rawSize: Int
    let compressedSize: Int
}

private struct KokoroPackManifest: Codable, Sendable {
    let id: String
    let title: String
    let version: Int
    let totalDownloadBytes: Int
    let totalDiskBytes: Int
    let files: [KokoroPackFileEntry]
}

// MARK: - Optional Downloadable Voice Pack Manager

@MainActor
public final class KokoroVoiceManager: ObservableObject {
    public static let baseURL = URL(string: "https://swordandquillbible.com/modules/voices/kokoro-en-v0_19/")!

    @Published public private(set) var isInstalled: Bool = false
    @Published public private(set) var isDownloading: Bool = false
    @Published public private(set) var downloadProgress: Double = 0.0
    @Published public private(set) var statusText: String? = nil
    @Published public private(set) var errorMessage: String? = nil

    public let voiceDir: URL
    private var downloadTask: Task<Void, Never>? = nil

    public var modelPath: String { voiceDir.appendingPathComponent("model.int8.onnx").path }
    public var voicesPath: String { voiceDir.appendingPathComponent("voices.bin").path }
    public var tokensPath: String { voiceDir.appendingPathComponent("tokens.txt").path }
    public var lexiconPath: String { voiceDir.appendingPathComponent("lexicon-en-us.txt").path }

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.voiceDir = appSupport.appendingPathComponent("KJVStudyBible/Voices/kokoro-en-v0_19", isDirectory: true)
        refreshInstallState()
    }

    public func refreshInstallState() {
        let fm = FileManager.default
        let required = ["model.int8.onnx", "voices.bin", "tokens.txt", "lexicon-en-us.txt"]
        let allPresent = required.allSatisfy { name in
            let p = voiceDir.appendingPathComponent(name).path
            guard fm.fileExists(atPath: p),
                  let attrs = try? fm.attributesOfItem(atPath: p),
                  let sz = attrs[.size] as? Int64 else { return false }
            return sz > 100
        }
        isInstalled = allPresent
    }

    public var formattedDiskSize: String {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: voiceDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 MB"
        }
        let total = items.reduce(Int64(0)) { sum, url in
            let sz = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(sz)
        }
        return String(format: "%.0f MB", Double(total) / 1_048_576.0)
    }

    public func startDownload() {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0.0
        errorMessage = nil
        statusText = "Fetching voice pack manifest…"

        downloadTask = Task { [weak self] in
            guard let self else { return }
            await self.performDownload()
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
        statusText = nil
    }

    public func removeVoicePack() {
        cancelDownload()
        try? FileManager.default.removeItem(at: voiceDir)
        isInstalled = false
        statusText = "Kokoro-82M voice pack removed."
    }

    private func performDownload() async {
        let fm = FileManager.default
        let stagingDir = voiceDir.deletingLastPathComponent().appendingPathComponent("kokoro-staging", isDirectory: true)

        do {
            let manifestURL = Self.baseURL.appendingPathComponent("manifest.json")
            let (manifestData, manifestResp) = try await URLSession.shared.data(from: manifestURL)
            if let http = manifestResp as? HTTPURLResponse, http.statusCode != 200 {
                throw NSError(domain: "KokoroVoice", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Voice pack server returned HTTP \(http.statusCode)."
                ])
            }
            let manifest = try JSONDecoder().decode(KokoroPackManifest.self, from: manifestData)

            try? fm.removeItem(at: stagingDir)
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            let totalBytes = max(1, Double(manifest.totalDownloadBytes))
            var completedBytes: Double = 0

            for (index, entry) in manifest.files.enumerated() {
                try Task.checkCancellation()
                statusText = "Downloading part \(index + 1) of \(manifest.files.count)…"

                let fileURL = Self.baseURL.appendingPathComponent(entry.file)
                let (tempURL, resp) = try await URLSession.shared.download(from: fileURL)
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    throw NSError(domain: "KokoroVoice", code: http.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to download \(entry.file) (HTTP \(http.statusCode))."
                    ])
                }

                statusText = "Unpacking part \(index + 1) of \(manifest.files.count)…"
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
            try? fm.removeItem(at: voiceDir)
            try fm.createDirectory(at: voiceDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: stagingDir, to: voiceDir)

            downloadProgress = 1.0
            isDownloading = false
            refreshInstallState()
            statusText = isInstalled ? "Kokoro-82M Studio Voices installed (11 voices, 100% offline)." : nil
        } catch is CancellationError {
            try? fm.removeItem(at: stagingDir)
            isDownloading = false
            downloadProgress = 0.0
            statusText = nil
        } catch {
            try? fm.removeItem(at: stagingDir)
            isDownloading = false
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
            throw NSError(domain: "KokoroVoice", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to decompress neural voice asset."
            ])
        }
        out.count = decodedCount
        return out
    }
}

// MARK: - Thread-Safe Kokoro-82M On-Device Synthesis Engine (SherpaOnnxC)

public struct KokoroSynthesizedAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Int32
}

public final class KokoroSpeechEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.aaron.KJVStudyBible.kokoro", qos: .userInitiated)
    private var ttsPtr: OpaquePointer? = nil
    private var loadedModelPath: String? = nil

    public init() {}

    deinit {
        if let ptr = ttsPtr {
            SherpaOnnxDestroyOfflineTts(ptr)
            ttsPtr = nil
        }
    }

    public func unload() {
        queue.async { [weak self] in
            guard let self else { return }
            if let ptr = self.ttsPtr {
                SherpaOnnxDestroyOfflineTts(ptr)
                self.ttsPtr = nil
                self.loadedModelPath = nil
            }
        }
    }

    public func synthesize(
        text: String,
        speakerId: Int32,
        speed: Float,
        modelPath: String,
        voicesPath: String,
        tokensPath: String,
        lexiconPath: String
    ) async -> KokoroSynthesizedAudio? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                if self.ttsPtr == nil || self.loadedModelPath != modelPath {
                    if let existing = self.ttsPtr {
                        SherpaOnnxDestroyOfflineTts(existing)
                        self.ttsPtr = nil
                    }
                    self.ttsPtr = Self.createTts(
                        modelPath: modelPath,
                        voicesPath: voicesPath,
                        tokensPath: tokensPath,
                        lexiconPath: lexiconPath
                    )
                    self.loadedModelPath = self.ttsPtr != nil ? modelPath : nil
                }

                guard let tts = self.ttsPtr else {
                    continuation.resume(returning: nil)
                    return
                }

                let cleaned = Self.normalizeForKokoro(text)
                guard !cleaned.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                var genConfig = SherpaOnnxGenerationConfig()
                genConfig.sid = speakerId
                genConfig.speed = max(0.5, min(2.0, speed))
                genConfig.silence_scale = 0.22

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

    private static func createTts(
        modelPath: String,
        voicesPath: String,
        tokensPath: String,
        lexiconPath: String
    ) -> OpaquePointer? {
        var config = SherpaOnnxOfflineTtsConfig()
        config.model.num_threads = 2
        config.model.debug = 0
        config.model.kokoro.length_scale = 1.0
        config.max_num_sentences = 2
        config.silence_scale = 0.22

        return modelPath.withCString { cModel in
            voicesPath.withCString { cVoices in
                tokensPath.withCString { cTokens in
                    lexiconPath.withCString { cLexicon in
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

    /// Light KJV text normalization so Kokoro reads smoothly (strips pilcrow ¶, brackets, etc.).
    private static func normalizeForKokoro(_ text: String) -> String {
        text
            .replacingOccurrences(of: "¶", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
