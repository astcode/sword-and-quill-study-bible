#!/usr/bin/env python3
"""Build and validate immutable kjv_reference.sqlite from local resource archives."""
import csv
import html
import json
import re
import sqlite3
import struct
import sys
import time
import zipfile
import zlib
from datetime import datetime, timezone
from pathlib import Path

RESOURCES_DIR = Path("/home/aaron/development/docs/resources")
OUT_DB = Path("/home/aaron/development/bible-app/Sources/KJVStudyBible/Resources/kjv_reference.sqlite")

BOOKS = [
    (1, "Genesis", "Gen", "OT"), (2, "Exodus", "Exod", "OT"), (3, "Leviticus", "Lev", "OT"),
    (4, "Numbers", "Num", "OT"), (5, "Deuteronomy", "Deut", "OT"), (6, "Joshua", "Josh", "OT"),
    (7, "Judges", "Judg", "OT"), (8, "Ruth", "Ruth", "OT"), (9, "1 Samuel", "1Sam", "OT"),
    (10, "2 Samuel", "2Sam", "OT"), (11, "1 Kings", "1Kgs", "OT"), (12, "2 Kings", "2Kgs", "OT"),
    (13, "1 Chronicles", "1Chr", "OT"), (14, "2 Chronicles", "2Chr", "OT"), (15, "Ezra", "Ezra", "OT"),
    (16, "Nehemiah", "Neh", "OT"), (17, "Esther", "Esth", "OT"), (18, "Job", "Job", "OT"),
    (19, "Psalms", "Ps", "OT"), (20, "Proverbs", "Prov", "OT"), (21, "Ecclesiastes", "Eccl", "OT"),
    (22, "Song of Solomon", "Song", "OT"), (23, "Isaiah", "Isa", "OT"), (24, "Jeremiah", "Jer", "OT"),
    (25, "Lamentations", "Lam", "OT"), (26, "Ezekiel", "Ezek", "OT"), (27, "Daniel", "Dan", "OT"),
    (28, "Hosea", "Hos", "OT"), (29, "Joel", "Joel", "OT"), (30, "Amos", "Amos", "OT"),
    (31, "Obadiah", "Obad", "OT"), (32, "Jonah", "Jonah", "OT"), (33, "Micah", "Mic", "OT"),
    (34, "Nahum", "Nah", "OT"), (35, "Habakkuk", "Hab", "OT"), (36, "Zephaniah", "Zeph", "OT"),
    (37, "Haggai", "Hag", "OT"), (38, "Zechariah", "Zech", "OT"), (39, "Malachi", "Mal", "OT"),
    (40, "Matthew", "Matt", "NT"), (41, "Mark", "Mark", "NT"), (42, "Luke", "Luke", "NT"),
    (43, "John", "John", "NT"), (44, "Acts", "Acts", "NT"), (45, "Romans", "Rom", "NT"),
    (46, "1 Corinthians", "1Cor", "NT"), (47, "2 Corinthians", "2Cor", "NT"), (48, "Galatians", "Gal", "NT"),
    (49, "Ephesians", "Eph", "NT"), (50, "Philippians", "Phil", "NT"), (51, "Colossians", "Col", "NT"),
    (52, "1 Thessalonians", "1Thess", "NT"), (53, "2 Thessalonians", "2Thess", "NT"),
    (54, "1 Timothy", "1Tim", "NT"), (55, "2 Timothy", "2Tim", "NT"), (56, "Titus", "Titus", "NT"),
    (57, "Philemon", "Phlm", "NT"), (58, "Hebrews", "Heb", "NT"), (59, "James", "Jas", "NT"),
    (60, "1 Peter", "1Pet", "NT"), (61, "2 Peter", "2Pet", "NT"), (62, "1 John", "1John", "NT"),
    (63, "2 John", "2John", "NT"), (64, "3 John", "3John", "NT"), (65, "Jude", "Jude", "NT"),
    (66, "Revelation", "Rev", "NT"),
]

