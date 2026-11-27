import AVFoundation
import Foundation
import SwiftUI

// MARK: - 100% Offline Read-Aloud Bible Audio Player (Kokoro-82M Neural + AVSpeechSynthesizer Fallback)

public enum AudioSleepTimer: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case endOfChapter = -1
    case minutes15 = 15
    case minutes30 = 30

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .off: return "Sleep Timer: Off"
        case .endOfChapter: return "Stop at End of Chapter"
        case .minutes15: return "Sleep in 15 min"
        case .minutes30: return "Sleep in 30 min"
        }
    }
    public var shortBadge: String? {
        switch self {
        case .off: return nil
        case .endOfChapter: return "1 ch"
        case .minutes15: return "15m"
        case .minutes30: return "30m"
        }
    }
}

@MainActor
public final class BibleAudioPlayer: NSObject, ObservableObject {
    @Published public var isActive: Bool = false
    @Published public var isPlaying: Bool = false
    @Published public var isSynthesizing: Bool = false
    @Published public var currentVerseIndex: Int = 0
    @Published public var currentVerseNumber: Int = 1
    @Published public var speechRateMultiplier: Float = 1.0
    @Published public var autoAdvanceChapter: Bool = true
    @Published public var chapterTitle: String = ""
    @Published public var sleepTimer: AudioSleepTimer = .off
    @Published public var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: "sq_audio_voice_id") ?? ""

    public let kokoroManager = KokoroVoiceManager()
    private let kokoroEngine = KokoroSpeechEngine()

    // Apple System Fallback
    private let synthesizer = AVSpeechSynthesizer()

    // Neural PCM Playback Engine (AVAudioEngine + AVAudioPlayerNode)
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var engineAttached = false
    private var engineSampleRate: Double = 0
    private var neuralGenerationID: UInt64 = 0
    private var neuralTask: Task<Void, Never>? = nil
    private var prefetchedVerseIndex: Int? = nil
    private var prefetchedAudio: KokoroSynthesizedAudio? = nil
    private var prefetchTask: Task<Void, Never>? = nil
    private var isNeuralPaused: Bool = false

    private var verses: [Verse] = []
    private var onHighlightVerse: ((Int) -> Void)?
    private var onChapterFinished: (() -> Void)?
    private var sleepDeadline: Date? = nil

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// True when Kokoro-82M is installed and the user has either chosen a Kokoro voice or not overridden it with an Apple voice.
    public var isUsingNeuralVoice: Bool {
        guard kokoroManager.isInstalled else { return false }
        if selectedVoiceIdentifier.isEmpty { return true }
        return selectedVoiceIdentifier.hasPrefix("kokoro:")
    }

    public var activeKokoroVoice: KokoroVoice {
        KokoroVoice.fromIdentifier(selectedVoiceIdentifier) ?? KokoroVoice.defaultVoice
    }

    public var activeVoiceDisplayName: String {
        if isUsingNeuralVoice {
            return "\(activeKokoroVoice.displayName) · Neural"
        }
        if let v = resolvedAppleVoice() {
            return v.name
        }
        return "System Voice"
    }

    public var availableEnglishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-") }
            .sorted { a, b in
                if a.quality.rawValue != b.quality.rawValue {
                    return a.quality.rawValue > b.quality.rawValue
                }
                return a.name < b.name
            }
    }

    public func selectKokoroVoice(_ voice: KokoroVoice) {
        selectedVoiceIdentifier = voice.id
        UserDefaults.standard.set(voice.id, forKey: "sq_audio_voice_id")
        clearPrefetch()
        if isPlaying || isSynthesizing {
            stopCurrentSpeechOnly()
            speakCurrentVerse()
        }
    }

    public func selectVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoiceIdentifier = voice.identifier
        UserDefaults.standard.set(voice.identifier, forKey: "sq_audio_voice_id")
        clearPrefetch()
        if isPlaying || isSynthesizing {
            stopCurrentSpeechOnly()
            speakCurrentVerse()
        }
    }

    public func setSleepTimer(_ timer: AudioSleepTimer) {
        sleepTimer = timer
        switch timer {
        case .off, .endOfChapter:
            sleepDeadline = nil
        case .minutes15:
            sleepDeadline = Date().addingTimeInterval(15 * 60)
        case .minutes30:
            sleepDeadline = Date().addingTimeInterval(30 * 60)
        }
    }

    public func startChapter(
        title: String,
        verses: [Verse],
        startingAtVerse: Int? = nil,
        onHighlightVerse: @escaping (Int) -> Void,
        onChapterFinished: @escaping () -> Void
    ) {
        guard !verses.isEmpty else { return }
        stop(hideBar: false)
        configureAudioSession()

        self.chapterTitle = title
        self.verses = verses
        self.onHighlightVerse = onHighlightVerse
        self.onChapterFinished = onChapterFinished
        self.isActive = true

        if let startV = startingAtVerse,
           let idx = verses.firstIndex(where: { $0.verse == startV }) {
            currentVerseIndex = idx
        } else {
            currentVerseIndex = 0
        }
        speakCurrentVerse()
    }

    /// Quick one-shot read-aloud (e.g., inside Memory Drills).
    public func speakSinglePassage(_ text: String) {
        configureAudioSession()
        stopCurrentSpeechOnly()

        if isUsingNeuralVoice {
            let voice = activeKokoroVoice
            let genID = bumpNeuralGeneration()
            let mPath = kokoroManager.modelPath
            let vPath = kokoroManager.voicesPath
            let tPath = kokoroManager.tokensPath
            let lPath = kokoroManager.lexiconPath

            neuralTask = Task { [weak self] in
                guard let self else { return }
                let audio = await self.kokoroEngine.synthesize(
                    text: text,
                    speakerId: voice.sid,
                    speed: 0.96,
                    modelPath: mPath,
                    voicesPath: vPath,
                    tokensPath: tPath,
                    lexiconPath: lPath
                )
                guard !Task.isCancelled, self.neuralGenerationID == genID, let audio else { return }
                self.playPCMBuffer(audio: audio, genID: genID, advanceOnComplete: false)
            }
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolvedAppleVoice()
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 0.95))
        synthesizer.speak(utterance)
    }

    public func togglePlayPause() {
        if !isActive { return }
        if isUsingNeuralVoice {
            if isPlaying {
                if playerNode.isPlaying {
                    playerNode.pause()
                    isNeuralPaused = true
                }
                isPlaying = false
            } else if isNeuralPaused {
                try? audioEngine.start()
                playerNode.play()
                isNeuralPaused = false
                isPlaying = true
            } else {
                speakCurrentVerse()
            }
            return
        }

        if isPlaying {
            synthesizer.pauseSpeaking(at: .word)
            isPlaying = false
        } else if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPlaying = true
        } else {
            speakCurrentVerse()
        }
    }

    public func nextVerse() {
        guard !verses.isEmpty else { return }
        stopCurrentSpeechOnly()
        if currentVerseIndex + 1 < verses.count {
            currentVerseIndex += 1
            speakCurrentVerse()
        } else if autoAdvanceChapter && sleepTimer != .endOfChapter {
            onChapterFinished?()
        } else {
            isPlaying = false
        }
    }

    public func previousVerse() {
        guard !verses.isEmpty else { return }
        stopCurrentSpeechOnly()
        clearPrefetch()
        currentVerseIndex = max(0, currentVerseIndex - 1)
        speakCurrentVerse()
    }

    public func cycleSpeed() {
        let speeds: [Float] = [0.85, 1.0, 1.2, 1.4]
        if let idx = speeds.firstIndex(where: { abs($0 - speechRateMultiplier) < 0.05 }) {
            speechRateMultiplier = speeds[(idx + 1) % speeds.count]
        } else {
            speechRateMultiplier = 1.0
        }
        clearPrefetch()
        if isPlaying || isSynthesizing {
            stopCurrentSpeechOnly()
            speakCurrentVerse()
        }
    }

    public func stop(hideBar: Bool = true) {
        stopCurrentSpeechOnly()
        clearPrefetch()
        isPlaying = false
        isSynthesizing = false
        if hideBar {
            isActive = false
            verses = []
            sleepDeadline = nil
            sleepTimer = .off
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            kokoroEngine.unload()
        }
    }

    private func stopCurrentSpeechOnly() {
        _ = bumpNeuralGeneration()
        neuralTask?.cancel()
        neuralTask = nil
        isNeuralPaused = false
        isSynthesizing = false
        if playerNode.isPlaying {
            playerNode.stop()
        }
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func clearPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchedVerseIndex = nil
        prefetchedAudio = nil
    }

    private func bumpNeuralGeneration() -> UInt64 {
        neuralGenerationID &+= 1
        return neuralGenerationID
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func speakCurrentVerse() {
        if let deadline = sleepDeadline, Date() >= deadline {
            stop(hideBar: false)
            sleepTimer = .off
            sleepDeadline = nil
            return
        }
        guard currentVerseIndex >= 0 && currentVerseIndex < verses.count else {
            isPlaying = false
            return
        }
        let v = verses[currentVerseIndex]
        currentVerseNumber = v.verse
        onHighlightVerse?(v.verse)

        if isUsingNeuralVoice {
            speakCurrentVerseNeural(verseIndex: currentVerseIndex, text: v.text)
            return
        }

        let utterance = AVSpeechUtterance(string: v.text)
        utterance.voice = resolvedAppleVoice()
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * speechRateMultiplier))
        utterance.postUtteranceDelay = 0.25
        isPlaying = true
        synthesizer.speak(utterance)
    }

    // MARK: - Kokoro-82M Neural Synthesis + Lookahead Pre-Buffering

    private func speakCurrentVerseNeural(verseIndex: Int, text: String) {
        let genID = bumpNeuralGeneration()
        let voice = activeKokoroVoice
        let speed = speechRateMultiplier
        let mPath = kokoroManager.modelPath
        let vPath = kokoroManager.voicesPath
        let tPath = kokoroManager.tokensPath
        let lPath = kokoroManager.lexiconPath

        isPlaying = true
        isNeuralPaused = false

        // Instant zero-gap hit if lookahead already synthesized this verse!
        if prefetchedVerseIndex == verseIndex, let ready = prefetchedAudio {
            prefetchedVerseIndex = nil
            prefetchedAudio = nil
            isSynthesizing = false
            playPCMBuffer(audio: ready, genID: genID, advanceOnComplete: true)
            scheduleLookaheadPrefetch(nextIndex: verseIndex + 1, voice: voice, speed: speed)
            return
        }

        isSynthesizing = true
        neuralTask = Task { [weak self] in
            guard let self else { return }
            let audio = await self.kokoroEngine.synthesize(
                text: text,
                speakerId: voice.sid,
                speed: speed,
                modelPath: mPath,
                voicesPath: vPath,
                tokensPath: tPath,
                lexiconPath: lPath
            )
            guard !Task.isCancelled, self.neuralGenerationID == genID else { return }
            self.isSynthesizing = false

            guard let audio else {
                // Graceful fallback to Apple voice if synthesis fails for any reason
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = self.resolvedAppleVoice()
                utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * speed))
                self.synthesizer.speak(utterance)
                return
            }

            self.playPCMBuffer(audio: audio, genID: genID, advanceOnComplete: true)
            self.scheduleLookaheadPrefetch(nextIndex: verseIndex + 1, voice: voice, speed: speed)
        }
    }

    private func scheduleLookaheadPrefetch(nextIndex: Int, voice: KokoroVoice, speed: Float) {
        prefetchTask?.cancel()
        guard nextIndex >= 0 && nextIndex < verses.count else { return }
        let nextText = verses[nextIndex].text
        let mPath = kokoroManager.modelPath
        let vPath = kokoroManager.voicesPath
        let tPath = kokoroManager.tokensPath
        let lPath = kokoroManager.lexiconPath

        prefetchTask = Task { [weak self] in
            guard let self else { return }
            let audio = await self.kokoroEngine.synthesize(
                text: nextText,
                speakerId: voice.sid,
                speed: speed,
                modelPath: mPath,
                voicesPath: vPath,
                tokensPath: tPath,
                lexiconPath: lPath
            )
            guard !Task.isCancelled, let audio else { return }
            self.prefetchedVerseIndex = nextIndex
            self.prefetchedAudio = audio
        }
    }

    private func playPCMBuffer(audio: KokoroSynthesizedAudio, genID: UInt64, advanceOnComplete: Bool) {
        let sampleRate = Double(audio.sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            if advanceOnComplete { advanceAfterVerseFinished() }
            return
        }

        // Add a subtle 0.22s natural pause after each verse
        let padSamples = Int(sampleRate * 0.22)
        let totalFrames = AVAudioFrameCount(audio.samples.count + padSamples)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            if advanceOnComplete { advanceAfterVerseFinished() }
            return
        }
        buffer.frameLength = totalFrames
        if let channel = buffer.floatChannelData?[0] {
            audio.samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    channel.update(from: base, count: audio.samples.count)
                }
            }
            if padSamples > 0 {
                (channel + audio.samples.count).initialize(repeating: 0, count: padSamples)
            }
        }

        if !engineAttached {
            audioEngine.attach(playerNode)
            engineAttached = true
        }
        if engineSampleRate != sampleRate {
            if audioEngine.isRunning { audioEngine.stop() }
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
            engineSampleRate = sampleRate
        }
        if !audioEngine.isRunning {
            try? audioEngine.start()
        }

        playerNode.stop()
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.neuralGenerationID == genID else { return }
                if advanceOnComplete {
                    self.advanceAfterVerseFinished()
                }
            }
        }
        playerNode.play()
    }

    private func advanceAfterVerseFinished() {
        guard isActive, isPlaying else { return }
        if let deadline = sleepDeadline, Date() >= deadline {
            stop(hideBar: false)
            sleepTimer = .off
            sleepDeadline = nil
            return
        }
        if currentVerseIndex + 1 < verses.count {
            currentVerseIndex += 1
            speakCurrentVerse()
        } else if sleepTimer == .endOfChapter {
            isPlaying = false
            sleepTimer = .off
        } else if autoAdvanceChapter {
            onChapterFinished?()
        } else {
            isPlaying = false
        }
    }

    private func resolvedAppleVoice() -> AVSpeechSynthesisVoice? {
        if !selectedVoiceIdentifier.isEmpty,
           !selectedVoiceIdentifier.hasPrefix("kokoro:"),
           let saved = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            return saved
        }
        let enVoices = availableEnglishVoices
        if let enhancedUS = enVoices.first(where: { ($0.quality == .enhanced || $0.quality == .premium) && $0.language == "en-US" }) {
            return enhancedUS
        }
        if let enhancedAny = enVoices.first(where: { $0.quality == .enhanced || $0.quality == .premium }) {
            return enhancedAny
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension BibleAudioPlayer: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.advanceAfterVerseFinished()
        }
    }
}

