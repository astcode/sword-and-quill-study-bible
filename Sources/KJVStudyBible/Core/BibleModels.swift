import Foundation
import SwiftUI
import UIKit

public struct Book: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let abbr: String
    public let testament: String // "OT" or "NT"
    public let chapterCount: Int
}

public struct Verse: Identifiable, Hashable, Sendable {
    public let id: Int
    public let bookId: Int
    public let chapter: Int
    public let verse: Int
    public let text: String
    public let textMarked: String

    public init(id: Int, bookId: Int, chapter: Int, verse: Int, text: String, textMarked: String = "") {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.text = text
        self.textMarked = textMarked
    }
}

public struct InterlinearWord: Identifiable, Hashable, Sendable {
    public let id: Int
    public let wordPos: Int
    public let originalText: String
    public let translit: String
    public let gloss: String
    public let strongsId: String
    public let morph: String
}

public enum StudyDictionarySource: String, CaseIterable, Identifiable, Sendable {
    case webster1828 = "1828"
    case easton = "Easton"
    case nave = "Nave"
    case torrey = "Torrey"

    public var id: String { rawValue }

    public var fullName: String {
        switch self {
        case .webster1828: return "Webster's 1828 Dictionary"
        case .easton: return "Easton's Bible Dictionary"
        case .nave: return "Nave's Topical Bible"
        case .torrey: return "Torrey's Topical Textbook"
        }
    }

    public var dbKey: String {
        switch self {
        case .webster1828: return "webster1828"
        case .easton: return "easton"
        case .nave: return "nave"
        case .torrey: return "torrey"
        }
    }
}

public struct StudyDictionaryEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let source: StudyDictionarySource
    public let headword: String
    public let body: String
}

public struct VerseRef: Hashable, Codable, Sendable {
    public let bookId: Int
    public let chapter: Int
    public let verse: Int?

    public init(bookId: Int, chapter: Int, verse: Int? = nil) {
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
    }
}

public struct CrossReference: Identifiable, Hashable, Sendable {
    public let id: Int
    public let fromBook: Int
    public let fromChapter: Int
    public let fromVerse: Int
    public let phrase: String
    public let toBook: Int
    public let toChapter: Int
    public let toVerseStart: Int
    public let toVerseEnd: Int
    public let toBookAbbr: String
    public let toBookName: String

    public var displayRef: String {
        if toVerseEnd > toVerseStart {
            return "\(toBookAbbr) \(toChapter):\(toVerseStart)–\(toVerseEnd)"
        }
        return "\(toBookAbbr) \(toChapter):\(toVerseStart)"
    }
}

public struct StrongsEntry: Identifiable, Hashable, Sendable {
    public var id: String { strongsId }
    public let strongsId: String
    public let testament: String
    public let lemma: String
    public let translit: String
    public let pronunciation: String
    public let derivation: String
    public let definition: String
    public let kjvUsage: String
}

public struct WebsterEntry: Identifiable, Hashable, Sendable {
    public let id: Int
    public let headword: String
    public let headwordNorm: String
    public let definition: String
}

public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: Int
    public let bookId: Int
    public let bookName: String
    public let chapter: Int
    public let verse: Int
    public let text: String

    public var referenceLabel: String {
        "\(bookName) \(chapter):\(verse)"
    }
}

public struct UserBookmark: Identifiable, Hashable, Sendable {
    public let id: String
    public let bookId: Int
    public let chapter: Int
    public let verse: Int
    public let label: String
    public let createdAt: String
}

public struct UserHighlight: Identifiable, Hashable, Sendable {
    public let id: String
    public let bookId: Int
    public let chapter: Int
    public let verse: Int
    public let colorHex: String
    public let category: String
    public let updatedAt: String
}

public struct PinnedReference: Identifiable, Hashable, Sendable {
    public let id: String
    public let bookId: Int
    public let chapter: Int
    public let targetBookId: Int
    public let targetChapter: Int
    public let targetVerseStart: Int
    public let targetVerseEnd: Int
    public let label: String
    public var posX: Double
    public var posY: Double
    public let updatedAt: String
}

