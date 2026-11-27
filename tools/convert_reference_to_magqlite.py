#!/usr/bin/env python3
"""
Convert kjv_reference.sqlite into MagQLite format (kjv_reference.mql + kjv_reference.mql.pages)
using paged_storage=True and single-column INT keys (bc_key, bcv_key) for sub-millisecond
O(log N) on-disk B+Tree lookups on iPadOS.
"""
import os
import sqlite3
import sys
import time
from pathlib import Path

MAGQLITE_PY_DIR = r"o:\phpLaragon\www\aiplay\magqlite\packages\python"
MAGQLITE_DLL = r"o:\phpLaragon\www\aiplay\magqlite\target\release\magqlite_ffi.dll"

if os.path.isdir(MAGQLITE_PY_DIR):
    sys.path.insert(0, MAGQLITE_PY_DIR)

from magqlite import MagQLite


def sql_literal(val) -> str:
    if val is None:
        return "NULL"
    if isinstance(val, bool):
        return "TRUE" if val else "FALSE"
    if isinstance(val, (int, float)):
        return repr(val)
    s = str(val).replace("\x00", "").replace("'", "''")
    return f"'{s}'"


SCHEMA_STATEMENTS = [
    """CREATE TABLE metadata (
        key TEXT NOT NULL,
        value TEXT NOT NULL
    );""",
    """CREATE TABLE books (
        id INT NOT NULL,
        name TEXT NOT NULL,
        abbr TEXT NOT NULL,
        testament TEXT NOT NULL,
        chapter_count INT NOT NULL
    );""",
    """CREATE TABLE verses (
        id INT NOT NULL,
        book_id INT NOT NULL,
        chapter INT NOT NULL,
        verse INT NOT NULL,
        bc_key INT NOT NULL,
        bcv_key INT NOT NULL,
        text_plain TEXT NOT NULL,
        text_marked TEXT NOT NULL
    );""",
    """CREATE TABLE tsk_cross_refs (
        id INT NOT NULL,
        from_book INT NOT NULL,
        from_chapter INT NOT NULL,
        from_verse INT NOT NULL,
        from_bc_key INT NOT NULL,
        phrase TEXT NOT NULL,
        to_book INT NOT NULL,
        to_chapter INT NOT NULL,
        to_verse_start INT NOT NULL,
        to_verse_end INT NOT NULL,
        sort_order INT NOT NULL
    );""",
    """CREATE TABLE strongs_lexicon (
        strongs_id TEXT NOT NULL,
        testament TEXT NOT NULL,
        lemma TEXT NOT NULL,
        translit TEXT NOT NULL,
        pronunciation TEXT NOT NULL,
        derivation TEXT NOT NULL,
        definition TEXT NOT NULL,
        kjv_usage TEXT NOT NULL
    );""",
    """CREATE TABLE webster_1828 (
        id INT NOT NULL,
        headword TEXT NOT NULL,
        headword_norm TEXT NOT NULL,
        definition TEXT NOT NULL
    );""",
    """CREATE TABLE interlinear_words (
        id INT NOT NULL,
        book_id INT NOT NULL,
        chapter INT NOT NULL,
        verse INT NOT NULL,
        bcv_key INT NOT NULL,
        word_pos INT NOT NULL,
        original_text TEXT NOT NULL,
        translit TEXT NOT NULL,
        gloss TEXT NOT NULL,
        strongs_id TEXT NOT NULL,
        morph TEXT NOT NULL
    );""",
    """CREATE TABLE biblical_places (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        name_norm TEXT NOT NULL,
        place_type TEXT NOT NULL,
        modern_name TEXT NOT NULL,
        description TEXT NOT NULL,
        lat FLOAT NOT NULL,
        lon FLOAT NOT NULL,
        verse_count INT NOT NULL
    );""",
    """CREATE TABLE place_verses (
        place_id TEXT NOT NULL,
        book_id INT NOT NULL,
        chapter INT NOT NULL,
        verse INT NOT NULL,
        bc_key INT NOT NULL,
        bcv_key INT NOT NULL
    );""",
    """CREATE TABLE study_dictionaries (
        id INT NOT NULL,
        source TEXT NOT NULL,
        headword TEXT NOT NULL,
        headword_norm TEXT NOT NULL,
        body TEXT NOT NULL
    );""",
]

INDEX_STATEMENTS = [
    "CREATE INDEX idx_books_id ON books (id);",
    "CREATE INDEX idx_verses_id ON verses (id);",
    "CREATE INDEX idx_verses_bc ON verses (bc_key);",
    "CREATE INDEX idx_verses_bcv ON verses (bcv_key);",
    "CREATE INDEX idx_tsk_from_bc ON tsk_cross_refs (from_bc_key);",
    "CREATE INDEX idx_strongs_id ON strongs_lexicon (strongs_id);",
    "CREATE INDEX idx_webster_norm ON webster_1828 (headword_norm);",
    "CREATE INDEX idx_interlinear_bcv ON interlinear_words (bcv_key);",
    "CREATE INDEX idx_interlinear_strongs ON interlinear_words (strongs_id);",
    "CREATE INDEX idx_places_id ON biblical_places (id);",
    "CREATE INDEX idx_places_name_norm ON biblical_places (name_norm);",
    "CREATE INDEX idx_place_verses_bc ON place_verses (bc_key);",
    "CREATE INDEX idx_place_verses_bcv ON place_verses (bcv_key);",
    "CREATE INDEX idx_place_verses_pid ON place_verses (place_id);",
    "CREATE INDEX idx_studydict_norm ON study_dictionaries (headword_norm);",
    "CREATE INDEX idx_studydict_src ON study_dictionaries (source);",
]

