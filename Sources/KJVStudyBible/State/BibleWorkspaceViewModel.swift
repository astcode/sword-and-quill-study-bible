import Foundation
import PencilKit
import SwiftUI
import UIKit

@MainActor
public final class BibleWorkspaceViewModel: ObservableObject {
    public let referenceDB: ReferenceDatabase
    public let studyDB: UserStudyDatabase

    // Books & current Scripture location
    @Published public var books: [Book] = []
    @Published public var currentBookId: Int = 43 // John
    @Published public var currentChapter: Int = 3
    @Published public var targetVerseToScroll: Int? = nil
    @Published public var verses: [Verse] = []
    @Published public var crossRefsByVerse: [Int: [CrossReference]] = [:]
    @Published public var chapterPlaces: [BiblicalPlace] = []

    // User study state for active chapter
    @Published public var chapterDrawing: PKDrawing = PKDrawing()
    @Published public var drawingRevision: Int = 0
    @Published public var chapterHighlights: [Int: UserHighlight] = [:]
    @Published public var pinnedReferences: [PinnedReference] = []
    @Published public var journalClips: [JournalClipCard] = []
    @Published public var activeClipDraft: ClipDraft? = nil
    @Published public var stickerLibrary: [StickerItem] = []
    @Published public var chapterStickers: [PlacedSticker] = []
    @Published public var selectedChapterStickerId: String? = nil
    @Published public var showStickerSheet: Bool = false
    @Published public var bookmarks: [UserBookmark] = []
    @Published public var notes: [UserNote] = []
    @Published public var allHighlights: [UserHighlight] = []
    @Published public var highlightCategories: [HighlightPreset] = HighlightPreset.defaults
    @Published public var collections: [StudyCollection] = []
    @Published public var readingHistory: [ReadingHistoryItem] = []
    @Published public var activeNotebookNote: UserNote? = nil
    @Published public var showHistorySheet: Bool = false
    @Published public var showMarginOCRScanner: Bool = false
    @Published public var showStudyDashboard: Bool = false
    @Published public var showReadingPlans: Bool = false
    @Published public var showMemoryDrills: Bool = false
    @Published public var showSupportSheet: Bool = false
    @Published public var audioSpeakingVerseNumber: Int? = nil
    @Published public var isAudioBarVisible: Bool = false
    public let audioPlayer = BibleAudioPlayer()
    public let storeManager = StoreManager()
    public let moduleManager = ModuleManager()
    @Published public var showLibraryManager: Bool = false
    @Published public var selectedCommentaryModuleId: String? = nil
    @Published public var chapterCommentaryEntries: [CommentaryEntry] = []
    @Published public var backupExportURL: URL? = nil
    @Published public var activeShareSheetItem: ShareSheetItem? = nil

    // Named Study Sessions ("Study Trails") & Permanent Bible Ink Links
    @Published public var studySessions: [StudySession] = []
    @Published public var activeStudy: StudySession? = nil
    @Published public var activeStudyTrail: [StudyTrailEntry] = []
    @Published public var chapterStudyLinks: [StudyMarginLink] = []
    @Published public var showNewStudySheet: Bool = false
    @Published public var showStudyTrailSheet: Bool = false
    @Published public var showStudyLibrarySheet: Bool = false
    @Published public var pinnedStudyIds: Set<String> = []
    @Published public var archivedStudyIds: Set<String> = []
    @Published public var starredTrailEntryIds: Set<String> = []
    @Published public var editingStudyMarginLink: StudyMarginLink? = nil
    @Published public var showAddStudyLinkSheet: Bool = false
    @Published public var sharingStudy: StudySession? = nil
    @Published public var incomingStudyPackage: StudySharePackage? = nil
    @Published public var showImportStudyFilePicker: Bool = false
    @Published public var teacherAuthorName: String = ""
    private var activeStudyPassageEntryId: String? = nil

    // Verse-Anchored Ink Reflow State
    public var currentVerseFrames: [Int: CGRect] = [:]
    public var currentScriptureWidth: CGFloat = 0
    public var currentCanvasWidth: CGFloat = 0
    private var savedInkAnchors: ChapterInkAnchors? = nil