public struct JournalClipCard: Identifiable, Hashable, Sendable {
    public let id: String
    public let bookId: Int
    public let chapter: Int
    public let sourceLabel: String
    public var excerpt: String
    public var userNote: String
    public var posX: Double
    public var posY: Double
    public let updatedAt: String
}

public struct ClipDraft: Identifiable, Hashable, Sendable {
    public let id: String
    public let editingCardId: String?
    public let sourceLabel: String
    public let initialExcerpt: String
    public let initialNote: String

    public init(editingCardId: String? = nil, sourceLabel: String, initialExcerpt: String, initialNote: String = "") {
        self.id = editingCardId ?? UUID().uuidString
        self.editingCardId = editingCardId
        self.sourceLabel = sourceLabel
        self.initialExcerpt = initialExcerpt
        self.initialNote = initialNote
    }
}

public enum NoteType: String, CaseIterable, Identifiable, Sendable {
    case passage = "Passage"
    case sermon = "Sermon"
    case study = "Study"
    case journal = "Journal"
    case chapter = "Chapter"

    public var id: String { rawValue }
}

public struct UserNote: Identifiable, Hashable, Sendable {
    public let id: String
    public let noteType: NoteType
    public let title: String
    public let body: String
    public let richBodyRTF: Data?
    public let drawingData: Data?
    public let bookId: Int?
    public let chapter: Int?
    public let verse: Int?
    public let updatedAt: String

    public init(id: String, noteType: NoteType, title: String, body: String, richBodyRTF: Data? = nil, drawingData: Data? = nil, bookId: Int?, chapter: Int?, verse: Int?, updatedAt: String) {
        self.id = id
        self.noteType = noteType
        self.title = title
        self.body = body
        self.richBodyRTF = richBodyRTF
        self.drawingData = drawingData
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.updatedAt = updatedAt
    }
}

public struct StudyCollection: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public let createdAt: String
}

public struct CollectionItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let collectionId: String
    public let bookId: Int
    public let chapter: Int
    public let verse: Int
    public let addedAt: String
}

public struct ReadingHistoryItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let bookId: Int
    public let chapter: Int
    public let verse: Int?
    public let visitedAt: String
    public let durationSeconds: Int

    public init(id: Int, bookId: Int, chapter: Int, verse: Int?, visitedAt: String, durationSeconds: Int = 0) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.visitedAt = visitedAt
        self.durationSeconds = durationSeconds
    }

    public var formattedDuration: String {
        let s = max(0, durationSeconds)
        if s < 5 { return "< 5s" }
        if s < 60 { return "\(s)s" }
        let mins = s / 60
        let remS = s % 60
        if mins < 60 {
            return remS > 0 ? "\(mins)m \(remS)s" : "\(mins)m"
        }
        let hrs = mins / 60
        let remM = mins % 60
        return remM > 0 ? "\(hrs)h \(remM)m" : "\(hrs)h"
    }

    public var formattedVisitedAt: String {
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: visitedAt) else { return "" }
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .short
        return df.string(from: date)
    }
}

public struct PersonalSearchHit: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: String // "Note", "Clip", "Bookmark", "Study", "Study Trail"
    public let title: String
    public let snippet: String
    public let bookId: Int?
    public let chapter: Int?
    public let verse: Int?
    public let noteId: String?
    public let studyId: String?

    public init(
        id: String,
        kind: String,
        title: String,
        snippet: String,
        bookId: Int?,
        chapter: Int?,
        verse: Int?,
        noteId: String?,
        studyId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.snippet = snippet
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.noteId = noteId
        self.studyId = studyId
    }
}

// MARK: - Notability-Style Stickers

public enum StickerKind: String, CaseIterable, Identifiable, Sendable {
    case symbol = "symbol"
    case drawn = "drawn"
    case imported = "imported"

    public var id: String { rawValue }
}

public struct StickerItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: StickerKind
    public let category: String
    public let symbolName: String?
    public let tintHex: String?
    public let imageData: Data?
    public let drawingData: Data?
    public let createdAt: String

    public init(id: String, name: String, kind: StickerKind, category: String, symbolName: String?, tintHex: String?, imageData: Data?, drawingData: Data? = nil, createdAt: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.category = category
        self.symbolName = symbolName
        self.tintHex = tintHex
        self.imageData = imageData
        self.drawingData = drawingData
        self.createdAt = createdAt
    }

    public var tintColor: Color {
        if let hex = tintHex, let ui = UIColor(hex: hex) {
            return Color(uiColor: ui)
        }
        return Color(red: 0.180, green: 0.380, blue: 0.620)
    }
}

