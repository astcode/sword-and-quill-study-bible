import SwiftUI

// MARK: - Scripture Memory Drills (Progressive Word-Hiding & First-Letter Flashcards)

public struct MemoryVerseCard: Identifiable, Hashable, Sendable {
    public let id: String
    public let bookId: Int
    public let chapter: Int
    public let verse: Int
    public let referenceLabel: String
    public let text: String
    public let isFromBookmark: Bool
}

public enum MemoryDrillMode: String, CaseIterable, Identifiable, Sendable {
    case read = "Read"
    case fade35 = "Fade 35%"
    case fade70 = "Fade 70%"
    case firstLetter = "First Letter"

    public var id: String { rawValue }
}

public struct MemoryDrillsSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [MemoryVerseCard] = []
    @State private var currentIndex: Int = 0
    @State private var mode: MemoryDrillMode = .fade35
    @State private var revealedWordIndices: Set<Int> = []
    @State private var masteredIds: Set<String> = []
    @State private var addRefInput: String = ""
    @State private var addRefFeedback: String? = nil
    @State private var filterUnmasteredOnly: Bool = false

    private var filteredCards: [MemoryVerseCard] {
        if filterUnmasteredOnly {
            let unmastered = cards.filter { !masteredIds.contains($0.id) }
            return unmastered.isEmpty ? cards : unmastered
        }
        return cards
    }

    private static let starterReferences: [(Int, Int, Int)] = [
        (43, 3, 16),   // John 3:16
        (19, 119, 105),// Psalm 119:105
        (20, 3, 5),    // Proverbs 3:5
        (20, 3, 6),    // Proverbs 3:6
        (45, 8, 28),   // Romans 8:28
        (50, 4, 6),    // Philippians 4:6
        (50, 4, 7),    // Philippians 4:7
        (23, 40, 31),  // Isaiah 40:31
        (49, 2, 8),    // Ephesians 2:8
        (55, 3, 16),   // 2 Timothy 3:16
        (6, 1, 9),     // Joshua 1:9
        (40, 11, 28),  // Matthew 11:28
    ]

    private var currentCard: MemoryVerseCard? {
        let deck = filteredCards
        guard !deck.isEmpty else { return nil }
        let safeIdx = max(0, min(currentIndex, deck.count - 1))
        return deck[safeIdx]
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Quick Add Any Verse Bar
                HStack(spacing: 8) {
                    TextField("Add any verse (e.g. Psalm 23:1, Rom 12:2)...", text: $addRefInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit { addCustomVerse() }
                    Button("Add") { addCustomVerse() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(addRefInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 18)

                if let msg = addRefFeedback {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 18)
                }

                // Header Mastery Progress + Filter
                HStack(spacing: 8) {
                    Label("\(masteredIds.count) / \(cards.count) Mastered", systemImage: "brain.head.profile")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Button {
                        filterUnmasteredOnly.toggle()
                        currentIndex = 0
                        revealedWordIndices.removeAll()
                    } label: {
                        Text(filterUnmasteredOnly ? "To Practice" : "All Verses")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(filterUnmasteredOnly ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                            .foregroundStyle(filterUnmasteredOnly ? Color.accentColor : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        cards.shuffle()
                        currentIndex = 0
                        revealedWordIndices.removeAll()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.caption.weight(.semibold))
                            .padding(6)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)

                // Progressive Mode Picker
                Picker("Drill Mode", selection: $mode) {
                    ForEach(MemoryDrillMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .onChange(of: mode) { _, _ in
                    revealedWordIndices.removeAll()
                }

                if let card = currentCard {
                    let words = card.text.split(separator: " ").map(String.init)
                    let isMastered = masteredIds.contains(card.id)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Button {
                                    viewModel.navigate(to: VerseRef(bookId: card.bookId, chapter: card.chapter, verse: card.verse))
                                    dismiss()
                                } label: {
                                    Text(card.referenceLabel)
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    viewModel.audioPlayer.speakSinglePassage("\(card.referenceLabel). \(card.text)")
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.caption.weight(.semibold))
                                        .padding(6)
                                        .background(Color.accentColor.opacity(0.14))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)

                                if isMastered {
                                    Label("Mastered", systemImage: "checkmark.seal.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.green)
                                }
                            }

                            // Interactive Word-by-Word Verse Canvas
                            MemoryWordFlowView(
                                words: words,
                                mode: mode,
                                seed: card.id.hashValue,
                                revealedIndices: revealedWordIndices
                            ) { idx in
                                if revealedWordIndices.contains(idx) {
                                    revealedWordIndices.remove(idx)
                                } else {
                                    revealedWordIndices.insert(idx)
                                }
                            }

                            Text("Tap any hidden word to peek. Cycle Read → Fade 35% → Fade 70% → First Letter.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(18)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 18)
                    }

                    // Action Row
                    HStack(spacing: 10) {
                        Button {
                            revealedWordIndices = Set(0..<words.count)
                        } label: {
                            Label("Reveal All", systemImage: "eye")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            revealedWordIndices.removeAll()
                        } label: {
                            Label("Hide", systemImage: "eye.slash")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            toggleMastered(card.id)
                        } label: {
                            Label(isMastered ? "Mastered ✓" : "Mark Mastered", systemImage: isMastered ? "checkmark.seal.fill" : "checkmark.seal")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isMastered ? .green : .accentColor)
                    }
                    .padding(.horizontal, 18)

                    // Prev / Next Card Bar
                    HStack {
                        let deck = filteredCards
                        Button {
                            guard !deck.isEmpty else { return }
                            currentIndex = (currentIndex - 1 + deck.count) % deck.count
                            revealedWordIndices.removeAll()
                        } label: {
                            Label("Previous", systemImage: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            guard !deck.isEmpty else { return }
                            currentIndex = (currentIndex + 1) % deck.count
                            revealedWordIndices.removeAll()
                        } label: {
                            Label("Next Verse", systemImage: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                } else {
                    Spacer()
                    Text("Loading memory verses...")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.top, 10)
            .navigationTitle("Scripture Memory Drills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                loadCards()
            }
        }
    }

    private func loadCards() {
        let saved = UserDefaults.standard.stringArray(forKey: "sq_memory_mastered_ids") ?? []
        masteredIds = Set(saved)

        var built: [MemoryVerseCard] = []
        var seen = Set<String>()

        // 0. User's custom added memory verses first
        let customKeys = UserDefaults.standard.stringArray(forKey: "sq_memory_custom_keys") ?? []
        for rawKey in customKeys {
            let parts = rawKey.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 3,
                  let verse = viewModel.referenceDB.verse(bookId: parts[0], chapter: parts[1], verse: parts[2]) else { continue }
            if seen.insert(rawKey).inserted {
                let bName = viewModel.bookName(parts[0])
                built.append(MemoryVerseCard(
                    id: rawKey,
                    bookId: parts[0],
                    chapter: parts[1],
                    verse: parts[2],
                    referenceLabel: "\(bName) \(parts[1]):\(parts[2])",
                    text: verse.text,
                    isFromBookmark: true
                ))
            }
        }

        // 1. User's own bookmarked verses first
        for bm in viewModel.bookmarks {
            let vNum = bm.verse
            guard vNum > 0,
                  let verse = viewModel.referenceDB.verse(bookId: bm.bookId, chapter: bm.chapter, verse: vNum) else { continue }
            let key = "\(bm.bookId):\(bm.chapter):\(vNum)"
            if seen.insert(key).inserted {
                let bName = viewModel.bookName(bm.bookId)
                built.append(MemoryVerseCard(
                    id: key,
                    bookId: bm.bookId,
                    chapter: bm.chapter,
                    verse: vNum,
                    referenceLabel: "\(bName) \(bm.chapter):\(vNum)",
                    text: verse.text,
                    isFromBookmark: true
                ))
            }
        }

        // 2. Curated starter pack of classic KJV memory verses
        for (b, c, v) in Self.starterReferences {
            let key = "\(b):\(c):\(v)"
            guard seen.insert(key).inserted,
                  let verse = viewModel.referenceDB.verse(bookId: b, chapter: c, verse: v) else { continue }
            let bName = viewModel.bookName(b)
            built.append(MemoryVerseCard(
                id: key,
                bookId: b,
                chapter: c,
                verse: v,
                referenceLabel: "\(bName) \(c):\(v)",
                text: verse.text,
                isFromBookmark: false
            ))
        }

        cards = built
    }

    private func addCustomVerse() {
        let trimmed = addRefInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let parsed = viewModel.referenceDB.parseDirectPassageRange(trimmed),
              let vNum = parsed.startVerse,
              let verse = viewModel.referenceDB.verse(bookId: parsed.bookId, chapter: parsed.chapter, verse: vNum) else {
            addRefFeedback = "Try a verse reference like \"Psalm 23:1\" or \"Romans 12:2\"."
            return
        }
        let key = "\(parsed.bookId):\(parsed.chapter):\(vNum)"
        var customKeys = UserDefaults.standard.stringArray(forKey: "sq_memory_custom_keys") ?? []
        if !customKeys.contains(key) {
            customKeys.insert(key, at: 0)
            UserDefaults.standard.set(customKeys, forKey: "sq_memory_custom_keys")
        }
        let bName = viewModel.bookName(parsed.bookId)
        let card = MemoryVerseCard(
            id: key,
            bookId: parsed.bookId,
            chapter: parsed.chapter,
            verse: vNum,
            referenceLabel: "\(bName) \(parsed.chapter):\(vNum)",
            text: verse.text,
            isFromBookmark: true
        )
        if let existingIdx = cards.firstIndex(where: { $0.id == key }) {
            currentIndex = existingIdx
        } else {
            cards.insert(card, at: 0)
            currentIndex = 0
        }
        revealedWordIndices.removeAll()
        addRefInput = ""
        addRefFeedback = "Added \(card.referenceLabel) to your Memory Deck!"
    }

    private func toggleMastered(_ id: String) {
        if masteredIds.contains(id) {
            masteredIds.remove(id)
        } else {
            masteredIds.insert(id)
        }
        UserDefaults.standard.set(Array(masteredIds), forKey: "sq_memory_mastered_ids")
    }
}

// MARK: - Wrapping Word Grid for Memory Drills

private struct MemoryWordFlowView: View {
    let words: [String]
    let mode: MemoryDrillMode
    let seed: Int
    let revealedIndices: Set<Int>
    let onToggleWord: (Int) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                let hidden = isWordHidden(index: idx) && !revealedIndices.contains(idx)
                Button {
                    onToggleWord(idx)
                } label: {
                    Text(displayText(for: word, hidden: hidden))
                        .font(.system(size: 19, weight: hidden ? .semibold : .regular, design: .serif))
                        .padding(.horizontal, hidden ? 6 : 2)
                        .padding(.vertical, 3)
                        .background(hidden ? Color.accentColor.opacity(0.14) : Color.clear)
                        .foregroundStyle(hidden ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isWordHidden(index: Int) -> Bool {
        switch mode {
        case .read: return false
        case .firstLetter: return true
        case .fade35:
            let hash = abs((index &* 2654435761) ^ seed) % 100
            return hash < 35
        case .fade70:
            let hash = abs((index &* 2654435761) ^ seed) % 100
            return hash < 70
        }
    }

    private func displayText(for word: String, hidden: Bool) -> String {
        guard hidden else { return word }
        if mode == .firstLetter {
            var result = ""
            var sawLetter = false
            for ch in word {
                if ch.isLetter {
                    if !sawLetter {
                        result.append(ch)
                        sawLetter = true
                    } else {
                        result.append("_")
                    }
                } else {
                    result.append(ch)
                }
            }
            return result
        }
        // Blank pill preserving trailing punctuation
        let punct = word.reversed().prefix(while: { !$0.isLetter && !$0.isNumber }).reversed()
        let letterCount = max(2, word.filter(\.isLetter).count)
        return String(repeating: "_", count: min(letterCount, 7)) + String(punct)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 500
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
