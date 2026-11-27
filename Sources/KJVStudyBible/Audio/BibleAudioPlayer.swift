import AVFoundation
import Foundation
import SwiftUI

// MARK: - 100% Offline Read-Aloud Bible Audio Player (AVSpeechSynthesizer)

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
    @Published public var currentVerseIndex: Int = 0
    @Published public var currentVerseNumber: Int = 1
    @Published public var speechRateMultiplier: Float = 1.0
    @Published public var autoAdvanceChapter: Bool = true
    @Published public var chapterTitle: String = ""
    @Published public var sleepTimer: AudioSleepTimer = .off
    @Published public var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: "sq_audio_voice_id") ?? ""

    private let synthesizer = AVSpeechSynthesizer()
    private var verses: [Verse] = []
    private var onHighlightVerse: ((Int) -> Void)?
    private var onChapterFinished: (() -> Void)?
    private var sleepDeadline: Date? = nil

    public override init() {
        super.init()
        synthesizer.delegate = self
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

    public func selectVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoiceIdentifier = voice.identifier
        UserDefaults.standard.set(voice.identifier, forKey: "sq_audio_voice_id")
        if isPlaying {
            synthesizer.stopSpeaking(at: .immediate)
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
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolvedVoice()
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 0.95))
        synthesizer.speak(utterance)
    }

    public func togglePlayPause() {
        if !isActive { return }
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
        synthesizer.stopSpeaking(at: .immediate)
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
        synthesizer.stopSpeaking(at: .immediate)
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
        if isPlaying {
            synthesizer.stopSpeaking(at: .immediate)
            speakCurrentVerse()
        }
    }

    public func stop(hideBar: Bool = true) {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        if hideBar {
            isActive = false
            verses = []
            sleepDeadline = nil
            sleepTimer = .off
        }
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

        let utterance = AVSpeechUtterance(string: v.text)
        utterance.voice = resolvedVoice()
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * speechRateMultiplier))
        utterance.postUtteranceDelay = 0.25
        isPlaying = true
        synthesizer.speak(utterance)
    }

    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        if !selectedVoiceIdentifier.isEmpty,
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
            guard let self, self.isActive, self.isPlaying else { return }
            if let deadline = self.sleepDeadline, Date() >= deadline {
                self.stop(hideBar: false)
                self.sleepTimer = .off
                self.sleepDeadline = nil
                return
            }
            if self.currentVerseIndex + 1 < self.verses.count {
                self.currentVerseIndex += 1
                self.speakCurrentVerse()
            } else if self.sleepTimer == .endOfChapter {
                self.isPlaying = false
                self.sleepTimer = .off
            } else if self.autoAdvanceChapter {
                self.onChapterFinished?()
            } else {
                self.isPlaying = false
            }
        }
    }
}

// MARK: - Compact Floating Audio Mini-Player Bar

public struct BibleAudioMiniBar: View {
    @ObservedObject var player: BibleAudioPlayer
    let theme: ReadingTheme
    let onClose: () -> Void

    public var body: some View {
        HStack(spacing: 11) {
            Image(systemName: player.isPlaying ? "waveform" : "speaker.wave.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accentBlue)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.chapterTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text("Verse \(player.currentVerseNumber)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
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

            // Voice Picker Menu
            Menu {
                ForEach(player.availableEnglishVoices.prefix(12), id: \.identifier) { voice in
                    Button {
                        player.selectVoice(voice)
                    } label: {
                        let qualityTag = voice.quality == .premium ? " ★" : (voice.quality == .enhanced ? " +" : "")
                        let selected = voice.identifier == player.selectedVoiceIdentifier
                        Label("\(voice.name) (\(voice.language))\(qualityTag)", systemImage: selected ? "checkmark" : "person.wave.2")
                    }
                }
            } label: {
                Image(systemName: "person.wave.2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
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