public struct PlacedSticker: Identifiable, Hashable, Sendable {
    public let id: String
    public let stickerId: String
    public let targetType: String // "chapter" or "note"
    public let targetKey: String  // "\(bookId)-\(chapter)" or noteId
    public var posX: Double
    public var posY: Double
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var opacity: Double
    public let updatedAt: String
}

// MARK: - Verse-Anchored Ink Reflow Snapshots

public struct VerseAnchorRect: Codable, Hashable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }
    public var midY: Double { minY + height * 0.5 }

    public init(rect: CGRect) {
        self.minX = Double(rect.minX)
        self.minY = Double(rect.minY)
        self.width = Double(rect.width)
        self.height = Double(rect.height)
    }
}

public struct ChapterInkAnchors: Codable, Hashable, Sendable {
    public let scriptureWidth: Double
    public let canvasWidth: Double
    public let verseRects: [Int: VerseAnchorRect]

    public init(scriptureWidth: Double, canvasWidth: Double, verseRects: [Int: VerseAnchorRect]) {
        self.scriptureWidth = scriptureWidth
        self.canvasWidth = canvasWidth
        self.verseRects = verseRects
    }
}

// MARK: - Biblical Geography & Places (Offline OpenBible Geocoding)

public struct BiblicalPlace: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let placeType: String
    public let modernName: String
    public let description: String
    public let lat: Double
    public let lon: Double
    public let verseCount: Int

    /// Great-circle distance in statute miles from Jerusalem (31.7781° N, 35.2360° E)
    public var milesFromJerusalem: Int {
        let jLat = 31.7781 * .pi / 180.0
        let jLon = 35.2360 * .pi / 180.0
        let pLat = lat * .pi / 180.0
        let pLon = lon * .pi / 180.0
        let dLat = pLat - jLat
        let dLon = pLon - jLon
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(jLat) * cos(pLat) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return Int(round(3958.8 * c))
    }
}

// MARK: - Personal Study Dashboard Stats

public struct BookStudyCount: Identifiable, Hashable, Sendable {
    public var id: Int { bookId }
    public let bookId: Int
    public let itemCount: Int
}

public struct StudyDashboardStats: Hashable, Sendable {
    public let chaptersWithInk: Int
    public let highlightedVerses: Int
    public let notebookCount: Int
    public let bookmarkCount: Int
    public let clipCount: Int
    public let pinnedRefCount: Int
    public let customStickerCount: Int
    public let uniqueChaptersVisited: Int
    public let topBooks: [BookStudyCount]
}

// MARK: - Named Study Sessions ("Study Trails") & Permanent Bible Ink Links

public struct StudySession: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public let startBookId: Int
    public let startChapter: Int
    public let startVerse: Int?
    public var summaryNote: String
    public let createdAt: String
    public var updatedAt: String
}

public enum StudyTrailKind: String, CaseIterable, Identifiable, Sendable {
    case passage = "Passage"
    case crossRef = "Cross-Ref"
    case strongs = "Strong's"
    case dictionary = "Dictionary"
    case place = "Place"
    case note = "Note"
    case clip = "Clip"
    case highlight = "Highlight"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .passage: return "book.closed"
        case .crossRef: return "arrow.triangle.branch"
        case .strongs: return "character.book.closed"
        case .dictionary: return "text.book.closed"
        case .place: return "map"
        case .note: return "note.text"
        case .clip: return "scissors"
        case .highlight: return "highlighter"
        }
    }
}