# (table_name, dst_cols, select_sql)
TABLES = [
    ("metadata", ["key", "value"], "SELECT key, value FROM metadata"),
    ("books", ["id", "name", "abbr", "testament", "chapter_count"], "SELECT id, name, abbr, testament, chapter_count FROM books"),
    (
        "verses",
        ["id", "book_id", "chapter", "verse", "bc_key", "bcv_key", "text_plain", "text_marked"],
        "SELECT id, book_id, chapter, verse, book_id * 1000 + chapter, book_id * 1000000 + chapter * 1000 + verse, text_plain, text_marked FROM verses",
    ),
    (
        "tsk_cross_refs",
        ["id", "from_book", "from_chapter", "from_verse", "from_bc_key", "phrase", "to_book", "to_chapter", "to_verse_start", "to_verse_end", "sort_order"],
        "SELECT id, from_book, from_chapter, from_verse, from_book * 1000 + from_chapter, phrase, to_book, to_chapter, to_verse_start, to_verse_end, sort_order FROM tsk_cross_refs",
    ),
    ("strongs_lexicon", ["strongs_id", "testament", "lemma", "translit", "pronunciation", "derivation", "definition", "kjv_usage"], "SELECT strongs_id, testament, lemma, translit, pronunciation, derivation, definition, kjv_usage FROM strongs_lexicon"),
    ("webster_1828", ["id", "headword", "headword_norm", "definition"], "SELECT id, headword, headword_norm, definition FROM webster_1828"),
    (
        "interlinear_words",
        ["id", "book_id", "chapter", "verse", "bcv_key", "word_pos", "original_text", "translit", "gloss", "strongs_id", "morph"],
        "SELECT id, book_id, chapter, verse, book_id * 1000000 + chapter * 1000 + verse, word_pos, original_text, translit, gloss, strongs_id, morph FROM interlinear_words",
    ),
    ("biblical_places", ["id", "name", "name_norm", "place_type", "modern_name", "description", "lat", "lon", "verse_count"], "SELECT id, name, name_norm, place_type, modern_name, description, lat, lon, verse_count FROM biblical_places"),
    (
        "place_verses",
        ["place_id", "book_id", "chapter", "verse", "bc_key", "bcv_key"],
        "SELECT place_id, book_id, chapter, verse, book_id * 1000 + chapter, book_id * 1000000 + chapter * 1000 + verse FROM place_verses",
    ),
    ("study_dictionaries", ["id", "source", "headword", "headword_norm", "body"], "SELECT id, source, headword, headword_norm, body FROM study_dictionaries"),
]


def convert(sqlite_path: Path, mql_path: Path, batch_size: int = 5000):
    t0 = time.perf_counter()
    for ext in ("", ".wal", ".pages", ".lock"):
        p = Path(str(mql_path) + ext)
        if p.exists():
            p.unlink()

    src = sqlite3.connect(f"file:{sqlite_path}?mode=ro", uri=True)
    cur = src.cursor()

    cfg = {
        "paged_storage": True,
        "durability": "off",
        "auto_checkpoint_frames": 0,
        "buffer_pool_pages": 4096,
    }
    lib_path = MAGQLITE_DLL if os.path.exists(MAGQLITE_DLL) else None

    with MagQLite(str(mql_path), config=cfg, lib_path=lib_path) as dst:
        print(f"MagQLite modules: {dst.modules()}", flush=True)
        for stmt in SCHEMA_STATEMENTS:
            dst.query(stmt)
        print("Created schema.", flush=True)

        for table, cols, select_sql in TABLES:
            ts = time.perf_counter()
            col_list = ", ".join(cols)
            cur.execute(select_sql)
            total = 0
            while True:
                rows = cur.fetchmany(batch_size)
                if not rows:
                    break
                values_sql = ", ".join(
                    "(" + ", ".join(sql_literal(v) for v in row) + ")"
                    for row in rows
                )
                dst.query(f"INSERT INTO {table} ({col_list}) VALUES {values_sql};")
                total += len(rows)
                if total % 50000 < batch_size and total >= 50000:
                    print(f"  {table}: {total:,} rows ({time.perf_counter() - ts:.1f}s)...", flush=True)
            print(f"  [OK] {table}: {total:,} rows in {time.perf_counter() - ts:.2f}s", flush=True)

        print("Building indexes...", flush=True)
        for idx_sql in INDEX_STATEMENTS:
            ti = time.perf_counter()
            dst.query(idx_sql)
            print(f"  [OK] {idx_sql.split()[2]} ({time.perf_counter() - ti:.2f}s)", flush=True)

        print("Running CHECKPOINT...", flush=True)
        tc = time.perf_counter()
        dst.query("CHECKPOINT;")
        print(f"  [OK] CHECKPOINT complete ({time.perf_counter() - tc:.2f}s)", flush=True)

    src.close()
    elapsed = time.perf_counter() - t0
    mql_size = mql_path.stat().st_size if mql_path.exists() else 0
    pages_path = Path(str(mql_path) + ".pages")
    pages_size = pages_path.stat().st_size if pages_path.exists() else 0
    print(
        f"DONE in {elapsed:.1f}s! kjv_reference.mql={mql_size / 1_048_576:.2f} MiB, "
        f"kjv_reference.mql.pages={pages_size / 1_048_576:.2f} MiB",
        flush=True,
    )


if __name__ == "__main__":
    src_arg = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"\\10.69.1.194\development\bible-app\Sources\KJVStudyBible\Resources\kjv_reference.sqlite")
    dst_arg = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"kjv_reference.mql")
    dst_arg.parent.mkdir(parents=True, exist_ok=True)
    convert(src_arg, dst_arg)
