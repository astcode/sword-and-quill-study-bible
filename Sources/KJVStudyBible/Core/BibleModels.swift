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
    public let drawingData: Data?
    public let bookId: Int?
    public let chapter: Int?
    public let verse: Int?
    public let updatedAt: String

    public init(id: String, noteType: NoteType, title: String, body: String, drawingData: Data? = nil, bookId: Int?, chapter: Int?, verse: Int?, updatedAt: String) {
        self.id = id
        self.noteType = noteType
        self.title = title
        self.body = body
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
    public let kind: String // "Note", "Clip", "Bookmark"
    public let title: String
    public let snippet: String
    public let bookId: Int?
    public let chapter: Int?
    public let verse: Int?
    public let noteId: String?
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

public enum ReadingTheme: String, CaseIterable, Identifiable, Sendable {
    case paperSepia = "Paper"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }

    public var canvasBackground: Color {
        switch self {
        case .paperSepia: return Color(red: 0.969, green: 0.949, blue: 0.902)
        case .light: return Color(red: 0.992, green: 0.992, blue: 0.988)
        case .dark: return Color(red: 0.125, green: 0.129, blue: 0.137)
        }
    }

    public var chromeBackground: Color {
        switch self {
        case .paperSepia: return Color(red: 0.941, green: 0.914, blue: 0.855)
        case .light: return Color(red: 0.960, green: 0.960, blue: 0.965)
        case .dark: return Color(red: 0.095, green: 0.098, blue: 0.106)
        }
    }

    public var panelBackground: Color {
        switch self {
        case .paperSepia: return Color(red: 0.953, green: 0.929, blue: 0.875)
        case .light: return Color(red: 0.972, green: 0.972, blue: 0.976)
        case .dark: return Color(red: 0.157, green: 0.165, blue: 0.176)
        }
    }

    public var primaryText: Color {
        switch self {
        case .paperSepia: return Color(red: 0.176, green: 0.145, blue: 0.110)
        case .light: return Color(red: 0.110, green: 0.110, blue: 0.120)
        case .dark: return Color(red: 0.949, green: 0.933, blue: 0.902)
        }
    }

    public var secondaryText: Color {
        switch self {
        case .paperSepia: return Color(red: 0.455, green: 0.400, blue: 0.335)
        case .light: return Color(red: 0.430, green: 0.435, blue: 0.455)
        case .dark: return Color(red: 0.630, green: 0.635, blue: 0.655)
        }
    }

    public var accentBlue: Color {
        switch self {
        case .paperSepia: return Color(red: 0.180, green: 0.380, blue: 0.620)
        case .light: return Color(red: 0.140, green: 0.410, blue: 0.760)
        case .dark: return Color(red: 0.533, green: 0.702, blue: 0.922)
        }
    }

    public var dividerColor: Color {
        switch self {
        case .paperSepia: return Color(red: 0.820, green: 0.780, blue: 0.705)
        case .light: return Color(red: 0.840, green: 0.845, blue: 0.860)
        case .dark: return Color(red: 0.282, green: 0.286, blue: 0.294)
        }
    }

    public var paperLineColor: Color {
        switch self {
        case .paperSepia: return Color(red: 0.80, green: 0.75, blue: 0.66).opacity(0.45)
        case .light: return Color.gray.opacity(0.20)
        case .dark: return Color.white.opacity(0.08)
        }
    }

    public var redLetterColor: Color {
        switch self {
        case .paperSepia: return Color(red: 0.620, green: 0.145, blue: 0.145)
        case .light: return Color(red: 0.690, green: 0.130, blue: 0.130)
        case .dark: return Color(red: 0.920, green: 0.455, blue: 0.455)
        }
    }

    public var preferredColorScheme: ColorScheme {
        self == .dark ? .dark : .light
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
    case places = "Places"
    case parallel = "Parallel Bible"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .crossRefs: return "arrow.triangle.branch"
        case .strongs: return "character.book.closed"
        case .dictionary: return "text.book.closed"
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
}