public struct StudyTrailEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let studyId: String
    public let kind: StudyTrailKind
    public let title: String
    public let detail: String
    public let bookId: Int?
    public let chapter: Int?
    public let verse: Int?
    public let refKey: String?
    public let durationSeconds: Int
    public let createdAt: String

    public var formattedDuration: String {
        let s = max(0, durationSeconds)
        if s < 5 { return "" }
        if s < 60 { return "\(s)s" }
        let mins = s / 60
        let remS = s % 60
        if mins < 60 { return remS > 0 ? "\(mins)m \(remS)s" : "\(mins)m" }
        let hrs = mins / 60
        let remM = mins % 60
        return remM > 0 ? "\(hrs)h \(remM)m" : "\(hrs)h"
    }
}

public struct StudyMarginLink: Identifiable, Hashable, Sendable {
    public let id: String
    public let studyId: String
    public var studyName: String
    public let bookId: Int
    public let chapter: Int
    public let verse: Int?
    public var noteText: String
    public var posX: Double
    public var posY: Double
    public let updatedAt: String
}

public enum ScriptureFontDesign: String, CaseIterable, Identifiable, Sendable {
    case serif = "Classic Serif"
    case sans = "Clean Sans"
    case rounded = "Soft Rounded"

    public var id: String { rawValue }

    public var fontDesign: Font.Design {
        switch self {
        case .serif: return .serif
        case .sans: return .default
        case .rounded: return .rounded
        }
    }
}

public struct CustomThemePalette: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var canvasHex: String
    public var textHex: String
    public var accentHex: String
    public var redLetterHex: String

    public init(id: String = UUID().uuidString, name: String, canvasHex: String, textHex: String, accentHex: String, redLetterHex: String) {
        self.id = id
        self.name = name
        self.canvasHex = canvasHex
        self.textHex = textHex
        self.accentHex = accentHex
        self.redLetterHex = redLetterHex
    }
}

public struct ReadingTheme: Identifiable, Hashable, Sendable {
    public let id: String
    public let rawValue: String
    public let canvasHex: String
    public let chromeHex: String
    public let panelHex: String
    public let primaryTextHex: String
    public let secondaryTextHex: String
    public let accentHex: String
    public let dividerHex: String
    public let redLetterHex: String
    public let isDark: Bool
    public let isCustom: Bool

    public static let paperSepia = ReadingTheme(
        id: "Paper", rawValue: "Paper",
        canvasHex: "#F7F2E6", chromeHex: "#F0E9DA", panelHex: "#F3EDDF",
        primaryTextHex: "#2D251C", secondaryTextHex: "#746655",
        accentHex: "#2E619E", dividerHex: "#D1C7B4", redLetterHex: "#9E2525",
        isDark: false, isCustom: false
    )

    public static let light = ReadingTheme(
        id: "Light", rawValue: "Light",
        canvasHex: "#FDFDFC", chromeHex: "#F5F5F6", panelHex: "#F8F8F9",
        primaryTextHex: "#1C1C1F", secondaryTextHex: "#6E6F74",
        accentHex: "#2469C2", dividerHex: "#D6D7DB", redLetterHex: "#B02121",
        isDark: false, isCustom: false
    )

    public static let agedParchment = ReadingTheme(
        id: "Parchment", rawValue: "Parchment",
        canvasHex: "#EFE6D0", chromeHex: "#E6DAC0", panelHex: "#EAE0C8",
        primaryTextHex: "#2A1F14", secondaryTextHex: "#6D5A44",
        accentHex: "#7C4D1E", dividerHex: "#C7B79A", redLetterHex: "#8F2222",
        isDark: false, isCustom: false
    )

    public static let sageStudy = ReadingTheme(
        id: "Sage", rawValue: "Sage",
        canvasHex: "#EEF3EC", chromeHex: "#E2EBE0", panelHex: "#E7EFE5",
        primaryTextHex: "#1D2820", secondaryTextHex: "#55685A",
        accentHex: "#2C6B54", dividerHex: "#C2D1C0", redLetterHex: "#9E2A2B",
        isDark: false, isCustom: false
    )

    public static let dark = ReadingTheme(
        id: "Dark", rawValue: "Dark",
        canvasHex: "#202123", chromeHex: "#18191B", panelHex: "#282A2D",
        primaryTextHex: "#F2EEE6", secondaryTextHex: "#A1A2A7",
        accentHex: "#88B3EB", dividerHex: "#48494B", redLetterHex: "#EB7474",
        isDark: true, isCustom: false
    )

