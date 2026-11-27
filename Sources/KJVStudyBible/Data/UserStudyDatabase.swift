import Foundation
import SQLite3

private let SQLITE_TRANSIENT_USER = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class UserStudyDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    public let dbURL: URL

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.dbURL = docs.appendingPathComponent("user_study.sqlite")
        var handle: OpaquePointer?
        if sqlite3_open_v2(dbURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK {
            self.db = handle
            initializeSchemaUnlocked()
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func initializeSchemaUnlocked() {
        guard let db else { return }
        let sql = """
        PRAGMA journal_mode = WAL;
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS ink_annotations (
            id TEXT PRIMARY KEY,
            book_id INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            pk_drawing_blob BLOB NOT NULL,
            ref_font_size REAL NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(book_id, chapter)
        );

        CREATE TABLE IF NOT EXISTS text_highlights (
            id TEXT PRIMARY KEY,
            book_id INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL,
            color_hex TEXT NOT NULL,
            category TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(book_id, chapter, verse)
        );

        CREATE TABLE IF NOT EXISTS bookmarks (
            id TEXT PRIMARY KEY,
            book_id INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL,
            label TEXT NOT NULL,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            note_type TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            pk_drawing_blob BLOB,
            book_id INTEGER,
            chapter INTEGER,
            verse INTEGER,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS highlight_categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color_hex TEXT NOT NULL,
            sort_order INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS collections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS collection_items (
            id TEXT PRIMARY KEY,
            collection_id TEXT NOT NULL,
            book_id INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL,
            added_at TEXT NOT NULL,
            UNIQUE(collection_id, book_id, chapter, verse)
        );

        CREATE TABLE IF NOT EXISTS nav_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER,
            visited_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS pinned_references (
            id TEXT PRIMARY KEY,
            book_id INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            target_book_id INTEGER NOT NULL,
            target_chapter INTEGER NOT NULL,
            target_verse_start INTEGER NOT NULL,
            target_verse_end INTEGER NOT NULL,
            label TEXT NOT NULL,
            pos_x REAL NOT NULL,
            pos_y REAL NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_pinned_refs_bc ON pinned_references(book_id, chapter);

        CREATE TABLE IF NOT EXISTS journal_clips (
            id TEXT PRIMARY KEY,
            book_id INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            source_label TEXT NOT NULL,
            excerpt TEXT NOT NULL,
            user_note TEXT NOT NULL,
            pos_x REAL NOT NULL,
            pos_y REAL NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_journal_clips_bc ON journal_clips(book_id, chapter);

        CREATE TABLE IF NOT EXISTS sticker_library (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            category TEXT NOT NULL,
            symbol_name TEXT,
            tint_hex TEXT,
            image_blob BLOB,
            pk_drawing_blob BLOB,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS placed_stickers (
            id TEXT PRIMARY KEY,
            sticker_id TEXT NOT NULL,
            target_type TEXT NOT NULL,
            target_key TEXT NOT NULL,
            pos_x REAL NOT NULL,
            pos_y REAL NOT NULL,
            width REAL NOT NULL,
            height REAL NOT NULL,
            rotation REAL NOT NULL,
            opacity REAL NOT NULL DEFAULT 1.0,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_placed_stickers_target ON placed_stickers(target_type, target_key);

        CREATE TABLE IF NOT EXISTS study_sessions (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            start_book_id INTEGER NOT NULL,
            start_chapter INTEGER NOT NULL,
            start_verse INTEGER,
            summary_note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS study_trail_entries (
            id TEXT PRIMARY KEY,
            study_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            title TEXT NOT NULL,
            detail TEXT NOT NULL DEFAULT '',
            book_id INTEGER,
            chapter INTEGER,
            verse INTEGER,
            ref_key TEXT,
            duration_seconds INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_study_trail_sid ON study_trail_entries(study_id, created_at);

        CREATE TABLE IF NOT EXISTS study_margin_links (
            id TEXT PRIMARY KEY,
            study_id TEXT NOT NULL,
            book_id INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER,
            note_text TEXT NOT NULL DEFAULT '',
            pos_x REAL NOT NULL,
            pos_y REAL NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_study_margin_links_bc ON study_margin_links(book_id, chapter);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
        // Safe migrations for existing installs
        sqlite3_exec(db, "ALTER TABLE notes ADD COLUMN pk_drawing_blob BLOB;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE placed_stickers ADD COLUMN opacity REAL NOT NULL DEFAULT 1.0;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE sticker_library ADD COLUMN pk_drawing_blob BLOB;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE ink_annotations ADD COLUMN verse_anchors_json TEXT;", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE nav_history ADD COLUMN duration_seconds INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
        collapseConsecutiveHistoryDuplicatesUnlocked()
        seedDefaultHighlightCategoriesUnlocked()
        seedDefaultStickersUnlocked()
    }

    private func seedDefaultHighlightCategoriesUnlocked() {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM highlight_categories", -1, &stmt, nil) == SQLITE_OK else { return }
        var count: Int32 = 0
        if sqlite3_step(stmt) == SQLITE_ROW { count = sqlite3_column_int(stmt, 0) }
        sqlite3_finalize(stmt)
        if count > 0 { return }

        for (idx, p) in HighlightPreset.defaults.enumerated() {
            var ins: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO highlight_categories(id, name, color_hex, sort_order) VALUES (?,?,?,?)", -1, &ins, nil) == SQLITE_OK {
                sqlite3_bind_text(ins, 1, p.id, -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_text(ins, 2, p.name, -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_text(ins, 3, p.hex, -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_int(ins, 4, Int32(idx))
                sqlite3_step(ins)
                sqlite3_finalize(ins)
            }
        }
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - Ink Persistence (with Verse-Anchored Reflow Metadata)

    public func loadChapterInk(bookId: Int, chapter: Int) -> (data: Data, anchors: ChapterInkAnchors?)? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT pk_drawing_blob, verse_anchors_json FROM ink_annotations WHERE book_id = ? AND chapter = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(stmt, 0) else { return nil }
        let len = Int(sqlite3_column_bytes(stmt, 0))
        let blob = Data(bytes: bytes, count: len)
        var anchors: ChapterInkAnchors? = nil
        if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
            let jsonStr = Self.colText(stmt, 1)
            if let jsonData = jsonStr.data(using: .utf8) {
                anchors = try? JSONDecoder().decode(ChapterInkAnchors.self, from: jsonData)
            }
        }
        return (blob, anchors)
    }

    public func saveChapterInk(bookId: Int, chapter: Int, data: Data, fontSize: Double, anchors: ChapterInkAnchors? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO ink_annotations(id, book_id, chapter, pk_drawing_blob, ref_font_size, verse_anchors_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(book_id, chapter) DO UPDATE SET
            pk_drawing_blob = excluded.pk_drawing_blob,
            ref_font_size = excluded.ref_font_size,
            verse_anchors_json = excluded.verse_anchors_json,
            updated_at = excluded.updated_at
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let id = "ink-\(bookId)-\(chapter)"
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_int(stmt, 2, Int32(bookId))
        sqlite3_bind_int(stmt, 3, Int32(chapter))
        _ = data.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, 4, raw.baseAddress, Int32(data.count), SQLITE_TRANSIENT_USER)
        }
        sqlite3_bind_double(stmt, 5, fontSize)
        if let anchors, let jsonData = try? JSONEncoder().encode(anchors), let jsonStr = String(data: jsonData, encoding: .utf8) {
            sqlite3_bind_text(stmt, 6, jsonStr, -1, SQLITE_TRANSIENT_USER)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_text(stmt, 7, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    // MARK: - Highlights

    public func highlights(bookId: Int, chapter: Int) -> [Int: UserHighlight] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [:] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, book_id, chapter, verse, color_hex, category, updated_at FROM text_highlights WHERE book_id = ? AND chapter = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        var map: [Int: UserHighlight] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let h = UserHighlight(
                id: Self.colText(stmt, 0),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                chapter: Int(sqlite3_column_int(stmt, 2)),
                verse: Int(sqlite3_column_int(stmt, 3)),
                colorHex: Self.colText(stmt, 4),
                category: Self.colText(stmt, 5),
                updatedAt: Self.colText(stmt, 6)
            )
            map[h.verse] = h
        }
        return map
    }

    public func allHighlights() -> [UserHighlight] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, book_id, chapter, verse, color_hex, category, updated_at FROM text_highlights ORDER BY updated_at DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var list: [UserHighlight] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            list.append(UserHighlight(
                id: Self.colText(stmt, 0),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                chapter: Int(sqlite3_column_int(stmt, 2)),
                verse: Int(sqlite3_column_int(stmt, 3)),
                colorHex: Self.colText(stmt, 4),
                category: Self.colText(stmt, 5),
                updatedAt: Self.colText(stmt, 6)
            ))
        }
        return list
    }

    public func setHighlight(bookId: Int, chapter: Int, verse: Int, colorHex: String, category: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO text_highlights(id, book_id, chapter, verse, color_hex, category, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(book_id, chapter, verse) DO UPDATE SET
            color_hex = excluded.color_hex,
            category = excluded.category,
            updated_at = excluded.updated_at
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, UUID().uuidString, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_int(stmt, 2, Int32(bookId))
        sqlite3_bind_int(stmt, 3, Int32(chapter))
        sqlite3_bind_int(stmt, 4, Int32(verse))
        sqlite3_bind_text(stmt, 5, colorHex, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 6, category, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 7, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    public func removeHighlight(bookId: Int, chapter: Int, verse: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM text_highlights WHERE book_id = ? AND chapter = ? AND verse = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        sqlite3_bind_int(stmt, 3, Int32(verse))
        sqlite3_step(stmt)
    }

    // MARK: - Bookmarks

    public func allBookmarks() -> [UserBookmark] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, book_id, chapter, verse, label, created_at FROM bookmarks ORDER BY created_at DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [UserBookmark] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(UserBookmark(
                id: Self.colText(stmt, 0),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                chapter: Int(sqlite3_column_int(stmt, 2)),
                verse: Int(sqlite3_column_int(stmt, 3)),
                label: Self.colText(stmt, 4),
                createdAt: Self.colText(stmt, 5)
            ))
        }
        return out
    }

    public func addBookmark(bookId: Int, chapter: Int, verse: Int, label: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO bookmarks(id, book_id, chapter, verse, label, created_at) VALUES (?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, UUID().uuidString, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_int(stmt, 2, Int32(bookId))
        sqlite3_bind_int(stmt, 3, Int32(chapter))
        sqlite3_bind_int(stmt, 4, Int32(verse))
        sqlite3_bind_text(stmt, 5, label, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 6, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    public func deleteBookmark(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM bookmarks WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    // MARK: - Notes (Typed + Apple Pencil Handwriting)

    public func allNotes() -> [UserNote] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, note_type, title, body, pk_drawing_blob, book_id, chapter, verse, updated_at FROM notes ORDER BY updated_at DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [UserNote] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var blobData: Data? = nil
            if sqlite3_column_type(stmt, 4) == SQLITE_BLOB, let ptr = sqlite3_column_blob(stmt, 4) {
                let len = Int(sqlite3_column_bytes(stmt, 4))
                if len > 0 { blobData = Data(bytes: ptr, count: len) }
            }
            let b: Int? = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 5))
            let c: Int? = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 6))
            let v: Int? = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 7))
            out.append(UserNote(
                id: Self.colText(stmt, 0),
                noteType: NoteType(rawValue: Self.colText(stmt, 1)) ?? .passage,
                title: Self.colText(stmt, 2),
                body: Self.colText(stmt, 3),
                drawingData: blobData,
                bookId: b,
                chapter: c,
                verse: v,
                updatedAt: Self.colText(stmt, 8)
            ))
        }
        return out
    }

    public func saveNote(id: String? = nil, noteType: NoteType, title: String, body: String, drawingData: Data? = nil, bookId: Int?, chapter: Int?, verse: Int?) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO notes(id, note_type, title, body, pk_drawing_blob, book_id, chapter, verse, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            note_type = excluded.note_type,
            title = excluded.title,
            body = excluded.body,
            pk_drawing_blob = excluded.pk_drawing_blob,
            book_id = excluded.book_id,
            chapter = excluded.chapter,
            verse = excluded.verse,
            updated_at = excluded.updated_at
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id ?? UUID().uuidString, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, noteType.rawValue, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 3, title, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 4, body, -1, SQLITE_TRANSIENT_USER)
        if let drawingData, !drawingData.isEmpty {
            _ = drawingData.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, 5, raw.baseAddress, Int32(drawingData.count), SQLITE_TRANSIENT_USER)
            }
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        if let bookId { sqlite3_bind_int(stmt, 6, Int32(bookId)) } else { sqlite3_bind_null(stmt, 6) }
        if let chapter { sqlite3_bind_int(stmt, 7, Int32(chapter)) } else { sqlite3_bind_null(stmt, 7) }
        if let verse { sqlite3_bind_int(stmt, 8, Int32(verse)) } else { sqlite3_bind_null(stmt, 8) }
        sqlite3_bind_text(stmt, 9, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    public func deleteNote(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM notes WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    // MARK: - Preferences

    public func getPreference(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM preferences WHERE key = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT_USER)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Self.colText(stmt, 0)
    }

    public func setPreference(_ key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO preferences(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    // MARK: - Pinned Reference Chips

    public func pinnedReferences(bookId: Int, chapter: Int) -> [PinnedReference] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, book_id, chapter, target_book_id, target_chapter, target_verse_start, target_verse_end, label, pos_x, pos_y, updated_at
            FROM pinned_references
            WHERE book_id = ? AND chapter = ?
            ORDER BY updated_at ASC
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        var out: [PinnedReference] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(PinnedReference(
                id: Self.colText(stmt, 0),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                chapter: Int(sqlite3_column_int(stmt, 2)),
                targetBookId: Int(sqlite3_column_int(stmt, 3)),
                targetChapter: Int(sqlite3_column_int(stmt, 4)),
                targetVerseStart: Int(sqlite3_column_int(stmt, 5)),
                targetVerseEnd: Int(sqlite3_column_int(stmt, 6)),
                label: Self.colText(stmt, 7),
                posX: sqlite3_column_double(stmt, 8),
                posY: sqlite3_column_double(stmt, 9),
                updatedAt: Self.colText(stmt, 10)
            ))
        }
        return out
    }

    public func upsertPinnedReference(_ pin: PinnedReference) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO pinned_references(id, book_id, chapter, target_book_id, target_chapter, target_verse_start, target_verse_end, label, pos_x, pos_y, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            pos_x = excluded.pos_x,
            pos_y = excluded.pos_y,
            label = excluded.label,
            updated_at = excluded.updated_at
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, pin.id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_int(stmt, 2, Int32(pin.bookId))
        sqlite3_bind_int(stmt, 3, Int32(pin.chapter))
        sqlite3_bind_int(stmt, 4, Int32(pin.targetBookId))
        sqlite3_bind_int(stmt, 5, Int32(pin.targetChapter))
        sqlite3_bind_int(stmt, 6, Int32(pin.targetVerseStart))
        sqlite3_bind_int(stmt, 7, Int32(pin.targetVerseEnd))
        sqlite3_bind_text(stmt, 8, pin.label, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_double(stmt, 9, pin.posX)
        sqlite3_bind_double(stmt, 10, pin.posY)
        sqlite3_bind_text(stmt, 11, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    public func deletePinnedReference(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM pinned_references WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    // MARK: - Journal Clip Cards (Movable Excerpts + User Notes)

    public func journalClips(bookId: Int, chapter: Int) -> [JournalClipCard] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, book_id, chapter, source_label, excerpt, user_note, pos_x, pos_y, updated_at
            FROM journal_clips
            WHERE book_id = ? AND chapter = ?
            ORDER BY updated_at ASC
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        var out: [JournalClipCard] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(JournalClipCard(
                id: Self.colText(stmt, 0),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                chapter: Int(sqlite3_column_int(stmt, 2)),
                sourceLabel: Self.colText(stmt, 3),
                excerpt: Self.colText(stmt, 4),
                userNote: Self.colText(stmt, 5),
                posX: sqlite3_column_double(stmt, 6),
                posY: sqlite3_column_double(stmt, 7),
                updatedAt: Self.colText(stmt, 8)
            ))
        }
        return out
    }

    public func upsertJournalClip(_ clip: JournalClipCard) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO journal_clips(id, book_id, chapter, source_label, excerpt, user_note, pos_x, pos_y, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            source_label = excluded.source_label,
            excerpt = excluded.excerpt,
            user_note = excluded.user_note,
            pos_x = excluded.pos_x,
            pos_y = excluded.pos_y,
            updated_at = excluded.updated_at
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, clip.id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_int(stmt, 2, Int32(clip.bookId))
        sqlite3_bind_int(stmt, 3, Int32(clip.chapter))
        sqlite3_bind_text(stmt, 4, clip.sourceLabel, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 5, clip.excerpt, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 6, clip.userNote, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_double(stmt, 7, clip.posX)
        sqlite3_bind_double(stmt, 8, clip.posY)
        sqlite3_bind_text(stmt, 9, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    public func deleteJournalClip(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM journal_clips WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    // MARK: - Custom Highlight Categories

    public func highlightCategories() -> [HighlightPreset] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return HighlightPreset.defaults }
        var stmt: OpaquePointer?
        let sql = "SELECT id, name, color_hex FROM highlight_categories ORDER BY sort_order ASC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return HighlightPreset.defaults }
        defer { sqlite3_finalize(stmt) }
        var out: [HighlightPreset] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(HighlightPreset(id: Self.colText(stmt, 0), name: Self.colText(stmt, 1), hex: Self.colText(stmt, 2)))
        }
        return out.isEmpty ? HighlightPreset.defaults : out
    }

    public func renameHighlightCategory(id: String, name: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "UPDATE highlight_categories SET name = ? WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    // MARK: - Topical Collections

    public func allCollections() -> [StudyCollection] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, name, created_at FROM collections ORDER BY name COLLATE NOCASE ASC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [StudyCollection] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(StudyCollection(id: Self.colText(stmt, 0), name: Self.colText(stmt, 1), createdAt: Self.colText(stmt, 2)))
        }
        return out
    }

    public func createCollection(name: String) -> StudyCollection {
        let col = StudyCollection(id: UUID().uuidString, name: name, createdAt: Self.isoNow())
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return col }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "INSERT INTO collections(id, name, created_at) VALUES (?,?,?)", -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, col.id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(stmt, 2, col.name, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(stmt, 3, col.createdAt, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
        }
        return col
    }

    public func deleteCollection(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        for sql in ["DELETE FROM collection_items WHERE collection_id = ?", "DELETE FROM collections WHERE id = ?"] {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }

    public func items(inCollection collectionId: String) -> [CollectionItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, collection_id, book_id, chapter, verse, added_at FROM collection_items WHERE collection_id = ? ORDER BY book_id, chapter, verse"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, collectionId, -1, SQLITE_TRANSIENT_USER)
        var out: [CollectionItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(CollectionItem(
                id: Self.colText(stmt, 0),
                collectionId: Self.colText(stmt, 1),
                bookId: Int(sqlite3_column_int(stmt, 2)),
                chapter: Int(sqlite3_column_int(stmt, 3)),
                verse: Int(sqlite3_column_int(stmt, 4)),
                addedAt: Self.colText(stmt, 5)
            ))
        }
        return out
    }

    public func addCollectionItem(collectionId: String, bookId: Int, chapter: Int, verse: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "INSERT OR IGNORE INTO collection_items(id, collection_id, book_id, chapter, verse, added_at) VALUES (?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, UUID().uuidString, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, collectionId, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_int(stmt, 3, Int32(bookId))
        sqlite3_bind_int(stmt, 4, Int32(chapter))
        sqlite3_bind_int(stmt, 5, Int32(verse))
        sqlite3_bind_text(stmt, 6, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    public func deleteCollectionItem(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM collection_items WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Reading History (Consecutive Deduplication + Time Spent)

    private func collapseConsecutiveHistoryDuplicatesUnlocked() {
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "SELECT id, book_id, chapter, duration_seconds FROM nav_history ORDER BY id ASC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        var rows: [(id: Int, bookId: Int, chapter: Int, dur: Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append((
                Int(sqlite3_column_int(stmt, 0)),
                Int(sqlite3_column_int(stmt, 1)),
                Int(sqlite3_column_int(stmt, 2)),
                Int(sqlite3_column_int(stmt, 3))
            ))
        }
        sqlite3_finalize(stmt)
        guard rows.count > 1 else { return }

        var prev = rows[0]
        var idsToDelete: [Int] = []
        var durAdds: [Int: Int] = [:]
        for cur in rows.dropFirst() {
            if cur.bookId == prev.bookId && cur.chapter == prev.chapter {
                // Keep the newer row and fold any duration from the older duplicate into it
                idsToDelete.append(prev.id)
                let carried = prev.dur + (durAdds[prev.id] ?? 0)
                if carried > 0 {
                    durAdds[cur.id, default: 0] += carried
                }
                durAdds.removeValue(forKey: prev.id)
                prev = cur
            } else {
                prev = cur
            }
        }
        guard !idsToDelete.isEmpty else { return }
        for (keepId, extraDur) in durAdds where extraDur > 0 {
            var uStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE nav_history SET duration_seconds = duration_seconds + ? WHERE id = ?", -1, &uStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(uStmt, 1, Int32(extraDur))
                sqlite3_bind_int(uStmt, 2, Int32(keepId))
                sqlite3_step(uStmt)
                sqlite3_finalize(uStmt)
            }
        }
        for delId in idsToDelete {
            var dStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM nav_history WHERE id = ?", -1, &dStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(dStmt, 1, Int32(delId))
                sqlite3_step(dStmt)
                sqlite3_finalize(dStmt)
            }
        }
    }

    @discardableResult
    public func recordHistory(bookId: Int, chapter: Int, verse: Int?) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }

        // Check the most recent history entry; if it is already the same (book, chapter), update it instead of duplicating!
        var lastStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id, book_id, chapter FROM nav_history ORDER BY id DESC LIMIT 1", -1, &lastStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(lastStmt) }
            if sqlite3_step(lastStmt) == SQLITE_ROW {
                let lastId = Int(sqlite3_column_int(lastStmt, 0))
                let lastBook = Int(sqlite3_column_int(lastStmt, 1))
                let lastChap = Int(sqlite3_column_int(lastStmt, 2))
                if lastBook == bookId && lastChap == chapter {
                    var upd: OpaquePointer?
                    let uSQL = verse != nil
                        ? "UPDATE nav_history SET visited_at = ?, verse = ? WHERE id = ?"
                        : "UPDATE nav_history SET visited_at = ? WHERE id = ?"
                    if sqlite3_prepare_v2(db, uSQL, -1, &upd, nil) == SQLITE_OK {
                        defer { sqlite3_finalize(upd) }
                        sqlite3_bind_text(upd, 1, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
                        if let verse {
                            sqlite3_bind_int(upd, 2, Int32(verse))
                            sqlite3_bind_int(upd, 3, Int32(lastId))
                        } else {
                            sqlite3_bind_int(upd, 2, Int32(lastId))
                        }
                        sqlite3_step(upd)
                    }
                    return lastId
                }
            }
        }

        var stmt: OpaquePointer?
        let sql = "INSERT INTO nav_history(book_id, chapter, verse, visited_at, duration_seconds) VALUES (?,?,?,?,0)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        if let verse { sqlite3_bind_int(stmt, 3, Int32(verse)) } else { sqlite3_bind_null(stmt, 3) }
        sqlite3_bind_text(stmt, 4, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
        return Int(sqlite3_last_insert_rowid(db))
    }

    public func addHistoryDuration(id: Int, seconds: Int) {
        guard seconds > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE nav_history SET duration_seconds = duration_seconds + ? WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(seconds))
            sqlite3_bind_int(stmt, 2, Int32(id))
            sqlite3_step(stmt)
        }
    }

    public func clearHistory() {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        sqlite3_exec(db, "DELETE FROM nav_history;", nil, nil, nil)
    }

    public func recentHistory(limit: Int = 50) -> [ReadingHistoryItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, book_id, chapter, verse, visited_at, duration_seconds FROM nav_history ORDER BY id DESC LIMIT ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var out: [ReadingHistoryItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let v: Int? = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 3))
            out.append(ReadingHistoryItem(
                id: Int(sqlite3_column_int(stmt, 0)),
                bookId: Int(sqlite3_column_int(stmt, 1)),
                chapter: Int(sqlite3_column_int(stmt, 2)),
                verse: v,
                visitedAt: Self.colText(stmt, 4),
                durationSeconds: Int(sqlite3_column_int(stmt, 5))
            ))
        }
        return out
    }

    // MARK: - Search Personal Study (Notes, Clips, Bookmarks)

    public func searchPersonalStudy(query raw: String, limit: Int = 30) -> [PersonalSearchHit] {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let pat = "%\(q)%"
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var hits: [PersonalSearchHit] = []

        // Notes
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id, note_type, title, body, book_id, chapter, verse FROM notes WHERE title LIKE ? OR body LIKE ? ORDER BY updated_at DESC LIMIT ?", -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, pat, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(stmt, 2, pat, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_int(stmt, 3, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let nid = Self.colText(stmt, 0)
                let b: Int? = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 4))
                let c: Int? = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 5))
                let v: Int? = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 6))
                hits.append(PersonalSearchHit(
                    id: "note-\(nid)",
                    kind: Self.colText(stmt, 1),
                    title: Self.colText(stmt, 2),
                    snippet: Self.colText(stmt, 3),
                    bookId: b, chapter: c, verse: v, noteId: nid
                ))
            }
        }

        // Journal Clips
        var cstmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id, source_label, excerpt, user_note, book_id, chapter FROM journal_clips WHERE source_label LIKE ? OR excerpt LIKE ? OR user_note LIKE ? ORDER BY updated_at DESC LIMIT ?", -1, &cstmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(cstmt) }
            sqlite3_bind_text(cstmt, 1, pat, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(cstmt, 2, pat, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(cstmt, 3, pat, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_int(cstmt, 4, Int32(limit))
            while sqlite3_step(cstmt) == SQLITE_ROW {
                let cid = Self.colText(cstmt, 0)
                let ex = Self.colText(cstmt, 2)
                let un = Self.colText(cstmt, 3)
                hits.append(PersonalSearchHit(
                    id: "clip-\(cid)",
                    kind: "Journal Clip",
                    title: Self.colText(cstmt, 1),
                    snippet: un.isEmpty ? ex : "\(ex) — \(un)",
                    bookId: Int(sqlite3_column_int(cstmt, 4)),
                    chapter: Int(sqlite3_column_int(cstmt, 5)),
                    verse: nil, noteId: nil
                ))
            }
        }

        // Bookmarks
        var bstmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id, label, book_id, chapter, verse FROM bookmarks WHERE label LIKE ? ORDER BY created_at DESC LIMIT ?", -1, &bstmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(bstmt) }
            sqlite3_bind_text(bstmt, 1, pat, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_int(bstmt, 2, Int32(limit))
            while sqlite3_step(bstmt) == SQLITE_ROW {
                hits.append(PersonalSearchHit(
                    id: "bm-\(Self.colText(bstmt, 0))",
                    kind: "Bookmark",
                    title: Self.colText(bstmt, 1),
                    snippet: "",
                    bookId: Int(sqlite3_column_int(bstmt, 2)),
                    chapter: Int(sqlite3_column_int(bstmt, 3)),
                    verse: Int(sqlite3_column_int(bstmt, 4)),
                    noteId: nil
                ))
            }
        }
        return hits
    }

    // MARK: - Named Study Sessions ("Study Trails") & Permanent Bible Ink Links

    public func allStudySessions() -> [StudySession] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, name, start_book_id, start_chapter, start_verse, summary_note, created_at, updated_at FROM study_sessions ORDER BY updated_at DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [StudySession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let v: Int? = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 4))
            out.append(StudySession(
                id: Self.colText(stmt, 0),
                name: Self.colText(stmt, 1),
                startBookId: Int(sqlite3_column_int(stmt, 2)),
                startChapter: Int(sqlite3_column_int(stmt, 3)),
                startVerse: v,
                summaryNote: Self.colText(stmt, 5),
                createdAt: Self.colText(stmt, 6),
                updatedAt: Self.colText(stmt, 7)
            ))
        }
        return out
    }

    public func createStudySession(name: String, startBookId: Int, startChapter: Int, startVerse: Int?, summaryNote: String = "") -> StudySession {
        lock.lock()
        defer { lock.unlock() }
        let now = Self.isoNow()
        let session = StudySession(
            id: UUID().uuidString,
            name: name.isEmpty ? "Untitled Study" : name,
            startBookId: startBookId,
            startChapter: startChapter,
            startVerse: startVerse,
            summaryNote: summaryNote,
            createdAt: now,
            updatedAt: now
        )
        guard let db else { return session }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO study_sessions(id, name, start_book_id, start_chapter, start_verse, summary_note, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return session }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, session.id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, session.name, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_int(stmt, 3, Int32(startBookId))
        sqlite3_bind_int(stmt, 4, Int32(startChapter))
        if let startVerse { sqlite3_bind_int(stmt, 5, Int32(startVerse)) } else { sqlite3_bind_null(stmt, 5) }
        sqlite3_bind_text(stmt, 6, summaryNote, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 7, now, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 8, now, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
        return session
    }

    public func updateStudySession(id: String, name: String, summaryNote: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "UPDATE study_sessions SET name = ?, summary_note = ?, updated_at = ? WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name.isEmpty ? "Untitled Study" : name, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, summaryNote, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 3, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 4, id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    public func deleteStudySession(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        for table in ["study_trail_entries", "study_margin_links"] {
            var s: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM \(table) WHERE study_id = ?", -1, &s, nil) == SQLITE_OK {
                sqlite3_bind_text(s, 1, id, -1, SQLITE_TRANSIENT_USER)
                sqlite3_step(s)
                sqlite3_finalize(s)
            }
        }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM study_sessions WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    @discardableResult
    public func appendStudyTrailEntry(
        studyId: String,
        kind: StudyTrailKind,
        title: String,
        detail: String = "",
        bookId: Int? = nil,
        chapter: Int? = nil,
        verse: Int? = nil,
        refKey: String? = nil
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }

        // Avoid consecutive duplicates of the exact same entry (e.g., same passage or same Strong's word)
        var lastStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id, kind, title, book_id, chapter FROM study_trail_entries WHERE study_id = ? ORDER BY rowid DESC LIMIT 1", -1, &lastStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(lastStmt) }
            sqlite3_bind_text(lastStmt, 1, studyId, -1, SQLITE_TRANSIENT_USER)
            if sqlite3_step(lastStmt) == SQLITE_ROW {
                let lastId = Self.colText(lastStmt, 0)
                let lastKind = Self.colText(lastStmt, 1)
                let lastTitle = Self.colText(lastStmt, 2)
                let lastB: Int? = sqlite3_column_type(lastStmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(lastStmt, 3))
                let lastC: Int? = sqlite3_column_type(lastStmt, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(lastStmt, 4))
                if lastKind == kind.rawValue && ((kind == .passage && lastB == bookId && lastC == chapter) || lastTitle == title) {
                    return lastId
                }
            }
        }

        let eid = UUID().uuidString
        let now = Self.isoNow()
        var stmt: OpaquePointer?
        let sql = "INSERT INTO study_trail_entries(id, study_id, kind, title, detail, book_id, chapter, verse, ref_key, duration_seconds, created_at) VALUES (?,?,?,?,?,?,?,?,?,0,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, eid, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, studyId, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 3, kind.rawValue, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 4, title, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 5, detail, -1, SQLITE_TRANSIENT_USER)
        if let bookId { sqlite3_bind_int(stmt, 6, Int32(bookId)) } else { sqlite3_bind_null(stmt, 6) }
        if let chapter { sqlite3_bind_int(stmt, 7, Int32(chapter)) } else { sqlite3_bind_null(stmt, 7) }
        if let verse { sqlite3_bind_int(stmt, 8, Int32(verse)) } else { sqlite3_bind_null(stmt, 8) }
        if let refKey { sqlite3_bind_text(stmt, 9, refKey, -1, SQLITE_TRANSIENT_USER) } else { sqlite3_bind_null(stmt, 9) }
        sqlite3_bind_text(stmt, 10, now, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)

        var touch: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE study_sessions SET updated_at = ? WHERE id = ?", -1, &touch, nil) == SQLITE_OK {
            sqlite3_bind_text(touch, 1, now, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(touch, 2, studyId, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(touch)
            sqlite3_finalize(touch)
        }
        return eid
    }

    public func addStudyTrailDuration(entryId: String, seconds: Int) {
        guard seconds > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE study_trail_entries SET duration_seconds = duration_seconds + ? WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(seconds))
            sqlite3_bind_text(stmt, 2, entryId, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
        }
    }

    public func studyTrailEntries(studyId: String) -> [StudyTrailEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, study_id, kind, title, detail, book_id, chapter, verse, ref_key, duration_seconds, created_at FROM study_trail_entries WHERE study_id = ? ORDER BY rowid DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, studyId, -1, SQLITE_TRANSIENT_USER)
        var out: [StudyTrailEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let b: Int? = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 5))
            let c: Int? = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 6))
            let v: Int? = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 7))
            let rk: String? = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : Self.colText(stmt, 8)
            out.append(StudyTrailEntry(
                id: Self.colText(stmt, 0),
                studyId: Self.colText(stmt, 1),
                kind: StudyTrailKind(rawValue: Self.colText(stmt, 2)) ?? .passage,
                title: Self.colText(stmt, 3),
                detail: Self.colText(stmt, 4),
                bookId: b,
                chapter: c,
                verse: v,
                refKey: rk,
                durationSeconds: Int(sqlite3_column_int(stmt, 9)),
                createdAt: Self.colText(stmt, 10)
            ))
        }
        return out
    }

    public func deleteStudyTrailEntry(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM study_trail_entries WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
        }
    }

    public func studyMarginLinks(bookId: Int, chapter: Int) -> [StudyMarginLink] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = """
            SELECT l.id, l.study_id, COALESCE(s.name, 'Study'), l.book_id, l.chapter, l.verse, l.note_text, l.pos_x, l.pos_y, l.updated_at
            FROM study_margin_links l
            LEFT JOIN study_sessions s ON s.id = l.study_id
            WHERE l.book_id = ? AND l.chapter = ?
            ORDER BY l.updated_at ASC
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(bookId))
        sqlite3_bind_int(stmt, 2, Int32(chapter))
        var out: [StudyMarginLink] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let v: Int? = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 5))
            out.append(StudyMarginLink(
                id: Self.colText(stmt, 0),
                studyId: Self.colText(stmt, 1),
                studyName: Self.colText(stmt, 2),
                bookId: Int(sqlite3_column_int(stmt, 3)),
                chapter: Int(sqlite3_column_int(stmt, 4)),
                verse: v,
                noteText: Self.colText(stmt, 6),
                posX: sqlite3_column_double(stmt, 7),
                posY: sqlite3_column_double(stmt, 8),
                updatedAt: Self.colText(stmt, 9)
            ))
        }
        return out
    }

    public func upsertStudyMarginLink(_ link: StudyMarginLink) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO study_margin_links(id, study_id, book_id, chapter, verse, note_text, pos_x, pos_y, updated_at)
        VALUES (?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
            note_text = excluded.note_text,
            pos_x = excluded.pos_x,
            pos_y = excluded.pos_y,
            updated_at = excluded.updated_at
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, link.id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, link.studyId, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_int(stmt, 3, Int32(link.bookId))
        sqlite3_bind_int(stmt, 4, Int32(link.chapter))
        if let v = link.verse { sqlite3_bind_int(stmt, 5, Int32(v)) } else { sqlite3_bind_null(stmt, 5) }
        sqlite3_bind_text(stmt, 6, link.noteText, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_double(stmt, 7, link.posX)
        sqlite3_bind_double(stmt, 8, link.posY)
        sqlite3_bind_text(stmt, 9, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    public func deleteStudyMarginLink(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM study_margin_links WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Safe Atomic WAL Backup Export

    // MARK: - Stickers Library & Placed Stickers

    private func seedDefaultStickersUnlocked() {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sticker_library", -1, &stmt, nil) == SQLITE_OK else { return }
        var count: Int32 = 0
        if sqlite3_step(stmt) == SQLITE_ROW { count = sqlite3_column_int(stmt, 0) }
        sqlite3_finalize(stmt)
        if count > 0 { return }

        let defaults: [(String, String, String, String)] = [
            ("builtin-cross", "Cross", "cross.fill", "#B93B3B"),
            ("builtin-crown", "Crown", "crown.fill", "#C6A645"),
            ("builtin-flame", "Spirit", "flame.fill", "#D96B27"),
            ("builtin-heart", "Grace & Love", "heart.fill", "#D66B7A"),
            ("builtin-star", "Promise", "star.fill", "#C6A645"),
            ("builtin-key", "Key Insight", "key.fill", "#3A78C2"),
            ("builtin-book", "Scripture", "book.closed.fill", "#4A3C2C"),
            ("builtin-light", "Truth", "lightbulb.fill", "#D49B2A"),
            ("builtin-prayer", "Prayer", "hands.sparkles.fill", "#7C52B5"),
            ("builtin-shield", "Faith", "shield.fill", "#2F7D57"),
            ("builtin-bookmark", "Memory", "bookmark.fill", "#3A78C2"),
            ("builtin-check", "Fulfilled", "checkmark.seal.fill", "#2F7D57"),
            ("builtin-warning", "Warning", "exclamationmark.triangle.fill", "#B93B3B"),
            ("builtin-question", "Question", "questionmark.circle.fill", "#7C52B5"),
            ("builtin-arrow", "Callout", "arrow.right.circle.fill", "#3A78C2"),
            ("builtin-glory", "Praise", "sparkles", "#C6A645")
        ]

        let now = Self.isoNow()
        for (id, name, sym, hex) in defaults {
            var ins: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO sticker_library(id, name, kind, category, symbol_name, tint_hex, image_blob, created_at) VALUES (?,?,?,?,?,?,NULL,?)", -1, &ins, nil) == SQLITE_OK {
                sqlite3_bind_text(ins, 1, id, -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_text(ins, 2, name, -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_text(ins, 3, StickerKind.symbol.rawValue, -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_text(ins, 4, "Bible Study", -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_text(ins, 5, sym, -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_text(ins, 6, hex, -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_text(ins, 7, now, -1, SQLITE_TRANSIENT_USER)
                sqlite3_step(ins)
                sqlite3_finalize(ins)
            }
        }
    }

    public func allStickers() -> [StickerItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, name, kind, category, symbol_name, tint_hex, image_blob, pk_drawing_blob, created_at FROM sticker_library ORDER BY CASE kind WHEN 'drawn' THEN 0 WHEN 'imported' THEN 1 ELSE 2 END, created_at DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [StickerItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sym: String? = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : Self.colText(stmt, 4)
            let hex: String? = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Self.colText(stmt, 5)
            var imgData: Data? = nil
            if sqlite3_column_type(stmt, 6) == SQLITE_BLOB, let ptr = sqlite3_column_blob(stmt, 6) {
                let len = Int(sqlite3_column_bytes(stmt, 6))
                if len > 0 { imgData = Data(bytes: ptr, count: len) }
            }
            var drawData: Data? = nil
            if sqlite3_column_type(stmt, 7) == SQLITE_BLOB, let ptr = sqlite3_column_blob(stmt, 7) {
                let len = Int(sqlite3_column_bytes(stmt, 7))
                if len > 0 { drawData = Data(bytes: ptr, count: len) }
            }
            out.append(StickerItem(
                id: Self.colText(stmt, 0),
                name: Self.colText(stmt, 1),
                kind: StickerKind(rawValue: Self.colText(stmt, 2)) ?? .symbol,
                category: Self.colText(stmt, 3),
                symbolName: sym,
                tintHex: hex,
                imageData: imgData,
                drawingData: drawData,
                createdAt: Self.colText(stmt, 8)
            ))
        }
        return out
    }

    public func saveCustomSticker(name: String, kind: StickerKind, category: String, imageData: Data, drawingData: Data? = nil) -> StickerItem {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID().uuidString
        let now = Self.isoNow()
        let item = StickerItem(
            id: id,
            name: name.isEmpty ? "Sticker" : name,
            kind: kind,
            category: category,
            symbolName: nil,
            tintHex: nil,
            imageData: imageData,
            drawingData: drawingData,
            createdAt: now
        )
        guard let db else { return item }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO sticker_library(id, name, kind, category, symbol_name, tint_hex, image_blob, pk_drawing_blob, created_at) VALUES (?,?,?,?,NULL,NULL,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return item }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, item.id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, item.name, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 3, item.kind.rawValue, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 4, item.category, -1, SQLITE_TRANSIENT_USER)
        _ = imageData.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, 5, raw.baseAddress, Int32(imageData.count), SQLITE_TRANSIENT_USER)
        }
        if let drawingData, !drawingData.isEmpty {
            _ = drawingData.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, 6, raw.baseAddress, Int32(drawingData.count), SQLITE_TRANSIENT_USER)
            }
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_text(stmt, 7, now, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
        return item
    }

    public func updateCustomSticker(id: String, name: String, imageData: Data, drawingData: Data?) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "UPDATE sticker_library SET name = ?, image_blob = ?, pk_drawing_blob = ? WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name.isEmpty ? "Sticker" : name, -1, SQLITE_TRANSIENT_USER)
        _ = imageData.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, 2, raw.baseAddress, Int32(imageData.count), SQLITE_TRANSIENT_USER)
        }
        if let drawingData, !drawingData.isEmpty {
            _ = drawingData.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, 3, raw.baseAddress, Int32(drawingData.count), SQLITE_TRANSIENT_USER)
            }
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_text(stmt, 4, id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    public func deleteStickerFromLibrary(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM sticker_library WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        var pStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM placed_stickers WHERE sticker_id = ?", -1, &pStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(pStmt, 1, id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(pStmt)
            sqlite3_finalize(pStmt)
        }
    }

    public func placedStickers(targetType: String, targetKey: String) -> [PlacedSticker] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, sticker_id, target_type, target_key, pos_x, pos_y, width, height, rotation, opacity, updated_at FROM placed_stickers WHERE target_type = ? AND target_key = ? ORDER BY updated_at ASC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, targetType, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, targetKey, -1, SQLITE_TRANSIENT_USER)
        var out: [PlacedSticker] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(PlacedSticker(
                id: Self.colText(stmt, 0),
                stickerId: Self.colText(stmt, 1),
                targetType: Self.colText(stmt, 2),
                targetKey: Self.colText(stmt, 3),
                posX: sqlite3_column_double(stmt, 4),
                posY: sqlite3_column_double(stmt, 5),
                width: sqlite3_column_double(stmt, 6),
                height: sqlite3_column_double(stmt, 7),
                rotation: sqlite3_column_double(stmt, 8),
                opacity: sqlite3_column_double(stmt, 9),
                updatedAt: Self.colText(stmt, 10)
            ))
        }
        return out
    }

    public func addPlacedSticker(stickerId: String, targetType: String, targetKey: String, posX: Double, posY: Double, width: Double = 72, height: Double = 72, rotation: Double = 0, opacity: Double = 1.0) -> PlacedSticker {
        lock.lock()
        defer { lock.unlock() }
        let now = Self.isoNow()
        let placed = PlacedSticker(
            id: UUID().uuidString,
            stickerId: stickerId,
            targetType: targetType,
            targetKey: targetKey,
            posX: posX,
            posY: posY,
            width: width,
            height: height,
            rotation: rotation,
            opacity: opacity,
            updatedAt: now
        )
        guard let db else { return placed }
        var stmt: OpaquePointer?
        let sql = "INSERT INTO placed_stickers(id, sticker_id, target_type, target_key, pos_x, pos_y, width, height, rotation, opacity, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return placed }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, placed.id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, placed.stickerId, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 3, placed.targetType, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 4, placed.targetKey, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_double(stmt, 5, placed.posX)
        sqlite3_bind_double(stmt, 6, placed.posY)
        sqlite3_bind_double(stmt, 7, placed.width)
        sqlite3_bind_double(stmt, 8, placed.height)
        sqlite3_bind_double(stmt, 9, placed.rotation)
        sqlite3_bind_double(stmt, 10, placed.opacity)
        sqlite3_bind_text(stmt, 11, now, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
        return placed
    }

    public func updatePlacedSticker(id: String, posX: Double, posY: Double, width: Double, height: Double, rotation: Double, opacity: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        let sql = "UPDATE placed_stickers SET pos_x = ?, pos_y = ?, width = ?, height = ?, rotation = ?, opacity = ?, updated_at = ? WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, posX)
        sqlite3_bind_double(stmt, 2, posY)
        sqlite3_bind_double(stmt, 3, width)
        sqlite3_bind_double(stmt, 4, height)
        sqlite3_bind_double(stmt, 5, rotation)
        sqlite3_bind_double(stmt, 6, opacity)
        sqlite3_bind_text(stmt, 7, Self.isoNow(), -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 8, id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_step(stmt)
    }

    public func deletePlacedSticker(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM placed_stickers WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    public func createBackupSnapshot() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let fname = "SwordAndQuill-Backup-\(df.string(from: Date())).sqlite"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(fname)
        try? FileManager.default.removeItem(at: dest)
        let escaped = dest.path.replacingOccurrences(of: "'", with: "''")
        let rc = sqlite3_exec(db, "VACUUM INTO '\(escaped)';", nil, nil, nil)
        return rc == SQLITE_OK ? dest : nil
    }

    // MARK: - Atomic SQLite Backup Restore (Validates Schema + Safety Snapshot + Online Backup API)

    public enum RestoreError: LocalizedError {
        case cannotOpenSource
        case invalidBackupSchema
        case backupCopyFailed

        public var errorDescription: String? {
            switch self {
            case .cannotOpenSource: return "Could not open the selected backup file."
            case .invalidBackupSchema: return "This file is not a valid Sword & Quill Study Bible backup (.sqlite)."
            case .backupCopyFailed: return "Restore failed while copying study data. Your previous data is untouched."
            }
        }
    }

    public func restoreFromBackup(url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        // Copy to temp first so security-scoped URLs and iCloud files work reliably with SQLite
        let tmpCopy = FileManager.default.temporaryDirectory.appendingPathComponent("wm-restore-\(UUID().uuidString).sqlite")
        try? FileManager.default.removeItem(at: tmpCopy)
        try FileManager.default.copyItem(at: url, to: tmpCopy)
        defer { try? FileManager.default.removeItem(at: tmpCopy) }

        var srcDB: OpaquePointer?
        guard sqlite3_open_v2(tmpCopy.path, &srcDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let srcDB else {
            throw RestoreError.cannotOpenSource
        }
        defer { sqlite3_close(srcDB) }

        // Validate that expected WellMarked tables exist
        var checkStmt: OpaquePointer?
        let checkSQL = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('ink_annotations','text_highlights','notes','bookmarks')"
        guard sqlite3_prepare_v2(srcDB, checkSQL, -1, &checkStmt, nil) == SQLITE_OK else {
            throw RestoreError.invalidBackupSchema
        }
        var foundTables: Int32 = 0
        if sqlite3_step(checkStmt) == SQLITE_ROW {
            foundTables = sqlite3_column_int(checkStmt, 0)
        }
        sqlite3_finalize(checkStmt)
        guard foundTables >= 3 else {
            throw RestoreError.invalidBackupSchema
        }

        lock.lock()
        defer { lock.unlock() }
        guard let destDB = db else { throw RestoreError.backupCopyFailed }

        // Atomic safety snapshot before overwriting
        let safetyDest = FileManager.default.temporaryDirectory.appendingPathComponent("WellMarked-PreRestore-Safety.sqlite")
        try? FileManager.default.removeItem(at: safetyDest)
        let esc = safetyDest.path.replacingOccurrences(of: "'", with: "''")
        sqlite3_exec(destDB, "VACUUM INTO '\(esc)';", nil, nil, nil)

        guard let backupHandle = sqlite3_backup_init(destDB, "main", srcDB, "main") else {
            throw RestoreError.backupCopyFailed
        }
        let stepRC = sqlite3_backup_step(backupHandle, -1)
        let finishRC = sqlite3_backup_finish(backupHandle)
        guard stepRC == SQLITE_DONE && finishRC == SQLITE_OK else {
            throw RestoreError.backupCopyFailed
        }

        // Ensure any newer columns/tables exist on older backups
        initializeSchemaUnlocked()
    }

    // MARK: - Study Dashboard Statistics

    public func studyDashboardStats() -> StudyDashboardStats {
        lock.lock()
        defer { lock.unlock() }
        guard let db else {
            return StudyDashboardStats(
                chaptersWithInk: 0, highlightedVerses: 0, notebookCount: 0,
                bookmarkCount: 0, clipCount: 0, pinnedRefCount: 0,
                customStickerCount: 0, uniqueChaptersVisited: 0, topBooks: []
            )
        }

        func countQuery(_ sql: String) -> Int {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
        }

        let inkCount = countQuery("SELECT COUNT(*) FROM ink_annotations WHERE length(pk_drawing_blob) > 20")
        let hlCount = countQuery("SELECT COUNT(*) FROM text_highlights")
        let noteCount = countQuery("SELECT COUNT(*) FROM notes")
        let bmCount = countQuery("SELECT COUNT(*) FROM bookmarks")
        let clipCount = countQuery("SELECT COUNT(*) FROM journal_clips")
        let pinCount = countQuery("SELECT COUNT(*) FROM pinned_references")
        let stickerCount = countQuery("SELECT COUNT(*) FROM sticker_library WHERE kind != 'symbol'")
        let visitedCount = countQuery("SELECT COUNT(*) FROM (SELECT DISTINCT book_id, chapter FROM nav_history)")

        var topBooks: [BookStudyCount] = []
        var bStmt: OpaquePointer?
        let topSQL = """
            SELECT book_id, COUNT(*) as cnt FROM (
                SELECT book_id FROM ink_annotations
                UNION ALL SELECT book_id FROM text_highlights
                UNION ALL SELECT book_id FROM bookmarks
                UNION ALL SELECT book_id FROM journal_clips
                UNION ALL SELECT book_id FROM notes WHERE book_id IS NOT NULL
            ) GROUP BY book_id ORDER BY cnt DESC LIMIT 6
        """
        if sqlite3_prepare_v2(db, topSQL, -1, &bStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(bStmt) }
            while sqlite3_step(bStmt) == SQLITE_ROW {
                topBooks.append(BookStudyCount(
                    bookId: Int(sqlite3_column_int(bStmt, 0)),
                    itemCount: Int(sqlite3_column_int(bStmt, 1))
                ))
            }
        }

        return StudyDashboardStats(
            chaptersWithInk: inkCount,
            highlightedVerses: hlCount,
            notebookCount: noteCount,
            bookmarkCount: bmCount,
            clipCount: clipCount,
            pinnedRefCount: pinCount,
            customStickerCount: stickerCount,
            uniqueChaptersVisited: visitedCount,
            topBooks: topBooks
        )
    }

    private static func colText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cstr)
    }
}
