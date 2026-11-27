import SwiftUI

// MARK: - Reading Plan Models & Generator

public struct ReadingChapterTarget: Identifiable, Hashable, Sendable {
    public let bookId: Int
    public let bookName: String
    public let bookAbbr: String
    public let chapter: Int
    public var id: String { "\(bookId):\(chapter)" }
    public var shortLabel: String { "\(bookAbbr) \(chapter)" }
}

public struct ReadingPlanDay: Identifiable, Hashable, Sendable {
    public let dayNumber: Int
    public let chapters: [ReadingChapterTarget]
    public var id: Int { dayNumber }

    public var summaryLabel: String {
        guard let first = chapters.first else { return "" }
        if chapters.count == 1 { return "\(first.bookName) \(first.chapter)" }
        let grouped = Dictionary(grouping: chapters, by: \.bookId)
        if grouped.count == 1, let last = chapters.last {
            return "\(first.bookName) \(first.chapter)–\(last.chapter)"
        }
        return chapters.map(\.shortLabel).joined(separator: ", ")
    }
}

public enum ReadingPlanTemplate: String, CaseIterable, Identifiable, Sendable {
    case fullBibleYear = "full_bible_365"
    case newTestament90 = "nt_90"
    case gospelsActs30 = "gospels_acts_30"
    case psalmsProverbs30 = "psalms_proverbs_30"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fullBibleYear: return "1-Year Complete Bible"
        case .newTestament90: return "90-Day New Testament"
        case .gospelsActs30: return "30-Day Gospels & Acts"
        case .psalmsProverbs30: return "30-Day Psalms & Proverbs"
        }
    }

    public var subtitle: String {
        switch self {
        case .fullBibleYear: return "365 days · Genesis to Revelation (~3–4 chapters/day)"
        case .newTestament90: return "90 days · Matthew to Revelation (~3 chapters/day)"
        case .gospelsActs30: return "30 days · Life of Christ & Early Church (~4 chapters/day)"
        case .psalmsProverbs30: return "30 days · 5 Psalms + 1 Proverb each day"
        }
    }

    public var icon: String {
        switch self {
        case .fullBibleYear: return "calendar"
        case .newTestament90: return "book.pages"
        case .gospelsActs30: return "cross"
        case .psalmsProverbs30: return "music.note.list"
        }
    }

    public var totalDays: Int {
        switch self {
        case .fullBibleYear: return 365
        case .newTestament90: return 90
        case .gospelsActs30: return 30
        case .psalmsProverbs30: return 30
        }
    }

    public func buildDays(books: [Book]) -> [ReadingPlanDay] {
        let bookById = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })

        if self == .psalmsProverbs30 {
            let psBook = bookById[19]
            let prBook = bookById[20]
            var days: [ReadingPlanDay] = []
            for d in 1...30 {
                var chs: [ReadingChapterTarget] = []
                if let ps = psBook {
                    let startPs = (d - 1) * 5 + 1
                    for c in startPs...min(150, startPs + 4) {
                        chs.append(ReadingChapterTarget(bookId: ps.id, bookName: ps.name, bookAbbr: ps.abbr, chapter: c))
                    }
                }
                if let pr = prBook {
                    chs.append(ReadingChapterTarget(bookId: pr.id, bookName: pr.name, bookAbbr: pr.abbr, chapter: d))
                    if d == 30 {
                        chs.append(ReadingChapterTarget(bookId: pr.id, bookName: pr.name, bookAbbr: pr.abbr, chapter: 31))
                    }
                }
                days.append(ReadingPlanDay(dayNumber: d, chapters: chs))
            }
            return days
        }

        let targetBookIds: [Int]
        switch self {
        case .fullBibleYear: targetBookIds = Array(1...66)
        case .newTestament90: targetBookIds = Array(40...66)
        case .gospelsActs30: targetBookIds = [40, 41, 42, 43, 44]
        case .psalmsProverbs30: targetBookIds = []
        }

        var allChapters: [ReadingChapterTarget] = []
        for bid in targetBookIds {
            guard let b = bookById[bid] else { continue }
            for ch in 1...b.chapterCount {
                allChapters.append(ReadingChapterTarget(bookId: b.id, bookName: b.name, bookAbbr: b.abbr, chapter: ch))
            }
        }
        guard !allChapters.isEmpty else { return [] }

        let total = totalDays
        var days: [ReadingPlanDay] = []
        var cursor = 0
        for d in 1...total {
            let remainingChapters = allChapters.count - cursor
            let remainingDays = total - d + 1
            let count = max(1, Int(ceil(Double(remainingChapters) / Double(remainingDays))))
            let end = min(allChapters.count, cursor + count)
            let slice = Array(allChapters[cursor..<end])
            days.append(ReadingPlanDay(dayNumber: d, chapters: slice))
            cursor = end
            if cursor >= allChapters.count { break }
        }
        return days
    }
}