    public static let midnightNavy = ReadingTheme(
        id: "Midnight", rawValue: "Midnight",
        canvasHex: "#121A26", chromeHex: "#0D131D", panelHex: "#182233",
        primaryTextHex: "#ECEFF4", secondaryTextHex: "#8FA0B8",
        accentHex: "#7DB0F2", dividerHex: "#2D3C54", redLetterHex: "#F07A7A",
        isDark: true, isCustom: false
    )

    public static let allCases: [ReadingTheme] = [
        .paperSepia, .light, .agedParchment, .sageStudy, .dark, .midnightNavy
    ]

    public init?(rawValue: String) {
        if let found = Self.allCases.first(where: { $0.rawValue == rawValue || $0.id == rawValue }) {
            self = found
            return
        }
        return nil
    }

    public init(
        id: String, rawValue: String,
        canvasHex: String, chromeHex: String, panelHex: String,
        primaryTextHex: String, secondaryTextHex: String,
        accentHex: String, dividerHex: String, redLetterHex: String,
        isDark: Bool, isCustom: Bool
    ) {
        self.id = id
        self.rawValue = rawValue
        self.canvasHex = canvasHex
        self.chromeHex = chromeHex
        self.panelHex = panelHex
        self.primaryTextHex = primaryTextHex
        self.secondaryTextHex = secondaryTextHex
        self.accentHex = accentHex
        self.dividerHex = dividerHex
        self.redLetterHex = redLetterHex
        self.isDark = isDark
        self.isCustom = isCustom
    }

    /// Builds a harmonious custom theme from 4 user-chosen colors, automatically computing chrome, panels, dividers, and light/dark mode.
    public static func fromCustom(_ p: CustomThemePalette) -> ReadingTheme {
        let baseUI = UIColor(hex: p.canvasHex) ?? UIColor(red: 0.969, green: 0.949, blue: 0.902, alpha: 1)
        let textUI = UIColor(hex: p.textHex) ?? UIColor(red: 0.176, green: 0.145, blue: 0.110, alpha: 1)
        let dark = baseUI.isDarkColor
        let chrome = baseUI.adjustedBrightness(by: dark ? -0.04 : -0.035)
        let panel = baseUI.adjustedBrightness(by: dark ? 0.045 : -0.02)
        let divider = baseUI.blended(with: textUI, fraction: dark ? 0.22 : 0.18)
        let secondary = textUI.blended(with: baseUI, fraction: 0.36)
        return ReadingTheme(
            id: "custom:\(p.id)",
            rawValue: p.name,
            canvasHex: p.canvasHex,
            chromeHex: chrome.toHexString(),
            panelHex: panel.toHexString(),
            primaryTextHex: p.textHex,
            secondaryTextHex: secondary.toHexString(),
            accentHex: p.accentHex,
            dividerHex: divider.toHexString(),
            redLetterHex: p.redLetterHex,
            isDark: dark,
            isCustom: true
        )
    }

    public var canvasBackground: Color { Color(uiColor: UIColor(hex: canvasHex) ?? .systemBackground) }
    public var chromeBackground: Color { Color(uiColor: UIColor(hex: chromeHex) ?? .secondarySystemBackground) }
    public var panelBackground: Color { Color(uiColor: UIColor(hex: panelHex) ?? .secondarySystemBackground) }
    public var primaryText: Color { Color(uiColor: UIColor(hex: primaryTextHex) ?? .label) }
    public var secondaryText: Color { Color(uiColor: UIColor(hex: secondaryTextHex) ?? .secondaryLabel) }
    public var accentBlue: Color { Color(uiColor: UIColor(hex: accentHex) ?? .systemBlue) }
    public var dividerColor: Color { Color(uiColor: UIColor(hex: dividerHex) ?? .separator) }
    public var redLetterColor: Color { Color(uiColor: UIColor(hex: redLetterHex) ?? .systemRed) }

    public var paperLineColor: Color {
        isDark ? Color.white.opacity(0.08) : dividerColor.opacity(0.45)
    }

    public var preferredColorScheme: ColorScheme {
        isDark ? .dark : .light
    }
}

