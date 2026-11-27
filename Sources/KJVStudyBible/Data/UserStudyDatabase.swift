import Foundation
import SQLite3

public final class UserStudyDatabase: @unchecked Sendable {
    private var db: MagQLite?
    private let lock = NSLock()
    public let dbURL: URL
    private let legacySQLiteURL: URL

    private static let dbConfig = MagQLiteConfig(
        durability: "normal",
        pagedStorage: false,
        bufferPoolPages: 256,
        autoCheckpointFrames: 32
    )

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.dbURL = docs.appendingPathComponent("user_study.mql")
        self.legacySQLiteURL = docs.appendingPathComponent("user_study.sqlite")
        if let opened = try? MagQLite(path: dbURL.path, config: Self.dbConfig) {
            self.db = opened
            initializeSchemaUnlocked()
            migrateLegacySQLiteIfNeededUnlocked()
            collapseConsecutiveHistoryDuplicatesUnlocked()
            seedDefaultHighlightCategoriesUnlocked()
            seedDefaultStickersUnlocked()
        }
    }

    deinit {
        db?.close()
    }

    private func initializeSchemaUnlocked() {
        guard let db else { return }
        let ddlStatements: [String] = [
            """
            CREATE TABLE IF NOT EXISTS ink_annotations (
                id TEXT PRIMARY KEY,
                book_id INT NOT NULL,
                chapter INT NOT NULL,
                pk_drawing_blob BLOB NOT NULL,
                ref_font_size FLOAT NOT NULL,
                verse_anchors_json TEXT,
                updated_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS text_highlights (
                id TEXT PRIMARY KEY,
                book_id INT NOT NULL,
                chapter INT NOT NULL,
                verse INT NOT NULL,
                color_hex TEXT NOT NULL,
                category TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS bookmarks (
                id TEXT PRIMARY KEY,
                book_id INT NOT NULL,
                chapter INT NOT NULL,
                verse INT NOT NULL,
                label TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS notes (
                id TEXT PRIMARY KEY,
                note_type TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                rich_body_rtf BLOB,
                pk_drawing_blob BLOB,
                book_id INT,
                chapter INT,
                verse INT,
                updated_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS highlight_categories (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color_hex TEXT NOT NULL,
                sort_order INT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS collections (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS collection_items (
                id TEXT PRIMARY KEY,
                collection_id TEXT NOT NULL,
                book_id INT NOT NULL,
                chapter INT NOT NULL,
                verse INT NOT NULL,
                added_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS nav_history (
                id SERIAL PRIMARY KEY,
                book_id INT NOT NULL,
                chapter INT NOT NULL,
                verse INT,
                visited_at TEXT NOT NULL,
                duration_seconds INT NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS preferences (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS pinned_references (
                id TEXT PRIMARY KEY,
                book_id INT NOT NULL,
                chapter INT NOT NULL,
                target_book_id INT NOT NULL,
                target_chapter INT NOT NULL,
                target_verse_start INT NOT NULL,
                target_verse_end INT NOT NULL,
                label TEXT NOT NULL,
                pos_x FLOAT NOT NULL,
                pos_y FLOAT NOT NULL,
                updated_at TEXT NOT NULL,
                study_id TEXT NOT NULL DEFAULT ''
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS journal_clips (
                id TEXT PRIMARY KEY,
                book_id INT NOT NULL,
                chapter INT NOT NULL,
                source_label TEXT NOT NULL,
                excerpt TEXT NOT NULL,
                user_note TEXT NOT NULL,
                pos_x FLOAT NOT NULL,
                pos_y FLOAT NOT NULL,
                updated_at TEXT NOT NULL,
                study_id TEXT NOT NULL DEFAULT ''
            );
            """,
            """
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
            """,
            """
            CREATE TABLE IF NOT EXISTS placed_stickers (
                id TEXT PRIMARY KEY,
                sticker_id TEXT NOT NULL,
                target_type TEXT NOT NULL,
                target_key TEXT NOT NULL,
                pos_x FLOAT NOT NULL,
                pos_y FLOAT NOT NULL,
                width FLOAT NOT NULL,
                height FLOAT NOT NULL,
                rotation FLOAT NOT NULL,
                opacity FLOAT NOT NULL DEFAULT 1.0,
                updated_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS study_sessions (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                start_book_id INT NOT NULL,
                start_chapter INT NOT NULL,
                start_verse INT,
                summary_note TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS study_trail_entries (
                id TEXT PRIMARY KEY,
                study_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                detail TEXT NOT NULL DEFAULT '',
                book_id INT,
                chapter INT,
                verse INT,
                ref_key TEXT,
                duration_seconds INT NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS study_margin_links (
                id TEXT PRIMARY KEY,
                study_id TEXT NOT NULL,
                book_id INT NOT NULL,
                chapter INT NOT NULL,
                verse INT,
                note_text TEXT NOT NULL DEFAULT '',
                pos_x FLOAT NOT NULL,
                pos_y FLOAT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS study_ink_annotations (
                id TEXT PRIMARY KEY,
                study_id TEXT NOT NULL,
                book_id INT NOT NULL,
                chapter INT NOT NULL,
                pk_drawing_blob BLOB NOT NULL,
                ref_font_size FLOAT NOT NULL,
                verse_anchors_json TEXT,
                updated_at TEXT NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_ink_bc ON ink_annotations (book_id);",
            "CREATE INDEX IF NOT EXISTS idx_hl_bc ON text_highlights (book_id);",
            "CREATE INDEX IF NOT EXISTS idx_pinned_refs_bc ON pinned_references (book_id);",
            "CREATE INDEX IF NOT EXISTS idx_journal_clips_bc ON journal_clips (book_id);",
            "CREATE INDEX IF NOT EXISTS idx_placed_stickers_key ON placed_stickers (target_key);",
            "CREATE INDEX IF NOT EXISTS idx_study_trail_sid ON study_trail_entries (study_id);",
            "CREATE INDEX IF NOT EXISTS idx_study_margin_links_bc ON study_margin_links (book_id);",
            "CREATE INDEX IF NOT EXISTS idx_study_ink_sid ON study_ink_annotations (study_id);",
        ]
        for stmt in ddlStatements {
            _ = try? db.query(stmt)
        }
    }

    // MARK: - Automatic One-Time SQLite -> MagQLite Migrator (Zero Data Loss)

    private func migrateLegacySQLiteIfNeededUnlocked() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacySQLiteURL.path) else { return }
        if getPreferenceUnlocked("migrated_from_sqlite_v1") != nil { return }

        // Keep a silent safety backup of the original SQLite file before migrating
        let safetyBak = legacySQLiteURL.deletingLastPathComponent().appendingPathComponent("user_study.sqlite.pre_magqlite.bak")
        if !fm.fileExists(atPath: safetyBak.path) {
            try? fm.copyItem(at: legacySQLiteURL, to: safetyBak)
        }

        if importFromSQLiteUnlocked(sqliteURL: legacySQLiteURL) {
            setPreferenceUnlocked("migrated_from_sqlite_v1", value: Self.isoNow())
            _ = try? db?.query("CHECKPOINT;")
        }
    }

    @discardableResult
    private func importFromSQLiteUnlocked(sqliteURL: URL) -> Bool {
        guard let db else { return false }
        var src: OpaquePointer?
        guard sqlite3_open_v2(sqliteURL.path, &src, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let src else {
            return false
        }
        defer { sqlite3_close(src) }

        func sText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, idx) else { return "" }
            return String(cString: c)
        }
        func sOptText(_ stmt: OpaquePointer?, _ idx: Int32) -> MagQLiteParam {
            sqlite3_column_type(stmt, idx) == SQLITE_NULL ? .null : .string(sText(stmt, idx))
        }
        func sOptInt(_ stmt: OpaquePointer?, _ idx: Int32) -> MagQLiteParam {
            sqlite3_column_type(stmt, idx) == SQLITE_NULL ? .null : .int(Int64(sqlite3_column_int64(stmt, idx)))
        }
        func sBlob(_ stmt: OpaquePointer?, _ idx: Int32) -> MagQLiteParam {
            guard sqlite3_column_type(stmt, idx) == SQLITE_BLOB, let ptr = sqlite3_column_blob(stmt, idx) else {
                return .null
            }
            let len = Int(sqlite3_column_bytes(stmt, idx))
            guard len > 0 else { return .null }
            return .blob(Data(bytes: ptr, count: len))
        }
        func sReqBlob(_ stmt: OpaquePointer?, _ idx: Int32) -> MagQLiteParam {
            guard sqlite3_column_type(stmt, idx) == SQLITE_BLOB, let ptr = sqlite3_column_blob(stmt, idx) else {
                return .blob(Data())
            }
            let len = Int(sqlite3_column_bytes(stmt, idx))
            return .blob(len > 0 ? Data(bytes: ptr, count: len) : Data())
        }
        func hasColumn(_ table: String, _ col: String) -> Bool {
            var s: OpaquePointer?
            guard sqlite3_prepare_v2(src, "PRAGMA table_info(\(table));", -1, &s, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(s) }
            while sqlite3_step(s) == SQLITE_ROW {
                if sText(s, 1).lowercased() == col.lowercased() { return true }
            }
            return false
        }

        // 1. preferences
        do {
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, "SELECT key, value FROM preferences;", -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let k = sText(s, 0), v = sText(s, 1)
                    _ = try? db.queryParams("DELETE FROM preferences WHERE key = ?;", params: [.string(k)])
                    _ = try? db.queryParams("INSERT INTO preferences (key, value) VALUES (?, ?);", params: [.string(k), .string(v)])
                }
            }
        }
        // 2. highlight_categories
        do {
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, "SELECT id, name, color_hex, sort_order FROM highlight_categories;", -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM highlight_categories WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams("INSERT INTO highlight_categories (id, name, color_hex, sort_order) VALUES (?, ?, ?, ?);", params: [
                        .string(id), .string(sText(s, 1)), .string(sText(s, 2)), .int(Int64(sqlite3_column_int64(s, 3)))
                    ])
                }
            }
        }
        // 3. ink_annotations
        do {
            let hasAnchors = hasColumn("ink_annotations", "verse_anchors_json")
            let q = hasAnchors
                ? "SELECT id, book_id, chapter, pk_drawing_blob, ref_font_size, verse_anchors_json, updated_at FROM ink_annotations;"
                : "SELECT id, book_id, chapter, pk_drawing_blob, ref_font_size, NULL, updated_at FROM ink_annotations;"
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, q, -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM ink_annotations WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO ink_annotations (id, book_id, chapter, pk_drawing_blob, ref_font_size, verse_anchors_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .int(Int64(sqlite3_column_int64(s, 1))), .int(Int64(sqlite3_column_int64(s, 2))),
                            sReqBlob(s, 3), .double(sqlite3_column_double(s, 4)), sOptText(s, 5), .string(sText(s, 6))
                        ]
                    )
                }
            }
        }
        // 4. study_ink_annotations
        do {
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, "SELECT id, study_id, book_id, chapter, pk_drawing_blob, ref_font_size, verse_anchors_json, updated_at FROM study_ink_annotations;", -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM study_ink_annotations WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO study_ink_annotations (id, study_id, book_id, chapter, pk_drawing_blob, ref_font_size, verse_anchors_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .string(sText(s, 1)), .int(Int64(sqlite3_column_int64(s, 2))), .int(Int64(sqlite3_column_int64(s, 3))),
                            sReqBlob(s, 4), .double(sqlite3_column_double(s, 5)), sOptText(s, 6), .string(sText(s, 7))
                        ]
                    )
                }
            }
        }
        // 5. text_highlights
        do {
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, "SELECT id, book_id, chapter, verse, color_hex, category, updated_at FROM text_highlights;", -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM text_highlights WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO text_highlights (id, book_id, chapter, verse, color_hex, category, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .int(Int64(sqlite3_column_int64(s, 1))), .int(Int64(sqlite3_column_int64(s, 2))),
                            .int(Int64(sqlite3_column_int64(s, 3))), .string(sText(s, 4)), .string(sText(s, 5)), .string(sText(s, 6))
                        ]
                    )
                }
            }
        }
        // 6. bookmarks
        do {
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, "SELECT id, book_id, chapter, verse, label, created_at FROM bookmarks;", -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM bookmarks WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO bookmarks (id, book_id, chapter, verse, label, created_at) VALUES (?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .int(Int64(sqlite3_column_int64(s, 1))), .int(Int64(sqlite3_column_int64(s, 2))),
                            .int(Int64(sqlite3_column_int64(s, 3))), .string(sText(s, 4)), .string(sText(s, 5))
                        ]
                    )
                }
            }
        }
        // 7. notes
        do {
            let hasRTF = hasColumn("notes", "rich_body_rtf")
            let q = hasRTF
                ? "SELECT id, note_type, title, body, rich_body_rtf, pk_drawing_blob, book_id, chapter, verse, updated_at FROM notes;"
                : "SELECT id, note_type, title, body, NULL, pk_drawing_blob, book_id, chapter, verse, updated_at FROM notes;"
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, q, -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM notes WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO notes (id, note_type, title, body, rich_body_rtf, pk_drawing_blob, book_id, chapter, verse, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .string(sText(s, 1)), .string(sText(s, 2)), .string(sText(s, 3)),
                            sBlob(s, 4), sBlob(s, 5), sOptInt(s, 6), sOptInt(s, 7), sOptInt(s, 8), .string(sText(s, 9))
                        ]
                    )
                }
            }
        }
        // 8. collections & collection_items
        do {
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, "SELECT id, name, created_at FROM collections;", -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM collections WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams("INSERT INTO collections (id, name, created_at) VALUES (?, ?, ?);", params: [.string(id), .string(sText(s, 1)), .string(sText(s, 2))])
                }
            }
            var s2: OpaquePointer?
            if sqlite3_prepare_v2(src, "SELECT id, collection_id, book_id, chapter, verse, added_at FROM collection_items;", -1, &s2, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s2) }
                while sqlite3_step(s2) == SQLITE_ROW {
                    let id = sText(s2, 0)
                    _ = try? db.queryParams("DELETE FROM collection_items WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO collection_items (id, collection_id, book_id, chapter, verse, added_at) VALUES (?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .string(sText(s2, 1)), .int(Int64(sqlite3_column_int64(s2, 2))),
                            .int(Int64(sqlite3_column_int64(s2, 3))), .int(Int64(sqlite3_column_int64(s2, 4))), .string(sText(s2, 5))
                        ]
                    )
                }
            }
        }
        // 9. nav_history
        do {
            let hasDur = hasColumn("nav_history", "duration_seconds")
            let q = hasDur
                ? "SELECT book_id, chapter, verse, visited_at, duration_seconds FROM nav_history ORDER BY id ASC;"
                : "SELECT book_id, chapter, verse, visited_at, 0 FROM nav_history ORDER BY id ASC;"
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, q, -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    _ = try? db.queryParams(
                        "INSERT INTO nav_history (book_id, chapter, verse, visited_at, duration_seconds) VALUES (?, ?, ?, ?, ?);",
                        params: [
                            .int(Int64(sqlite3_column_int64(s, 0))), .int(Int64(sqlite3_column_int64(s, 1))),
                            sOptInt(s, 2), .string(sText(s, 3)), .int(Int64(sqlite3_column_int64(s, 4)))
                        ]
                    )
                }
            }
        }
        // 10. pinned_references
        do {
            let hasStudy = hasColumn("pinned_references", "study_id")
            let q = hasStudy
                ? "SELECT id, book_id, chapter, target_book_id, target_chapter, target_verse_start, target_verse_end, label, pos_x, pos_y, updated_at, study_id FROM pinned_references;"
                : "SELECT id, book_id, chapter, target_book_id, target_chapter, target_verse_start, target_verse_end, label, pos_x, pos_y, updated_at, '' FROM pinned_references;"
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, q, -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM pinned_references WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO pinned_references (id, book_id, chapter, target_book_id, target_chapter, target_verse_start, target_verse_end, label, pos_x, pos_y, updated_at, study_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .int(Int64(sqlite3_column_int64(s, 1))), .int(Int64(sqlite3_column_int64(s, 2))),
                            .int(Int64(sqlite3_column_int64(s, 3))), .int(Int64(sqlite3_column_int64(s, 4))),
                            .int(Int64(sqlite3_column_int64(s, 5))), .int(Int64(sqlite3_column_int64(s, 6))),
                            .string(sText(s, 7)), .double(sqlite3_column_double(s, 8)), .double(sqlite3_column_double(s, 9)),
                            .string(sText(s, 10)), .string(sText(s, 11))
                        ]
                    )
                }
            }
        }
        // 11. journal_clips
        do {
            let hasStudy = hasColumn("journal_clips", "study_id")
            let q = hasStudy
                ? "SELECT id, book_id, chapter, source_label, excerpt, user_note, pos_x, pos_y, updated_at, study_id FROM journal_clips;"
                : "SELECT id, book_id, chapter, source_label, excerpt, user_note, pos_x, pos_y, updated_at, '' FROM journal_clips;"
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, q, -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM journal_clips WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO journal_clips (id, book_id, chapter, source_label, excerpt, user_note, pos_x, pos_y, updated_at, study_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .int(Int64(sqlite3_column_int64(s, 1))), .int(Int64(sqlite3_column_int64(s, 2))),
                            .string(sText(s, 3)), .string(sText(s, 4)), .string(sText(s, 5)),
                            .double(sqlite3_column_double(s, 6)), .double(sqlite3_column_double(s, 7)),
                            .string(sText(s, 8)), .string(sText(s, 9))
                        ]
                    )
                }
            }
        }
        // 12. sticker_library & placed_stickers
        do {
            let hasDraw = hasColumn("sticker_library", "pk_drawing_blob")
            let q = hasDraw
                ? "SELECT id, name, kind, category, symbol_name, tint_hex, image_blob, pk_drawing_blob, created_at FROM sticker_library;"
                : "SELECT id, name, kind, category, symbol_name, tint_hex, image_blob, NULL, created_at FROM sticker_library;"
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, q, -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM sticker_library WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO sticker_library (id, name, kind, category, symbol_name, tint_hex, image_blob, pk_drawing_blob, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .string(sText(s, 1)), .string(sText(s, 2)), .string(sText(s, 3)),
                            sOptText(s, 4), sOptText(s, 5), sBlob(s, 6), sBlob(s, 7), .string(sText(s, 8))
                        ]
                    )
                }
            }
            let hasOp = hasColumn("placed_stickers", "opacity")
            let q2 = hasOp
                ? "SELECT id, sticker_id, target_type, target_key, pos_x, pos_y, width, height, rotation, opacity, updated_at FROM placed_stickers;"
                : "SELECT id, sticker_id, target_type, target_key, pos_x, pos_y, width, height, rotation, 1.0, updated_at FROM placed_stickers;"
            var s2: OpaquePointer?
            if sqlite3_prepare_v2(src, q2, -1, &s2, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s2) }
                while sqlite3_step(s2) == SQLITE_ROW {
                    let id = sText(s2, 0)
                    _ = try? db.queryParams("DELETE FROM placed_stickers WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO placed_stickers (id, sticker_id, target_type, target_key, pos_x, pos_y, width, height, rotation, opacity, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .string(sText(s2, 1)), .string(sText(s2, 2)), .string(sText(s2, 3)),
                            .double(sqlite3_column_double(s2, 4)), .double(sqlite3_column_double(s2, 5)),
                            .double(sqlite3_column_double(s2, 6)), .double(sqlite3_column_double(s2, 7)),
                            .double(sqlite3_column_double(s2, 8)), .double(sqlite3_column_double(s2, 9)),
                            .string(sText(s2, 10))
                        ]
                    )
                }
            }
        }
        // 13. study_sessions, study_trail_entries, study_margin_links
        do {
            var s: OpaquePointer?
            if sqlite3_prepare_v2(src, "SELECT id, name, start_book_id, start_chapter, start_verse, summary_note, created_at, updated_at FROM study_sessions;", -1, &s, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s) }
                while sqlite3_step(s) == SQLITE_ROW {
                    let id = sText(s, 0)
                    _ = try? db.queryParams("DELETE FROM study_sessions WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO study_sessions (id, name, start_book_id, start_chapter, start_verse, summary_note, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .string(sText(s, 1)), .int(Int64(sqlite3_column_int64(s, 2))),
                            .int(Int64(sqlite3_column_int64(s, 3))), sOptInt(s, 4),
                            .string(sText(s, 5)), .string(sText(s, 6)), .string(sText(s, 7))
                        ]
                    )
                }
            }
            var s2: OpaquePointer?
            if sqlite3_prepare_v2(src, "SELECT id, study_id, kind, title, detail, book_id, chapter, verse, ref_key, duration_seconds, created_at FROM study_trail_entries;", -1, &s2, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s2) }
                while sqlite3_step(s2) == SQLITE_ROW {
                    let id = sText(s2, 0)
                    _ = try? db.queryParams("DELETE FROM study_trail_entries WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO study_trail_entries (id, study_id, kind, title, detail, book_id, chapter, verse, ref_key, duration_seconds, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .string(sText(s2, 1)), .string(sText(s2, 2)), .string(sText(s2, 3)),
                            .string(sText(s2, 4)), sOptInt(s2, 5), sOptInt(s2, 6), sOptInt(s2, 7),
                            sOptText(s2, 8), .int(Int64(sqlite3_column_int64(s2, 9))), .string(sText(s2, 10))
                        ]
                    )
                }
            }
            var s3: OpaquePointer?
            if sqlite3_prepare_v2(src, "SELECT id, study_id, book_id, chapter, verse, note_text, pos_x, pos_y, updated_at FROM study_margin_links;", -1, &s3, nil) == SQLITE_OK {
                defer { sqlite3_finalize(s3) }
                while sqlite3_step(s3) == SQLITE_ROW {
                    let id = sText(s3, 0)
                    _ = try? db.queryParams("DELETE FROM study_margin_links WHERE id = ?;", params: [.string(id)])
                    _ = try? db.queryParams(
                        "INSERT INTO study_margin_links (id, study_id, book_id, chapter, verse, note_text, pos_x, pos_y, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
                        params: [
                            .string(id), .string(sText(s3, 1)), .int(Int64(sqlite3_column_int64(s3, 2))),
                            .int(Int64(sqlite3_column_int64(s3, 3))), sOptInt(s3, 4),
                            .string(sText(s3, 5)), .double(sqlite3_column_double(s3, 6)),
                            .double(sqlite3_column_double(s3, 7)), .string(sText(s3, 8))
                        ]
                    )
                }
            }
        }
        return true
    }

    private func seedDefaultHighlightCategoriesUnlocked() {
        guard let db else { return }
        if let res = try? db.query("SELECT COUNT(*) FROM highlight_categories;"),
           let cnt = res.rows.first?.int(at: 0), cnt > 0 {
            return
        }
        for (idx, p) in HighlightPreset.defaults.enumerated() {
            _ = try? db.queryParams(
                "INSERT INTO highlight_categories (id, name, color_hex, sort_order) VALUES (?, ?, ?, ?);",
                params: [.string(p.id), .string(p.name), .string(p.hex), .int(Int64(idx))]
            )
        }
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - Ink Persistence (Everyday Bible + Tracing-Paper Study Layer)

    public func loadChapterInk(bookId: Int, chapter: Int, studyId: String = "") -> (data: Data, anchors: ChapterInkAnchors?)? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        let isStudy = !studyId.isEmpty
        let res: MagQLiteResult?
        if isStudy {
            res = try? db.queryParams(
                "SELECT pk_drawing_blob, verse_anchors_json FROM study_ink_annotations WHERE study_id = ? AND book_id = ? AND chapter = ? LIMIT 1;",
                params: [.string(studyId), .int(Int64(bookId)), .int(Int64(chapter))]
            )
        } else {
            res = try? db.queryParams(
                "SELECT pk_drawing_blob, verse_anchors_json FROM ink_annotations WHERE book_id = ? AND chapter = ? LIMIT 1;",
                params: [.int(Int64(bookId)), .int(Int64(chapter))]
            )
        }
        guard let row = res?.rows.first, let blob = row.blob(at: 0) else { return nil }
        var anchors: ChapterInkAnchors? = nil
        if let jsonStr = row.string(at: 1), let jsonData = jsonStr.data(using: .utf8) {
            anchors = try? JSONDecoder().decode(ChapterInkAnchors.self, from: jsonData)
        }
        return (blob, anchors)
    }

    public func saveChapterInk(bookId: Int, chapter: Int, data: Data, fontSize: Double, anchors: ChapterInkAnchors? = nil, studyId: String = "") {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        let anchorsParam: MagQLiteParam
        if let anchors, let jsonData = try? JSONEncoder().encode(anchors), let jsonStr = String(data: jsonData, encoding: .utf8) {
            anchorsParam = .string(jsonStr)
        } else {
            anchorsParam = .null
        }
        let now = Self.isoNow()
        if !studyId.isEmpty {
            let rowId = "sink-\(studyId)-\(bookId)-\(chapter)"
            _ = try? db.queryParams(
                "DELETE FROM study_ink_annotations WHERE study_id = ? AND book_id = ? AND chapter = ?;",
                params: [.string(studyId), .int(Int64(bookId)), .int(Int64(chapter))]
            )
            _ = try? db.queryParams(
                "INSERT INTO study_ink_annotations (id, study_id, book_id, chapter, pk_drawing_blob, ref_font_size, verse_anchors_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
                params: [.string(rowId), .string(studyId), .int(Int64(bookId)), .int(Int64(chapter)), .blob(data), .double(fontSize), anchorsParam, .string(now)]
            )
        } else {
            let rowId = "ink-\(bookId)-\(chapter)"
            _ = try? db.queryParams(
                "DELETE FROM ink_annotations WHERE book_id = ? AND chapter = ?;",
                params: [.int(Int64(bookId)), .int(Int64(chapter))]
            )
            _ = try? db.queryParams(
                "INSERT INTO ink_annotations (id, book_id, chapter, pk_drawing_blob, ref_font_size, verse_anchors_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?);",
                params: [.string(rowId), .int(Int64(bookId)), .int(Int64(chapter)), .blob(data), .double(fontSize), anchorsParam, .string(now)]
            )
        }
    }

    // MARK: - Highlights

    public func highlights(bookId: Int, chapter: Int) -> [Int: UserHighlight] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [:] }
        guard let res = try? db.queryParams(
            "SELECT id, book_id, chapter, verse, color_hex, category, updated_at FROM text_highlights WHERE book_id = ? AND chapter = ?;",
            params: [.int(Int64(bookId)), .int(Int64(chapter))]
        ) else { return [:] }
        var map: [Int: UserHighlight] = [:]
        for row in res.rows {
            let h = UserHighlight(
                id: row.string(at: 0) ?? "",
                bookId: Int(row.int(at: 1) ?? 0),
                chapter: Int(row.int(at: 2) ?? 0),
                verse: Int(row.int(at: 3) ?? 0),
                colorHex: row.string(at: 4) ?? "",
                category: row.string(at: 5) ?? "",
                updatedAt: row.string(at: 6) ?? ""
            )
            map[h.verse] = h
        }
        return map
    }

    public func allHighlights() -> [UserHighlight] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.query("SELECT id, book_id, chapter, verse, color_hex, category, updated_at FROM text_highlights ORDER BY updated_at DESC;") else {
            return []
        }
        return res.rows.map { row in
            UserHighlight(
                id: row.string(at: 0) ?? "",
                bookId: Int(row.int(at: 1) ?? 0),
                chapter: Int(row.int(at: 2) ?? 0),
                verse: Int(row.int(at: 3) ?? 0),
                colorHex: row.string(at: 4) ?? "",
                category: row.string(at: 5) ?? "",
                updatedAt: row.string(at: 6) ?? ""
            )
        }
    }

    public func setHighlight(bookId: Int, chapter: Int, verse: Int, colorHex: String, category: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams(
            "DELETE FROM text_highlights WHERE book_id = ? AND chapter = ? AND verse = ?;",
            params: [.int(Int64(bookId)), .int(Int64(chapter)), .int(Int64(verse))]
        )
        _ = try? db.queryParams(
            "INSERT INTO text_highlights (id, book_id, chapter, verse, color_hex, category, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?);",
            params: [.string(UUID().uuidString), .int(Int64(bookId)), .int(Int64(chapter)), .int(Int64(verse)), .string(colorHex), .string(category), .string(Self.isoNow())]
        )
    }

    public func removeHighlight(bookId: Int, chapter: Int, verse: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams(
            "DELETE FROM text_highlights WHERE book_id = ? AND chapter = ? AND verse = ?;",
            params: [.int(Int64(bookId)), .int(Int64(chapter)), .int(Int64(verse))]
        )
    }

    // MARK: - Bookmarks

    public func allBookmarks() -> [UserBookmark] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.query("SELECT id, book_id, chapter, verse, label, created_at FROM bookmarks ORDER BY created_at DESC;") else {
            return []
        }
        return res.rows.map { row in
            UserBookmark(
                id: row.string(at: 0) ?? "",
                bookId: Int(row.int(at: 1) ?? 0),
                chapter: Int(row.int(at: 2) ?? 0),
                verse: Int(row.int(at: 3) ?? 0),
                label: row.string(at: 4) ?? "",
                createdAt: row.string(at: 5) ?? ""
            )
        }
    }

    public func addBookmark(bookId: Int, chapter: Int, verse: Int, label: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams(
            "INSERT INTO bookmarks (id, book_id, chapter, verse, label, created_at) VALUES (?, ?, ?, ?, ?, ?);",
            params: [.string(UUID().uuidString), .int(Int64(bookId)), .int(Int64(chapter)), .int(Int64(verse)), .string(label), .string(Self.isoNow())]
        )
    }

    public func deleteBookmark(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM bookmarks WHERE id = ?;", params: [.string(id)])
    }

    // MARK: - Notes (Typed + WYSIWYG RTF + Apple Pencil Handwriting)

    public func allNotes() -> [UserNote] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.query("SELECT id, note_type, title, body, rich_body_rtf, pk_drawing_blob, book_id, chapter, verse, updated_at FROM notes ORDER BY updated_at DESC;") else {
            return []
        }
        return res.rows.map { row in
            let rtfData = row.isNull(at: 4) ? nil : row.blob(at: 4)
            let drawData = row.isNull(at: 5) ? nil : row.blob(at: 5)
            let b: Int? = row.isNull(at: 6) ? nil : row.int(at: 6).map(Int.init)
            let c: Int? = row.isNull(at: 7) ? nil : row.int(at: 7).map(Int.init)
            let v: Int? = row.isNull(at: 8) ? nil : row.int(at: 8).map(Int.init)
            return UserNote(
                id: row.string(at: 0) ?? "",
                noteType: NoteType(rawValue: row.string(at: 1) ?? "") ?? .passage,
                title: row.string(at: 2) ?? "",
                body: row.string(at: 3) ?? "",
                richBodyRTF: rtfData,
                drawingData: drawData,
                bookId: b,
                chapter: c,
                verse: v,
                updatedAt: row.string(at: 9) ?? ""
            )
        }
    }

    public func saveNote(id: String? = nil, noteType: NoteType, title: String, body: String, richBodyRTF: Data? = nil, drawingData: Data? = nil, bookId: Int?, chapter: Int?, verse: Int?) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        let noteId = id ?? UUID().uuidString
        _ = try? db.queryParams("DELETE FROM notes WHERE id = ?;", params: [.string(noteId)])
        let rtfParam: MagQLiteParam = (richBodyRTF != nil && !richBodyRTF!.isEmpty) ? .blob(richBodyRTF!) : .null
        let drawParam: MagQLiteParam = (drawingData != nil && !drawingData!.isEmpty) ? .blob(drawingData!) : .null
        let bParam: MagQLiteParam = bookId.map { .int(Int64($0)) } ?? .null
        let cParam: MagQLiteParam = chapter.map { .int(Int64($0)) } ?? .null
        let vParam: MagQLiteParam = verse.map { .int(Int64($0)) } ?? .null
        _ = try? db.queryParams(
            "INSERT INTO notes (id, note_type, title, body, rich_body_rtf, pk_drawing_blob, book_id, chapter, verse, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            params: [.string(noteId), .string(noteType.rawValue), .string(title), .string(body), rtfParam, drawParam, bParam, cParam, vParam, .string(Self.isoNow())]
        )
    }

    public func deleteNote(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM notes WHERE id = ?;", params: [.string(id)])
    }

    // MARK: - Preferences

    private func getPreferenceUnlocked(_ key: String) -> String? {
        guard let db,
              let res = try? db.queryParams("SELECT value FROM preferences WHERE key = ? LIMIT 1;", params: [.string(key)]),
              let row = res.rows.first else { return nil }
        return row.string(at: 0)
    }

    private func setPreferenceUnlocked(_ key: String, value: String) {
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM preferences WHERE key = ?;", params: [.string(key)])
        _ = try? db.queryParams("INSERT INTO preferences (key, value) VALUES (?, ?);", params: [.string(key), .string(value)])
    }

    public func getPreference(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return getPreferenceUnlocked(key)
    }

    public func setPreference(_ key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        setPreferenceUnlocked(key, value: value)
    }

    // MARK: - Pinned Reference Chips (Scoped by study_id; '' = Everyday Bible)

    public func pinnedReferences(bookId: Int, chapter: Int, studyId: String = "") -> [PinnedReference] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.queryParams(
                  "SELECT id, book_id, chapter, target_book_id, target_chapter, target_verse_start, target_verse_end, label, pos_x, pos_y, updated_at FROM pinned_references WHERE book_id = ? AND chapter = ? AND study_id = ? ORDER BY updated_at ASC;",
                  params: [.int(Int64(bookId)), .int(Int64(chapter)), .string(studyId)]
              ) else { return [] }
        return res.rows.map { row in
            PinnedReference(
                id: row.string(at: 0) ?? "",
                bookId: Int(row.int(at: 1) ?? 0),
                chapter: Int(row.int(at: 2) ?? 0),
                targetBookId: Int(row.int(at: 3) ?? 0),
                targetChapter: Int(row.int(at: 4) ?? 0),
                targetVerseStart: Int(row.int(at: 5) ?? 0),
                targetVerseEnd: Int(row.int(at: 6) ?? 0),
                label: row.string(at: 7) ?? "",
                posX: row.double(at: 8) ?? 0,
                posY: row.double(at: 9) ?? 0,
                updatedAt: row.string(at: 10) ?? ""
            )
        }
    }

    public func upsertPinnedReference(_ pin: PinnedReference, studyId: String = "") {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM pinned_references WHERE id = ?;", params: [.string(pin.id)])
        _ = try? db.queryParams(
            "INSERT INTO pinned_references (id, book_id, chapter, target_book_id, target_chapter, target_verse_start, target_verse_end, label, pos_x, pos_y, updated_at, study_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            params: [
                .string(pin.id), .int(Int64(pin.bookId)), .int(Int64(pin.chapter)),
                .int(Int64(pin.targetBookId)), .int(Int64(pin.targetChapter)),
                .int(Int64(pin.targetVerseStart)), .int(Int64(pin.targetVerseEnd)),
                .string(pin.label), .double(pin.posX), .double(pin.posY),
                .string(Self.isoNow()), .string(studyId)
            ]
        )
    }

    public func deletePinnedReference(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM pinned_references WHERE id = ?;", params: [.string(id)])
    }

    // MARK: - Journal Clip Cards (Scoped by study_id; '' = Everyday Bible)

    public func journalClips(bookId: Int, chapter: Int, studyId: String = "") -> [JournalClipCard] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.queryParams(
                  "SELECT id, book_id, chapter, source_label, excerpt, user_note, pos_x, pos_y, updated_at FROM journal_clips WHERE book_id = ? AND chapter = ? AND study_id = ? ORDER BY updated_at ASC;",
                  params: [.int(Int64(bookId)), .int(Int64(chapter)), .string(studyId)]
              ) else { return [] }
        return res.rows.map { row in
            JournalClipCard(
                id: row.string(at: 0) ?? "",
                bookId: Int(row.int(at: 1) ?? 0),
                chapter: Int(row.int(at: 2) ?? 0),
                sourceLabel: row.string(at: 3) ?? "",
                excerpt: row.string(at: 4) ?? "",
                userNote: row.string(at: 5) ?? "",
                posX: row.double(at: 6) ?? 0,
                posY: row.double(at: 7) ?? 0,
                updatedAt: row.string(at: 8) ?? ""
            )
        }
    }

    public func upsertJournalClip(_ clip: JournalClipCard, studyId: String = "") {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM journal_clips WHERE id = ?;", params: [.string(clip.id)])
        _ = try? db.queryParams(
            "INSERT INTO journal_clips (id, book_id, chapter, source_label, excerpt, user_note, pos_x, pos_y, updated_at, study_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            params: [
                .string(clip.id), .int(Int64(clip.bookId)), .int(Int64(clip.chapter)),
                .string(clip.sourceLabel), .string(clip.excerpt), .string(clip.userNote),
                .double(clip.posX), .double(clip.posY), .string(Self.isoNow()), .string(studyId)
            ]
        )
    }

    public func deleteJournalClip(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM journal_clips WHERE id = ?;", params: [.string(id)])
    }

    // MARK: - Custom Highlight Categories

    public func highlightCategories() -> [HighlightPreset] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.query("SELECT id, name, color_hex FROM highlight_categories ORDER BY sort_order ASC;") else {
            return HighlightPreset.defaults
        }
        let out = res.rows.map { row in
            HighlightPreset(id: row.string(at: 0) ?? "", name: row.string(at: 1) ?? "", hex: row.string(at: 2) ?? "")
        }
        return out.isEmpty ? HighlightPreset.defaults : out
    }

    public func renameHighlightCategory(id: String, name: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("UPDATE highlight_categories SET name = ? WHERE id = ?;", params: [.string(name), .string(id)])
    }

    // MARK: - Topical Collections

    public func allCollections() -> [StudyCollection] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.query("SELECT id, name, created_at FROM collections ORDER BY LOWER(name) ASC;") else {
            return []
        }
        return res.rows.map { row in
            StudyCollection(id: row.string(at: 0) ?? "", name: row.string(at: 1) ?? "", createdAt: row.string(at: 2) ?? "")
        }
    }

    public func createCollection(name: String) -> StudyCollection {
        let col = StudyCollection(id: UUID().uuidString, name: name, createdAt: Self.isoNow())
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return col }
        _ = try? db.queryParams("INSERT INTO collections (id, name, created_at) VALUES (?, ?, ?);", params: [.string(col.id), .string(col.name), .string(col.createdAt)])
        return col
    }

    public func deleteCollection(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM collection_items WHERE collection_id = ?;", params: [.string(id)])
        _ = try? db.queryParams("DELETE FROM collections WHERE id = ?;", params: [.string(id)])
    }

    public func items(inCollection collectionId: String) -> [CollectionItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.queryParams(
                  "SELECT id, collection_id, book_id, chapter, verse, added_at FROM collection_items WHERE collection_id = ? ORDER BY book_id, chapter, verse;",
                  params: [.string(collectionId)]
              ) else { return [] }
        return res.rows.map { row in
            CollectionItem(
                id: row.string(at: 0) ?? "",
                collectionId: row.string(at: 1) ?? "",
                bookId: Int(row.int(at: 2) ?? 0),
                chapter: Int(row.int(at: 3) ?? 0),
                verse: Int(row.int(at: 4) ?? 0),
                addedAt: row.string(at: 5) ?? ""
            )
        }
    }

    public func addCollectionItem(collectionId: String, bookId: Int, chapter: Int, verse: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        if let existing = try? db.queryParams(
            "SELECT id FROM collection_items WHERE collection_id = ? AND book_id = ? AND chapter = ? AND verse = ? LIMIT 1;",
            params: [.string(collectionId), .int(Int64(bookId)), .int(Int64(chapter)), .int(Int64(verse))]
        ), !existing.rows.isEmpty {
            return
        }
        _ = try? db.queryParams(
            "INSERT INTO collection_items (id, collection_id, book_id, chapter, verse, added_at) VALUES (?, ?, ?, ?, ?, ?);",
            params: [.string(UUID().uuidString), .string(collectionId), .int(Int64(bookId)), .int(Int64(chapter)), .int(Int64(verse)), .string(Self.isoNow())]
        )
    }

    public func deleteCollectionItem(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM collection_items WHERE id = ?;", params: [.string(id)])
    }

    // MARK: - Reading History (Consecutive Deduplication + Time Spent)

    private func collapseConsecutiveHistoryDuplicatesUnlocked() {
        guard let db,
              let res = try? db.query("SELECT id, book_id, chapter, duration_seconds FROM nav_history ORDER BY id ASC;") else { return }
        let rows: [(id: Int, bookId: Int, chapter: Int, dur: Int)] = res.rows.map { r in
            (Int(r.int(at: 0) ?? 0), Int(r.int(at: 1) ?? 0), Int(r.int(at: 2) ?? 0), Int(r.int(at: 3) ?? 0))
        }
        guard rows.count > 1 else { return }

        var prev = rows[0]
        var idsToDelete: [Int] = []
        var durAdds: [Int: Int] = [:]
        for cur in rows.dropFirst() {
            if cur.bookId == prev.bookId && cur.chapter == prev.chapter {
                idsToDelete.append(prev.id)
                let carried = prev.dur + (durAdds[prev.id] ?? 0)
                if carried > 0 { durAdds[cur.id, default: 0] += carried }
                durAdds.removeValue(forKey: prev.id)
                prev = cur
            } else {
                prev = cur
            }
        }
        guard !idsToDelete.isEmpty else { return }
        for (keepId, extraDur) in durAdds where extraDur > 0 {
            _ = try? db.queryParams("UPDATE nav_history SET duration_seconds = duration_seconds + ? WHERE id = ?;", params: [.int(Int64(extraDur)), .int(Int64(keepId))])
        }
        for delId in idsToDelete {
            _ = try? db.queryParams("DELETE FROM nav_history WHERE id = ?;", params: [.int(Int64(delId))])
        }
    }

    @discardableResult
    public func recordHistory(bookId: Int, chapter: Int, verse: Int?) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }

        if let lastRes = try? db.query("SELECT id, book_id, chapter FROM nav_history ORDER BY id DESC LIMIT 1;"),
           let lastRow = lastRes.rows.first {
            let lastId = Int(lastRow.int(at: 0) ?? 0)
            let lastBook = Int(lastRow.int(at: 1) ?? 0)
            let lastChap = Int(lastRow.int(at: 2) ?? 0)
            if lastBook == bookId && lastChap == chapter {
                if let verse {
                    _ = try? db.queryParams("UPDATE nav_history SET visited_at = ?, verse = ? WHERE id = ?;", params: [.string(Self.isoNow()), .int(Int64(verse)), .int(Int64(lastId))])
                } else {
                    _ = try? db.queryParams("UPDATE nav_history SET visited_at = ? WHERE id = ?;", params: [.string(Self.isoNow()), .int(Int64(lastId))])
                }
                return lastId
            }
        }

        let vParam: MagQLiteParam = verse.map { .int(Int64($0)) } ?? .null
        if let ins = try? db.queryParams(
            "INSERT INTO nav_history (book_id, chapter, verse, visited_at, duration_seconds) VALUES (?, ?, ?, ?, 0) RETURNING id;",
            params: [.int(Int64(bookId)), .int(Int64(chapter)), vParam, .string(Self.isoNow())]
        ), let newId = ins.rows.first?.int(at: 0) {
            return Int(newId)
        }
        return nil
    }

    public func addHistoryDuration(id: Int, seconds: Int) {
        guard seconds > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("UPDATE nav_history SET duration_seconds = duration_seconds + ? WHERE id = ?;", params: [.int(Int64(seconds)), .int(Int64(id))])
    }

    public func clearHistory() {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.query("DELETE FROM nav_history;")
    }

    public func recentHistory(limit: Int = 50) -> [ReadingHistoryItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let safeLimit = max(1, min(limit, 500))
        guard let res = try? db.query("SELECT id, book_id, chapter, verse, visited_at, duration_seconds FROM nav_history ORDER BY id DESC LIMIT \(safeLimit);") else {
            return []
        }
        return res.rows.map { row in
            let v: Int? = row.isNull(at: 3) ? nil : row.int(at: 3).map(Int.init)
            return ReadingHistoryItem(
                id: Int(row.int(at: 0) ?? 0),
                bookId: Int(row.int(at: 1) ?? 0),
                chapter: Int(row.int(at: 2) ?? 0),
                verse: v,
                visitedAt: row.string(at: 4) ?? "",
                durationSeconds: Int(row.int(at: 5) ?? 0)
            )
        }
    }

    // MARK: - Search Personal Study (Notes, Clips, Bookmarks)

    public func searchPersonalStudy(query raw: String, limit: Int = 30) -> [PersonalSearchHit] {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let pat = "%\(q.lowercased())%"
        let safeLimit = max(1, min(limit, 200))
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var hits: [PersonalSearchHit] = []

        if let res = try? db.queryParams(
            "SELECT id, note_type, title, body, book_id, chapter, verse FROM notes WHERE LOWER(title) LIKE ? OR LOWER(body) LIKE ? ORDER BY updated_at DESC LIMIT \(safeLimit);",
            params: [.string(pat), .string(pat)]
        ) {
            for row in res.rows {
                let nid = row.string(at: 0) ?? ""
                hits.append(PersonalSearchHit(
                    id: "note-\(nid)",
                    kind: row.string(at: 1) ?? "Note",
                    title: row.string(at: 2) ?? "",
                    snippet: row.string(at: 3) ?? "",
                    bookId: row.isNull(at: 4) ? nil : row.int(at: 4).map(Int.init),
                    chapter: row.isNull(at: 5) ? nil : row.int(at: 5).map(Int.init),
                    verse: row.isNull(at: 6) ? nil : row.int(at: 6).map(Int.init),
                    noteId: nid
                ))
            }
        }

        if let res = try? db.queryParams(
            "SELECT id, source_label, excerpt, user_note, book_id, chapter FROM journal_clips WHERE LOWER(source_label) LIKE ? OR LOWER(excerpt) LIKE ? OR LOWER(user_note) LIKE ? ORDER BY updated_at DESC LIMIT \(safeLimit);",
            params: [.string(pat), .string(pat), .string(pat)]
        ) {
            for row in res.rows {
                let cid = row.string(at: 0) ?? ""
                let ex = row.string(at: 2) ?? ""
                let un = row.string(at: 3) ?? ""
                hits.append(PersonalSearchHit(
                    id: "clip-\(cid)",
                    kind: "Journal Clip",
                    title: row.string(at: 1) ?? "",
                    snippet: un.isEmpty ? ex : "\(ex) — \(un)",
                    bookId: Int(row.int(at: 4) ?? 0),
                    chapter: Int(row.int(at: 5) ?? 0),
                    verse: nil,
                    noteId: nil
                ))
            }
        }

        if let res = try? db.queryParams(
            "SELECT id, label, book_id, chapter, verse FROM bookmarks WHERE LOWER(label) LIKE ? ORDER BY created_at DESC LIMIT \(safeLimit);",
            params: [.string(pat)]
        ) {
            for row in res.rows {
                hits.append(PersonalSearchHit(
                    id: "bm-\(row.string(at: 0) ?? "")",
                    kind: "Bookmark",
                    title: row.string(at: 1) ?? "",
                    snippet: "",
                    bookId: Int(row.int(at: 2) ?? 0),
                    chapter: Int(row.int(at: 3) ?? 0),
                    verse: Int(row.int(at: 4) ?? 0),
                    noteId: nil
                ))
            }
        }

        // Named Study Sessions
        if let res = try? db.queryParams(
            "SELECT id, name, summary_note, start_book_id, start_chapter, start_verse FROM study_sessions WHERE LOWER(name) LIKE ? OR LOWER(summary_note) LIKE ? ORDER BY updated_at DESC LIMIT \(safeLimit);",
            params: [.string(pat), .string(pat)]
        ) {
            for row in res.rows {
                let sid = row.string(at: 0) ?? ""
                hits.append(PersonalSearchHit(
                    id: "study-\(sid)",
                    kind: "Study",
                    title: row.string(at: 1) ?? "",
                    snippet: row.string(at: 2) ?? "",
                    bookId: Int(row.int(at: 3) ?? 1),
                    chapter: Int(row.int(at: 4) ?? 1),
                    verse: row.isNull(at: 5) ? nil : row.int(at: 5).map(Int.init),
                    noteId: nil,
                    studyId: sid
                ))
            }
        }

        // Study Trail Entries
        if let res = try? db.queryParams(
            "SELECT e.id, e.study_id, COALESCE(s.name, 'Study'), e.title, e.detail, e.book_id, e.chapter, e.verse FROM study_trail_entries e LEFT JOIN study_sessions s ON s.id = e.study_id WHERE LOWER(e.title) LIKE ? OR LOWER(e.detail) LIKE ? ORDER BY e.created_at DESC LIMIT \(safeLimit);",
            params: [.string(pat), .string(pat)]
        ) {
            for row in res.rows {
                let eid = row.string(at: 0) ?? ""
                let sid = row.string(at: 1) ?? ""
                let sName = row.string(at: 2) ?? "Study"
                let det = row.string(at: 4) ?? ""
                hits.append(PersonalSearchHit(
                    id: "trail-\(eid)",
                    kind: "Study: \(sName)",
                    title: row.string(at: 3) ?? "",
                    snippet: det,
                    bookId: row.isNull(at: 5) ? nil : row.int(at: 5).map(Int.init),
                    chapter: row.isNull(at: 6) ? nil : row.int(at: 6).map(Int.init),
                    verse: row.isNull(at: 7) ? nil : row.int(at: 7).map(Int.init),
                    noteId: nil,
                    studyId: sid
                ))
            }
        }
        return hits
    }

    public func studyTrailCounts() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.query("SELECT study_id FROM study_trail_entries;") else { return [:] }
        var counts: [String: Int] = [:]
        for row in res.rows {
            if let sid = row.string(at: 0), !sid.isEmpty {
                counts[sid, default: 0] += 1
            }
        }
        return counts
    }

    public func studyMarginLinkCounts() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.query("SELECT study_id FROM study_margin_links;") else { return [:] }
        var counts: [String: Int] = [:]
        for row in res.rows {
            if let sid = row.string(at: 0), !sid.isEmpty {
                counts[sid, default: 0] += 1
            }
        }
        return counts
    }

    public func studyIdsMatchingTrail(query raw: String) -> Set<String> {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let pat = "%\(q.lowercased())%"
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.queryParams(
                  "SELECT DISTINCT study_id FROM study_trail_entries WHERE LOWER(title) LIKE ? OR LOWER(detail) LIKE ?;",
                  params: [.string(pat), .string(pat)]
              ) else { return [] }
        return Set(res.rows.compactMap { $0.string(at: 0) })
    }

    // MARK: - Named Study Sessions ("Study Trails") & Permanent Bible Ink Links

    public func allStudySessions() -> [StudySession] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.query("SELECT id, name, start_book_id, start_chapter, start_verse, summary_note, created_at, updated_at FROM study_sessions ORDER BY updated_at DESC;") else {
            return []
        }
        return res.rows.map { row in
            StudySession(
                id: row.string(at: 0) ?? "",
                name: row.string(at: 1) ?? "",
                startBookId: Int(row.int(at: 2) ?? 1),
                startChapter: Int(row.int(at: 3) ?? 1),
                startVerse: row.isNull(at: 4) ? nil : row.int(at: 4).map(Int.init),
                summaryNote: row.string(at: 5) ?? "",
                createdAt: row.string(at: 6) ?? "",
                updatedAt: row.string(at: 7) ?? ""
            )
        }
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
        let vParam: MagQLiteParam = startVerse.map { .int(Int64($0)) } ?? .null
        _ = try? db.queryParams(
            "INSERT INTO study_sessions (id, name, start_book_id, start_chapter, start_verse, summary_note, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
            params: [.string(session.id), .string(session.name), .int(Int64(startBookId)), .int(Int64(startChapter)), vParam, .string(summaryNote), .string(now), .string(now)]
        )
        return session
    }

    public func updateStudySession(id: String, name: String, summaryNote: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams(
            "UPDATE study_sessions SET name = ?, summary_note = ?, updated_at = ? WHERE id = ?;",
            params: [.string(name.isEmpty ? "Untitled Study" : name), .string(summaryNote), .string(Self.isoNow()), .string(id)]
        )
    }

    public func deleteStudySession(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        for table in ["study_trail_entries", "study_margin_links", "study_ink_annotations", "pinned_references", "journal_clips"] {
            _ = try? db.queryParams("DELETE FROM \(table) WHERE study_id = ?;", params: [.string(id)])
        }
        _ = try? db.queryParams("DELETE FROM placed_stickers WHERE target_type = 'study_chapter' AND target_key LIKE ?;", params: [.string("\(id)-%")])
        _ = try? db.queryParams("DELETE FROM study_sessions WHERE id = ?;", params: [.string(id)])
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

        if let lastRes = try? db.queryParams(
            "SELECT id, kind, title, book_id, chapter FROM study_trail_entries WHERE study_id = ? ORDER BY created_at DESC LIMIT 1;",
            params: [.string(studyId)]
        ), let lastRow = lastRes.rows.first {
            let lastId = lastRow.string(at: 0) ?? ""
            let lastKind = lastRow.string(at: 1) ?? ""
            let lastTitle = lastRow.string(at: 2) ?? ""
            let lastB: Int? = lastRow.isNull(at: 3) ? nil : lastRow.int(at: 3).map(Int.init)
            let lastC: Int? = lastRow.isNull(at: 4) ? nil : lastRow.int(at: 4).map(Int.init)
            if lastKind == kind.rawValue && ((kind == .passage && lastB == bookId && lastC == chapter) || lastTitle == title) {
                return lastId
            }
        }

        let eid = UUID().uuidString
        let now = Self.isoNow()
        _ = try? db.queryParams(
            "INSERT INTO study_trail_entries (id, study_id, kind, title, detail, book_id, chapter, verse, ref_key, duration_seconds, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?);",
            params: [
                .string(eid), .string(studyId), .string(kind.rawValue), .string(title), .string(detail),
                bookId.map { .int(Int64($0)) } ?? .null,
                chapter.map { .int(Int64($0)) } ?? .null,
                verse.map { .int(Int64($0)) } ?? .null,
                refKey.map { .string($0) } ?? .null,
                .string(now)
            ]
        )
        _ = try? db.queryParams("UPDATE study_sessions SET updated_at = ? WHERE id = ?;", params: [.string(now), .string(studyId)])
        return eid
    }

    public func addStudyTrailDuration(entryId: String, seconds: Int) {
        guard seconds > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("UPDATE study_trail_entries SET duration_seconds = duration_seconds + ? WHERE id = ?;", params: [.int(Int64(seconds)), .string(entryId)])
    }

    public func studyTrailEntries(studyId: String) -> [StudyTrailEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.queryParams(
                  "SELECT id, study_id, kind, title, detail, book_id, chapter, verse, ref_key, duration_seconds, created_at FROM study_trail_entries WHERE study_id = ? ORDER BY created_at DESC;",
                  params: [.string(studyId)]
              ) else { return [] }
        return res.rows.map { row in
            StudyTrailEntry(
                id: row.string(at: 0) ?? "",
                studyId: row.string(at: 1) ?? "",
                kind: StudyTrailKind(rawValue: row.string(at: 2) ?? "") ?? .passage,
                title: row.string(at: 3) ?? "",
                detail: row.string(at: 4) ?? "",
                bookId: row.isNull(at: 5) ? nil : row.int(at: 5).map(Int.init),
                chapter: row.isNull(at: 6) ? nil : row.int(at: 6).map(Int.init),
                verse: row.isNull(at: 7) ? nil : row.int(at: 7).map(Int.init),
                refKey: row.isNull(at: 8) ? nil : row.string(at: 8),
                durationSeconds: Int(row.int(at: 9) ?? 0),
                createdAt: row.string(at: 10) ?? ""
            )
        }
    }

    public func deleteStudyTrailEntry(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM study_trail_entries WHERE id = ?;", params: [.string(id)])
    }

    public func studyMarginLinks(studyId: String) -> [StudyMarginLink] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.queryParams(
                  """
                  SELECT l.id, l.study_id, COALESCE(s.name, 'Study'), l.book_id, l.chapter, l.verse, l.note_text, l.pos_x, l.pos_y, l.updated_at
                  FROM study_margin_links l
                  LEFT JOIN study_sessions s ON s.id = l.study_id
                  WHERE l.study_id = ?
                  ORDER BY l.updated_at ASC;
                  """,
                  params: [.string(studyId)]
              ) else { return [] }
        return res.rows.map(Self.readStudyMarginLinkRow)
    }

    public func studyMarginLinks(bookId: Int, chapter: Int) -> [StudyMarginLink] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.queryParams(
                  """
                  SELECT l.id, l.study_id, COALESCE(s.name, 'Study'), l.book_id, l.chapter, l.verse, l.note_text, l.pos_x, l.pos_y, l.updated_at
                  FROM study_margin_links l
                  LEFT JOIN study_sessions s ON s.id = l.study_id
                  WHERE l.book_id = ? AND l.chapter = ?
                  ORDER BY l.updated_at ASC;
                  """,
                  params: [.int(Int64(bookId)), .int(Int64(chapter))]
              ) else { return [] }
        return res.rows.map(Self.readStudyMarginLinkRow)
    }

    private static func readStudyMarginLinkRow(_ row: MagQLiteRow) -> StudyMarginLink {
        StudyMarginLink(
            id: row.string(at: 0) ?? "",
            studyId: row.string(at: 1) ?? "",
            studyName: row.string(at: 2) ?? "Study",
            bookId: Int(row.int(at: 3) ?? 1),
            chapter: Int(row.int(at: 4) ?? 1),
            verse: row.isNull(at: 5) ? nil : row.int(at: 5).map(Int.init),
            noteText: row.string(at: 6) ?? "",
            posX: row.double(at: 7) ?? 0,
            posY: row.double(at: 8) ?? 0,
            updatedAt: row.string(at: 9) ?? ""
        )
    }

    public func upsertStudyMarginLink(_ link: StudyMarginLink) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM study_margin_links WHERE id = ?;", params: [.string(link.id)])
        _ = try? db.queryParams(
            "INSERT INTO study_margin_links (id, study_id, book_id, chapter, verse, note_text, pos_x, pos_y, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
            params: [
                .string(link.id), .string(link.studyId), .int(Int64(link.bookId)), .int(Int64(link.chapter)),
                link.verse.map { .int(Int64($0)) } ?? .null,
                .string(link.noteText), .double(link.posX), .double(link.posY), .string(Self.isoNow())
            ]
        )
    }

    public func deleteStudyMarginLink(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM study_margin_links WHERE id = ?;", params: [.string(id)])
    }

    // MARK: - Stickers Library & Placed Stickers

    private func seedDefaultStickersUnlocked() {
        guard let db else { return }
        if let res = try? db.query("SELECT COUNT(*) FROM sticker_library;"),
           let cnt = res.rows.first?.int(at: 0), cnt > 0 {
            return
        }
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
            _ = try? db.queryParams(
                "INSERT INTO sticker_library (id, name, kind, category, symbol_name, tint_hex, image_blob, pk_drawing_blob, created_at) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, ?);",
                params: [.string(id), .string(name), .string(StickerKind.symbol.rawValue), .string("Bible Study"), .string(sym), .string(hex), .string(now)]
            )
        }
    }

    public func allStickers() -> [StickerItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.query("SELECT id, name, kind, category, symbol_name, tint_hex, image_blob, pk_drawing_blob, created_at FROM sticker_library ORDER BY CASE WHEN kind = 'drawn' THEN 0 WHEN kind = 'imported' THEN 1 ELSE 2 END, created_at DESC;") else {
            return []
        }
        return res.rows.map { row in
            StickerItem(
                id: row.string(at: 0) ?? "",
                name: row.string(at: 1) ?? "",
                kind: StickerKind(rawValue: row.string(at: 2) ?? "") ?? .symbol,
                category: row.string(at: 3) ?? "",
                symbolName: row.isNull(at: 4) ? nil : row.string(at: 4),
                tintHex: row.isNull(at: 5) ? nil : row.string(at: 5),
                imageData: row.isNull(at: 6) ? nil : row.blob(at: 6),
                drawingData: row.isNull(at: 7) ? nil : row.blob(at: 7),
                createdAt: row.string(at: 8) ?? ""
            )
        }
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
        let drawParam: MagQLiteParam = (drawingData != nil && !drawingData!.isEmpty) ? .blob(drawingData!) : .null
        _ = try? db.queryParams(
            "INSERT INTO sticker_library (id, name, kind, category, symbol_name, tint_hex, image_blob, pk_drawing_blob, created_at) VALUES (?, ?, ?, ?, NULL, NULL, ?, ?, ?);",
            params: [.string(item.id), .string(item.name), .string(item.kind.rawValue), .string(item.category), .blob(imageData), drawParam, .string(now)]
        )
        return item
    }

    public func updateCustomSticker(id: String, name: String, imageData: Data, drawingData: Data?) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        let drawParam: MagQLiteParam = (drawingData != nil && !drawingData!.isEmpty) ? .blob(drawingData!) : .null
        _ = try? db.queryParams(
            "UPDATE sticker_library SET name = ?, image_blob = ?, pk_drawing_blob = ? WHERE id = ?;",
            params: [.string(name.isEmpty ? "Sticker" : name), .blob(imageData), drawParam, .string(id)]
        )
    }

    public func deleteStickerFromLibrary(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM sticker_library WHERE id = ?;", params: [.string(id)])
        _ = try? db.queryParams("DELETE FROM placed_stickers WHERE sticker_id = ?;", params: [.string(id)])
    }

    public func placedStickers(targetType: String, targetKey: String) -> [PlacedSticker] {
        lock.lock()
        defer { lock.unlock() }
        guard let db,
              let res = try? db.queryParams(
                  "SELECT id, sticker_id, target_type, target_key, pos_x, pos_y, width, height, rotation, opacity, updated_at FROM placed_stickers WHERE target_type = ? AND target_key = ? ORDER BY updated_at ASC;",
                  params: [.string(targetType), .string(targetKey)]
              ) else { return [] }
        return res.rows.map { row in
            PlacedSticker(
                id: row.string(at: 0) ?? "",
                stickerId: row.string(at: 1) ?? "",
                targetType: row.string(at: 2) ?? "",
                targetKey: row.string(at: 3) ?? "",
                posX: row.double(at: 4) ?? 0,
                posY: row.double(at: 5) ?? 0,
                width: row.double(at: 6) ?? 72,
                height: row.double(at: 7) ?? 72,
                rotation: row.double(at: 8) ?? 0,
                opacity: row.double(at: 9) ?? 1.0,
                updatedAt: row.string(at: 10) ?? ""
            )
        }
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
        _ = try? db.queryParams(
            "INSERT INTO placed_stickers (id, sticker_id, target_type, target_key, pos_x, pos_y, width, height, rotation, opacity, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
            params: [
                .string(placed.id), .string(placed.stickerId), .string(placed.targetType), .string(placed.targetKey),
                .double(placed.posX), .double(placed.posY), .double(placed.width), .double(placed.height),
                .double(placed.rotation), .double(placed.opacity), .string(now)
            ]
        )
        return placed
    }

    public func updatePlacedSticker(id: String, posX: Double, posY: Double, width: Double, height: Double, rotation: Double, opacity: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams(
            "UPDATE placed_stickers SET pos_x = ?, pos_y = ?, width = ?, height = ?, rotation = ?, opacity = ?, updated_at = ? WHERE id = ?;",
            params: [.double(posX), .double(posY), .double(width), .double(height), .double(rotation), .double(opacity), .string(Self.isoNow()), .string(id)]
        )
    }

    public func deletePlacedSticker(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = try? db.queryParams("DELETE FROM placed_stickers WHERE id = ?;", params: [.string(id)])
    }

    // MARK: - 1-Click MagQLite Hot Backup (`BACKUP TO`) & Dual-Format Restore (.mql + legacy .sqlite)

    public func createBackupSnapshot() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let fname = "SwordAndQuill-Backup-\(df.string(from: Date())).mql"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(fname)
        try? FileManager.default.removeItem(at: dest)
        do {
            _ = try db.backup(to: dest.path)
            return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
        } catch {
            return nil
        }
    }

    public enum RestoreError: LocalizedError {
        case cannotOpenSource
        case invalidBackupSchema
        case backupCopyFailed

        public var errorDescription: String? {
            switch self {
            case .cannotOpenSource: return "Could not open the selected backup file."
            case .invalidBackupSchema: return "This file is not a valid Sword & Quill Study Bible backup (.mql or .sqlite)."
            case .backupCopyFailed: return "Restore failed while copying study data. Your previous data is untouched."
            }
        }
    }

    public func restoreFromBackup(url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let tmpCopy = FileManager.default.temporaryDirectory.appendingPathComponent("sq-restore-\(UUID().uuidString).\(ext.isEmpty ? "mql" : ext)")
        try? FileManager.default.removeItem(at: tmpCopy)
        try FileManager.default.copyItem(at: url, to: tmpCopy)
        defer {
            try? FileManager.default.removeItem(at: tmpCopy)
            try? FileManager.default.removeItem(atPath: tmpCopy.path + ".wal")
            try? FileManager.default.removeItem(atPath: tmpCopy.path + ".lock")
        }

        // Support legacy .sqlite backups seamlessly!
        if ext == "sqlite" || ext == "db" {
            lock.lock()
            defer { lock.unlock() }
            if let db {
                let safetyDest = FileManager.default.temporaryDirectory.appendingPathComponent("SwordAndQuill-PreRestore-Safety.mql")
                try? FileManager.default.removeItem(at: safetyDest)
                _ = try? db.backup(to: safetyDest.path)
            }
            guard importFromSQLiteUnlocked(sqliteURL: tmpCopy) else {
                throw RestoreError.invalidBackupSchema
            }
            _ = try? db?.query("CHECKPOINT;")
            return
        }

        // Validate .mql backup by opening it and verifying expected tables
        guard let testDB = try? MagQLite(path: tmpCopy.path, config: Self.dbConfig) else {
            throw RestoreError.cannotOpenSource
        }
        let hasInk = (try? testDB.query("SELECT COUNT(*) FROM ink_annotations;")) != nil
        let hasHl = (try? testDB.query("SELECT COUNT(*) FROM text_highlights;")) != nil
        let hasNotes = (try? testDB.query("SELECT COUNT(*) FROM notes;")) != nil
        testDB.close()
        guard hasInk && hasHl && hasNotes else {
            throw RestoreError.invalidBackupSchema
        }

        lock.lock()
        defer { lock.unlock() }

        // Atomic safety snapshot before overwriting
        if let db {
            let safetyDest = FileManager.default.temporaryDirectory.appendingPathComponent("SwordAndQuill-PreRestore-Safety.mql")
            try? FileManager.default.removeItem(at: safetyDest)
            _ = try? db.backup(to: safetyDest.path)
            db.close()
            self.db = nil
        }

        let fm = FileManager.default
        try? fm.removeItem(at: dbURL)
        try? fm.removeItem(atPath: dbURL.path + ".wal")
        try? fm.removeItem(atPath: dbURL.path + ".lock")
        try fm.copyItem(at: tmpCopy, to: dbURL)

        guard let reopened = try? MagQLite(path: dbURL.path, config: Self.dbConfig) else {
            throw RestoreError.backupCopyFailed
        }
        self.db = reopened
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
            guard let res = try? db.query(sql), let n = res.rows.first?.int(at: 0) else { return 0 }
            return Int(n)
        }

        let inkCount = countQuery("SELECT COUNT(*) FROM ink_annotations;")
        let hlCount = countQuery("SELECT COUNT(*) FROM text_highlights;")
        let noteCount = countQuery("SELECT COUNT(*) FROM notes;")
        let bmCount = countQuery("SELECT COUNT(*) FROM bookmarks;")
        let clipCount = countQuery("SELECT COUNT(*) FROM journal_clips;")
        let pinCount = countQuery("SELECT COUNT(*) FROM pinned_references;")
        let stickerCount = countQuery("SELECT COUNT(*) FROM sticker_library WHERE kind != 'symbol';")

        var visitedSet = Set<String>()
        if let vRes = try? db.query("SELECT DISTINCT book_id, chapter FROM nav_history;") {
            for r in vRes.rows {
                visitedSet.insert("\(r.int(at: 0) ?? 0):\(r.int(at: 1) ?? 0)")
            }
        }

        var bookCounts: [Int: Int] = [:]
        for q in [
            "SELECT book_id FROM ink_annotations;",
            "SELECT book_id FROM text_highlights;",
            "SELECT book_id FROM bookmarks;",
            "SELECT book_id FROM journal_clips;",
            "SELECT book_id FROM notes WHERE book_id IS NOT NULL;"
        ] {
            if let res = try? db.query(q) {
                for r in res.rows {
                    if let bid = r.int(at: 0), bid > 0 {
                        bookCounts[Int(bid), default: 0] += 1
                    }
                }
            }
        }
        let topBooks = bookCounts
            .map { BookStudyCount(bookId: $0.key, itemCount: $0.value) }
            .sorted { $0.itemCount > $1.itemCount }
            .prefix(6)

        return StudyDashboardStats(
            chaptersWithInk: inkCount,
            highlightedVerses: hlCount,
            notebookCount: noteCount,
            bookmarkCount: bmCount,
            clipCount: clipCount,
            pinnedRefCount: pinCount,
            customStickerCount: stickerCount,
            uniqueChaptersVisited: visitedSet.count,
            topBooks: Array(topBooks)
        )
    }
}