// MARK: - Reading Plans Sheet

public struct ReadingPlansSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: ReadingPlanTemplate = {
        if let raw = UserDefaults.standard.string(forKey: "sq_active_reading_plan"),
           let plan = ReadingPlanTemplate(rawValue: raw) {
            return plan
        }
        return .fullBibleYear
    }()
    @State private var completedDays: Set<Int> = []
    @State private var showIncompleteOnly: Bool = false
    @State private var showResetConfirm: Bool = false

    private var days: [ReadingPlanDay] {
        selectedPlan.buildDays(books: viewModel.books)
    }

    private var visibleDays: [ReadingPlanDay] {
        if showIncompleteOnly {
            return days.filter { !completedDays.contains($0.dayNumber) }
        }
        return days
    }

    private var progressFraction: Double {
        guard !days.isEmpty else { return 0 }
        return Double(completedDays.count) / Double(days.count)
    }

    private var nextUnreadDay: ReadingPlanDay? {
        days.first(where: { !completedDays.contains($0.dayNumber) })
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Plan Selector Strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ReadingPlanTemplate.allCases) { plan in
                            let active = (plan == selectedPlan)
                            Button {
                                selectedPlan = plan
                                UserDefaults.standard.set(plan.rawValue, forKey: "sq_active_reading_plan")
                                loadCompletedDays()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: plan.icon)
                                        .font(.caption)
                                    Text(plan.title)
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(active ? Color.accentColor : Color.secondary.opacity(0.12))
                                .foregroundStyle(active ? .white : .primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                // Progress Summary Banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedPlan.title)
                                .font(.headline)
                            Text(selectedPlan.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(completedDays.count) / \(days.count) days")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }

                    ProgressView(value: progressFraction)
                        .tint(Color.accentColor)

                    HStack {
                        if let next = nextUnreadDay {
                            Button {
                                if let first = next.chapters.first {
                                    viewModel.navigate(to: VerseRef(bookId: first.bookId, chapter: first.chapter, verse: 1))
                                    dismiss()
                                }
                            } label: {
                                Label("Continue Day \(next.dayNumber): \(next.summaryLabel)", systemImage: "play.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Label("Plan Completed!", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Toggle("Unread only", isOn: $showIncompleteOnly)
                            .labelsHidden()
                        Text("Unread only")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                Divider()

                // Day-by-Day List (auto-scrolls to next unread day!)
                ScrollViewReader { proxy in
                    List {
                        ForEach(visibleDays) { day in
                            let isDone = completedDays.contains(day.dayNumber)
                            HStack(alignment: .top, spacing: 12) {
                                Button {
                                    toggleDay(day.dayNumber)
                                } label: {
                                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isDone ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Day \(day.dayNumber)")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(isDone ? .secondary : .primary)
                                        Text("· \(day.summaryLabel)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(day.chapters) { ch in
                                                Button {
                                                    viewModel.navigate(to: VerseRef(bookId: ch.bookId, chapter: ch.chapter, verse: 1))
                                                    dismiss()
                                                } label: {
                                                    Text(ch.shortLabel)
                                                        .font(.caption2.weight(.semibold))
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.accentColor.opacity(0.12))
                                                        .foregroundStyle(Color.accentColor)
                                                        .clipShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .id(day.dayNumber)
                        }
                    }
                    .listStyle(.plain)
                    .onAppear {
                        loadCompletedDays()
                        if let next = nextUnreadDay {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation { proxy.scrollTo(next.dayNumber, anchor: .top) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bible Reading Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") { showResetConfirm = true }
                        .disabled(completedDays.isEmpty)
                }
            }
            .confirmationDialog("Reset \(selectedPlan.title) progress?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset All Completed Days", role: .destructive) {
                    completedDays.removeAll()
                    UserDefaults.standard.removeObject(forKey: storageKey(for: selectedPlan))
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func storageKey(for plan: ReadingPlanTemplate) -> String {
        "sq_reading_plan_done_\(plan.rawValue)"
    }

    private func loadCompletedDays() {
        let arr = UserDefaults.standard.array(forKey: storageKey(for: selectedPlan)) as? [Int] ?? []
        completedDays = Set(arr)
    }

    private func toggleDay(_ day: Int) {
        if completedDays.contains(day) {
            completedDays.remove(day)
        } else {
            completedDays.insert(day)
        }
        UserDefaults.standard.set(Array(completedDays).sorted(), forKey: storageKey(for: selectedPlan))
    }
}