STEP_BOOK_MAP = {
    "Gen": 1, "Exo": 2, "Lev": 3, "Num": 4, "Deu": 5, "Jos": 6, "Jdg": 7, "Rut": 8,
    "1Sa": 9, "2Sa": 10, "1Ki": 11, "2Ki": 12, "1Ch": 13, "2Ch": 14, "Ezr": 15, "Neh": 16,
    "Est": 17, "Job": 18, "Psa": 19, "Pro": 20, "Ecc": 21, "Sng": 22, "Isa": 23, "Jer": 24,
    "Lam": 25, "Ezk": 26, "Dan": 27, "Hos": 28, "Jol": 29, "Amo": 30, "Oba": 31, "Jon": 32,
    "Mic": 33, "Nam": 34, "Hab": 35, "Zep": 36, "Hag": 37, "Zec": 38, "Mal": 39,
    "Mat": 40, "Mrk": 41, "Luk": 42, "Jhn": 43, "Act": 44, "Rom": 45, "1Co": 46, "2Co": 47,
    "Gal": 48, "Eph": 49, "Php": 50, "Col": 51, "1Th": 52, "2Th": 53, "1Ti": 54, "2Ti": 55,
    "Tit": 56, "Phm": 57, "Heb": 58, "Jas": 59, "1Pe": 60, "2Pe": 61, "1Jn": 62, "2Jn": 63,
    "3Jn": 64, "Jud": 65, "Rev": 66,
}

OSIS_BOOK_MAP = {
    "Gen": 1, "Exod": 2, "Lev": 3, "Num": 4, "Deut": 5, "Josh": 6, "Judg": 7, "Ruth": 8,
    "1Sam": 9, "2Sam": 10, "1Kgs": 11, "2Kgs": 12, "1Chr": 13, "2Chr": 14, "Ezra": 15, "Neh": 16,
    "Esth": 17, "Job": 18, "Ps": 19, "Prov": 20, "Eccl": 21, "Song": 22, "Isa": 23, "Jer": 24,
    "Lam": 25, "Ezek": 26, "Dan": 27, "Hos": 28, "Joel": 29, "Amos": 30, "Obad": 31, "Jonah": 32,
    "Mic": 33, "Nah": 34, "Hab": 35, "Zeph": 36, "Hag": 37, "Zech": 38, "Mal": 39,
    "Matt": 40, "Mark": 41, "Luke": 42, "John": 43, "Acts": 44, "Rom": 45, "1Cor": 46, "2Cor": 47,
    "Gal": 48, "Eph": 49, "Phil": 50, "Col": 51, "1Thess": 52, "2Thess": 53, "1Tim": 54, "2Tim": 55,
    "Titus": 56, "Phlm": 57, "Heb": 58, "Jas": 59, "1Pet": 60, "2Pet": 61, "1John": 62, "2John": 63,
    "3John": 64, "Jude": 65, "Rev": 66,
}

TAG_RE = re.compile(r"<[^>]+>")
P_CLOSE_RE = re.compile(r"(?:</p>\s*<p>|<br\s*/?>\s*<br\s*/?>)", re.I)
BR_RE = re.compile(r"<br\s*/?>", re.I)
STRONG_NUM_RE = re.compile(r"([GH])0*([1-9]\d*)")


def clean_markup(raw: str) -> str:
    txt = P_CLOSE_RE.sub("\n\n", raw)
    txt = BR_RE.sub("\n", txt)
    txt = re.sub(r"</(?:p|div|entryFree|item|def|sense)>", "\n", txt, flags=re.I)
    txt = TAG_RE.sub("", txt)
    txt = html.unescape(txt)
    txt = re.sub(r"[ \t]+", " ", txt)
    txt = re.sub(r" *\n *", "\n", txt)
    txt = re.sub(r"\n{3,}", "\n\n", txt)
    return txt.strip()


