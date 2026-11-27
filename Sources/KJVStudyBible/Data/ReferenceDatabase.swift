import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class ReferenceDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private var bookMap: [Int: Book] = [:]
    private var cachedBooks: [Book] = []

    public init() {
        let url = Self.locateDatabase()
        if let url {
            var handle: OpaquePointer?
            if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                self.db = handle
                self.cachedBooks = loadAllBooksUnlocked()
                for b in cachedBooks {
                    self.bookMap[b.id] = b
                }
            }
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public var isLoaded: Bool { db != nil }

    private static func locateDatabase() -> URL? {
        if let url = Bundle.module.url(forResource: "kjv_reference", withExtension: "sqlite") {
            return url
        }
        if let url = Bundle.module.url(forResource: "kjv_reference", withExtension: "sqlite", subdirectory: "Resources") {
            return url
        }
        if let url = Bundle.main.url(forResource: "kjv_reference", withExtension: "sqlite") {
            return url
        }
        return nil
    }

    public func allBooks() -> [Book] {
        lock.lock()
        defer { lock.unlock() }
        return cachedBooks
    }

    public func book(id: Int) -> Book? {
        lock.lock()
        defer { lock.unlock() }
        return bookMap[id]
    }

    private func loadAllBooksUnlocked() -> [Book] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, name, abbr, testament, chapter_count FROM books ORDER BY id"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [Book] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(stmt, 0))
            let name = Self.columnText(stmt, 1)
            let abbr = Self.columnText(stmt, 2)
            let testament = Self.columnText(stmt, 3)
            let chCount = Int(sqlite3_column_int(stmt, 4))
            result.append(Book(id: id, name: name, abbr: abbr, testament: testament, chapterCount: chCount))
        }
        return result
    }

    public func verses(bookId: Int, chapter: Int) -> [Verse] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, book_id, chapter, verse, text_plain, text_marked FROM verses WHERE book_id = ? AND chapter = ? ORDER BY verse"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        var result: [Verse] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(Verse(
                id: Int(sqlite3_column_int(stmt, 0)),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                chapter: Int(sqlite3_column_int(stmt, 2)),
                verse: Int(sqlite3_column_int(stmt, 3)),
                text: Self.columnText(stmt, 4),
                textMarked: Self.columnText(stmt, 5)
            ))
        }
        return result
    }

    public func verse(bookId: Int, chapter: Int, verse: Int) -> Verse? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT id, book_id, chapter, verse, text_plain, text_marked FROM verses WHERE book_id = ? AND chapter = ? AND verse = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        sqlite3_bind_int(stmt, 3, Int32(verse))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Verse(
            id: Int(sqlite3_column_int(stmt, 0)),
            bookId: Int(sqlite3_column_int(stmt, 1)),
            chapter: Int(sqlite3_column_int(stmt, 2)),
            verse: Int(sqlite3_column_int(stmt, 3)),
            text: Self.columnText(stmt, 4),
            textMarked: Self.columnText(stmt, 5)
        )
    }

    public func verses(bookId: Int, chapter: Int, startVerse: Int, endVerse: Int) -> [Verse] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let lo = max(1, min(startVerse, endVerse))
        let hi = max(startVerse, endVerse)
        let sql = "SELECT id, book_id, chapter, verse, text_plain, text_marked FROM verses WHERE book_id = ? AND chapter = ? AND verse BETWEEN ? AND ? ORDER BY verse"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        sqlite3_bind_int(stmt, 3, Int32(lo))
        sqlite3_bind_int(stmt, 4, Int32(hi))
        var result: [Verse] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(Verse(
                id: Int(sqlite3_column_int(stmt, 0)),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                chapter: Int(sqlite3_column_int(stmt, 2)),
                verse: Int(sqlite3_column_int(stmt, 3)),
                text: Self.columnText(stmt, 4),
                textMarked: Self.columnText(stmt, 5)
            ))
        }
        return result
    }

    public func interlinearWords(bookId: Int, chapter: Int, verse: Int) -> [InterlinearWord] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, word_pos, original_text, translit, gloss, strongs_id, morph
            FROM interlinear_words
            WHERE book_id = ? AND chapter = ? AND verse = ?
            ORDER BY word_pos
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        sqlite3_bind_int(stmt, 3, Int32(verse))
        var out: [InterlinearWord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(InterlinearWord(
                id: Int(sqlite3_column_int(stmt, 0)),
                wordPos: Int(sqlite3_column_int(stmt, 1)),
                originalText: Self.columnText(stmt, 2),
                translit: Self.columnText(stmt, 3),
                gloss: Self.columnText(stmt, 4),
                strongsId: Self.columnText(stmt, 5),
                morph: Self.columnText(stmt, 6)
            ))
        }
        return out
    }

    public func entriesForVerse(source: StudyDictionarySource, verse: Verse, limit: Int = 12) -> [StudyDictionaryEntry] {
        if source == .webster1828 {
            let keywords = Self.extractKeywords(from: verse.text, maxCount: 4)
            var out: [StudyDictionaryEntry] = []
            var seen = Set<String>()
            for kw in keywords {
                for entry in lookupWebster(word: kw).prefix(1) {
                    if seen.insert(entry.headwordNorm).inserted {
                        out.append(StudyDictionaryEntry(
                            id: "web-\(entry.id)",
                            source: .webster1828,
                            headword: entry.headword,
                            body: entry.definition
                        ))
                    }
                }
            }
            return out
        }

        let abbrs = Self.citationPatterns(for: verse.bookId, chapter: verse.chapter, verse: verse.verse)
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        var results: [StudyDictionaryEntry] = []
        var seen = Set<Int>()

        // 1. Entries directly citing this exact verse (e.g. "Joh 3:16", "John 3:16", "Ge 1:1")
        if !abbrs.isEmpty {
            let likeClauses = abbrs.map { _ in "body LIKE ?" }.joined(separator: " OR ")
            let sql = """
                SELECT id, headword, body FROM study_dictionaries
                WHERE source = ? AND (\(likeClauses))
                ORDER BY headword ASC
                LIMIT ?
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, source.dbKey, -1, SQLITE_TRANSIENT)
                for (idx, pat) in abbrs.enumerated() {
                    sqlite3_bind_text(stmt, Int32(2 + idx), "%\(pat)%", -1, SQLITE_TRANSIENT)
                }
                sqlite3_bind_int(stmt, Int32(2 + abbrs.count), Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let rowId = Int(sqlite3_column_int(stmt, 0))
                    if seen.insert(rowId).inserted {
                        results.append(StudyDictionaryEntry(
                            id: "\(source.dbKey)-\(rowId)",
                            source: source,
                            headword: Self.columnText(stmt, 1),
                            body: Self.columnText(stmt, 2)
                        ))
                    }
                }
            }
        }

        // 2. Also match key headwords from the verse (great for Easton's names/places like Nicodemus, Pharisees)
        if results.count < limit {
            let keywords = Self.extractKeywords(from: verse.text, maxCount: 6)
            for kw in keywords {
                if results.count >= limit { break }
                let norm = kw.lowercased().filter { $0.isLetter || $0.isNumber }
                guard norm.count >= 4 else { continue }
                var stmt: OpaquePointer?
                let sql = "SELECT id, headword, body FROM study_dictionaries WHERE source = ? AND headword_norm = ? LIMIT 2"
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    defer { sqlite3_finalize(stmt) }
                    sqlite3_bind_text(stmt, 1, source.dbKey, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, norm, -1, SQLITE_TRANSIENT)
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let rowId = Int(sqlite3_column_int(stmt, 0))
                        if seen.insert(rowId).inserted {
                            results.append(StudyDictionaryEntry(
                                id: "\(source.dbKey)-\(rowId)",
                                source: source,
                                headword: Self.columnText(stmt, 1),
                                body: Self.columnText(stmt, 2)
                            ))
                        }
                    }
                }
            }
        }

        return results
    }

    private static let stopWords: Set<String> = [
        "the", "and", "that", "have", "for", "not", "with", "you", "this", "but", "his", "from",
        "they", "she", "which", "will", "one", "all", "would", "there", "their", "what", "about",
        "when", "make", "like", "time", "just", "him", "know", "take", "into", "your", "some",
        "could", "them", "than", "then", "now", "look", "only", "come", "its", "over", "also",
        "unto", "thee", "thou", "thy", "ye", "hath", "shalt", "shall", "said", "saying", "came",
        "were", "was", "are", "been", "being", "who", "whom", "whose", "where", "thereof",
        "whosoever", "therefore", "behold", "verily", "neither", "upon", "before", "after", "these", "those"
    ]

    private static func extractKeywords(from text: String, maxCount: Int) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for raw in text.split(separator: " ") {
            let clean = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            let low = clean.lowercased()
            guard clean.count >= 4, !stopWords.contains(low), seen.insert(low).inserted else { continue }
            out.append(clean)
            if out.count >= maxCount { break }
        }
        return out
    }

    private static let bookCitationPrefixes: [Int: [String]] = [
        1: ["Gen", "Ge"], 2: ["Exod", "Ex"], 3: ["Lev", "Le"], 4: ["Num", "Nu"], 5: ["Deut", "De"],
        6: ["Josh", "Jos"], 7: ["Judg", "Jg"], 8: ["Ruth", "Ru"], 9: ["1Sam", "1Sa", "1 Sam"], 10: ["2Sam", "2Sa", "2 Sam"],
        11: ["1Kgs", "1Ki", "1 Kgs"], 12: ["2Kgs", "2Ki", "2 Kgs"], 13: ["1Chr", "1Ch", "1 Chr"], 14: ["2Chr", "2Ch", "2 Chr"],
        15: ["Ezra", "Ezr"], 16: ["Neh", "Ne"], 17: ["Esth", "Es"], 18: ["Job"], 19: ["Ps", "Psa"], 20: ["Prov", "Pr"],
        21: ["Eccl", "Ec"], 22: ["Song", "So"], 23: ["Isa", "Is"], 24: ["Jer", "Je"], 25: ["Lam", "La"],
        26: ["Ezek", "Eze"], 27: ["Dan", "Da"], 28: ["Hos", "Ho"], 29: ["Joel", "Joe"], 30: ["Amos", "Am"],
        31: ["Obad", "Ob"], 32: ["Jonah", "Jon"], 33: ["Mic", "Mi"], 34: ["Nah", "Na"], 35: ["Hab"],
        36: ["Zeph", "Zep"], 37: ["Hag"], 38: ["Zech", "Zec"], 39: ["Mal"],
        40: ["Matt", "Mt", "Mat"], 41: ["Mark", "Mr", "Mk"], 42: ["Luke", "Lu", "Lk"], 43: ["John", "Joh", "Jn"],
        44: ["Acts", "Ac"], 45: ["Rom", "Ro"], 46: ["1Cor", "1Co", "1 Cor"], 47: ["2Cor", "2Co", "2 Cor"],
        48: ["Gal", "Ga"], 49: ["Eph"], 50: ["Phil", "Php"], 51: ["Col"],
        52: ["1Thess", "1Th", "1 Thess"], 53: ["2Thess", "2Th", "2 Thess"], 54: ["1Tim", "1Ti", "1 Tim"], 55: ["2Tim", "2Ti", "2 Tim"],
        56: ["Titus", "Tit"], 57: ["Phlm", "Phm"], 58: ["Heb"], 59: ["Jas", "Jam"],
        60: ["1Pet", "1Pe", "1 Pet"], 61: ["2Pet", "2Pe", "2 Pet"], 62: ["1John", "1Jo", "1Jn", "1 John"],
        63: ["2John", "2Jo", "2Jn"], 64: ["3John", "3Jo", "3Jn"], 65: ["Jude", "Jud"], 66: ["Rev", "Re"]
    ]

    private static func citationPatterns(for bookId: Int, chapter: Int, verse: Int) -> [String] {
        let prefixes = bookCitationPrefixes[bookId] ?? []
        var pats: [String] = []
        for p in prefixes {
            pats.append("\(p) \(chapter):\(verse)")
            pats.append("\(p). \(chapter):\(verse)")
        }
        return pats
    }

    public func searchStudyDictionary(source: StudyDictionarySource, query raw: String, limit: Int = 12) -> [StudyDictionaryEntry] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if source == .webster1828 {
            return lookupWebster(word: trimmed).map {
                StudyDictionaryEntry(id: "web-\($0.id)", source: .webster1828, headword: $0.headword, body: $0.definition)
            }
        }

        let norm = trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        var results: [StudyDictionaryEntry] = []
        var seen = Set<Int>()

        // 1. Exact or prefix headword match first
        if !norm.isEmpty {
            var stmt: OpaquePointer?
            let sql = """
                SELECT id, headword, body FROM study_dictionaries
                WHERE source = ? AND (headword_norm = ? OR headword_norm LIKE ?)
                ORDER BY CASE WHEN headword_norm = ? THEN 0 ELSE 1 END, length(headword_norm)
                LIMIT ?
            """
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, source.dbKey, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, norm, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, "\(norm)%", -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, norm, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 5, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let rowId = Int(sqlite3_column_int(stmt, 0))
                    seen.insert(rowId)
                    results.append(StudyDictionaryEntry(
                        id: "\(source.dbKey)-\(rowId)",
                        source: source,
                        headword: Self.columnText(stmt, 1),
                        body: Self.columnText(stmt, 2)
                    ))
                }
            }
        }

        // 2. FTS5 full-text fallback if fewer than limit
        if results.count < limit {
            let tokens = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            if !tokens.isEmpty {
                let ftsQuery = tokens.map { "\"\($0)\"" }.joined(separator: " ")
                var stmt: OpaquePointer?
                let sql = """
                    SELECT d.id, d.headword, d.body
                    FROM study_dictionaries_fts f
                    JOIN study_dictionaries d ON d.id = f.rowid
                    WHERE study_dictionaries_fts MATCH ? AND d.source = ?
                    LIMIT ?
                """
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    defer { sqlite3_finalize(stmt) }
                    sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, source.dbKey, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(stmt, 3, Int32(limit))
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let rowId = Int(sqlite3_column_int(stmt, 0))
                        if seen.insert(rowId).inserted {
                            results.append(StudyDictionaryEntry(
                                id: "\(source.dbKey)-\(rowId)",
                                source: source,
                                headword: Self.columnText(stmt, 1),
                                body: Self.columnText(stmt, 2)
                            ))
                        }
                    }
                }
            }
        }

        return results
    }

    public func verseCount(bookId: Int, chapter: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM verses WHERE book_id = ? AND chapter = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    public func crossReferences(bookId: Int, chapter: Int) -> [Int: [CrossReference]] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [:] }
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, from_book, from_chapter, from_verse, phrase, to_book, to_chapter, to_verse_start, to_verse_end
            FROM tsk_cross_refs
            WHERE from_book = ? AND from_chapter = ?
            ORDER BY from_verse, sort_order
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        var grouped: [Int: [CrossReference]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let fromVerse = Int(sqlite3_column_int(stmt, 3))
            let toBook = Int(sqlite3_column_int(stmt, 5))
            let targetBook = bookMap[toBook]
            let ref = CrossReference(
                id: Int(sqlite3_column_int(stmt, 0)),
                fromBook: Int(sqlite3_column_int(stmt, 1)),
                fromChapter: Int(sqlite3_column_int(stmt, 2)),
                fromVerse: fromVerse,
                phrase: Self.columnText(stmt, 4),
                toBook: toBook,
                toChapter: Int(sqlite3_column_int(stmt, 6)),
                toVerseStart: Int(sqlite3_column_int(stmt, 7)),
                toVerseEnd: Int(sqlite3_column_int(stmt, 8)),
                toBookAbbr: targetBook?.abbr ?? "Book \(toBook)",
                toBookName: targetBook?.name ?? "Book \(toBook)"
            )
            grouped[fromVerse, default: []].append(ref)
        }
        return grouped
    }

    public func parseDirectPassageRange(_ raw: String) -> (bookId: Int, chapter: Int, startVerse: Int?, endVerse: Int?)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pattern = #"^([1-3]?\s*[A-Za-z][A-Za-z\s\.]+?)\s+(\d+)(?::(\d+)(?:\s*[-–]\s*(\d+))?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let bookRange = Range(match.range(at: 1), in: trimmed),
              let chRange = Range(match.range(at: 2), in: trimmed),
              let chapter = Int(trimmed[chRange]) else { return nil }

        let bookToken = trimmed[bookRange].replacingOccurrences(of: ".", with: "").lowercased().trimmingCharacters(in: .whitespaces)
        let compactToken = bookToken.replacingOccurrences(of: " ", with: "")
        let startV: Int? = Range(match.range(at: 3), in: trimmed).flatMap { Int(trimmed[$0]) }
        let endV: Int? = Range(match.range(at: 4), in: trimmed).flatMap { Int(trimmed[$0]) } ?? startV

        let books = allBooks()
        if let matched = books.first(where: {
            $0.name.lowercased() == bookToken ||
            $0.abbr.lowercased() == compactToken ||
            $0.name.lowercased().replacingOccurrences(of: " ", with: "") == compactToken ||
            $0.name.lowercased().hasPrefix(bookToken)
        }) {
            let clampedCh = max(1, min(chapter, matched.chapterCount))
            return (matched.id, clampedCh, startV, endV)
        }
        return nil
    }

    public func parseDirectReference(_ raw: String) -> VerseRef? {
        guard let parsed = parseDirectPassageRange(raw) else { return nil }
        return VerseRef(bookId: parsed.bookId, chapter: parsed.chapter, verse: parsed.startVerse)
    }

    public func searchScripture(query: String, scopeBookId: Int? = nil, limit: Int = 80) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let direct = parseDirectPassageRange(trimmed) {
            let bName = book(id: direct.bookId)?.name ?? "Book \(direct.bookId)"
            if let sv = direct.startVerse {
                let ev = direct.endVerse ?? sv
                let rangeVerses = verses(bookId: direct.bookId, chapter: direct.chapter, startVerse: sv, endVerse: ev)
                return rangeVerses.map {
                    SearchResult(id: $0.id, bookId: $0.bookId, bookName: bName, chapter: $0.chapter, verse: $0.verse, text: $0.text)
                }
            } else {
                let vs = verses(bookId: direct.bookId, chapter: direct.chapter)
                return vs.map {
                    SearchResult(id: $0.id, bookId: $0.bookId, bookName: bName, chapter: $0.chapter, verse: $0.verse, text: $0.text)
                }
            }
        }

        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        let safeQuery: String
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            safeQuery = trimmed
        } else {
            let tokens = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            guard !tokens.isEmpty else { return [] }
            safeQuery = tokens.map { "\"\($0)\"" }.joined(separator: " ")
        }

        let sql: String
        if scopeBookId != nil {
            sql = """
                SELECT v.id, v.book_id, b.name, v.chapter, v.verse, v.text_plain
                FROM verses_fts f
                JOIN verses v ON v.id = f.rowid
                JOIN books b ON b.id = v.book_id
                WHERE verses_fts MATCH ? AND v.book_id = ?
                ORDER BY v.id
                LIMIT ?
            """
        } else {
            sql = """
                SELECT v.id, v.book_id, b.name, v.chapter, v.verse, v.text_plain
                FROM verses_fts f
                JOIN verses v ON v.id = f.rowid
                JOIN books b ON b.id = v.book_id
                WHERE verses_fts MATCH ?
                ORDER BY v.id
                LIMIT ?
            """
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, safeQuery, -1, SQLITE_TRANSIENT)
        if let scopeBookId {
            sqlite3_bind_int(stmt, 2, Int32(scopeBookId))
            sqlite3_bind_int(stmt, 3, Int32(limit))
        } else {
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }
        var results: [SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(SearchResult(
                id: Int(sqlite3_column_int(stmt, 0)),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                bookName: Self.columnText(stmt, 2),
                chapter: Int(sqlite3_column_int(stmt, 3)),
                verse: Int(sqlite3_column_int(stmt, 4)),
                text: Self.columnText(stmt, 5)
            ))
        }
        return results
    }

    public func lookupStrongs(id raw: String) -> StrongsEntry? {
        let sid = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !sid.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT strongs_id, testament, lemma, translit, pronunciation, derivation, definition, kjv_usage FROM strongs_lexicon WHERE strongs_id = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sid, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Self.readStrongsRow(stmt)
    }

    public func versesForStrongs(strongsId raw: String, limit: Int = 30) -> [SearchResult] {
        let sid = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !sid.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = """
            SELECT DISTINCT v.id, v.book_id, b.name, v.chapter, v.verse, v.text_plain
            FROM interlinear_words w
            JOIN verses v ON v.book_id = w.book_id AND v.chapter = w.chapter AND v.verse = w.verse
            JOIN books b ON b.id = v.book_id
            WHERE w.strongs_id = ?
            ORDER BY v.id
            LIMIT ?
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sid, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var out: [SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(SearchResult(
                id: Int(sqlite3_column_int(stmt, 0)),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                bookName: Self.columnText(stmt, 2),
                chapter: Int(sqlite3_column_int(stmt, 3)),
                verse: Int(sqlite3_column_int(stmt, 4)),
                text: Self.columnText(stmt, 5)
            ))
        }
        return out
    }

    private static let dictBookAliases: [String: Int] = [
        "gen": 1, "ge": 1, "gn": 1, "genesis": 1,
        "exod": 2, "exo": 2, "ex": 2, "exodus": 2,
        "lev": 3, "le": 3, "lv": 3, "leviticus": 3,
        "num": 4, "nu": 4, "nm": 4, "numbers": 4,
        "deut": 5, "deu": 5, "dt": 5, "deuteronomy": 5,
        "josh": 6, "jos": 6, "joshua": 6,
        "judg": 7, "jdg": 7, "judges": 7,
        "ruth": 8, "ru": 8,
        "1sam": 9, "1sa": 9, "1sm": 9, "1samuel": 9,
        "2sam": 10, "2sa": 10, "2sm": 10, "2samuel": 10,
        "1kgs": 11, "1ki": 11, "1kings": 11,
        "2kgs": 12, "2ki": 12, "2kings": 12,
        "1chr": 13, "1ch": 13, "1chronicles": 13,
        "2chr": 14, "2ch": 14, "2chronicles": 14,
        "ezra": 15, "ezr": 15,
        "neh": 16, "ne": 16, "nehemiah": 16,
        "esth": 17, "est": 17, "esther": 17,
        "job": 18,
        "ps": 19, "psa": 19, "pss": 19, "psalm": 19, "psalms": 19,
        "prov": 20, "pro": 20, "pr": 20, "proverbs": 20,
        "eccl": 21, "ecc": 21, "ec": 21, "ecclesiastes": 21,
        "song": 22, "sng": 22, "sos": 22, "cant": 22,
        "isa": 23, "is": 23, "isaiah": 23,
        "jer": 24, "je": 24, "jeremiah": 24,
        "lam": 25, "la": 25, "lamentations": 25,
        "ezek": 26, "ezk": 26, "eze": 26, "ezekiel": 26,
        "dan": 27, "da": 27, "daniel": 27,
        "hos": 28, "ho": 28, "hosea": 28,
        "joel": 29, "jol": 29,
        "amos": 30, "amo": 30, "am": 30,
        "obad": 31, "oba": 31, "ob": 31, "obadiah": 31,
        "jonah": 32, "jon": 32,
        "mic": 33, "mi": 33, "micah": 33,
        "nah": 34, "na": 34, "nahum": 34,
        "hab": 35, "habakkuk": 35,
        "zeph": 36, "zep": 36, "zephaniah": 36,
        "hag": 37, "haggai": 37,
        "zech": 38, "zec": 38, "zechariah": 38,
        "mal": 39, "malachi": 39,
        "matt": 40, "mat": 40, "mt": 40, "matthew": 40,
        "mark": 41, "mrk": 41, "mk": 41, "mr": 41,
        "luke": 42, "luk": 42, "lk": 42, "lu": 42,
        "john": 43, "jhn": 43, "joh": 43, "jn": 43,
        "acts": 44, "act": 44, "ac": 44,
        "rom": 45, "ro": 45, "rm": 45, "romans": 45,
        "1cor": 46, "1co": 46, "1corinthians": 46,
        "2cor": 47, "2co": 47, "2corinthians": 47,
        "gal": 48, "ga": 48, "galatians": 48,
        "eph": 49, "ephesians": 49,
        "phil": 50, "php": 50, "philippians": 50,
        "col": 51, "colossians": 51,
        "1thess": 52, "1th": 52, "1thessalonians": 52,
        "2thess": 53, "2th": 53, "2thessalonians": 53,
        "1tim": 54, "1ti": 54, "1timothy": 54,
        "2tim": 55, "2ti": 55, "2timothy": 55,
        "titus": 56, "tit": 56,
        "phlm": 57, "phm": 57, "philemon": 57,
        "heb": 58, "hebrews": 58,
        "jas": 59, "jam": 59, "james": 59,
        "1pet": 60, "1pe": 60, "1pt": 60, "1peter": 60,
        "2pet": 61, "2pe": 61, "2pt": 61, "2peter": 61,
        "1john": 62, "1jn": 62, "1jo": 62,
        "2john": 63, "2jn": 63, "2jo": 63,
        "3john": 64, "3jn": 64, "3jo": 64,
        "jude": 65, "jud": 65,
        "rev": 66, "re": 66, "revelation": 66,
    ]

    public func extractReferences(from text: String, limit: Int = 20) -> [CrossReference] {
        let pattern = #"\b([1-3]?\s?[A-Za-z]{2,14})\.?\s+(\d{1,3}):(\d{1,3})(?:[-–](\d{1,3}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var out: [CrossReference] = []
        var seen = Set<String>()
        for (idx, m) in matches.enumerated() {
            guard let bRange = Range(m.range(at: 1), in: text),
                  let cRange = Range(m.range(at: 2), in: text),
                  let vRange = Range(m.range(at: 3), in: text),
                  let ch = Int(text[cRange]),
                  let vs = Int(text[vRange]) else { continue }
            let rawBook = text[bRange].replacingOccurrences(of: " ", with: "").lowercased()
            guard let bookId = Self.dictBookAliases[rawBook],
                  let book = book(id: bookId),
                  ch >= 1 && ch <= book.chapterCount else { continue }
            let ve = Range(m.range(at: 4), in: text).flatMap { Int(text[$0]) } ?? vs
            let key = "\(bookId):\(ch):\(vs)-\(ve)"
            if seen.insert(key).inserted {
                out.append(CrossReference(
                    id: 900_000 + idx,
                    fromBook: bookId,
                    fromChapter: ch,
                    fromVerse: vs,
                    phrase: "Dictionary Reference",
                    toBook: bookId,
                    toChapter: ch,
                    toVerseStart: vs,
                    toVerseEnd: max(vs, ve),
                    toBookAbbr: book.abbr,
                    toBookName: book.name
                ))
                if out.count >= limit { break }
            }
        }
        return out
    }

    public func searchStrongs(word raw: String, testament: String? = nil, limit: Int = 8) -> [StrongsEntry] {
        let cleaned = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard !cleaned.isEmpty else { return [] }
        if (cleaned.first == "G" || cleaned.first == "g" || cleaned.first == "H" || cleaned.first == "h"),
           cleaned.dropFirst().allSatisfy({ $0.isNumber }),
           let exact = lookupStrongs(id: cleaned) {
            return [exact]
        }

        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let sql: String
        if testament != nil {
            sql = """
                SELECT s.strongs_id, s.testament, s.lemma, s.translit, s.pronunciation, s.derivation, s.definition, s.kjv_usage
                FROM strongs_fts f
                JOIN strongs_lexicon s ON s.rowid = f.rowid
                WHERE strongs_fts MATCH ? AND s.testament = ?
                LIMIT ?
            """
        } else {
            sql = """
                SELECT s.strongs_id, s.testament, s.lemma, s.translit, s.pronunciation, s.derivation, s.definition, s.kjv_usage
                FROM strongs_fts f
                JOIN strongs_lexicon s ON s.rowid = f.rowid
                WHERE strongs_fts MATCH ?
                LIMIT ?
            """
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let q = "\"\(cleaned.lowercased())\""
        sqlite3_bind_text(stmt, 1, q, -1, SQLITE_TRANSIENT)
        if let testament {
            sqlite3_bind_text(stmt, 2, testament, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(limit))
        } else {
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }
        var out: [StrongsEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Self.readStrongsRow(stmt))
        }
        return out
    }

    public func lookupWebster(word raw: String) -> [WebsterEntry] {
        let norm = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !norm.isEmpty else { return [] }
        let candidates = Self.stemCandidates(for: norm)
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        for cand in candidates {
            var stmt: OpaquePointer?
            let sql = "SELECT id, headword, headword_norm, definition FROM webster_1828 WHERE headword_norm = ? LIMIT 4"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, cand, -1, SQLITE_TRANSIENT)
                var hits: [WebsterEntry] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    hits.append(WebsterEntry(
                        id: Int(sqlite3_column_int(stmt, 0)),
                        headword: Self.columnText(stmt, 1),
                        headwordNorm: Self.columnText(stmt, 2),
                        definition: Self.columnText(stmt, 3)
                    ))
                }
                if !hits.isEmpty { return hits }
            }
        }
        return []
    }

    // MARK: - Biblical Geography & Places

    public func placesForChapter(bookId: Int, chapter: Int) -> [BiblicalPlace] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = """
            SELECT DISTINCT p.id, p.name, p.place_type, p.modern_name, p.description, p.lat, p.lon, p.verse_count
            FROM place_verses pv
            JOIN biblical_places p ON p.id = pv.place_id
            WHERE pv.book_id = ? AND pv.chapter = ?
            ORDER BY p.verse_count DESC, p.name ASC
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        return Self.readPlaceRows(stmt)
    }

    public func placesForVerse(bookId: Int, chapter: Int, verse: Int) -> [BiblicalPlace] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = """
            SELECT DISTINCT p.id, p.name, p.place_type, p.modern_name, p.description, p.lat, p.lon, p.verse_count
            FROM place_verses pv
            JOIN biblical_places p ON p.id = pv.place_id
            WHERE pv.book_id = ? AND pv.chapter = ? AND pv.verse = ?
            ORDER BY p.verse_count DESC, p.name ASC
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        sqlite3_bind_int(stmt, 3, Int32(verse))
        return Self.readPlaceRows(stmt)
    }

    public func searchPlaces(query raw: String, limit: Int = 40) -> [BiblicalPlace] {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let norm = q.lowercased().filter { $0.isLetter || $0.isNumber }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, name, place_type, modern_name, description, lat, lon, verse_count
            FROM biblical_places
            WHERE name_norm LIKE ? OR modern_name LIKE ? OR description LIKE ?
            ORDER BY CASE WHEN name_norm = ? THEN 0 WHEN name_norm LIKE ? THEN 1 ELSE 2 END, verse_count DESC, name ASC
            LIMIT ?
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let containsNorm = "%\(norm)%"
        let prefixNorm = "\(norm)%"
        let containsRaw = "%\(q)%"
        sqlite3_bind_text(stmt, 1, containsNorm, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, containsRaw, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, containsRaw, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, norm, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, prefixNorm, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 6, Int32(limit))
        return Self.readPlaceRows(stmt)
    }

    public func versesForPlace(placeId: String, limit: Int = 30) -> [SearchResult] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = """
            SELECT v.id, v.book_id, b.name, v.chapter, v.verse, v.text_plain
            FROM place_verses pv
            JOIN verses v ON v.book_id = pv.book_id AND v.chapter = pv.chapter AND v.verse = pv.verse
            JOIN books b ON b.id = v.book_id
            WHERE pv.place_id = ?
            ORDER BY v.id
            LIMIT ?
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, placeId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var out: [SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(SearchResult(
                id: Int(sqlite3_column_int(stmt, 0)),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                bookName: Self.columnText(stmt, 2),
                chapter: Int(sqlite3_column_int(stmt, 3)),
                verse: Int(sqlite3_column_int(stmt, 4)),
                text: Self.columnText(stmt, 5)
            ))
        }
        return out
    }

    private static func readPlaceRows(_ stmt: OpaquePointer?) -> [BiblicalPlace] {
        var out: [BiblicalPlace] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(BiblicalPlace(
                id: columnText(stmt, 0),
                name: columnText(stmt, 1),
                placeType: columnText(stmt, 2),
                modernName: columnText(stmt, 3),
                description: columnText(stmt, 4),
                lat: sqlite3_column_double(stmt, 5),
                lon: sqlite3_column_double(stmt, 6),
                verseCount: Int(sqlite3_column_int(stmt, 7))
            ))
        }
        return out
    }

    private static func stemCandidates(for word: String) -> [String] {
        var list = [word]
        for suffix in ["eth", "est", "ing", "ed", "es", "s", "ly"] {
            if word.hasSuffix(suffix) && word.count > suffix.count + 2 {
                let stem = String(word.dropLast(suffix.count))
                list.append(stem)
                list.append(stem + "e")
            }
        }
        return list
    }

    private static func readStrongsRow(_ stmt: OpaquePointer?) -> StrongsEntry {
        StrongsEntry(
            strongsId: columnText(stmt, 0),
            testament: columnText(stmt, 1),
            lemma: columnText(stmt, 2),
            translit: columnText(stmt, 3),
            pronunciation: columnText(stmt, 4),
            derivation: columnText(stmt, 5),
            definition: columnText(stmt, 6),
            kjvUsage: columnText(stmt, 7)
        )
    }

    private static func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cstr)
    }
}