    // Browser-style Back / Forward history
    @Published private var historyStack: [VerseRef] = []
    @Published private var historyIndex: Int = -1
    public var activeHistoryRowId: Int? = nil
    private var chapterEnteredAt: Date = Date()
    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex >= 0 && historyIndex < historyStack.count - 1 }

    // Workspace Modes & Collapsible Panels
    @Published public var workspaceMode: WorkspaceMode = .journaling
    @Published public var showReferencePanel: Bool = true
    @Published public var showJournalPanel: Bool = true
    @Published public var showInkInReadingMode: Bool = false
    @Published public var leftPanelTab: LeftPanelTab = .crossRefs
    @Published public var referenceFilter: ReferenceSourceFilter = .tsk
    @Published public var showAllReferencesExpanded: Bool = false
    @Published public var expandedReferenceVerses: Set<Int> = []
    @Published public var paperStyle: JournalPaperStyle = .ruled
    @Published public var journalZoomScale: CGFloat = 1.0
    @Published public var leftPanelWidth: CGFloat = 0 // 0 = auto default; > 0 = user-dragged width

    // Parallel Bible Reader State (Left Panel Parallel Tab)
    @Published public var parallelBookId: Int = 40 // Matthew (great for Gospel harmony with John!)
    @Published public var parallelChapter: Int = 1
    @Published public var parallelVerses: [Verse] = []

    // Blue Letter Bible–style Verse Action Popover
    @Published public var popoverVerse: Verse? = nil

    public var shouldShowInkOverlay: Bool {
        showJournalPanel || showInkInReadingMode
    }

    // Reading Appearance
    @Published public var theme: ReadingTheme = .paperSepia
    @Published public var customThemes: [CustomThemePalette] = []
    @Published public var fontSize: Double = 19.0
    @Published public var studyDeskFontSize: Double = 14.0
    @Published public var scriptureFontDesign: ScriptureFontDesign = .serif
    @Published public var lineSpacing: Double = 8.0
    @Published public var showVerseNumbers: Bool = true
    @Published public var showRedLetter: Bool = true
    @Published public var showItalics: Bool = true
    @Published public var isLeftHandedLayout: Bool = false
    @Published public var keepScreenAwake: Bool = false {
        didSet {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
    }

    // Writing Toolbox State (bottom bar)
    @Published public var showPenToolbox: Bool = false
    @Published public var selectedTool: WritingToolKind = .pen
    @Published public var selectedColor: InkColorPreset = InkColorPreset.defaults[1] // Study Blue
    @Published public var strokeWidth: Double = 3.0
    @Published public var inkOpacity: Double = 1.0
    @Published public var pencilOnly: Bool = true
    @Published public var canUndo: Bool = false
    @Published public var canRedo: Bool = false

    // Undo / Redo callbacks wired to active PKCanvasView
    public var onUndoRequest: (() -> Void)?
    public var onRedoRequest: (() -> Void)?

    // Modals, Drawers & Contextual Study Panel
    @Published public var showMainMenu: Bool = false
    @Published public var showScripturePicker: Bool = false
    @Published public var showSearchSheet: Bool = false
    @Published public var showSavedSheet: Bool = false
    @Published public var showNotesSheet: Bool = false
    @Published public var showViewSettings: Bool = false

    @Published public var showStudyPanel: Bool = false
    @Published public var studyVerse: Verse? = nil
    @Published public var studyWord: String? = nil
    @Published public var studyStrongsResults: [StrongsEntry] = []
    @Published public var studyWebsterResults: [WebsterEntry] = []
    @Published public var interlinearWords: [InterlinearWord] = []
    @Published public var selectedStrongsEntry: StrongsEntry? = nil
    @Published public var strongsOccurrences: [SearchResult] = []
    @Published public var selectedDictionarySource: StudyDictionarySource = .webster1828
    @Published public var studyDictionaryResults: [StudyDictionaryEntry] = []
    @Published public var previewCrossRef: CrossReference? = nil
    @Published public var previewCrossRefVerses: [Verse] = []
    @Published public var previewCrossRefShowContext: Bool = false
    @Published public var activePinnedRefId: String? = nil

    @Published public var toastMessage: String? = nil

    public init() {
        self.referenceDB = ReferenceDatabase()
        #if DEBUG
        if let showcaseMode = ProcessInfo.processInfo.environment["SWORDQUILL_SHOWCASE"], !showcaseMode.isEmpty {
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("sq_showcase_\(showcaseMode).mql")
            try? FileManager.default.removeItem(at: tmpURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: tmpURL.path + ".wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: tmpURL.path + ".pages"))
            self.studyDB = UserStudyDatabase(customURL: tmpURL)
            self.books = referenceDB.allBooks()
            reloadUserCollections()
            navigate(to: VerseRef(bookId: 43, chapter: 14, verse: nil), pushHistory: true)
            navigateParallel(bookId: 40, chapter: 5)
            applyDebugShowcase(mode: showcaseMode)
            return
        }
        #endif
        self.studyDB = UserStudyDatabase()
        self.books = referenceDB.allBooks()

        restorePreferences()
        reloadUserCollections()
        navigate(to: VerseRef(bookId: currentBookId, chapter: currentChapter, verse: nil), pushHistory: true)
        navigateParallel(bookId: parallelBookId, chapter: parallelChapter)
    }

    public var currentBook: Book? {
        referenceDB.book(id: currentBookId)
    }

    public var currentLocationTitle: String {
        "\(currentBook?.name ?? "John") \(currentChapter)"
    }

    public var chapterNotesByVerse: [Int: [UserNote]] {
        var map: [Int: [UserNote]] = [:]
        for n in notes where n.bookId == currentBookId && n.chapter == currentChapter {
            let v = n.verse ?? 1
            map[v, default: []].append(n)
        }
        return map
    }

    public var activePKTool: PKTool {
        let baseColor = selectedColor.uiColor.withAlphaComponent(CGFloat(inkOpacity))
        switch selectedTool {
        case .pen:
            return PKInkingTool(.pen, color: baseColor, width: CGFloat(strokeWidth))
        case .pencil:
            return PKInkingTool(.pencil, color: baseColor, width: CGFloat(max(2.0, strokeWidth * 1.4)))
        case .marker:
            return PKInkingTool(.marker, color: baseColor, width: CGFloat(max(6.0, strokeWidth * 2.5)))
        case .highlighter:
            let hiColor = selectedColor.uiColor.withAlphaComponent(CGFloat(min(0.45, inkOpacity * 0.45)))
            return PKInkingTool(.marker, color: hiColor, width: CGFloat(max(14.0, strokeWidth * 4.0)))
        case .eraserVector:
            return PKEraserTool(.vector)
        case .eraserBitmap:
            return PKEraserTool(.bitmap)
        case .lasso:
            return PKLassoTool()
        }
    }

    // MARK: - Navigation & History

    public func flushCurrentChapterTime() {
        guard let rowId = activeHistoryRowId else { return }
        let elapsed = Int(Date().timeIntervalSince(chapterEnteredAt))
        chapterEnteredAt = Date()
        // Cap single-span idle at 4 hours so overnight sleep doesn't skew stats
        let bounded = min(max(0, elapsed), 4 * 3600)
        if bounded > 0 {
            studyDB.addHistoryDuration(id: rowId, seconds: bounded)
            readingHistory = studyDB.recentHistory(limit: 50)
            if let studyEntryId = activeStudyPassageEntryId {
                studyDB.addStudyTrailDuration(entryId: studyEntryId, seconds: bounded)
                if let sid = activeStudy?.id {
                    activeStudyTrail = studyDB.studyTrailEntries(studyId: sid)
                }
            }
        }
    }

    public func clearReadingHistory() {
        studyDB.clearHistory()
        activeHistoryRowId = studyDB.recordHistory(bookId: currentBookId, chapter: currentChapter, verse: nil)
        chapterEnteredAt = Date()
        readingHistory = studyDB.recentHistory(limit: 50)
        showToast("Reading history cleared")
    }

    public var activeLayerStudyId: String {
        activeStudy?.id ?? ""
    }

    private var activeStickerTargetType: String {
        activeStudy == nil ? "chapter" : "study_chapter"
    }

    private var activeStickerTargetKey: String {
        if let sid = activeStudy?.id {
            return "\(sid)-\(currentBookId)-\(currentChapter)"
        }
        return "\(currentBookId)-\(currentChapter)"
    }

    public func reloadActiveChapterLayer() {
        let sid = activeLayerStudyId
        pinnedReferences = studyDB.pinnedReferences(bookId: currentBookId, chapter: currentChapter, studyId: sid)
        journalClips = studyDB.journalClips(bookId: currentBookId, chapter: currentChapter, studyId: sid)
        chapterStickers = studyDB.placedStickers(targetType: activeStickerTargetType, targetKey: activeStickerTargetKey)
        chapterStudyLinks = studyDB.studyMarginLinks(bookId: currentBookId, chapter: currentChapter)
        selectedChapterStickerId = nil

        if let loaded = studyDB.loadChapterInk(bookId: currentBookId, chapter: currentChapter, studyId: sid),
           let parsed = try? PKDrawing(data: loaded.data) {
            chapterDrawing = parsed
            savedInkAnchors = loaded.anchors
        } else {
            chapterDrawing = PKDrawing()
            savedInkAnchors = nil
        }
        drawingRevision += 1
    }

    public func navigate(to ref: VerseRef, pushHistory: Bool = true) {
        flushCurrentChapterTime()
        currentBookId = ref.bookId
        currentChapter = ref.chapter
        targetVerseToScroll = ref.verse

        verses = referenceDB.verses(bookId: ref.bookId, chapter: ref.chapter)
        crossRefsByVerse = referenceDB.crossReferences(bookId: ref.bookId, chapter: ref.chapter)
        chapterPlaces = referenceDB.placesForChapter(bookId: ref.bookId, chapter: ref.chapter)
        reloadChapterCommentary()
        expandedReferenceVerses = []
        chapterHighlights = studyDB.highlights(bookId: ref.bookId, chapter: ref.chapter)
        currentVerseFrames = [:]
        reloadActiveChapterLayer()

        if pushHistory {
            if historyIndex < historyStack.count - 1 {
                historyStack = Array(historyStack.prefix(historyIndex + 1))
            }
            if historyStack.last != ref {
                historyStack.append(ref)
                historyIndex = historyStack.count - 1
            }
        }

        studyDB.setPreference("last_book_id", value: String(currentBookId))
        studyDB.setPreference("last_chapter", value: String(currentChapter))
        activeHistoryRowId = studyDB.recordHistory(bookId: currentBookId, chapter: currentChapter, verse: ref.verse)
        chapterEnteredAt = Date()
        readingHistory = studyDB.recentHistory(limit: 50)

        if let study = activeStudy {
            let label = ref.verse != nil ? "\(bookName(currentBookId)) \(currentChapter):\(ref.verse!)" : "\(bookName(currentBookId)) \(currentChapter)"
            activeStudyPassageEntryId = studyDB.appendStudyTrailEntry(
                studyId: study.id,
                kind: .passage,
                title: label,
                bookId: currentBookId,
                chapter: currentChapter,
                verse: ref.verse
            )
            activeStudyTrail = studyDB.studyTrailEntries(studyId: study.id)
        }
    }

    public func startChapterAudio(startingAtVerse: Int? = nil) {
        guard !verses.isEmpty else { return }
        isAudioBarVisible = true
        audioPlayer.startChapter(
            title: currentLocationTitle,
            verses: verses,
            startingAtVerse: startingAtVerse,
            onHighlightVerse: { [weak self] vNum in
                self?.audioSpeakingVerseNumber = vNum
            },
            onChapterFinished: { [weak self] in
                guard let self else { return }
                self.nextChapter()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if self.audioPlayer.isActive {
                        self.startChapterAudio(startingAtVerse: 1)
                    }
                }
            }
        )
    }

    public func stopChapterAudio() {
        audioPlayer.stop(hideBar: true)
        isAudioBarVisible = false
        audioSpeakingVerseNumber = nil
    }

    public func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        navigate(to: historyStack[historyIndex], pushHistory: false)
    }

    public func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        navigate(to: historyStack[historyIndex], pushHistory: false)
    }

    public func nextChapter() {
        guard let b = currentBook else { return }
        if currentChapter < b.chapterCount {
            navigate(to: VerseRef(bookId: b.id, chapter: currentChapter + 1))
        } else if b.id < 66 {
            navigate(to: VerseRef(bookId: b.id + 1, chapter: 1))
        }
    }

    public func previousChapter() {
        if currentChapter > 1 {
            navigate(to: VerseRef(bookId: currentBookId, chapter: currentChapter - 1))
        } else if currentBookId > 1, let prevBook = referenceDB.book(id: currentBookId - 1) {
            navigate(to: VerseRef(bookId: prevBook.id, chapter: prevBook.chapterCount))
        }
    }

    // MARK: - Modes & Collapsible Panels

    public func applyMode(_ mode: WorkspaceMode) {
        workspaceMode = mode
        switch mode {
        case .journaling:
            showReferencePanel = true
            showJournalPanel = true
            showStudyPanel = false
            if referenceFilter == .hidden { referenceFilter = .tsk }
        case .bibleAndNotes:
            showReferencePanel = false
            showJournalPanel = true
            showStudyPanel = false
        case .reading:
            showReferencePanel = false
            showJournalPanel = false
            showStudyPanel = false
            journalZoomScale = 1.0
        case .study:
            showReferencePanel = true
            showJournalPanel = false
            showStudyPanel = false
            if studyVerse == nil, let first = verses.first {
                studyVerse = first
            }
        }
        persistLayoutPreferences()
    }

    public func openLeftPanel(tab: LeftPanelTab) {
        leftPanelTab = tab
        showReferencePanel = true
        showStudyPanel = false
        if studyVerse == nil, let first = verses.first {
            studyVerse = first
        }
        syncModeFromPanels()
        persistLayoutPreferences()
    }

    public func openVersePopover(_ verse: Verse) {
        popoverVerse = verse
    }

    public func openLeftStudy(tab: LeftPanelTab, for verse: Verse, dictionarySource: StudyDictionarySource? = nil) {
        popoverVerse = nil
        studyVerse = verse
        studyWord = nil
        selectedStrongsEntry = nil
        previewCrossRef = nil
        previewCrossRefVerses = []
        activePinnedRefId = nil
        leftPanelTab = tab
        showReferencePanel = true
        showStudyPanel = false
        interlinearWords = referenceDB.interlinearWords(bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse)
        if let src = dictionarySource {
            selectedDictionarySource = src
        }
        if tab == .dictionary {
            loadContextualDictionaryForActiveVerse()
        }
        if tab == .parallel {
            navigateParallel(bookId: verse.bookId, chapter: verse.chapter)
        }
        syncModeFromPanels()
        persistLayoutPreferences()
    }

    public func loadContextualDictionaryForActiveVerse(source: StudyDictionarySource? = nil) {
        if let source { selectedDictionarySource = source }
        guard let v = studyVerse ?? verses.first else { return }
        studyWord = nil
        studyDictionaryResults = referenceDB.entriesForVerse(source: selectedDictionarySource, verse: v, limit: 14)
    }

    public func loadInterlinearForActiveVerse() {
        guard let v = studyVerse ?? verses.first else { return }
        interlinearWords = referenceDB.interlinearWords(bookId: v.bookId, chapter: v.chapter, verse: v.verse)
    }

    public func selectStrongsId(_ strongsId: String) {
        selectedStrongsEntry = referenceDB.lookupStrongs(id: strongsId)
        strongsOccurrences = referenceDB.versesForStrongs(strongsId: strongsId, limit: 30)
        if let entry = selectedStrongsEntry {
            recordStudyEvent(
                kind: .strongs,
                title: "\(entry.strongsId) · \(entry.lemma) (\(entry.translit))",
                detail: String(entry.definition.prefix(120)),
                bookId: studyVerse?.bookId ?? currentBookId,
                chapter: studyVerse?.chapter ?? currentChapter,
                verse: studyVerse?.verse,
                refKey: entry.strongsId
            )
        }
    }

    // MARK: - Journal Clip Cards (Trimmed Excerpts + Editable User Notes)

    public func startClipToJournal(sourceLabel: String, text: String) {
        activeClipDraft = ClipDraft(sourceLabel: sourceLabel, initialExcerpt: text, initialNote: "")
    }

    public func startEditClip(_ clip: JournalClipCard) {
        activeClipDraft = ClipDraft(
            editingCardId: clip.id,
            sourceLabel: clip.sourceLabel,
            initialExcerpt: clip.excerpt,
            initialNote: clip.userNote
        )
    }

    public func saveClipDraft(sourceLabel: String, excerpt: String, userNote: String, editingCardId: String?) {
        let trimmedExcerpt = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExcerpt.isEmpty || !trimmedNote.isEmpty else { return }

        if !showJournalPanel {
            showJournalPanel = true
            syncModeFromPanels()
        }

        if let existingId = editingCardId, let existing = journalClips.first(where: { $0.id == existingId }) {
            let updated = JournalClipCard(
                id: existing.id,
                bookId: existing.bookId,
                chapter: existing.chapter,
                sourceLabel: sourceLabel,
                excerpt: trimmedExcerpt,
                userNote: trimmedNote,
                posX: existing.posX,
                posY: existing.posY,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            studyDB.upsertJournalClip(updated, studyId: activeLayerStudyId)
            journalClips = studyDB.journalClips(bookId: currentBookId, chapter: currentChapter, studyId: activeLayerStudyId)
            showToast("Updated journal clip")
        } else {
            let yOffset = 110.0 + Double(journalClips.count % 6) * 95.0
            let card = JournalClipCard(
                id: UUID().uuidString,
                bookId: currentBookId,
                chapter: currentChapter,
                sourceLabel: sourceLabel,
                excerpt: trimmedExcerpt,
                userNote: trimmedNote,
                posX: defaultJournalMarginX(),
                posY: yOffset,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            studyDB.upsertJournalClip(card, studyId: activeLayerStudyId)
            journalClips = studyDB.journalClips(bookId: currentBookId, chapter: currentChapter, studyId: activeLayerStudyId)
            recordStudyEvent(kind: .clip, title: sourceLabel, detail: trimmedNote.isEmpty ? String(trimmedExcerpt.prefix(100)) : trimmedNote, bookId: currentBookId, chapter: currentChapter)
            showToast("Added clip to journal")
        }
        activeClipDraft = nil
    }

    public func moveJournalClip(id: String, to point: CGPoint) {
        guard let idx = journalClips.firstIndex(where: { $0.id == id }) else { return }
        journalClips[idx].posX = max(16, Double(point.x))
        journalClips[idx].posY = max(16, Double(point.y))
        studyDB.upsertJournalClip(journalClips[idx], studyId: activeLayerStudyId)
    }

    public func removeJournalClip(id: String) {
        studyDB.deleteJournalClip(id: id)
        journalClips = studyDB.journalClips(bookId: currentBookId, chapter: currentChapter, studyId: activeLayerStudyId)
        activeClipDraft = nil
        showToast("Removed journal clip")
    }

    public func runDictionaryLookup(query: String, source: StudyDictionarySource? = nil) {
        if let source { selectedDictionarySource = source }
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        studyWord = cleaned
        studyDictionaryResults = referenceDB.searchStudyDictionary(source: selectedDictionarySource, query: cleaned, limit: 14)
    }

    public func navigateParallel(bookId: Int, chapter: Int) {
        parallelBookId = bookId
        let maxCh = referenceDB.book(id: bookId)?.chapterCount ?? 1
        parallelChapter = max(1, min(chapter, maxCh))
        parallelVerses = referenceDB.verses(bookId: parallelBookId, chapter: parallelChapter)
        studyDB.setPreference("parallel_book_id", value: String(parallelBookId))
        studyDB.setPreference("parallel_chapter", value: String(parallelChapter))
    }

    public func parallelNextChapter() {
        let maxCh = referenceDB.book(id: parallelBookId)?.chapterCount ?? 1
        if parallelChapter < maxCh {
            navigateParallel(bookId: parallelBookId, chapter: parallelChapter + 1)
        } else if parallelBookId < 66 {
            navigateParallel(bookId: parallelBookId + 1, chapter: 1)
        }
    }

    public func parallelPreviousChapter() {
        if parallelChapter > 1 {
            navigateParallel(bookId: parallelBookId, chapter: parallelChapter - 1)
        } else if parallelBookId > 1, let prev = referenceDB.book(id: parallelBookId - 1) {
            navigateParallel(bookId: prev.id, chapter: prev.chapterCount)
        }
    }

    public var parallelLocationTitle: String {
        "\(bookName(parallelBookId)) \(parallelChapter)"
    }

    public func toggleReferencePanel() {
        showReferencePanel.toggle()
        if showReferencePanel && referenceFilter == .hidden {
            referenceFilter = .tsk
        }
        syncModeFromPanels()
        persistLayoutPreferences()
    }

    public func toggleJournalPanel() {
        showJournalPanel.toggle()
        syncModeFromPanels()
        persistLayoutPreferences()
    }

    public func setReferenceFilter(_ filter: ReferenceSourceFilter) {
        referenceFilter = filter
        showReferencePanel = (filter != .hidden)
        syncModeFromPanels()
        persistLayoutPreferences()
    }

    public func setShowAllReferencesExpanded(_ expanded: Bool) {
        showAllReferencesExpanded = expanded
        if !expanded {
            expandedReferenceVerses.removeAll()
        }
        studyDB.setPreference("show_all_refs", value: expanded ? "1" : "0")
    }

    public func toggleReferenceExpansion(for verse: Int) {
        if expandedReferenceVerses.contains(verse) {
            expandedReferenceVerses.remove(verse)
        } else {
            expandedReferenceVerses.insert(verse)
        }
    }

    public func isReferenceExpanded(for verse: Int) -> Bool {
        showAllReferencesExpanded || expandedReferenceVerses.contains(verse)
    }

    public func groupedCrossReferences(for verse: Int) -> [(phrase: String, refs: [CrossReference])] {
        let refs = crossRefsByVerse[verse] ?? []
        var order: [String] = []
        var map: [String: [CrossReference]] = [:]
        for r in refs {
            let key = r.phrase.isEmpty ? "General" : r.phrase
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(r)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func syncModeFromPanels() {
        if showReferencePanel && showJournalPanel {
            workspaceMode = .journaling
        } else if !showReferencePanel && showJournalPanel {
            workspaceMode = .bibleAndNotes
        } else if showReferencePanel && !showJournalPanel {
            workspaceMode = .study
        } else {
            workspaceMode = .reading
        }
    }

    // MARK: - Ink Updates & Verse-Anchored Ink Reflow

    private func makeCurrentInkAnchors() -> ChapterInkAnchors? {
        guard !currentVerseFrames.isEmpty else { return nil }
        var map: [Int: VerseAnchorRect] = [:]
        for (v, rect) in currentVerseFrames {
            map[v] = VerseAnchorRect(rect: rect)
        }
        return ChapterInkAnchors(
            scriptureWidth: Double(currentScriptureWidth),
            canvasWidth: Double(currentCanvasWidth),
            verseRects: map,
            isLeftHanded: isLeftHandedLayout
        )
    }

    public func defaultJournalMarginX(offset: Double = 0) -> Double {
        if !showJournalPanel {
            return 120.0 + offset
        }
        if isLeftHandedLayout {
            return 28.0 + offset
        }
        let sWidth = currentScriptureWidth > 0 ? Double(currentScriptureWidth) : 430.0
        return sWidth + 24.0 + offset
    }

    /// Spine-mirrors active chapter margin items (pins, clips, study links, stickers) AND Apple Pencil
    /// handwriting clusters across the gutter between Right-Handed and Left-Handed modes — preserving
    /// distance from the Bible spine while keeping every word and card 100% upright & readable.
    public func repositionCanvasItemsForHandednessChange(fromLeftHanded oldLeft: Bool, toLeftHanded newLeft: Bool) {
        guard oldLeft != newLeft, showJournalPanel else { return }
        let sWidth = currentScriptureWidth > 0 ? Double(currentScriptureWidth) : 440.0
        let cWidth = currentCanvasWidth > sWidth ? Double(currentCanvasWidth) : (sWidth + 340.0)
        let jWidth = max(140.0, cWidth - sWidth - 1.0)

        func mirrorItemX(_ posX: Double, itemWidth w: Double) -> Double {
            let halfW = w * 0.5
            let centerX = posX + halfW
            if !oldLeft && newLeft {
                // Right-Handed -> Left-Handed
                if centerX >= sWidth - 8.0 {
                    let distFromGutter = max(0, centerX - (sWidth + 1.0))
                    let targetCenter = jWidth - distFromGutter
                    let clampedLeft = min(max(10.0, targetCenter - halfW), max(10.0, jWidth - w - 10.0))
                    return clampedLeft
                } else {
                    return posX + (jWidth + 1.0)
                }
            } else {
                // Left-Handed -> Right-Handed
                if centerX < jWidth + 8.0 {
                    let distFromGutter = max(0, jWidth - centerX)
                    let targetCenter = (sWidth + 1.0) + distFromGutter
                    let clampedLeft = min(max(sWidth + 10.0, targetCenter - halfW), max(sWidth + 10.0, cWidth - w - 10.0))
                    return clampedLeft
                } else {
                    return max(10.0, posX - (jWidth + 1.0))
                }
            }
        }

        // 1. Spine-mirror cards, chips, links, and stickers using their actual width (so .offset left-edge never overlaps Bible!)
        for idx in pinnedReferences.indices {
            pinnedReferences[idx].posX = mirrorItemX(pinnedReferences[idx].posX, itemWidth: 88.0)
            studyDB.upsertPinnedReference(pinnedReferences[idx], studyId: activeLayerStudyId)
        }
        for idx in journalClips.indices {
            journalClips[idx].posX = mirrorItemX(journalClips[idx].posX, itemWidth: 224.0)
            studyDB.upsertJournalClip(journalClips[idx], studyId: activeLayerStudyId)
        }
        for idx in chapterStudyLinks.indices {
            chapterStudyLinks[idx].posX = mirrorItemX(chapterStudyLinks[idx].posX, itemWidth: 214.0)
            studyDB.upsertStudyMarginLink(chapterStudyLinks[idx])
        }
        for idx in chapterStickers.indices {
            let stW = max(24.0, chapterStickers[idx].width)
            chapterStickers[idx].posX = mirrorItemX(chapterStickers[idx].posX, itemWidth: stW)
            let st = chapterStickers[idx]
            studyDB.updatePlacedSticker(
                id: st.id,
                posX: st.posX,
                posY: st.posY,
                width: st.width,
                height: st.height,
                rotation: st.rotation,
                opacity: st.opacity
            )
        }

        // 2. Immediately spine-mirror Apple Pencil handwriting clusters (zero backwards letters!)
        if !chapterDrawing.strokes.isEmpty {
            let movedDrawing = spineMirrorDrawing(
                chapterDrawing,
                fromLeftHanded: oldLeft,
                toLeftHanded: newLeft,
                scriptureWidth: sWidth,
                canvasWidth: cWidth
            )
            self.chapterDrawing = movedDrawing
            self.drawingRevision += 1

            // Update saved anchors to reflect the new handedness so updateLayoutForInkReflow doesn't double-move
            if let oldA = savedInkAnchors {
                let shiftScripture = (!oldLeft && newLeft) ? (jWidth + 1.0) : -(jWidth + 1.0)
                var shiftedRects: [Int: VerseAnchorRect] = [:]
                for (k, r) in oldA.verseRects {
                    shiftedRects[k] = VerseAnchorRect(rect: CGRect(x: r.minX + shiftScripture, y: r.minY, width: r.width, height: r.height))
                }
                let updatedAnchors = ChapterInkAnchors(
                    scriptureWidth: oldA.scriptureWidth,
                    canvasWidth: oldA.canvasWidth,
                    verseRects: shiftedRects,
                    isLeftHanded: newLeft
                )
                self.savedInkAnchors = updatedAnchors
                studyDB.saveChapterInk(
                    bookId: currentBookId,
                    chapter: currentChapter,
                    data: movedDrawing.dataRepresentation(),
                    fontSize: fontSize,
                    anchors: updatedAnchors,
                    studyId: activeLayerStudyId
                )
            } else {
                studyDB.saveChapterInk(
                    bookId: currentBookId,
                    chapter: currentChapter,
                    data: movedDrawing.dataRepresentation(),
                    fontSize: fontSize,
                    anchors: makeCurrentInkAnchors(),
                    studyId: activeLayerStudyId
                )
            }
        }
    }

    private func spineMirrorDrawing(
        _ drawing: PKDrawing,
        fromLeftHanded oldLeft: Bool,
        toLeftHanded newLeft: Bool,
        scriptureWidth sWidth: Double,
        canvasWidth cWidth: Double
    ) -> PKDrawing {
        let jWidth = max(140.0, cWidth - sWidth - 1.0)
        let strokes = drawing.strokes
        guard !strokes.isEmpty else { return drawing }

        var scriptureIndices: [Int] = []
        var marginIndices: [Int] = []
        for (i, st) in strokes.enumerated() {
            let midX = Double(st.renderBounds.midX)
            let isMargin = oldLeft ? (midX < jWidth + 6.0) : (midX >= sWidth - 6.0)
            if isMargin {
                marginIndices.append(i)
            } else {
                scriptureIndices.append(i)
            }
        }

        var resultStrokes = strokes

        // A. Over-Scripture strokes translate cleanly to stay locked to the exact Bible words
        let scriptureDX: CGFloat = CGFloat((!oldLeft && newLeft) ? (jWidth + 1.0) : -(jWidth + 1.0))
        for i in scriptureIndices {
            var s = resultStrokes[i]
            s.transform = s.transform.concatenating(CGAffineTransform(translationX: scriptureDX, y: 0))
            resultStrokes[i] = s
        }

        // B. Cluster nearby margin strokes into note blocks (union-find on expanded bounding boxes)
        // so each handwritten word/note stays intact left-to-right while its block center mirrors across the spine!
        var parent = Array(0..<marginIndices.count)
        func find(_ x: Int) -> Int {
            var cur = x
            while parent[cur] != cur {
                parent[cur] = parent[parent[cur]]
                cur = parent[cur]
            }
            return cur
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        let expandedRects = marginIndices.map { strokes[$0].renderBounds.insetBy(dx: -36, dy: -26) }
        for a in 0..<marginIndices.count {
            for b in (a + 1)..<marginIndices.count {
                if expandedRects[a].intersects(expandedRects[b]) {
                    union(a, b)
                }
            }
        }

        var clusters: [Int: [Int]] = [:]
        for idx in 0..<marginIndices.count {
            clusters[find(idx), default: []].append(marginIndices[idx])
        }

        for (_, strokeIds) in clusters {
            var box = CGRect.null
            for sid in strokeIds {
                box = box.union(strokes[sid].renderBounds)
            }
            let midX = Double(box.midX)
            let halfW = Double(box.width) * 0.5
            let targetMidX: Double
            if !oldLeft && newLeft {
                let distFromGutter = max(0, midX - (sWidth + 1.0))
                let rawTarget = jWidth - distFromGutter
                targetMidX = min(max(halfW + 8.0, rawTarget), max(halfW + 8.0, jWidth - halfW - 8.0))
            } else {
                let distFromGutter = max(0, jWidth - midX)
                let rawTarget = (sWidth + 1.0) + distFromGutter
                targetMidX = min(max(sWidth + 8.0 + halfW, rawTarget), max(sWidth + 8.0 + halfW, cWidth - halfW - 8.0))
            }
            let dx = CGFloat(targetMidX - midX)
            for sid in strokeIds {
                var s = resultStrokes[sid]
                s.transform = s.transform.concatenating(CGAffineTransform(translationX: dx, y: 0))
                resultStrokes[sid] = s
            }
        }

        return PKDrawing(strokes: resultStrokes)
    }

    public func handleCanvasDrawingChanged(_ newDrawing: PKDrawing, canUndo: Bool, canRedo: Bool) {
        self.chapterDrawing = newDrawing
        self.canUndo = canUndo
        self.canRedo = canRedo
        let anchors = makeCurrentInkAnchors()
        if let anchors { self.savedInkAnchors = anchors }
        let data = newDrawing.dataRepresentation()
        studyDB.saveChapterInk(bookId: currentBookId, chapter: currentChapter, data: data, fontSize: fontSize, anchors: anchors, studyId: activeLayerStudyId)
    }

    public func updateLayoutForInkReflow(verseFrames: [Int: CGRect], scriptureWidth: CGFloat, canvasWidth: CGFloat) {
        currentVerseFrames = verseFrames
        currentScriptureWidth = scriptureWidth
        currentCanvasWidth = canvasWidth

        guard !chapterDrawing.strokes.isEmpty,
              !verseFrames.isEmpty,
              verseFrames.count >= max(1, verses.count / 2) else { return }

        guard let currentAnchors = makeCurrentInkAnchors() else { return }

        // First time capturing anchors for legacy ink — save baseline without moving strokes
        guard let oldAnchors = savedInkAnchors, !oldAnchors.verseRects.isEmpty else {
            savedInkAnchors = currentAnchors
            studyDB.saveChapterInk(
                bookId: currentBookId,
                chapter: currentChapter,
                data: chapterDrawing.dataRepresentation(),
                fontSize: fontSize,
                anchors: currentAnchors,
                studyId: activeLayerStudyId
            )
            return
        }

        let oldLeft = oldAnchors.isLeftHanded ?? false
        let newLeft = isLeftHandedLayout

        // Check whether verse positions, column widths, or handedness shifted meaningfully (> 8pt)
        var maxDelta: Double = abs(currentAnchors.scriptureWidth - oldAnchors.scriptureWidth)
        for (v, newRect) in currentAnchors.verseRects {
            if let oldRect = oldAnchors.verseRects[v] {
                maxDelta = max(maxDelta, abs(newRect.minY - oldRect.minY))
                maxDelta = max(maxDelta, abs(newRect.minX - oldRect.minX))
                maxDelta = max(maxDelta, abs(newRect.height - oldRect.height))
            }
        }
        guard maxDelta > 8.0 || oldLeft != newLeft else { return }

        let oldScriptureMinX: Double = oldAnchors.verseRects.values.map(\.minX).min() ?? (oldLeft ? max(0, oldAnchors.canvasWidth - oldAnchors.scriptureWidth) : 0)
        let oldScriptureMaxX: Double = oldAnchors.verseRects.values.map(\.maxX).max() ?? (oldScriptureMinX + oldAnchors.scriptureWidth)
        let newScriptureMinX: Double = currentAnchors.verseRects.values.map(\.minX).min() ?? (newLeft ? max(0, currentAnchors.canvasWidth - currentAnchors.scriptureWidth) : 0)
        let newScriptureMaxX: Double = currentAnchors.verseRects.values.map(\.maxX).max() ?? (newScriptureMinX + currentAnchors.scriptureWidth)

        let oldMarginOriginX: Double = oldLeft ? 0.0 : (oldScriptureMaxX + 1.0)
        let newMarginOriginX: Double = newLeft ? 0.0 : (newScriptureMaxX + 1.0)

        let sortedOldVerses = oldAnchors.verseRects.sorted { $0.key < $1.key }
        var reflowedStrokes: [PKStroke] = []
        reflowedStrokes.reserveCapacity(chapterDrawing.strokes.count)

        for stroke in chapterDrawing.strokes {
            let bounds = stroke.renderBounds
            let midY = Double(bounds.midY)
            let midX = Double(bounds.midX)

            // Find nearest verse vertically in the previous layout
            var bestVerse = sortedOldVerses.first!.key
            var bestDist = Double.greatestFiniteMagnitude
            for (v, rect) in sortedOldVerses {
                let dist: Double
                if midY >= rect.minY && midY <= rect.maxY {
                    dist = 0
                } else if midY < rect.minY {
                    dist = rect.minY - midY
                } else {
                    dist = midY - rect.maxY
                }
                if dist < bestDist {
                    bestDist = dist
                    bestVerse = v
                }
            }

            guard let oldRect = oldAnchors.verseRects[bestVerse],
                  let newRect = currentAnchors.verseRects[bestVerse] else {
                reflowedStrokes.append(stroke)
                continue
            }

            let relY = min(1.25, max(-0.25, (midY - oldRect.minY) / max(1.0, oldRect.height)))
            let targetMidY = newRect.minY + relY * newRect.height
            let dy = targetMidY - midY

            let wasInMargin = oldLeft ? (midX < oldScriptureMinX - 4.0) : (midX > oldScriptureMaxX + 4.0)
            let dx: Double
            if wasInMargin {
                // Margin handwriting translates cleanly to the active Journal Margin (without flipping letters!)
                dx = newMarginOriginX - oldMarginOriginX
            } else {
                // Over-Scripture underlines/circles track the Scripture column origin
                dx = newRect.minX - oldRect.minX
            }

            var moved = stroke
            moved.transform = moved.transform.concatenating(CGAffineTransform(translationX: CGFloat(dx), y: CGFloat(dy)))
            reflowedStrokes.append(moved)
        }

        let updatedDrawing = PKDrawing(strokes: reflowedStrokes)
        self.chapterDrawing = updatedDrawing
        self.savedInkAnchors = currentAnchors
        self.drawingRevision += 1
        studyDB.saveChapterInk(
            bookId: currentBookId,
            chapter: currentChapter,
            data: updatedDrawing.dataRepresentation(),
            fontSize: fontSize,
            anchors: currentAnchors,
            studyId: activeLayerStudyId
        )
    }

    // MARK: - Printable / Shareable PDF Export

    public func exportCurrentChapterPDF() {
        let lookup = Dictionary(uniqueKeysWithValues: stickerLibrary.map { ($0.id, $0) })
        let chapNotes = notes.filter { $0.bookId == currentBookId && $0.chapter == currentChapter }
        if let url = StudyPDFExporter.exportAnnotatedChapter(
            bookName: currentBook?.name ?? "Bible",
            chapter: currentChapter,
            verses: verses,
            highlights: chapterHighlights,
            drawing: chapterDrawing,
            canvasWidth: max(currentCanvasWidth, 640),
            verseFrames: currentVerseFrames,
            pinnedRefs: pinnedReferences,
            clips: journalClips,
            chapterNotes: chapNotes,
            placedStickers: chapterStickers,
            stickerLookup: lookup,
            showRedLetter: showRedLetter,
            showItalics: showItalics
        ) {
            activeShareSheetItem = ShareSheetItem(url: url)
        } else {
            showToast("Could not generate chapter PDF")
        }
    }

    public func triggerUndo() {
        onUndoRequest?()
    }

    public func triggerRedo() {
        onRedoRequest?()
    }

    // MARK: - Contextual Word / Verse Study

    public func openVerseStudy(_ verse: Verse) {
        studyVerse = verse
        studyWord = nil
        studyStrongsResults = []
        studyWebsterResults = []
        previewCrossRef = nil
        previewCrossRefVerses = []
        previewCrossRefShowContext = false
        activePinnedRefId = nil
        showReferencePanel = true
        showStudyPanel = false
    }

    public func openWordStudy(word: String, in verse: Verse, switchToTab: LeftPanelTab? = nil) {
        let cleaned = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard !cleaned.isEmpty else { return }
        studyVerse = verse
        studyWord = cleaned
        previewCrossRef = nil
        previewCrossRefVerses = []
        previewCrossRefShowContext = false
        activePinnedRefId = nil
        let test = referenceDB.book(id: verse.bookId)?.testament
        studyStrongsResults = referenceDB.searchStrongs(word: cleaned, testament: test, limit: 8)
        studyWebsterResults = referenceDB.lookupWebster(word: cleaned)
        if let tab = switchToTab {
            leftPanelTab = tab
        }
        showReferencePanel = true
        showStudyPanel = false
    }

    public func openCrossRefPreview(_ ref: CrossReference, pinnedId: String? = nil) {
        previewCrossRef = ref
        activePinnedRefId = pinnedId
        previewCrossRefShowContext = false
        previewCrossRefVerses = referenceDB.verses(
            bookId: ref.toBook,
            chapter: ref.toChapter,
            startVerse: ref.toVerseStart,
            endVerse: max(ref.toVerseStart, ref.toVerseEnd)
        )
        recordStudyEvent(
            kind: .crossRef,
            title: ref.displayRef,
            detail: ref.phrase,
            bookId: ref.toBook,
            chapter: ref.toChapter,
            verse: ref.toVerseStart
        )
    }

    public func dismissCrossRefPreview() {
        previewCrossRef = nil
        previewCrossRefVerses = []
        previewCrossRefShowContext = false
        activePinnedRefId = nil
    }

    public func toggleCrossRefContext() {
        guard let ref = previewCrossRef else { return }
        previewCrossRefShowContext.toggle()
        let start = previewCrossRefShowContext ? max(1, ref.toVerseStart - 2) : ref.toVerseStart
        let end = previewCrossRefShowContext ? max(ref.toVerseStart, ref.toVerseEnd) + 2 : max(ref.toVerseStart, ref.toVerseEnd)
        previewCrossRefVerses = referenceDB.verses(
            bookId: ref.toBook,
            chapter: ref.toChapter,
            startVerse: start,
            endVerse: end
        )
    }

    // MARK: - Pinned Reference Chips (Draggable on Journal)

    public func pinCrossReference(_ ref: CrossReference, at point: CGPoint? = nil, defaultX: Double = 520) {
        if !showJournalPanel {
            showJournalPanel = true
            syncModeFromPanels()
        }
        let yOffset = 90.0 + Double(pinnedReferences.count % 8) * 44.0
        let posX = point.map { Double($0.x) } ?? defaultJournalMarginX(offset: 40.0)
        let posY = point.map { Double($0.y) } ?? yOffset
        let pin = PinnedReference(
            id: UUID().uuidString,
            bookId: currentBookId,
            chapter: currentChapter,
            targetBookId: ref.toBook,
            targetChapter: ref.toChapter,
            targetVerseStart: ref.toVerseStart,
            targetVerseEnd: ref.toVerseEnd,
            label: ref.displayRef,
            posX: posX,
            posY: posY,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        studyDB.upsertPinnedReference(pin, studyId: activeLayerStudyId)
        pinnedReferences = studyDB.pinnedReferences(bookId: currentBookId, chapter: currentChapter, studyId: activeLayerStudyId)
        showToast("Pinned \(ref.displayRef) to journal")
    }

    public func pinReferenceFromDragPayload(_ payload: String, at point: CGPoint) {
        let parts = payload.split(separator: "|")
        guard parts.count == 5,
              let tb = Int(parts[0]),
              let tc = Int(parts[1]),
              let tvs = Int(parts[2]),
              let tve = Int(parts[3]) else { return }
        let label = String(parts[4])
        let pin = PinnedReference(
            id: UUID().uuidString,
            bookId: currentBookId,
            chapter: currentChapter,
            targetBookId: tb,
            targetChapter: tc,
            targetVerseStart: tvs,
            targetVerseEnd: tve,
            label: label,
            posX: Double(point.x),
            posY: Double(point.y),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        studyDB.upsertPinnedReference(pin, studyId: activeLayerStudyId)
        pinnedReferences = studyDB.pinnedReferences(bookId: currentBookId, chapter: currentChapter, studyId: activeLayerStudyId)
        showToast("Dropped \(label) into journal")
    }

    public func movePinnedReference(id: String, to point: CGPoint) {
        guard let idx = pinnedReferences.firstIndex(where: { $0.id == id }) else { return }
        pinnedReferences[idx].posX = max(24, Double(point.x))
        pinnedReferences[idx].posY = max(24, Double(point.y))
        studyDB.upsertPinnedReference(pinnedReferences[idx], studyId: activeLayerStudyId)
    }

    public func removePinnedReference(id: String) {
        studyDB.deletePinnedReference(id: id)
        pinnedReferences = studyDB.pinnedReferences(bookId: currentBookId, chapter: currentChapter, studyId: activeLayerStudyId)
        showToast("Removed pinned reference")
    }

    public func openPinnedReference(_ pin: PinnedReference) {
        let targetBook = referenceDB.book(id: pin.targetBookId)
        let ref = CrossReference(
            id: abs(pin.id.hashValue),
            fromBook: pin.bookId,
            fromChapter: pin.chapter,
            fromVerse: 1,
            phrase: "Pinned in Journal",
            toBook: pin.targetBookId,
            toChapter: pin.targetChapter,
            toVerseStart: pin.targetVerseStart,
            toVerseEnd: pin.targetVerseEnd,
            toBookAbbr: targetBook?.abbr ?? "Book \(pin.targetBookId)",
            toBookName: targetBook?.name ?? "Book \(pin.targetBookId)"
        )
        openCrossRefPreview(ref, pinnedId: pin.id)
    }

    public func setZoom(_ scale: CGFloat) {
        journalZoomScale = min(3.5, max(1.0, scale))
    }

    // MARK: - Highlights, Bookmarks, Notes, Copy

    public func applyHighlight(verse: Verse, preset: HighlightPreset) {
        studyDB.setHighlight(bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse, colorHex: preset.hex, category: preset.name)
        chapterHighlights = studyDB.highlights(bookId: currentBookId, chapter: currentChapter)
        allHighlights = studyDB.allHighlights()
        recordStudyEvent(
            kind: .highlight,
            title: "\(bookName(verse.bookId)) \(verse.chapter):\(verse.verse) (\(preset.name))",
            detail: String(verse.text.prefix(110)),
            bookId: verse.bookId,
            chapter: verse.chapter,
            verse: verse.verse
        )
        showToast("Highlighted \(bookName(verse.bookId)) \(verse.chapter):\(verse.verse)")
    }

    public func removeHighlight(verse: Verse) {
        studyDB.removeHighlight(bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse)
        chapterHighlights = studyDB.highlights(bookId: currentBookId, chapter: currentChapter)
        allHighlights = studyDB.allHighlights()
        showToast("Highlight removed")
    }

    public func addBookmark(for verse: Verse, customLabel: String? = nil) {
        let label = customLabel?.isEmpty == false ? customLabel! : "\(bookName(verse.bookId)) \(verse.chapter):\(verse.verse)"
        studyDB.addBookmark(bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse, label: label)
        bookmarks = studyDB.allBookmarks()
        showToast("Bookmarked \(label)")
    }

    public func deleteBookmark(_ bookmark: UserBookmark) {
        studyDB.deleteBookmark(id: bookmark.id)
        bookmarks = studyDB.allBookmarks()
    }

    public func saveNote(id: String? = nil, type: NoteType, title: String, body: String, richBodyRTF: Data? = nil, drawingData: Data? = nil, verse: Verse?) {
        studyDB.saveNote(
            id: id,
            noteType: type,
            title: title,
            body: body,
            richBodyRTF: richBodyRTF,
            drawingData: drawingData,
            bookId: verse?.bookId ?? currentBookId,
            chapter: verse?.chapter ?? currentChapter,
            verse: verse?.verse
        )
        notes = studyDB.allNotes()
        recordStudyEvent(
            kind: .note,
            title: title.isEmpty ? "\(type.rawValue) Note" : title,
            detail: String(body.prefix(110)),
            bookId: verse?.bookId ?? currentBookId,
            chapter: verse?.chapter ?? currentChapter,
            verse: verse?.verse
        )
        showToast("Notebook saved")
    }

    public func openNewNotebook(type: NoteType = .sermon, verse: Verse? = nil) {
        let v = verse
        let defaultTitle: String
        if let v {
            defaultTitle = "\(type.rawValue) — \(bookName(v.bookId)) \(v.chapter):\(v.verse)"
        } else {
            defaultTitle = "\(type.rawValue) — \(currentLocationTitle)"
        }
        activeNotebookNote = UserNote(
            id: UUID().uuidString,
            noteType: type,
            title: defaultTitle,
            body: "",
            drawingData: nil,
            bookId: v?.bookId ?? currentBookId,
            chapter: v?.chapter ?? currentChapter,
            verse: v?.verse,
            updatedAt: ""
        )
    }

    public func openExistingNotebook(_ note: UserNote) {
        activeNotebookNote = note
    }

    public func createCollection(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        _ = studyDB.createCollection(name: clean)
        collections = studyDB.allCollections()
        showToast("Created collection \"\(clean)\"")
    }

    public func deleteCollection(_ col: StudyCollection) {
        studyDB.deleteCollection(id: col.id)
        collections = studyDB.allCollections()
    }

    public func addVerseToCollection(_ verse: Verse, collection: StudyCollection) {
        studyDB.addCollectionItem(collectionId: collection.id, bookId: verse.bookId, chapter: verse.chapter, verse: verse.verse)
        showToast("Added \(bookName(verse.bookId)) \(verse.chapter):\(verse.verse) to \(collection.name)")
    }

    public func renameHighlightCategory(id: String, newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        studyDB.renameHighlightCategory(id: id, name: clean)
        highlightCategories = studyDB.highlightCategories()
        showToast("Updated highlight label")
    }

    public func prepareBackupExport() -> URL? {
        let url = studyDB.createBackupSnapshot()
        backupExportURL = url
        if url != nil {
            showToast("Backup ready to share")
        }
        return url
    }

    public func restoreFromBackup(url: URL) throws {
        try studyDB.restoreFromBackup(url: url)
        restorePreferences()
        reloadUserCollections()
        navigate(to: VerseRef(bookId: currentBookId, chapter: currentChapter, verse: nil), pushHistory: false)
        showToast("Study backup restored!")
    }

    public func deleteNote(_ note: UserNote) {
        studyDB.deleteNote(id: note.id)
        notes = studyDB.allNotes()
    }

    public func copyVerseToClipboard(_ verse: Verse) {
        let formatted = "\"\(verse.text)\" — \(bookName(verse.bookId)) \(verse.chapter):\(verse.verse) (KJV)"
        UIPasteboard.general.string = formatted
        showToast("Copied \(bookName(verse.bookId)) \(verse.chapter):\(verse.verse)")
    }

    public func bookName(_ id: Int) -> String {
        referenceDB.book(id: id)?.name ?? "Book \(id)"
    }

    public func reloadUserCollections() {
        bookmarks = studyDB.allBookmarks()
        notes = studyDB.allNotes()
        allHighlights = studyDB.allHighlights()
        highlightCategories = studyDB.highlightCategories()
        collections = studyDB.allCollections()
        readingHistory = studyDB.recentHistory(limit: 50)
        stickerLibrary = studyDB.allStickers()
        studySessions = studyDB.allStudySessions()
        if let activeId = studyDB.getPreference("active_study_id"), !activeId.isEmpty,
           let found = studySessions.first(where: { $0.id == activeId }) {
            activeStudy = found
            activeStudyTrail = studyDB.studyTrailEntries(studyId: found.id)
        }
    }

    // MARK: - Named Study Sessions ("Study Trails") & Permanent Bible Ink Links

    public func recordStudyEvent(
        kind: StudyTrailKind,
        title: String,
        detail: String = "",
        bookId: Int? = nil,
        chapter: Int? = nil,
        verse: Int? = nil,
        refKey: String? = nil
    ) {
        guard let study = activeStudy else { return }
        _ = studyDB.appendStudyTrailEntry(
            studyId: study.id,
            kind: kind,
            title: title,
            detail: detail,
            bookId: bookId,
            chapter: chapter,
            verse: verse,
            refKey: refKey
        )
        activeStudyTrail = studyDB.studyTrailEntries(studyId: study.id)
        studySessions = studyDB.allStudySessions()
    }

    public func createAndStartStudy(name: String, startBookId: Int, startChapter: Int, startVerse: Int?, summaryNote: String = "") {
        flushCurrentChapterTime()
        let session = studyDB.createStudySession(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            startBookId: startBookId,
            startChapter: startChapter,
            startVerse: startVerse,
            summaryNote: summaryNote
        )
        studySessions = studyDB.allStudySessions()
        activeStudy = session
        studyDB.setPreference("active_study_id", value: session.id)
        navigate(to: VerseRef(bookId: startBookId, chapter: startChapter, verse: startVerse), pushHistory: true)
        showToast("Started Study: \"\(session.name)\"")
    }

    public func activateStudy(_ session: StudySession, jumpToLastPassage: Bool = true) {
        flushCurrentChapterTime()
        activeStudy = session
        studyDB.setPreference("active_study_id", value: session.id)
        let trail = studyDB.studyTrailEntries(studyId: session.id)
        activeStudyTrail = trail
        if jumpToLastPassage {
            if let lastP = trail.first(where: { $0.kind == .passage && $0.bookId != nil && $0.chapter != nil }),
               let b = lastP.bookId, let c = lastP.chapter {
                navigate(to: VerseRef(bookId: b, chapter: c, verse: lastP.verse), pushHistory: true)
            } else {
                navigate(to: VerseRef(bookId: session.startBookId, chapter: session.startChapter, verse: session.startVerse), pushHistory: true)
            }
        } else {
            reloadActiveChapterLayer()
        }
        showToast("Study Layer: \"\(session.name)\"")
    }

    public func exitActiveStudy() {
        flushCurrentChapterTime()
        activeStudy = nil
        activeStudyTrail = []
        activeStudyPassageEntryId = nil
        studyDB.setPreference("active_study_id", value: "")
        reloadActiveChapterLayer()
        showToast("Back to Everyday Bible")
    }

    public func renameStudy(id: String, newName: String, summaryNote: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        studyDB.updateStudySession(id: id, name: clean, summaryNote: summaryNote)
        studySessions = studyDB.allStudySessions()
        if activeStudy?.id == id {
            activeStudy = studySessions.first(where: { $0.id == id })
        }
        chapterStudyLinks = studyDB.studyMarginLinks(bookId: currentBookId, chapter: currentChapter)
        showToast("Updated Study \"\(clean)\"")
    }

    public func deleteStudy(_ session: StudySession) {
        if activeStudy?.id == session.id {
            exitActiveStudy()
        }
        studyDB.deleteStudySession(id: session.id)
        studySessions = studyDB.allStudySessions()
        chapterStudyLinks = studyDB.studyMarginLinks(bookId: currentBookId, chapter: currentChapter)
        showToast("Deleted Study")
    }

    public func deleteStudyTrailEntry(_ entry: StudyTrailEntry) {
        studyDB.deleteStudyTrailEntry(id: entry.id)
        if let sid = activeStudy?.id {
            activeStudyTrail = studyDB.studyTrailEntries(studyId: sid)
        }
    }

    public func addStudyMarginLink(study: StudySession, verse: Int?, noteText: String) {
        let offset = Double(chapterStudyLinks.count % 5)
        let startX: Double = defaultJournalMarginX(offset: offset * 14.0)
        let startY: Double = 90.0 + offset * 48.0
        let link = StudyMarginLink(
            id: UUID().uuidString,
            studyId: study.id,
            studyName: study.name,
            bookId: currentBookId,
            chapter: currentChapter,
            verse: verse,
            noteText: noteText.trimmingCharacters(in: .whitespacesAndNewlines),
            posX: startX,
            posY: startY,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        studyDB.upsertStudyMarginLink(link)
        chapterStudyLinks = studyDB.studyMarginLinks(bookId: currentBookId, chapter: currentChapter)
        if workspaceMode == .reading && !showInkInReadingMode {
            showInkInReadingMode = true
        }
        recordStudyEvent(
            kind: .note,
            title: "Linked to \(currentLocationTitle)\(verse != nil ? ":\(verse!)" : "")",
            detail: link.noteText,
            bookId: currentBookId,
            chapter: currentChapter,
            verse: verse
        )
        showToast("Linked \"\(study.name)\" to \(currentLocationTitle)")
    }

    public func updateStudyMarginLink(_ link: StudyMarginLink) {
        studyDB.upsertStudyMarginLink(link)
        chapterStudyLinks = studyDB.studyMarginLinks(bookId: currentBookId, chapter: currentChapter)
    }

    public func removeStudyMarginLink(id: String) {
        studyDB.deleteStudyMarginLink(id: id)
        chapterStudyLinks = studyDB.studyMarginLinks(bookId: currentBookId, chapter: currentChapter)
        showToast("Removed study link")
    }

    // MARK: - Shareable Study Lessons (.sqstudy, Classroom QR Code, Clickable Links)

    public func setTeacherAuthorName(_ name: String) {
        teacherAuthorName = name
        studyDB.setPreference("teacher_author_name", value: name)
    }

    public func handleIncomingURL(_ url: URL) {
        if url.pathExtension.lowercased() == "sqmod" {
            moduleManager.importLocalSQMod(url: url)
            syncCommentarySelection()
            showToast(moduleManager.statusMessage ?? "Imported study module")
            return
        }
        if let pkg = StudyPackageCodec.decode(from: url) {
            incomingStudyPackage = pkg
        } else {
            showToast("Could not read Study Lesson file or link")
        }
    }

    // MARK: - Modular Library & Commentaries

    public func selectCommentaryModule(_ moduleId: String) {
        selectedCommentaryModuleId = moduleId
        studyDB.setPreference("selected_commentary_id", value: moduleId)
        reloadChapterCommentary()
    }

    public func syncCommentarySelection() {
        let enabled = moduleManager.enabledCommentaries
        if enabled.isEmpty {
            selectedCommentaryModuleId = nil
            chapterCommentaryEntries = []
            if leftPanelTab == .commentary {
                leftPanelTab = .crossRefs
            }
            return
        }
        if let cur = selectedCommentaryModuleId, enabled.contains(where: { $0.id == cur }) {
            reloadChapterCommentary()
        } else {
            selectedCommentaryModuleId = enabled.first?.id
            reloadChapterCommentary()
        }
    }

    public func reloadChapterCommentary() {
        let enabled = moduleManager.enabledCommentaries
        guard !enabled.isEmpty else {
            chapterCommentaryEntries = []
            return
        }
        let targetId: String
        if let cur = selectedCommentaryModuleId, enabled.contains(where: { $0.id == cur }) {
            targetId = cur
        } else if let saved = studyDB.getPreference("selected_commentary_id"),
                  enabled.contains(where: { $0.id == saved }) {
            targetId = saved
            selectedCommentaryModuleId = saved
        } else {
            targetId = enabled[0].id
            selectedCommentaryModuleId = targetId
        }
        chapterCommentaryEntries = moduleManager.commentaryEntries(
            moduleId: targetId,
            bookId: currentBookId,
            chapter: currentChapter
        )
    }

    public func importStudyPackage(_ package: StudySharePackage, includeMarginNotes: Bool) {
        flushCurrentChapterTime()
        let session = studyDB.createStudySession(
            name: package.name,
            startBookId: package.startBookId,
            startChapter: package.startChapter,
            startVerse: package.startVerse,
            summaryNote: package.summary ?? ""
        )
        for item in package.entries {
            let kind = StudyTrailKind(rawValue: item.k) ?? .passage
            _ = studyDB.appendStudyTrailEntry(
                studyId: session.id,
                kind: kind,
                title: item.t,
                detail: item.d ?? "",
                bookId: item.b,
                chapter: item.c,
                verse: item.v,
                refKey: item.r
            )
        }
        if includeMarginNotes, let marginNotes = package.marginNotes {
            for (idx, mn) in marginNotes.enumerated() {
                let link = StudyMarginLink(
                    id: UUID().uuidString,
                    studyId: session.id,
                    studyName: session.name,
                    bookId: mn.b,
                    chapter: mn.c,
                    verse: mn.v,
                    noteText: mn.n,
                    posX: 430.0 + Double(idx % 4) * 14.0,
                    posY: 90.0 + Double(idx % 6) * 52.0,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
                studyDB.upsertStudyMarginLink(link)
            }
        }
        studySessions = studyDB.allStudySessions()
        activeStudy = session
        studyDB.setPreference("active_study_id", value: session.id)
        activeStudyTrail = studyDB.studyTrailEntries(studyId: session.id)
        navigate(to: VerseRef(bookId: session.startBookId, chapter: session.startChapter, verse: session.startVerse), pushHistory: true)
        showToast("Imported Study \"\(session.name)\"")
    }

    // MARK: - Stickers (Library + Chapter Placement)

    public func stickerItem(for id: String) -> StickerItem? {
        stickerLibrary.first(where: { $0.id == id })
    }

    public func saveCustomSticker(name: String, kind: StickerKind, category: String, imageData: Data, drawingData: Data? = nil) -> StickerItem {
        let item = studyDB.saveCustomSticker(name: name, kind: kind, category: category, imageData: imageData, drawingData: drawingData)
        stickerLibrary = studyDB.allStickers()
        showToast("Saved sticker \"\(item.name)\"")
        return item
    }

    public func updateCustomSticker(id: String, name: String, imageData: Data, drawingData: Data?) -> StickerItem? {
        studyDB.updateCustomSticker(id: id, name: name, imageData: imageData, drawingData: drawingData)
        stickerLibrary = studyDB.allStickers()
        showToast("Updated sticker \"\(name)\"")
        return stickerItem(for: id)
    }

    public func deleteStickerFromLibrary(_ item: StickerItem) {
        studyDB.deleteStickerFromLibrary(id: item.id)
        stickerLibrary = studyDB.allStickers()
        chapterStickers = studyDB.placedStickers(targetType: "chapter", targetKey: "\(currentBookId)-\(currentChapter)")
        showToast("Deleted sticker")
    }

    public func placeStickerOnChapter(_ item: StickerItem) {
        let offsetIndex = Double(chapterStickers.count % 6)
        let startX: Double = defaultJournalMarginX(offset: offsetIndex * 16.0)
        let startY: Double = 110.0 + offsetIndex * 28.0
        let defaultSize: Double = item.kind == .symbol ? 68.0 : 96.0
        let placed = studyDB.addPlacedSticker(
            stickerId: item.id,
            targetType: activeStickerTargetType,
            targetKey: activeStickerTargetKey,
            posX: startX,
            posY: startY,
            width: defaultSize,
            height: defaultSize,
            rotation: 0
        )
        chapterStickers.append(placed)
        selectedChapterStickerId = placed.id
        if workspaceMode == .reading && !showInkInReadingMode {
            showInkInReadingMode = true
        }
        showToast("Added \"\(item.name)\" sticker — drag to position")
    }

    public func updateChapterSticker(_ updated: PlacedSticker) {
        if let idx = chapterStickers.firstIndex(where: { $0.id == updated.id }) {
            chapterStickers[idx] = updated
        }
        studyDB.updatePlacedSticker(
            id: updated.id,
            posX: updated.posX,
            posY: updated.posY,
            width: updated.width,
            height: updated.height,
            rotation: updated.rotation,
            opacity: updated.opacity
        )
    }

    public func removeChapterSticker(id: String) {
        studyDB.deletePlacedSticker(id: id)
        chapterStickers.removeAll(where: { $0.id == id })
        if selectedChapterStickerId == id {
            selectedChapterStickerId = nil
        }
    }

    public func persistAppearancePreferences() {
        studyDB.setPreference("theme", value: theme.id)
        studyDB.setPreference("font_size", value: String(fontSize))
        studyDB.setPreference("study_desk_font_size", value: String(studyDeskFontSize))
        studyDB.setPreference("scripture_font_design", value: scriptureFontDesign.rawValue)
        studyDB.setPreference("line_spacing", value: String(lineSpacing))
        studyDB.setPreference("paper_style", value: paperStyle.rawValue)
        studyDB.setPreference("pencil_only", value: pencilOnly ? "1" : "0")
        studyDB.setPreference("show_ink_reading", value: showInkInReadingMode ? "1" : "0")
        studyDB.setPreference("show_red_letter", value: showRedLetter ? "1" : "0")
        studyDB.setPreference("show_italics", value: showItalics ? "1" : "0")
        studyDB.setPreference("show_verse_numbers", value: showVerseNumbers ? "1" : "0")
        studyDB.setPreference("left_handed_layout", value: isLeftHandedLayout ? "1" : "0")
        studyDB.setPreference("keep_screen_awake", value: keepScreenAwake ? "1" : "0")
        persistCustomThemes()
    }

    public func saveCustomTheme(_ palette: CustomThemePalette, applyImmediately: Bool = true) {
        if let idx = customThemes.firstIndex(where: { $0.id == palette.id }) {
            customThemes[idx] = palette
        } else {
            customThemes.append(palette)
        }
        persistCustomThemes()
        if applyImmediately {
            theme = ReadingTheme.fromCustom(palette)
            studyDB.setPreference("theme", value: theme.id)
        }
        showToast("Saved theme \"\(palette.name)\"")
    }

    public func deleteCustomTheme(_ palette: CustomThemePalette) {
        customThemes.removeAll(where: { $0.id == palette.id })
        persistCustomThemes()
        if theme.id == "custom:\(palette.id)" {
            theme = .paperSepia
            studyDB.setPreference("theme", value: theme.id)
        }
    }

    private func persistCustomThemes() {
        if let data = try? JSONEncoder().encode(customThemes),
           let json = String(data: data, encoding: .utf8) {
            studyDB.setPreference("custom_themes_json", value: json)
        }
    }

    public var allAvailableThemes: [ReadingTheme] {
        ReadingTheme.allCases + customThemes.map { ReadingTheme.fromCustom($0) }
    }

    public func persistLayoutPreferences() {
        studyDB.setPreference("show_ref", value: showReferencePanel ? "1" : "0")
        studyDB.setPreference("show_journal", value: showJournalPanel ? "1" : "0")
        studyDB.setPreference("left_panel_width", value: String(format: "%.1f", Double(leftPanelWidth)))
        studyDB.setPreference("ref_filter", value: referenceFilter.rawValue)
    }

    private func restorePreferences() {
        if let raw = studyDB.getPreference("custom_themes_json"),
           let d = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([CustomThemePalette].self, from: d) {
            customThemes = decoded
        }
        if let b = studyDB.getPreference("last_book_id").flatMap(Int.init) { currentBookId = b }
        if let c = studyDB.getPreference("last_chapter").flatMap(Int.init) { currentChapter = c }
        if let tId = studyDB.getPreference("theme") {
            if let builtIn = ReadingTheme(rawValue: tId) {
                theme = builtIn
            } else if tId.hasPrefix("custom:") {
                let cid = String(tId.dropFirst("custom:".count))
                if let custom = customThemes.first(where: { $0.id == cid }) {
                    theme = ReadingTheme.fromCustom(custom)
                }
            }
        }
        if let f = studyDB.getPreference("font_size").flatMap(Double.init) { fontSize = f }
        if let sf = studyDB.getPreference("study_desk_font_size").flatMap(Double.init) { studyDeskFontSize = sf }
        if let fd = studyDB.getPreference("scripture_font_design").flatMap(ScriptureFontDesign.init(rawValue:)) { scriptureFontDesign = fd }
        if let l = studyDB.getPreference("line_spacing").flatMap(Double.init) { lineSpacing = l }
        if let p = studyDB.getPreference("paper_style").flatMap(JournalPaperStyle.init(rawValue:)) { paperStyle = p }
        if let po = studyDB.getPreference("pencil_only") { pencilOnly = (po != "0") }
        if let sir = studyDB.getPreference("show_ink_reading") { showInkInReadingMode = (sir == "1") }
        if let srl = studyDB.getPreference("show_red_letter") { showRedLetter = (srl != "0") }
        if let sit = studyDB.getPreference("show_italics") { showItalics = (sit != "0") }
        if let svn = studyDB.getPreference("show_verse_numbers") { showVerseNumbers = (svn != "0") }
        if let lh = studyDB.getPreference("left_handed_layout") { isLeftHandedLayout = (lh == "1") }
        if let ka = studyDB.getPreference("keep_screen_awake") { keepScreenAwake = (ka == "1") }
        if let sr = studyDB.getPreference("show_ref") { showReferencePanel = (sr != "0") }
        if let sj = studyDB.getPreference("show_journal") { showJournalPanel = (sj != "0") }
        if let lpw = studyDB.getPreference("left_panel_width").flatMap(Double.init) { leftPanelWidth = CGFloat(lpw) }
        if let rf = studyDB.getPreference("ref_filter").flatMap(ReferenceSourceFilter.init(rawValue:)) { referenceFilter = rf }
        if let sar = studyDB.getPreference("show_all_refs") { showAllReferencesExpanded = (sar == "1") }
        if let pb = studyDB.getPreference("parallel_book_id").flatMap(Int.init) { parallelBookId = pb }
        if let pc = studyDB.getPreference("parallel_chapter").flatMap(Int.init) { parallelChapter = pc }
        if let ta = studyDB.getPreference("teacher_author_name") { teacherAuthorName = ta }
        if let raw = studyDB.getPreference("pinned_study_ids"), let d = raw.data(using: .utf8), let arr = try? JSONDecoder().decode([String].self, from: d) {
            pinnedStudyIds = Set(arr)
        }
        if let raw = studyDB.getPreference("archived_study_ids"), let d = raw.data(using: .utf8), let arr = try? JSONDecoder().decode([String].self, from: d) {
            archivedStudyIds = Set(arr)
        }
        if let raw = studyDB.getPreference("starred_trail_entry_ids"), let d = raw.data(using: .utf8), let arr = try? JSONDecoder().decode([String].self, from: d) {
            starredTrailEntryIds = Set(arr)
        }
        syncModeFromPanels()
    }

    public var quickMenuStudies: [StudySession] {
        let nonArchived = studySessions.filter { !archivedStudyIds.contains($0.id) }
        let pinned = nonArchived.filter { pinnedStudyIds.contains($0.id) }
        let unpinned = nonArchived.filter { !pinnedStudyIds.contains($0.id) }
        return Array((pinned + unpinned).prefix(6))
    }

    public func togglePinStudy(_ studyId: String) {
        if pinnedStudyIds.contains(studyId) {
            pinnedStudyIds.remove(studyId)
        } else {
            pinnedStudyIds.insert(studyId)
            archivedStudyIds.remove(studyId)
        }
        persistStudyOrganization()
    }

    public func toggleArchiveStudy(_ studyId: String) {
        if archivedStudyIds.contains(studyId) {
            archivedStudyIds.remove(studyId)
        } else {
            archivedStudyIds.insert(studyId)
            pinnedStudyIds.remove(studyId)
            if activeStudy?.id == studyId {
                exitActiveStudy()
            }
        }
        persistStudyOrganization()
    }

    public func toggleStarTrailEntry(_ entryId: String) {
        if starredTrailEntryIds.contains(entryId) {
            starredTrailEntryIds.remove(entryId)
        } else {
            starredTrailEntryIds.insert(entryId)
        }
        persistStudyOrganization()
    }

    private func persistStudyOrganization() {
        if let d = try? JSONEncoder().encode(Array(pinnedStudyIds)), let s = String(data: d, encoding: .utf8) {
            studyDB.setPreference("pinned_study_ids", value: s)
        }
        if let d = try? JSONEncoder().encode(Array(archivedStudyIds)), let s = String(data: d, encoding: .utf8) {
            studyDB.setPreference("archived_study_ids", value: s)
        }
        if let d = try? JSONEncoder().encode(Array(starredTrailEntryIds)), let s = String(data: d, encoding: .utf8) {
            studyDB.setPreference("starred_trail_entry_ids", value: s)
        }
    }

    public func showToast(_ msg: String) {
        toastMessage = msg
        Task {
            try? await Task.sleep(for: .seconds(2))
            if self.toastMessage == msg {
                self.toastMessage = nil
            }
        }
    }
}