public enum WorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case journaling = "Journaling"
    case bibleAndNotes = "Bible + Notes"
    case reading = "Reading"
    case study = "Study"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .journaling: return "rectangle.split.3x1"
        case .bibleAndNotes: return "rectangle.split.2x1"
        case .reading: return "book"
        case .study: return "text.book.closed"
        }
    }
}

public enum LeftPanelTab: String, CaseIterable, Identifiable, Sendable {
    case crossRefs = "TSK Cross-Refs"
    case strongs = "Interlinear"
    case dictionary = "Dictionaries"
    case commentary = "Commentaries"
    case places = "Places"
    case parallel = "Parallel Bible"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .crossRefs: return "arrow.triangle.branch"
        case .strongs: return "character.book.closed"
        case .dictionary: return "text.book.closed"
        case .commentary: return "text.quote"
        case .places: return "map"
        case .parallel: return "book.pages"
        }
    }
}

public enum ReferenceSourceFilter: String, CaseIterable, Identifiable, Sendable {
    case tsk = "TSK Cross-Refs"
    case personal = "Personal Notes"
    case all = "All References"
    case hidden = "Hide Panel"

    public var id: String { rawValue }
}

public enum JournalPaperStyle: String, CaseIterable, Identifiable, Sendable {
    case ruled = "Ruled Paper"
    case dotGrid = "Dot Grid"
    case plain = "Blank Paper"

    public var id: String { rawValue }
}

public enum WritingToolKind: String, CaseIterable, Identifiable, Sendable {
    case pen = "Pen"
    case pencil = "Pencil"
    case marker = "Marker"
    case highlighter = "Highlight"
    case eraserVector = "Erase Stroke"
    case eraserBitmap = "Erase Pixel"
    case lasso = "Lasso"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .highlighter: return "scribble.variable"
        case .eraserVector: return "eraser"
        case .eraserBitmap: return "eraser.line.dashed"
        case .lasso: return "lasso"
        }
    }
}

public struct InkColorPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let hex: String

    public static let defaults: [InkColorPreset] = [
        InkColorPreset(id: "ink", name: "Classic Ink", hex: "#2B241B"),
        InkColorPreset(id: "blue", name: "Study Blue", hex: "#3A78C2"),
        InkColorPreset(id: "sky", name: "Light Blue", hex: "#88B3EB"),
        InkColorPreset(id: "crimson", name: "Crimson", hex: "#B93B3B"),
        InkColorPreset(id: "forest", name: "Forest", hex: "#2F7D57"),
        InkColorPreset(id: "gold", name: "Gold", hex: "#C6A645"),
        InkColorPreset(id: "violet", name: "Violet", hex: "#7C52B5"),
    ]

    public var uiColor: UIColor {
        UIColor(hex: hex) ?? .label
    }

    public var swiftUIColor: Color {
        Color(uiColor: uiColor)
    }
}

public struct HighlightPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let hex: String

    public static let defaults: [HighlightPreset] = [
        HighlightPreset(id: "gold", name: "Promise", hex: "#C6A645"),
        HighlightPreset(id: "blue", name: "Grace", hex: "#5A96E3"),
        HighlightPreset(id: "green", name: "Growth", hex: "#5FA876"),
        HighlightPreset(id: "rose", name: "Redemption", hex: "#D66B7A"),
        HighlightPreset(id: "violet", name: "Prayer", hex: "#9B7AD6"),
    ]

    public var color: Color {
        Color(uiColor: UIColor(hex: hex) ?? .systemYellow)
    }
}

public extension UIColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    var isDarkColor: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.5
    }

    func adjustedBrightness(by delta: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(
            red: min(1, max(0, r + delta)),
            green: min(1, max(0, g + delta)),
            blue: min(1, max(0, b + delta)),
            alpha: a
        )
    }

    func blended(with other: UIColor, fraction: CGFloat) -> UIColor {
        let f = min(1, max(0, fraction))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 1
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 1
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * f,
            green: g1 + (g2 - g1) * f,
            blue: b1 + (b2 - b1) * f,
            alpha: 1.0
        )
    }

    func toHexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(min(1, max(0, r)) * 255))
        let gi = Int(round(min(1, max(0, g)) * 255))
        let bi = Int(round(min(1, max(0, b)) * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}