// MARK: - Compact Floating Audio Mini-Player Bar

public struct BibleAudioMiniBar: View {
    @ObservedObject var player: BibleAudioPlayer
    @ObservedObject var kokoro: KokoroVoiceManager
    let theme: ReadingTheme
    let onClose: () -> Void

    public init(player: BibleAudioPlayer, theme: ReadingTheme, onClose: @escaping () -> Void) {
        self.player = player
        self.kokoro = player.kokoroManager
        self.theme = theme
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 11) {
            if player.isSynthesizing {
                ProgressView()
                    .scaleEffect(0.75)
            } else {
                Image(systemName: player.isPlaying ? "waveform" : "speaker.wave.2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accentBlue)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(player.chapterTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    if player.isUsingNeuralVoice {
                        Text("NEURAL")
                            .font(.system(size: 8.5, weight: .heavy))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(theme.accentBlue.opacity(0.16))
                            .foregroundStyle(theme.accentBlue)
                            .clipShape(Capsule())
                    }
                }
                if kokoro.isDownloading {
                    Text("Downloading Kokoro-82M… \(Int(kokoro.downloadProgress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.accentBlue)
                } else {
                    Text("Verse \(player.currentVerseNumber) · \(player.activeVoiceDisplayName)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Button { player.previousVerse() } label: {
                Image(systemName: "backward.fill")
                    .font(.subheadline)
            }

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(theme.accentBlue)
            }

            Button { player.nextVerse() } label: {
                Image(systemName: "forward.fill")
                    .font(.subheadline)
            }

            Button { player.cycleSpeed() } label: {
                Text(String(format: "%.2g×", player.speechRateMultiplier))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(theme.accentBlue.opacity(0.14))
                    .foregroundStyle(theme.accentBlue)
                    .clipShape(Capsule())
            }

            // Voice Picker Menu (Kokoro-82M Studio Neural + Apple System Fallback)
            Menu {
                if kokoro.isInstalled {
                    Section("Kokoro-82M Studio Neural (Offline)") {
                        ForEach(KokoroVoice.allVoices) { kv in
                            Button {
                                player.selectKokoroVoice(kv)
                            } label: {
                                let selected = player.isUsingNeuralVoice && player.activeKokoroVoice.id == kv.id
                                Label("\(kv.displayName) · \(kv.accent) — \(kv.styleHint)", systemImage: selected ? "checkmark" : "sparkles")
                            }
                        }
                    }
                } else {
                    Section("Studio Neural Narrator (Kokoro-82M)") {
                        if kokoro.isDownloading {
                            Button("Cancel Download (\(Int(kokoro.downloadProgress * 100))%)") {
                                kokoro.cancelDownload()
                            }
                        } else {
                            Button {
                                kokoro.startDownload()
                            } label: {
                                Label("Download Kokoro-82M Voices (~96 MB)", systemImage: "arrow.down.circle.fill")
                            }
                        }
                    }
                }

                Section("Apple System Voices") {
                    ForEach(player.availableEnglishVoices.prefix(10), id: \.identifier) { voice in
                        Button {
                            player.selectVoice(voice)
                        } label: {
                            let qualityTag = voice.quality == .premium ? " ★" : (voice.quality == .enhanced ? " +" : "")
                            let selected = !player.isUsingNeuralVoice && voice.identifier == player.selectedVoiceIdentifier
                            Label("\(voice.name) (\(voice.language))\(qualityTag)", systemImage: selected ? "checkmark" : "person.wave.2")
                        }
                    }
                }
            } label: {
                Image(systemName: player.isUsingNeuralVoice ? "sparkles" : "person.wave.2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(player.isUsingNeuralVoice ? theme.accentBlue : theme.primaryText)
            }

            // Sleep Timer Menu
            Menu {
                ForEach(AudioSleepTimer.allCases) { timer in
                    Button {
                        player.setSleepTimer(timer)
                    } label: {
                        Label(timer.label, systemImage: player.sleepTimer == timer ? "checkmark" : "moon.zzz")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "moon.zzz")
                        .font(.caption.weight(.semibold))
                    if let badge = player.sleepTimer.shortBadge {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                    }
                }
                .foregroundStyle(player.sleepTimer == .off ? theme.secondaryText : theme.accentBlue)
            }

            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .foregroundStyle(theme.primaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.panelBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(theme.accentBlue.opacity(0.4), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.16), radius: 8, y: 3)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}