def norm_key(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", s.lower())


def read_sword_rawld(zf: zipfile.ZipFile, prefix: str):
    idx = zf.read(prefix + ".idx")
    dat = zf.read(prefix + ".dat")
    entries = []
    for i in range(0, len(idx) - 5, 6):
        off, size = struct.unpack("<IH", idx[i:i + 6])
        raw = dat[off:off + size].decode("utf-8", errors="replace")
        if "\r\n" in raw:
            k, v = raw.split("\r\n", 1)
        elif "\n" in raw:
            k, v = raw.split("\n", 1)
        else:
            continue
        k = k.strip()
        v = clean_markup(v)
        if k and v:
            entries.append((k, norm_key(k), v))
    return entries


def read_sword_zld(zf: zipfile.ZipFile, prefix: str):
    idx = zf.read(prefix + ".idx")
    dat = zf.read(prefix + ".dat")
    zdx = zf.read(prefix + ".zdx")
    zdt = zf.read(prefix + ".zdt")
    blocks = []
    for i in range(0, len(zdx) - 7, 8):
        boff, bsize = struct.unpack("<II", zdx[i:i + 8])
        blocks.append((boff, bsize))
    cache = {}

    def get_block(bi: int) -> bytes:
        if bi not in cache:
            boff, bsize = blocks[bi]
            cache[bi] = zlib.decompress(zdt[boff:boff + bsize])
        return cache[bi]

    entries = []
    for i in range(0, len(idx) - 7, 8):
        off, size = struct.unpack("<II", idx[i:i + 8])
        raw = dat[off:off + size]
        nl = raw.find(b"\n")
        if nl < 0:
            continue
        key = raw[:nl].decode("utf-8", errors="replace").strip()
        rest = raw[nl + 1:]
        if len(rest) < 8:
            continue
        bnum, eidx = struct.unpack("<II", rest[:8])
        if bnum >= len(blocks):
            continue
        blk = get_block(bnum)
        hdr_off = 4 + eidx * 8
        if hdr_off + 8 > len(blk):
            continue
        eoff, esize = struct.unpack("<II", blk[hdr_off:hdr_off + 8])
        body_raw = blk[eoff:eoff + esize].decode("utf-8", errors="replace")
        body = clean_markup(body_raw)
        if key and body:
            entries.append((key, norm_key(key), body))
    return entries


def parse_kjv_sword_markup(kjv_zip: Path, verse_counts_by_bc: dict) -> dict:
    """Extract lightweight <i> (translator italics) and <r> (Words of Christ) per (book, ch, verse) from SWORD KJV.zip."""
    marked = {}
    with zipfile.ZipFile(kjv_zip) as zf:
        for test, book_range in [("ot", range(1, 40)), ("nt", range(40, 67))]:
            bzs = zf.read(f"modules/texts/ztext/kjv/{test}.bzs")
            bzz = zf.read(f"modules/texts/ztext/kjv/{test}.bzz")
            bzv = zf.read(f"modules/texts/ztext/kjv/{test}.bzv")

            # Decompress blocks lazily
            blocks = []
            for i in range(0, len(bzs) - 11, 12):
                boff, csize, usize = struct.unpack("<III", bzs[i:i + 12])
                blocks.append((boff, csize))
            blk_cache = {}

            def get_blk(bi: int) -> bytes:
                if bi not in blk_cache:
                    boff, csize = blocks[bi]
                    blk_cache[bi] = zlib.decompress(bzz[boff:boff + csize])
                return blk_cache[bi]

            # Build KJV versification slot order matching SWORD KJV v11n:
            # 1 module intro + 1 testament intro, then for each book: 1 book intro,
            # then for each chapter: 1 chapter intro + N verses.
            slot = 2  # skip module intro (0) and testament intro (1)
            for b in book_range:
                slot += 1  # book intro
                max_ch = max(c for (bk, c) in verse_counts_by_bc if bk == b)
                for c in range(1, max_ch + 1):
                    slot += 1  # chapter intro
                    vcnt = verse_counts_by_bc[(b, c)]
                    for v in range(1, vcnt + 1):
                        off10 = slot * 10
                        slot += 1
                        if off10 + 10 > len(bzv):
                            continue
                        bnum, voff, vsize = struct.unpack("<IIH", bzv[off10:off10 + 10])
                        if vsize == 0 or bnum >= len(blocks):
                            continue
                        raw = get_blk(bnum)[voff:voff + vsize].decode("utf-8", errors="replace")
                        # Only keep compact <i> and <r> tags if present
                        if "transChange" not in raw and 'who="Jesus"' not in raw:
                            continue
                        cleaned = convert_osis_to_light_markup(raw)
                        if cleaned:
                            marked[(b, c, v)] = cleaned
    return marked


def convert_osis_to_light_markup(raw: str) -> str:
    # Remove notes, titles, milestones
    s = re.sub(r"<note\b[^>]*>.*?</note>", "", raw, flags=re.S)
    s = re.sub(r"<title\b[^>]*>.*?</title>", "", s, flags=re.S)
    # Mark translator italics
    s = re.sub(r'<transChange\b[^>]*type="added"[^>]*>(.*?)</transChange>', r"[[I]]\1[[/I]]", s, flags=re.S)
    # Mark Words of Christ (<q who="Jesus" ...>...</q> or milestoned <q sID="..." who="Jesus".../> ... <q eID="..." .../>)
    s = re.sub(r'<q\b[^>]*who="Jesus"[^>]*/>', "[[R]]", s)
    s = re.sub(r'<q\b[^>]*eID="[^"]*"[^>]*/>', "[[/R]]", s)
    s = re.sub(r'<q\b[^>]*who="Jesus"[^>]*>(.*?)</q>', r"[[R]]\1[[/R]]", s, flags=re.S)
    # Strip remaining XML tags
    s = TAG_RE.sub("", s)
    s = html.unescape(s)
    s = re.sub(r"\s+", " ", s).strip()
    # Restore lightweight <i> / <r> markers
    s = s.replace("[[I]]", "<i>").replace("[[/I]]", "</i>")
    s = s.replace("[[R]]", "<r>").replace("[[/R]]", "</r>")
    return s


def main():
    t0 = time.monotonic()
    tmp_db = OUT_DB.with_suffix(".sqlite.tmp")
    if tmp_db.exists():
        tmp_db.unlink()

    conn = sqlite3.connect(str(tmp_db))
    conn.execute("PRAGMA journal_mode = OFF;")
    conn.execute("PRAGMA synchronous = OFF;")
    conn.execute("PRAGMA temp_store = MEMORY;")

    conn.executescript("""
    CREATE TABLE metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    CREATE TABLE books (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        abbr TEXT NOT NULL,
        testament TEXT NOT NULL,
        chapter_count INTEGER NOT NULL
    );
    CREATE TABLE verses (
        id INTEGER PRIMARY KEY,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        text_plain TEXT NOT NULL,
        text_marked TEXT NOT NULL DEFAULT ''
    );
    CREATE INDEX idx_verses_bcv ON verses(book_id, chapter, verse);
    CREATE VIRTUAL TABLE verses_fts USING fts5(
        text_plain,
        content='verses',
        content_rowid='id',
        tokenize='porter unicode61'
    );

    CREATE TABLE tsk_cross_refs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_book INTEGER NOT NULL,
        from_chapter INTEGER NOT NULL,
        from_verse INTEGER NOT NULL,
        phrase TEXT NOT NULL,
        to_book INTEGER NOT NULL,
        to_chapter INTEGER NOT NULL,
        to_verse_start INTEGER NOT NULL,
        to_verse_end INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
    );
    CREATE INDEX idx_tsk_from ON tsk_cross_refs(from_book, from_chapter, from_verse, sort_order);

    CREATE TABLE strongs_lexicon (
        strongs_id TEXT PRIMARY KEY,
        testament TEXT NOT NULL,
        lemma TEXT NOT NULL,
        translit TEXT NOT NULL,
        pronunciation TEXT NOT NULL,
        derivation TEXT NOT NULL,
        definition TEXT NOT NULL,
        kjv_usage TEXT NOT NULL
    );
    CREATE VIRTUAL TABLE strongs_fts USING fts5(
        strongs_id, lemma, translit, definition, kjv_usage,
        content='strongs_lexicon',
        content_rowid='rowid'
    );

    CREATE TABLE webster_1828 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        headword TEXT NOT NULL,
        headword_norm TEXT NOT NULL,
        definition TEXT NOT NULL
    );
    CREATE INDEX idx_webster_norm ON webster_1828(headword_norm);

    CREATE TABLE interlinear_words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        word_pos INTEGER NOT NULL,
        original_text TEXT NOT NULL,
        translit TEXT NOT NULL,
        gloss TEXT NOT NULL,
        strongs_id TEXT NOT NULL,
        morph TEXT NOT NULL
    );
    CREATE INDEX idx_interlinear_bcv ON interlinear_words(book_id, chapter, verse, word_pos);
    CREATE INDEX idx_interlinear_strongs ON interlinear_words(strongs_id);

    CREATE TABLE biblical_places (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        name_norm TEXT NOT NULL,
        place_type TEXT NOT NULL,
        modern_name TEXT NOT NULL,
        description TEXT NOT NULL,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        verse_count INTEGER NOT NULL
    );
    CREATE INDEX idx_places_name_norm ON biblical_places(name_norm);

    CREATE TABLE place_verses (
        place_id TEXT NOT NULL,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        PRIMARY KEY (place_id, book_id, chapter, verse)
    );
    CREATE INDEX idx_place_verses_bc ON place_verses(book_id, chapter, verse);
    CREATE INDEX idx_place_verses_pid ON place_verses(place_id, book_id, chapter, verse);

    CREATE TABLE study_dictionaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        headword TEXT NOT NULL,
        headword_norm TEXT NOT NULL,
        body TEXT NOT NULL
    );
    CREATE INDEX idx_studydict_src_norm ON study_dictionaries(source, headword_norm);
    CREATE VIRTUAL TABLE study_dictionaries_fts USING fts5(
        source, headword, body,
        content='study_dictionaries',
        content_rowid='id',
        tokenize='porter unicode61'
    );
    """)

    # 1. Import KJV verses + SWORD italics/red-letter markup
    src = sqlite3.connect(f"file:{RESOURCES_DIR / 'kjv.sqlite'}?mode=ro", uri=True)
    rows = src.execute("SELECT id, book_id, chapter, number, text FROM verses ORDER BY book_id, chapter, number").fetchall()
    src.close()
    assert len(rows) == 31102, f"Expected 31102 KJV verses, got {len(rows)}"

    ch_counts = {}
    verse_counts_by_bc = {}
    for _, b, c, v, _ in rows:
        if c > ch_counts.get(b, 0):
            ch_counts[b] = c
        if v > verse_counts_by_bc.get((b, c), 0):
            verse_counts_by_bc[(b, c)] = v

    marked_map = parse_kjv_sword_markup(RESOURCES_DIR / "KJV.zip", verse_counts_by_bc)
    conn.executemany(
        "INSERT INTO books(id, name, abbr, testament, chapter_count) VALUES (?, ?, ?, ?, ?)",
        [(b, name, abbr, test, ch_counts[b]) for b, name, abbr, test in BOOKS]
    )
    conn.executemany(
        "INSERT INTO verses(id, book_id, chapter, verse, text_plain, text_marked) VALUES (?, ?, ?, ?, ?, ?)",
        [(vid, b, c, v, txt, marked_map.get((b, c, v), "")) for vid, b, c, v, txt in rows]
    )
    conn.execute("INSERT INTO verses_fts(verses_fts) VALUES('rebuild')")
    print(f"[1/6] KJV imported: 66 books, {len(rows)} verses ({len(marked_map)} with italics/red-letter markup)")

    # 2. Import TSK Cross-References
    with zipfile.ZipFile(RESOURCES_DIR / "tsk-bible-cross-references-main.zip") as zf:
        vlist = json.loads(zf.read("bible-cross-references-main/json/bible_verses.json"))
        id_to_bcv = {}
        for v in vlist:
            ch = v.get("kjv_ch")
            vs = v.get("kjv_vs")
            if ch and vs:
                id_to_bcv[v["id"]] = (int(v["book_id"]), int(ch), int(vs))

        xrefs = json.loads(zf.read("bible-cross-references-main/json/cross_references.json"))
        tsk_batch = []
        for entry in xrefs:
            fbcv = id_to_bcv.get(entry["verse_id"])
            if not fbcv:
                continue
            phrase = (entry.get("kjv") or "").strip()
            sort_base = int(entry.get("sort") or 0) * 100
            for idx, ref_group in enumerate(entry.get("refs") or []):
                if not ref_group:
                    continue
                first = id_to_bcv.get(ref_group[0])
                last = id_to_bcv.get(ref_group[-1])
                if not first:
                    continue
                tb, tc, tvs = first
                tve = last[2] if (last and last[0] == tb and last[1] == tc) else tvs
                tsk_batch.append((fbcv[0], fbcv[1], fbcv[2], phrase, tb, tc, tvs, tve, sort_base + idx))
        conn.executemany(
            "INSERT INTO tsk_cross_refs(from_book, from_chapter, from_verse, phrase, to_book, to_chapter, to_verse_start, to_verse_end, sort_order) VALUES (?,?,?,?,?,?,?,?,?)",
            tsk_batch
        )
    print(f"[2/6] TSK cross-references imported: {len(tsk_batch)} links")

    # 3. Import Strong's Greek & Hebrew Lexicons
    strongs_batch = []
    with zipfile.ZipFile(RESOURCES_DIR / "strongs-master.zip") as zf:
        for fn, test in [
            ("strongs-master/hebrew/strongs-hebrew-dictionary.js", "OT"),
            ("strongs-master/greek/strongs-greek-dictionary.js", "NT"),
        ]:
            txt = zf.read(fn).decode("utf-8")
            d = json.loads(txt[txt.find("{"):txt.rfind("}") + 1])
            for sid, item in d.items():
                strongs_batch.append((
                    sid.strip().upper(),
                    test,
                    (item.get("lemma") or "").strip(),
                    (item.get("translit") or item.get("xlit") or "").strip(),
                    (item.get("pron") or "").strip(),
                    (item.get("derivation") or "").strip(),
                    (item.get("strongs_def") or "").strip(),
                    (item.get("kjv_def") or "").strip(),
                ))
    conn.executemany(
        "INSERT OR REPLACE INTO strongs_lexicon(strongs_id, testament, lemma, translit, pronunciation, derivation, definition, kjv_usage) VALUES (?,?,?,?,?,?,?,?)",
        strongs_batch
    )
    conn.execute("INSERT INTO strongs_fts(strongs_fts) VALUES('rebuild')")
    print(f"[3/6] Strong's lexicon imported: {len(strongs_batch)} entries")

    # 4. Import Webster's 1828 Dictionary
    csv.field_size_limit(sys.maxsize)
    webster_batch = []
    with (RESOURCES_DIR / "webster1828.txt").open("r", encoding="utf-8", errors="replace", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 2:
                continue
            hw = row[0].strip()
            if not hw:
                continue
            defn = clean_markup(row[1])
            if not defn:
                continue
            webster_batch.append((hw, norm_key(hw), defn))
    conn.executemany(
        "INSERT INTO webster_1828(headword, headword_norm, definition) VALUES (?,?,?)",
        webster_batch
    )
    print(f"[4/6] Webster's 1828 imported: {len(webster_batch)} entries")

    # 5. Import Interlinear Greek NT (TAGNT) + Hebrew OT (TAHOT) from STEPBible-Data-master.zip
    interlinear_count = 0
    ref_re = re.compile(r"^([1-3]?[A-Za-z]{2,3})\.(\d+)\.(\d+)#(\d+)")
    with zipfile.ZipFile(RESOURCES_DIR / "STEPBible-Data-master.zip") as zf:
        step_files = [
            ("OT", "STEPBible-Data-master/Translators Amalgamated OT+NT/TAHOT Gen-Deu - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt"),
            ("OT", "STEPBible-Data-master/Translators Amalgamated OT+NT/TAHOT Jos-Est - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt"),
            ("OT", "STEPBible-Data-master/Translators Amalgamated OT+NT/TAHOT Job-Sng - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt"),
            ("OT", "STEPBible-Data-master/Translators Amalgamated OT+NT/TAHOT Isa-Mal - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt"),
            ("NT", "STEPBible-Data-master/Translators Amalgamated OT+NT/TAGNT Mat-Jhn - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt"),
            ("NT", "STEPBible-Data-master/Translators Amalgamated OT+NT/TAGNT Act-Rev - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt"),
        ]
        batch = []
        for test, fn in step_files:
            with zf.open(fn) as f:
                for raw in f:
                    line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
                    if not line or line.startswith(("#", "=")) or "\t" not in line:
                        continue
                    cols = line.split("\t")
                    m = ref_re.match(cols[0])
                    if not m:
                        continue
                    b_id = STEP_BOOK_MAP.get(m.group(1))
                    if not b_id:
                        continue
                    ch, vs, wpos = int(m.group(2)), int(m.group(3)), int(m.group(4))
                    if test == "NT":
                        if len(cols) < 5:
                            continue
                        orig_full = cols[1].strip()
                        # Split "Βίβλος (Biblos)" into Greek + translit
                        if "(" in orig_full and orig_full.endswith(")"):
                            idx_p = orig_full.rfind("(")
                            orig = orig_full[:idx_p].strip()
                            translit = orig_full[idx_p + 1:-1].strip()
                        else:
                            orig, translit = orig_full, ""
                        gloss = cols[2].strip()
                        sm = cols[3].strip()
                        strongs_m = STRONG_NUM_RE.search(sm)
                        strongs_id = f"{strongs_m.group(1)}{strongs_m.group(2)}" if strongs_m else ""
                        morph = sm.split("=", 1)[1].strip() if "=" in sm else ""
                    else:
                        if len(cols) < 6:
                            continue
                        orig = cols[1].strip().replace("/", "")
                        translit = cols[2].strip()
                        gloss = cols[3].strip()
                        # Prefer root Strong's in col 4 ({H7225G})
                        sm = cols[4].strip()
                        braced = re.search(r"\{([GH]0*[1-9]\d*)", sm)
                        strongs_m = STRONG_NUM_RE.search(braced.group(1) if braced else sm)
                        strongs_id = f"{strongs_m.group(1)}{strongs_m.group(2)}" if strongs_m else ""
                        morph = cols[5].strip()
                    batch.append((b_id, ch, vs, wpos, orig, translit, gloss, strongs_id, morph))
                    if len(batch) >= 50000:
                        conn.executemany(
                            "INSERT INTO interlinear_words(book_id, chapter, verse, word_pos, original_text, translit, gloss, strongs_id, morph) VALUES (?,?,?,?,?,?,?,?,?)",
                            batch
                        )
                        interlinear_count += len(batch)
                        batch.clear()
        if batch:
            conn.executemany(
                "INSERT INTO interlinear_words(book_id, chapter, verse, word_pos, original_text, translit, gloss, strongs_id, morph) VALUES (?,?,?,?,?,?,?,?,?)",
                batch
            )
            interlinear_count += len(batch)
            batch.clear()
    print(f"[5/6] Interlinear Hebrew/Greek words imported: {interlinear_count}")

    # 6. Import Easton's Bible Dictionary, Nave's Topical Bible, Torrey's New Topical Textbook
    dict_counts = {}
    with zipfile.ZipFile(RESOURCES_DIR / "Easton.zip") as zf:
        easton = read_sword_zld(zf, "modules/lexdict/zld/easton/easton")
        conn.executemany(
            "INSERT INTO study_dictionaries(source, headword, headword_norm, body) VALUES ('easton', ?, ?, ?)",
            easton
        )
        dict_counts["easton"] = len(easton)
    with zipfile.ZipFile(RESOURCES_DIR / "Nave.zip") as zf:
        nave = read_sword_zld(zf, "modules/lexdict/zld/nave/dict")
        conn.executemany(
            "INSERT INTO study_dictionaries(source, headword, headword_norm, body) VALUES ('nave', ?, ?, ?)",
            nave
        )
        dict_counts["nave"] = len(nave)
    with zipfile.ZipFile(RESOURCES_DIR / "Torrey.zip") as zf:
        torrey = read_sword_rawld(zf, "modules/lexdict/rawld/torrey/torrey")
        conn.executemany(
            "INSERT INTO study_dictionaries(source, headword, headword_norm, body) VALUES ('torrey', ?, ?, ?)",
            torrey
        )
        dict_counts["torrey"] = len(torrey)
    conn.execute("INSERT INTO study_dictionaries_fts(study_dictionaries_fts) VALUES('rebuild')")
    print(f"[6/7] Study dictionaries imported: {dict_counts}")

    # 7. Import Biblical Geography & Places (OpenBible Bible-Geocoding-Data-main.zip)
    places_batch = []
    place_verses_batch = []
    seen_pv = set()
    with zipfile.ZipFile(RESOURCES_DIR / "Bible-Geocoding-Data-main.zip") as zf:
        with zf.open("Bible-Geocoding-Data-main/data/ancient.jsonl") as fh:
            for raw_line in fh:
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                obj = json.loads(line)
                pid = (obj.get("id") or "").strip()
                name = (obj.get("friendly_id") or "").strip()
                if not pid or not name:
                    continue

                # Extract best representative lon,lat + modern identification name
                lat = None
                lon = None
                modern_name = ""
                idents = obj.get("identifications") or []
                for ident in idents:
                    resolutions = ident.get("resolutions") or []
                    for res in resolutions:
                        ll = res.get("lonlat")
                        if ll and "," in ll:
                            parts = ll.split(",", 1)
                            try:
                                lon_v = float(parts[0].strip())
                                lat_v = float(parts[1].strip())
                                lat, lon = lat_v, lon_v
                                modern_name = clean_markup(res.get("description") or ident.get("description") or "")
                                break
                            except ValueError:
                                pass
                    if lat is not None:
                        break
                if lat is None or lon is None:
                    continue

                types = obj.get("types") or []
                place_type = str(types[0]).title() if types else "Place"
                desc = clean_markup(obj.get("comment") or "")

                v_refs = obj.get("verses") or []
                linked_count = 0
                for vr in v_refs:
                    osis = (vr.get("osis") or "").strip()
                    parts = osis.split(".")
                    if len(parts) < 3:
                        continue
                    b_id = OSIS_BOOK_MAP.get(parts[0])
                    if not b_id:
                        continue
                    try:
                        ch = int(parts[1])
                        vs = int(parts[2])
                    except ValueError:
                        continue
                    key = (pid, b_id, ch, vs)
                    if key not in seen_pv:
                        seen_pv.add(key)
                        place_verses_batch.append(key)
                        linked_count += 1

                places_batch.append((pid, name, norm_key(name), place_type, modern_name, desc, lat, lon, linked_count))

    conn.executemany(
        "INSERT OR REPLACE INTO biblical_places(id, name, name_norm, place_type, modern_name, description, lat, lon, verse_count) VALUES (?,?,?,?,?,?,?,?,?)",
        places_batch
    )
    conn.executemany(
        "INSERT OR IGNORE INTO place_verses(place_id, book_id, chapter, verse) VALUES (?,?,?,?)",
        place_verses_batch
    )
    print(f"[7/7] Biblical places imported: {len(places_batch)} places, {len(place_verses_batch)} verse links")

    # Metadata & VACUUM
    meta = [
        ("schema_version", "3"),
        ("translation", "KJV"),
        ("built_at", datetime.now(timezone.utc).isoformat()),
        ("verse_count", str(len(rows))),
        ("marked_verse_count", str(len(marked_map))),
        ("tsk_count", str(len(tsk_batch))),
        ("strongs_count", str(len(strongs_batch))),
        ("webster_count", str(len(webster_batch))),
        ("interlinear_count", str(interlinear_count)),
        ("easton_count", str(dict_counts["easton"])),
        ("nave_count", str(dict_counts["nave"])),
        ("torrey_count", str(dict_counts["torrey"])),
        ("places_count", str(len(places_batch))),
        ("place_verses_count", str(len(place_verses_batch))),
    ]
    conn.executemany("INSERT INTO metadata(key, value) VALUES (?, ?)", meta)
    conn.commit()
    conn.execute("VACUUM")
    conn.close()

    tmp_db.replace(OUT_DB)

    # Read-only Verification
    vconn = sqlite3.connect(f"file:{OUT_DB}?mode=ro", uri=True)
    b_cnt = vconn.execute("SELECT COUNT(*) FROM books").fetchone()[0]
    v_cnt = vconn.execute("SELECT COUNT(*) FROM verses").fetchone()[0]
    j316_m = vconn.execute("SELECT text_marked FROM verses WHERE book_id=43 AND chapter=3 AND verse=16").fetchone()[0]
    il_j316 = vconn.execute("SELECT original_text, gloss, strongs_id FROM interlinear_words WHERE book_id=43 AND chapter=3 AND verse=16 ORDER BY word_pos LIMIT 5").fetchall()
    il_g11 = vconn.execute("SELECT original_text, gloss, strongs_id FROM interlinear_words WHERE book_id=1 AND chapter=1 AND verse=1 ORDER BY word_pos LIMIT 3").fetchall()
    easton_grace = vconn.execute("SELECT COUNT(*) FROM study_dictionaries WHERE source='easton' AND headword_norm='grace'").fetchone()[0]
    nave_faith = vconn.execute("SELECT COUNT(*) FROM study_dictionaries WHERE source='nave' AND headword_norm='faith'").fetchone()[0]
    torrey_prayer = vconn.execute("SELECT COUNT(*) FROM study_dictionaries WHERE source='torrey' AND headword_norm LIKE 'prayer%'").fetchone()[0]
    vconn.close()

    assert b_cnt == 66 and v_cnt == 31102
    assert len(il_j316) >= 3 and len(il_g11) >= 3
    assert easton_grace > 0 and nave_faith > 0 and torrey_prayer > 0

    size_mb = OUT_DB.stat().st_size / (1024 * 1024)
    print(f"\n=== VERIFICATION PASSED ({time.monotonic() - t0:.1f}s) ===")
    print(f"Output DB: {OUT_DB} ({size_mb:.1f} MiB)")
    print(f"John 3:16 marked: {j316_m[:120]}")
    print(f"John 3:16 Interlinear sample: {il_j316[:3]}")
    print(f"Gen 1:1 Interlinear sample: {il_g11[:3]}")
    print(f"Easton 'grace': {easton_grace} | Nave 'faith': {nave_faith} | Torrey 'prayer*': {torrey_prayer}")


if __name__ == "__main__":
    main()
