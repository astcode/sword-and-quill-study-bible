import Foundation

public enum ScriptureSearchMode: String, CaseIterable, Identifiable, Sendable {
    case exact = "Exact"
    case wordStartsWith = "Word Forms"
    case contains = "Contains"
    case meaning = "Meaning"

    public var id: String { rawValue }
}

public final class ReferenceDatabase: @unchecked Sendable {
    private var db: MagQLite?
    private let lock = NSLock()
    private var bookMap: [Int: Book] = [:]
    private var cachedBooks: [Book] = []

    public init() {
        if let path = Self.locateOrStageDatabase() {
            let cfg = MagQLiteConfig(
                durability: "off",
                pagedStorage: true,
                bufferPoolPages: 512,
                autoCheckpointFrames: 0
            )
            if let opened = try? MagQLite(path: path, config: cfg) {
                self.db = opened
                self.cachedBooks = loadAllBooksUnlocked()
                for b in cachedBooks {
                    self.bookMap[b.id] = b
                }
            }
        }
    }

    deinit {
        db?.close()
    }

    public var isLoaded: Bool { db != nil }

    private static func bcKey(_ bookId: Int, _ chapter: Int) -> Int64 {
        Int64(bookId * 1000 + chapter)
    }

    private static func bcvKey(_ bookId: Int, _ chapter: Int, _ verse: Int) -> Int64 {
        Int64(bookId * 1_000_000 + chapter * 1000 + verse)
    }

    private static func locateBundledMql() -> URL? {
        if let url = Bundle.module.url(forResource: "kjv_reference", withExtension: "mql") {
            return url
        }
        if let url = Bundle.module.url(forResource: "kjv_reference", withExtension: "mql", subdirectory: "Resources") {
            return url
        }
        if let url = Bundle.main.url(forResource: "kjv_reference", withExtension: "mql") {
            return url
        }
        return nil
    }

    /// Ensures `kjv_reference.mql` and `kjv_reference.mql.pages` are staged in writable Application Support
    /// (since iOS app bundles are read-only and MagQLite may open `.pages` / `.lock` read-write).
    private static func locateOrStageDatabase() -> String? {
        guard let bundleMql = locateBundledMql() else { return nil }
        let bundlePages = URL(fileURLWithPath: bundleMql.path + ".pages")

        let fm = FileManager.default
        guard let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return bundleMql.path
        }
        let dir = appSup.appendingPathComponent("KJVStudyBible/MagQLiteRef", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let dstMql = dir.appendingPathComponent("kjv_reference.mql")
        let dstPages = dir.appendingPathComponent("kjv_reference.mql.pages")

        let srcPagesSize = (try? fm.attributesOfItem(atPath: bundlePages.path)[.size] as? NSNumber)?.int64Value ?? -1
        let dstPagesSize = (try? fm.attributesOfItem(atPath: dstPages.path)[.size] as? NSNumber)?.int64Value ?? -2

        if !fm.fileExists(atPath: dstMql.path) || srcPagesSize != dstPagesSize {
            try? fm.removeItem(at: dstMql)
            try? fm.removeItem(at: dstPages)
            try? fm.removeItem(atPath: dstMql.path + ".wal")
            try? fm.removeItem(atPath: dstMql.path + ".lock")
            try? fm.copyItem(at: bundleMql, to: dstMql)
            if fm.fileExists(atPath: bundlePages.path) {
                try? fm.copyItem(at: bundlePages, to: dstPages)
            }
        }
        return dstMql.path
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
        let sql = "SELECT id, name, abbr, testament, chapter_count FROM books ORDER BY id;"
        guard let res = try? db.query(sql) else { return [] }
        return res.rows.map { row in
            Book(
                id: Int(row.int(at: 0) ?? 0),
                name: row.string(at: 1) ?? "",
                abbr: row.string(at: 2) ?? "",
                testament: row.string(at: 3) ?? "",
                chapterCount: Int(row.int(at: 4) ?? 0)
            )
        }
    }

    public func verses(bookId: Int, chapter: Int) -> [Verse] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let sql = "SELECT id, book_id, chapter, verse, text_plain, text_marked FROM verses WHERE bc_key = ? ORDER BY verse;"
        guard let res = try? db.queryParams(sql, params: [.int(Self.bcKey(bookId, chapter))]) else { return [] }
        return res.rows.map(Self.readVerseRow)
    }

    public func verse(bookId: Int, chapter: Int, verse: Int) -> Verse? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        let sql = "SELECT id, book_id, chapter, verse, text_plain, text_marked FROM verses WHERE bcv_key = ? LIMIT 1;"
        guard let res = try? db.queryParams(sql, params: [.int(Self.bcvKey(bookId, chapter, verse))]),
              let row = res.rows.first else { return nil }
        return Self.readVerseRow(row)
    }

    public func verses(bookId: Int, chapter: Int, startVerse: Int, endVerse: Int) -> [Verse] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let lo = max(1, min(startVerse, endVerse))
        let hi = max(startVerse, endVerse)
        let sql = "SELECT id, book_id, chapter, verse, text_plain, text_marked FROM verses WHERE bc_key = ? AND verse >= ? AND verse <= ? ORDER BY verse;"
        guard let res = try? db.queryParams(sql, params: [
            .int(Self.bcKey(bookId, chapter)),
            .int(Int64(lo)),
            .int(Int64(hi))
        ]) else { return [] }
        return res.rows.map(Self.readVerseRow)
    }

    public func interlinearWords(bookId: Int, chapter: Int, verse: Int) -> [InterlinearWord] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let sql = """
            SELECT id, word_pos, original_text, translit, gloss, strongs_id, morph
            FROM interlinear_words
            WHERE bcv_key = ?
            ORDER BY word_pos;
        """
        guard let res = try? db.queryParams(sql, params: [.int(Self.bcvKey(bookId, chapter, verse))]) else { return [] }
        return res.rows.map { row in
            InterlinearWord(
                id: Int(row.int(at: 0) ?? 0),
                wordPos: Int(row.int(at: 1) ?? 0),
                originalText: row.string(at: 2) ?? "",
                translit: row.string(at: 3) ?? "",
                gloss: row.string(at: 4) ?? "",
                strongsId: row.string(at: 5) ?? "",
                morph: row.string(at: 6) ?? ""
            )
        }
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

        let safeLimit = max(1, min(limit, 500))
        if !abbrs.isEmpty {
            let likeClauses = abbrs.map { _ in "body LIKE ?" }.joined(separator: " OR ")
            let sql = """
                SELECT id, headword, body FROM study_dictionaries
                WHERE source = ? AND (\(likeClauses))
                ORDER BY headword ASC
                LIMIT \(safeLimit);
            """
            var params: [MagQLiteParam] = [.string(source.dbKey)]
            for pat in abbrs {
                params.append(.string("%\(pat)%"))
            }
            if let res = try? db.queryParams(sql, params: params) {
                for row in res.rows {
                    let rowId = Int(row.int(at: 0) ?? 0)
                    if seen.insert(rowId).inserted {
                        results.append(StudyDictionaryEntry(
                            id: "\(source.dbKey)-\(rowId)",
                            source: source,
                            headword: row.string(at: 1) ?? "",
                            body: row.string(at: 2) ?? ""
                        ))
                    }
                }
            }
        }

        if results.count < limit {
            let keywords = Self.extractKeywords(from: verse.text, maxCount: 6)
            for kw in keywords {
                if results.count >= limit { break }
                let norm = kw.lowercased().filter { $0.isLetter || $0.isNumber }
                guard norm.count >= 4 else { continue }
                let sql = "SELECT id, headword, body FROM study_dictionaries WHERE headword_norm = ? AND source = ? LIMIT 2;"
                if let res = try? db.queryParams(sql, params: [.string(norm), .string(source.dbKey)]) {
                    for row in res.rows {
                        let rowId = Int(row.int(at: 0) ?? 0)
                        if seen.insert(rowId).inserted {
                            results.append(StudyDictionaryEntry(
                                id: "\(source.dbKey)-\(rowId)",
                                source: source,
                                headword: row.string(at: 1) ?? "",
                                body: row.string(at: 2) ?? ""
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

        let safeLimit = max(1, min(limit, 500))
        // 1. Exact or prefix headword match first
        if !norm.isEmpty {
            let sql = """
                SELECT id, headword, body FROM study_dictionaries
                WHERE source = ? AND (headword_norm = ? OR headword_norm LIKE ?)
                ORDER BY CASE WHEN headword_norm = ? THEN 0 ELSE 1 END, LENGTH(headword_norm)
                LIMIT \(safeLimit);
            """
            if let res = try? db.queryParams(sql, params: [
                .string(source.dbKey),
                .string(norm),
                .string("\(norm)%"),
                .string(norm)
            ]) {
                for row in res.rows {
                    let rowId = Int(row.int(at: 0) ?? 0)
                    seen.insert(rowId)
                    results.append(StudyDictionaryEntry(
                        id: "\(source.dbKey)-\(rowId)",
                        source: source,
                        headword: row.string(at: 1) ?? "",
                        body: row.string(at: 2) ?? ""
                    ))
                }
            }
        }

        // 2. MagQLite BM25 / FTS_MATCH fallback if fewer than limit
        if results.count < limit {
            let tokens = trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            if !tokens.isEmpty {
                let ftsQuery = tokens.joined(separator: " ")
                let sql = """
                    SELECT id, headword, body, BM25(body, ?) AS score
                    FROM study_dictionaries
                    WHERE source = ? AND (FTS_MATCH(headword, ?) OR FTS_MATCH(body, ?))
                    ORDER BY score DESC
                    LIMIT \(safeLimit);
                """
                if let res = try? db.queryParams(sql, params: [
                    .string(ftsQuery),
                    .string(source.dbKey),
                    .string(ftsQuery),
                    .string(ftsQuery)
                ]) {
                    for row in res.rows {
                        let rowId = Int(row.int(at: 0) ?? 0)
                        if seen.insert(rowId).inserted {
                            results.append(StudyDictionaryEntry(
                                id: "\(source.dbKey)-\(rowId)",
                                source: source,
                                headword: row.string(at: 1) ?? "",
                                body: row.string(at: 2) ?? ""
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
        let sql = "SELECT COUNT(*) FROM verses WHERE bc_key = ?;"
        guard let res = try? db.queryParams(sql, params: [.int(Self.bcKey(bookId, chapter))]),
              let row = res.rows.first else { return 0 }
        return Int(row.int(at: 0) ?? 0)
    }

    public func crossReferences(bookId: Int, chapter: Int) -> [Int: [CrossReference]] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [:] }
        let sql = """
            SELECT id, from_book, from_chapter, from_verse, phrase, to_book, to_chapter, to_verse_start, to_verse_end
            FROM tsk_cross_refs
            WHERE from_bc_key = ?
            ORDER BY from_verse, sort_order;
        """
        guard let res = try? db.queryParams(sql, params: [.int(Self.bcKey(bookId, chapter))]) else { return [:] }
        var grouped: [Int: [CrossReference]] = [:]
        for row in res.rows {
            let fromVerse = Int(row.int(at: 3) ?? 0)
            let toBook = Int(row.int(at: 5) ?? 0)
            let targetBook = bookMap[toBook]
            let ref = CrossReference(
                id: Int(row.int(at: 0) ?? 0),
                fromBook: Int(row.int(at: 1) ?? 0),
                fromChapter: Int(row.int(at: 2) ?? 0),
                fromVerse: fromVerse,
                phrase: row.string(at: 4) ?? "",
                toBook: toBook,
                toChapter: Int(row.int(at: 6) ?? 0),
                toVerseStart: Int(row.int(at: 7) ?? 0),
                toVerseEnd: Int(row.int(at: 8) ?? 0),
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

    public func searchScripture(
        query: String,
        scopeBookId: Int? = nil,
        matchMode: ScriptureSearchMode = .exact,
        limit: Int? = nil
    ) -> [SearchResult] {
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

        let tokens = trimmed
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        guard !tokens.isEmpty else { return [] }

        let limitClause: String
        if let limit {
            limitClause = " LIMIT \(max(1, min(limit, 5000)))"
        } else {
            limitClause = ""
        }

        let sql: String
        var params: [MagQLiteParam] = []

        switch matchMode {
        case .meaning:
            return searchScriptureSemanticUnlocked(tokens: tokens, scopeBookId: scopeBookId, limit: limit ?? 60)

        case .exact:
            let ftsQuery = tokens.joined(separator: " ")
            if let scopeBookId {
                sql = "SELECT id, book_id, chapter, verse, text_plain FROM verses WHERE book_id = ? AND FTS_MATCH(text_plain, ?) ORDER BY id ASC\(limitClause);"
                params = [.int(Int64(scopeBookId)), .string(ftsQuery)]
            } else {
                sql = "SELECT id, book_id, chapter, verse, text_plain FROM verses WHERE FTS_MATCH(text_plain, ?) ORDER BY id ASC\(limitClause);"
                params = [.string(ftsQuery)]
            }

        case .wordStartsWith, .contains:
            let likeClauses = tokens.map { _ in "LOWER(text_plain) LIKE ?" }.joined(separator: " AND ")
            let sqlLimit = (matchMode == .contains) ? limitClause : ""
            if let scopeBookId {
                sql = "SELECT id, book_id, chapter, verse, text_plain FROM verses WHERE book_id = ? AND \(likeClauses) ORDER BY id ASC\(sqlLimit);"
                params.append(.int(Int64(scopeBookId)))
            } else {
                sql = "SELECT id, book_id, chapter, verse, text_plain FROM verses WHERE \(likeClauses) ORDER BY id ASC\(sqlLimit);"
            }
            for tok in tokens {
                params.append(.string("%\(tok)%"))
            }
        }

        guard let res = try? db.queryParams(sql, params: params) else { return [] }

        // Precompile word-start regexes if Word Forms mode is active
        let wordStartRegexes: [NSRegularExpression]
        if matchMode == .wordStartsWith {
            wordStartRegexes = tokens.compactMap { tok in
                let escaped = NSRegularExpression.escapedPattern(for: tok)
                return try? NSRegularExpression(pattern: "\\b\(escaped)", options: [.caseInsensitive])
            }
        } else {
            wordStartRegexes = []
        }

        var out: [SearchResult] = []
        out.reserveCapacity(res.rows.count)
        for row in res.rows {
            let text = row.string(at: 4) ?? ""
            if !wordStartRegexes.isEmpty {
                let nsRange = NSRange(text.startIndex..., in: text)
                let allMatch = wordStartRegexes.allSatisfy { $0.firstMatch(in: text, range: nsRange) != nil }
                if !allMatch { continue }
            }
            let bookId = Int(row.int(at: 1) ?? 0)
            out.append(SearchResult(
                id: Int(row.int(at: 0) ?? 0),
                bookId: bookId,
                bookName: bookMap[bookId]?.name ?? "Book \(bookId)",
                chapter: Int(row.int(at: 2) ?? 0),
                verse: Int(row.int(at: 3) ?? 0),
                text: text
            ))
            if let limit, out.count >= limit { break }
        }
        return out
    }

    /// 100% offline semantic / meaning search powered natively by MagQLite's VECTOR(64) and <=> cosine distance.
    private func searchScriptureSemanticUnlocked(tokens: [String], scopeBookId: Int?, limit: Int) -> [SearchResult] {
        guard let db else { return [] }
        let dim = 64
        var qVec = [Double](repeating: 0.0, count: dim)
        var hitCount = 0

        let vocabSql = "SELECT emb, idf FROM semantic_vocab WHERE word = ? LIMIT 1;"
        for rawTok in tokens {
            let candidates = Self.stemCandidates(for: rawTok)
            for cand in candidates {
                if let res = try? db.queryParams(vocabSql, params: [.string(cand)]),
                   let row = res.rows.first,
                   let vec = Self.parseVector(row.values.first) {
                    let idf = row.double(at: 1) ?? 4.0
                    let count = min(dim, vec.count)
                    for i in 0..<count {
                        qVec[i] += vec[i] * idf
                    }
                    hitCount += 1
                    break
                }
            }
        }
        guard hitCount > 0 else { return [] }

        let norm = sqrt(qVec.reduce(0.0) { $0 + $1 * $1 })
        guard norm > 0 else { return [] }
        let vecLiteral = "[" + qVec.map { String(format: "%.4f", $0 / norm) }.joined(separator: ",") + "]"
        let safeLimit = max(1, min(limit, 200))

        let vecSql: String
        let vecRes: MagQLiteResult?
        if let scopeBookId {
            vecSql = "SELECT verse_id, emb <=> '\(vecLiteral)' AS dist FROM verse_vectors WHERE book_id = ? ORDER BY dist ASC LIMIT \(safeLimit);"
            vecRes = try? db.queryParams(vecSql, params: [.int(Int64(scopeBookId))])
        } else {
            vecSql = "SELECT verse_id, emb <=> '\(vecLiteral)' AS dist FROM verse_vectors ORDER BY dist ASC LIMIT \(safeLimit);"
            vecRes = try? db.query(vecSql)
        }
        guard let rows = vecRes?.rows else { return [] }

        var out: [SearchResult] = []
        out.reserveCapacity(rows.count)
        let verseSql = "SELECT id, book_id, chapter, verse, text_plain FROM verses WHERE id = ? LIMIT 1;"
        for row in rows {
            guard let vid = row.int(at: 0),
                  let vRes = try? db.queryParams(verseSql, params: [.int(vid)]),
                  let vRow = vRes.rows.first else { continue }
            let bookId = Int(vRow.int(at: 1) ?? 0)
            out.append(SearchResult(
                id: Int(vRow.int(at: 0) ?? 0),
                bookId: bookId,
                bookName: bookMap[bookId]?.name ?? "Book \(bookId)",
                chapter: Int(vRow.int(at: 2) ?? 0),
                verse: Int(vRow.int(at: 3) ?? 0),
                text: vRow.string(at: 4) ?? ""
            ))
        }
        return out
    }

    private static func parseVector(_ raw: Any?) -> [Double]? {
        if let arr = raw as? [Double] { return arr }
        if let arr = raw as? [NSNumber] { return arr.map { $0.doubleValue } }
        if let arr = raw as? [Any] {
            let parsed = arr.compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? Double) }
            return parsed.isEmpty ? nil : parsed
        }
        if let str = raw as? String {
            let trimmed = str.trimmingCharacters(in: CharacterSet(charactersIn: "[] \n\t"))
            let parsed = trimmed.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return parsed.isEmpty ? nil : parsed
        }
        return nil
    }

    public func lookupStrongs(id raw: String) -> StrongsEntry? {
        let sid = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !sid.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        let sql = "SELECT strongs_id, testament, lemma, translit, pronunciation, derivation, definition, kjv_usage FROM strongs_lexicon WHERE strongs_id = ? LIMIT 1;"
        guard let res = try? db.queryParams(sql, params: [.string(sid)]),
              let row = res.rows.first else { return nil }
        return Self.readStrongsRow(row)
    }

    public func versesForStrongs(strongsId raw: String, limit: Int = 30) -> [SearchResult] {
        let sid = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !sid.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        // 2-step indexed lookup: hits TEXT B+Tree on interlinear_words(strongs_id) then INT B+Tree on verses(bcv_key)
        let safeLimit = max(1, min(limit, 500))
        let keySql = "SELECT DISTINCT bcv_key FROM interlinear_words WHERE strongs_id = ? LIMIT \(safeLimit);"
        guard let keyRes = try? db.queryParams(keySql, params: [.string(sid)]) else { return [] }
        var out: [SearchResult] = []
        let vSql = "SELECT id, book_id, chapter, verse, text_plain FROM verses WHERE bcv_key = ? LIMIT 1;"
        for kRow in keyRes.rows {
            guard let bcv = kRow.int(at: 0),
                  let vRes = try? db.queryParams(vSql, params: [.int(bcv)]),
                  let vRow = vRes.rows.first else { continue }
            let bookId = Int(vRow.int(at: 1) ?? 0)
            out.append(SearchResult(
                id: Int(vRow.int(at: 0) ?? 0),
                bookId: bookId,
                bookName: bookMap[bookId]?.name ?? "Book \(bookId)",
                chapter: Int(vRow.int(at: 2) ?? 0),
                verse: Int(vRow.int(at: 3) ?? 0),
                text: vRow.string(at: 4) ?? ""
            ))
        }
        return out.sorted { $0.id < $1.id }
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
        let q = cleaned.lowercased()
        let safeLimit = max(1, min(limit, 500))
        let sql: String
        let params: [MagQLiteParam]
        if let testament {
            sql = """
                SELECT strongs_id, testament, lemma, translit, pronunciation, derivation, definition, kjv_usage
                FROM strongs_lexicon
                WHERE testament = ? AND (FTS_MATCH(definition, ?) OR FTS_MATCH(kjv_usage, ?) OR FTS_MATCH(translit, ?))
                LIMIT \(safeLimit);
            """
            params = [.string(testament), .string(q), .string(q), .string(q)]
        } else {
            sql = """
                SELECT strongs_id, testament, lemma, translit, pronunciation, derivation, definition, kjv_usage
                FROM strongs_lexicon
                WHERE FTS_MATCH(definition, ?) OR FTS_MATCH(kjv_usage, ?) OR FTS_MATCH(translit, ?)
                LIMIT \(safeLimit);
            """
            params = [.string(q), .string(q), .string(q)]
        }
        guard let res = try? db.queryParams(sql, params: params) else { return [] }
        return res.rows.map(Self.readStrongsRow)
    }

    public func lookupWebster(word raw: String) -> [WebsterEntry] {
        let norm = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !norm.isEmpty else { return [] }
        let candidates = Self.stemCandidates(for: norm)
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let sql = "SELECT id, headword, headword_norm, definition FROM webster_1828 WHERE headword_norm = ? LIMIT 4;"
        for cand in candidates {
            if let res = try? db.queryParams(sql, params: [.string(cand)]), !res.rows.isEmpty {
                return res.rows.map { row in
                    WebsterEntry(
                        id: Int(row.int(at: 0) ?? 0),
                        headword: row.string(at: 1) ?? "",
                        headwordNorm: row.string(at: 2) ?? "",
                        definition: row.string(at: 3) ?? ""
                    )
                }
            }
        }
        return []
    }

    // MARK: - Biblical Geography & Places

    public func placesForChapter(bookId: Int, chapter: Int) -> [BiblicalPlace] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let sql = """
            SELECT DISTINCT p.id, p.name, p.place_type, p.modern_name, p.description, p.lat, p.lon, p.verse_count
            FROM place_verses pv
            JOIN biblical_places p ON p.id = pv.place_id
            WHERE pv.bc_key = ?
            ORDER BY p.verse_count DESC, p.name ASC;
        """
        guard let res = try? db.queryParams(sql, params: [.int(Self.bcKey(bookId, chapter))]) else { return [] }
        return res.rows.map(Self.readPlaceRow)
    }

    public func placesForVerse(bookId: Int, chapter: Int, verse: Int) -> [BiblicalPlace] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let sql = """
            SELECT DISTINCT p.id, p.name, p.place_type, p.modern_name, p.description, p.lat, p.lon, p.verse_count
            FROM place_verses pv
            JOIN biblical_places p ON p.id = pv.place_id
            WHERE pv.bcv_key = ?
            ORDER BY p.verse_count DESC, p.name ASC;
        """
        guard let res = try? db.queryParams(sql, params: [.int(Self.bcvKey(bookId, chapter, verse))]) else { return [] }
        return res.rows.map(Self.readPlaceRow)
    }

    public func searchPlaces(query raw: String, limit: Int = 40) -> [BiblicalPlace] {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let norm = q.lowercased().filter { $0.isLetter || $0.isNumber }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let safeLimit = max(1, min(limit, 500))
        let sql = """
            SELECT id, name, place_type, modern_name, description, lat, lon, verse_count
            FROM biblical_places
            WHERE name_norm LIKE ? OR modern_name LIKE ? OR description LIKE ?
            ORDER BY CASE WHEN name_norm = ? THEN 0 WHEN name_norm LIKE ? THEN 1 ELSE 2 END, verse_count DESC, name ASC
            LIMIT \(safeLimit);
        """
        guard let res = try? db.queryParams(sql, params: [
            .string("%\(norm)%"),
            .string("%\(q)%"),
            .string("%\(q)%"),
            .string(norm),
            .string("\(norm)%")
        ]) else { return [] }
        return res.rows.map(Self.readPlaceRow)
    }

    public func nearbyPlaces(
        lat: Double,
        lon: Double,
        radiusMiles: Double = 25,
        excludeId: String? = nil,
        limit: Int = 12
    ) -> [(place: BiblicalPlace, miles: Double)] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let radiusKm = max(1.0, radiusMiles * 1.609344)
        let safeLimit = max(1, min(limit, 50))
        let sql: String
        let params: [MagQLiteParam]
        if let excludeId, !excludeId.isEmpty {
            sql = """
                SELECT id, name, place_type, modern_name, description, lat, lon, verse_count,
                       ST_DISTANCE_KM(?, ?, lat, lon) AS km
                FROM biblical_places
                WHERE id != ? AND ST_WITHIN_KM(?, ?, lat, lon, ?)
                ORDER BY km ASC
                LIMIT \(safeLimit);
            """
            params = [
                .double(lat), .double(lon),
                .string(excludeId),
                .double(lat), .double(lon), .double(radiusKm)
            ]
        } else {
            sql = """
                SELECT id, name, place_type, modern_name, description, lat, lon, verse_count,
                       ST_DISTANCE_KM(?, ?, lat, lon) AS km
                FROM biblical_places
                WHERE ST_WITHIN_KM(?, ?, lat, lon, ?)
                ORDER BY km ASC
                LIMIT \(safeLimit);
            """
            params = [
                .double(lat), .double(lon),
                .double(lat), .double(lon), .double(radiusKm)
            ]
        }
        guard let res = try? db.queryParams(sql, params: params) else { return [] }
        return res.rows.map { row in
            let place = Self.readPlaceRow(row)
            let km = row.double(at: 8) ?? 0
            return (place: place, miles: km / 1.609344)
        }
    }

    public func versesForPlace(placeId: String, limit: Int = 30) -> [SearchResult] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let safeLimit = max(1, min(limit, 500))
        let keySql = "SELECT DISTINCT bcv_key FROM place_verses WHERE place_id = ? LIMIT \(safeLimit);"
        guard let keyRes = try? db.queryParams(keySql, params: [.string(placeId)]) else { return [] }
        var out: [SearchResult] = []
        let vSql = "SELECT id, book_id, chapter, verse, text_plain FROM verses WHERE bcv_key = ? LIMIT 1;"
        for kRow in keyRes.rows {
            guard let bcv = kRow.int(at: 0),
                  let vRes = try? db.queryParams(vSql, params: [.int(bcv)]),
                  let vRow = vRes.rows.first else { continue }
            let bookId = Int(vRow.int(at: 1) ?? 0)
            out.append(SearchResult(
                id: Int(vRow.int(at: 0) ?? 0),
                bookId: bookId,
                bookName: bookMap[bookId]?.name ?? "Book \(bookId)",
                chapter: Int(vRow.int(at: 2) ?? 0),
                verse: Int(vRow.int(at: 3) ?? 0),
                text: vRow.string(at: 4) ?? ""
            ))
        }
        return out.sorted { $0.id < $1.id }
    }

    private static func readVerseRow(_ row: MagQLiteRow) -> Verse {
        Verse(
            id: Int(row.int(at: 0) ?? 0),
            bookId: Int(row.int(at: 1) ?? 0),
            chapter: Int(row.int(at: 2) ?? 0),
            verse: Int(row.int(at: 3) ?? 0),
            text: row.string(at: 4) ?? "",
            textMarked: row.string(at: 5) ?? ""
        )
    }

    private static func readPlaceRow(_ row: MagQLiteRow) -> BiblicalPlace {
        BiblicalPlace(
            id: row.string(at: 0) ?? "",
            name: row.string(at: 1) ?? "",
            placeType: row.string(at: 2) ?? "",
            modernName: row.string(at: 3) ?? "",
            description: row.string(at: 4) ?? "",
            lat: row.double(at: 5) ?? 0,
            lon: row.double(at: 6) ?? 0,
            verseCount: Int(row.int(at: 7) ?? 0)
        )
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

    private static func readStrongsRow(_ row: MagQLiteRow) -> StrongsEntry {
        StrongsEntry(
            strongsId: row.string(at: 0) ?? "",
            testament: row.string(at: 1) ?? "",
            lemma: row.string(at: 2) ?? "",
            translit: row.string(at: 3) ?? "",
            pronunciation: row.string(at: 4) ?? "",
            derivation: row.string(at: 5) ?? "",
            definition: row.string(at: 6) ?? "",
            kjvUsage: row.string(at: 7) ?? ""
        )
    }
}
