#!/usr/bin/env python3
"""
Convert MyBible commentary .zip archives into Sword & Quill .sqmod packages
(SQM1 header + manifest.json + raw-deflate MagQLite .mql + raw-deflate .mql.pages)
and generate catalog.json for swordandquillbible.com/modules/.
"""
import html
import json
import os
import re
import shutil
import sqlite3
import struct
import sys
import tempfile
import time
import zlib
from pathlib import Path

MAGQLITE_PY_DIR = r"o:\phpLaragon\www\aiplay\magqlite\packages\python"
MAGQLITE_DLL = r"o:\phpLaragon\www\aiplay\magqlite\target\release\magqlite_ffi.dll"
if os.path.isdir(MAGQLITE_PY_DIR):
    sys.path.insert(0, MAGQLITE_PY_DIR)
from magqlite import MagQLite

# Standard MyBible 66 canonical book numbers -> canonical 1..66
MYBIBLE_BOOKS = [
    10, 20, 30, 40, 50, 60, 70, 80, 90, 100,
    110, 120, 130, 140, 150, 160, 190, 220, 230, 240,
    250, 260, 290, 300, 310, 330, 340, 350, 360, 370,
    380, 390, 400, 410, 420, 430, 440, 450, 460, 470,
    480, 490, 500, 510, 520, 530, 540, 550, 560, 570,
    580, 590, 600, 610, 620, 630, 640, 650, 660, 670,
    680, 690, 700, 710, 720, 730,
]
BOOK_MAP = {mb: idx + 1 for idx, mb in enumerate(MYBIBLE_BOOKS)}

CURATED_MODULES = [
    {
        "zip": "SI-KJVNOTES.commentaries.zip",
        "id": "kjv-notes",
        "title": "KJV 1611 Marginal Notes",
        "shortTitle": "KJV Notes",
        "abbr": "KJV",
        "author": "King James Translators (1611)",
        "description": "Original alternate Hebrew & Greek renderings and marginal notes from the 1611 King James translators.",
        "starter": True,
    },
    {
        "zip": "SI-SCOFIELD.commentaries.zip",
        "id": "scofield-1917",
        "title": "Scofield Reference Notes (1917)",
        "shortTitle": "Scofield",
        "abbr": "SCO",
        "author": "C. I. Scofield (1843–1921)",
        "description": "Classic 1917 Scofield Reference Bible study notes covering major biblical themes and covenants.",
        "starter": True,
    },
    {
        "zip": "SI-MATTHEWHENRY.commentaries.zip",
        "id": "matthew-henry",
        "title": "Matthew Henry's Commentary",
        "shortTitle": "M. Henry",
        "abbr": "MHC",
        "author": "Matthew Henry (1662–1714)",
        "description": "Beloved six-volume devotional and pastoral exposition of the entire Old and New Testaments.",
        "starter": False,
    },
    {
        "zip": "SI-JFBU.commentaries.zip",
        "id": "jfb",
        "title": "Jamieson, Fausset & Brown",
        "shortTitle": "JFB",
        "abbr": "JFB",
        "author": "Jamieson, Fausset & Brown (1871)",
        "description": "Crisp, balanced, scholarly verse-by-verse commentary prized by pastors and Bible teachers.",
        "starter": False,
    },
    {
        "zip": "SI-BARNES.commentaries.zip",
        "id": "barnes",
        "title": "Barnes' Notes on the Bible",
        "shortTitle": "Barnes",
        "abbr": "BRN",
        "author": "Albert Barnes (1798–1870)",
        "description": "Clear, practical verse-by-verse notes written specifically for Sunday School teachers and Bible readers.",
        "starter": False,
    },
    {
        "zip": "SI-GILL.commentaries.zip",
        "id": "john-gill",
        "title": "John Gill's Exposition",
        "shortTitle": "John Gill",
        "abbr": "GIL",
        "author": "John Gill (1697–1771)",
        "description": "Exhaustive verse-by-verse exposition of the entire Bible with rich Hebrew, Greek, and historical insight.",
        "starter": False,
    },
    {
        "zip": "SI-SPURGEON.commentaries.zip",
        "id": "spurgeon",
        "title": "Spurgeon's Expositions",
        "shortTitle": "Spurgeon",
        "abbr": "SPG",
        "author": "Charles H. Spurgeon (1834–1892)",
        "description": "Warm, Christ-centered expositions and preaching insights from the Prince of Preachers.",
        "starter": False,
    },
    {
        "zip": "SI-ADAMCLARKE.commentaries.zip",
        "id": "adam-clarke",
        "title": "Adam Clarke's Commentary",
        "shortTitle": "A. Clarke",
        "abbr": "CLK",
        "author": "Adam Clarke (1762–1832)",
        "description": "Monumental linguistic, historical, and textual commentary across all 66 books.",
        "starter": False,
    },
    {
        "zip": "SI-POOLE.commentaries.zip",
        "id": "matthew-poole",
        "title": "Matthew Poole's Commentary",
        "shortTitle": "M. Poole",
        "abbr": "MPL",
        "author": "Matthew Poole (1624–1679)",
        "description": "Concise, incisive Puritan annotations on the Holy Bible — admired by Spurgeon as a preacher's companion.",
        "starter": False,
    },
    {
        "zip": "SI-KD.commentaries.zip",
        "id": "keil-delitzsch",
        "title": "Keil & Delitzsch (Old Testament)",
        "shortTitle": "Keil & Del.",
        "abbr": "K&D",
        "author": "C. F. Keil & F. Delitzsch (1861–1890)",
        "description": "Classic scholarly Old Testament commentary grounded in Hebrew grammar and historical context.",
        "starter": False,
    },
    {
        "zip": "SI-VINCENTWS.commentaries.zip",
        "id": "vincent-word-studies",
        "title": "Vincent's Word Studies (NT)",
        "shortTitle": "Vincent NT",
        "abbr": "VWS",
        "author": "Marvin R. Vincent (1834–1922)",
        "description": "Vivid Greek word studies illuminating nuances and imagery across the New Testament.",
        "starter": False,
    },
    {
        "zip": "SI-CBNOTES.commentaries.zip",
        "id": "companion-bible",
        "title": "The Companion Bible Notes",
        "shortTitle": "Companion",
        "abbr": "CBN",
        "author": "E. W. Bullinger (1837–1913)",
        "description": "Detailed KJV structural notes, figures of speech, and lexical observations.",
        "starter": False,
    },
]

TAG_P_RE = re.compile(r"</p\s*>", re.IGNORECASE)
TAG_BR_RE = re.compile(r"<br\s*/?>", re.IGNORECASE)
TAG_ALL_RE = re.compile(r"<[^>]+>")
MULTI_NL_RE = re.compile(r"\n{3,}")
MULTI_SP_RE = re.compile(r"[ \t]{2,}")


def clean_html(raw: str) -> str:
    if not raw:
        return ""
    s = raw.replace("\x00", "")
    s = TAG_P_RE.sub("\n\n", s)
    s = TAG_BR_RE.sub("\n", s)
    s = TAG_ALL_RE.sub("", s)
    s = html.unescape(s)
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    lines = [MULTI_SP_RE.sub(" ", ln).strip() for ln in s.split("\n")]
    s = "\n".join(lines)
    s = MULTI_NL_RE.sub("\n\n", s).strip()
    return s


def sql_lit(val) -> str:
    if val is None:
        return "NULL"
    if isinstance(val, int):
        return str(val)
    s = str(val).replace("\x00", "").replace("'", "''")
    return f"'{s}'"


def deflate_raw(data: bytes) -> bytes:
    """Raw RFC 1951 deflate (matches Apple Foundation NSData.decompressed(using: .zlib))."""
    comp = zlib.compressobj(level=6, method=zlib.DEFLATED, wbits=-15)
    return comp.compress(data) + comp.flush()


def build_sqmod(zip_path: Path, meta: dict, out_sqmod: Path) -> dict:
    import zipfile

    t0 = time.time()
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        with zipfile.ZipFile(zip_path) as zf:
            sq_names = [n for n in zf.namelist() if n.lower().endswith(".sqlite3")]
            if not sq_names:
                raise RuntimeError(f"No .sqlite3 inside {zip_path}")
            sqlite_path = Path(zf.extract(sq_names[0], td_path))

        sconn = sqlite3.connect(str(sqlite_path))
        scur = sconn.cursor()
        raw_rows = scur.execute(
            "SELECT book_number, chapter_number_from, verse_number_from, chapter_number_to, verse_number_to, text FROM commentaries ORDER BY book_number, chapter_number_from, verse_number_from"
        ).fetchall()
        sconn.close()

        mql_path = td_path / f"{meta['id']}.mql"
        cfg = {
            "paged_storage": True,
            "durability": "normal",
            "auto_checkpoint_frames": 100000,
            "buffer_pool_pages": 2048,
        }
        lib_path = MAGQLITE_DLL if os.path.exists(MAGQLITE_DLL) else None
        db = MagQLite(str(mql_path), config=cfg, lib_path=lib_path)
        db.query(
            """CREATE TABLE commentary_entries (
                id INT NOT NULL,
                book_id INT NOT NULL,
                chapter_from INT NOT NULL,
                verse_from INT NOT NULL,
                chapter_to INT NOT NULL,
                verse_to INT NOT NULL,
                bc_key INT NOT NULL,
                body TEXT NOT NULL
            );"""
        )

        entry_id = 0
        batch = []
        BATCH_SIZE = 200

        def flush_batch():
            if not batch:
                return
            vals = ",".join(batch)
            db.query(
                f"INSERT INTO commentary_entries (id, book_id, chapter_from, verse_from, chapter_to, verse_to, bc_key, body) VALUES {vals};"
            )
            batch.clear()

        for bn, cf, vf, ct, vt, txt in raw_rows:
            try:
                book_id = BOOK_MAP.get(int(bn))
            except Exception:
                continue
            if not book_id:
                continue
            body = clean_html(txt)
            if not body:
                continue
            cf_i = int(cf or 1)
            vf_i = int(vf or 0)
            ct_i = int(ct or cf_i)
            vt_i = int(vt or vf_i)
            if vt_i < vf_i and ct_i == cf_i:
                vt_i = vf_i
            bc_key = book_id * 1000 + cf_i
            entry_id += 1
            batch.append(
                f"({entry_id},{book_id},{cf_i},{vf_i},{ct_i},{vt_i},{bc_key},{sql_lit(body)})"
            )
            if len(batch) >= BATCH_SIZE:
                flush_batch()

        flush_batch()
        db.query("CREATE INDEX idx_comm_bc ON commentary_entries(bc_key);")
        try:
            db.query("CHECKPOINT;")
        except Exception:
            pass
        db.close()

        mql_bytes = mql_path.read_bytes()
        pages_path = Path(str(mql_path) + ".pages")
        pages_bytes = pages_path.read_bytes() if pages_path.exists() else b""

        mql_z = deflate_raw(mql_bytes)
        pages_z = deflate_raw(pages_bytes) if pages_bytes else b""

        manifest = {
            "id": meta["id"],
            "kind": "commentary",
            "title": meta["title"],
            "shortTitle": meta["shortTitle"],
            "abbr": meta["abbr"],
            "author": meta["author"],
            "description": meta["description"],
            "copyright": "Public Domain",
            "version": 1,
            "entryCount": entry_id,
            "mqlRawSize": len(mql_bytes),
            "pagesRawSize": len(pages_bytes),
            "starter": bool(meta.get("starter", False)),
        }
        manifest_bytes = json.dumps(manifest, ensure_ascii=False).encode("utf-8")

        out_sqmod.parent.mkdir(parents=True, exist_ok=True)
        with open(out_sqmod, "wb") as f:
            f.write(b"SQM1")
            f.write(struct.pack("<I", len(manifest_bytes)))
            f.write(manifest_bytes)
            f.write(struct.pack("<II", len(mql_bytes), len(mql_z)))
            f.write(mql_z)
            f.write(struct.pack("<II", len(pages_bytes), len(pages_z)))
            f.write(pages_z)

        dl_bytes = out_sqmod.stat().st_size
        manifest["downloadBytes"] = dl_bytes
        manifest["downloadURL"] = f"https://swordandquillbible.com/modules/{meta['id']}.sqmod"
        dt = time.time() - t0
        print(
            f"  [OK] {meta['id']:<22} {entry_id:6d} entries | raw={(len(mql_bytes)+len(pages_bytes))/1e6:5.2f}MB -> sqmod={dl_bytes/1e6:5.2f}MB ({dt:.1f}s)"
        )
        return manifest


def main():
    src_dir = Path(r"\\10.69.1.194\development\bible-app\data-sources\commentaries")
    web_mod_dir = Path(
        r"C:\Users\Aaron Thomas\.gemini\antigravity\brain\5d25c776-1065-47e4-98b1-900cf357550b\scratch\website\modules"
    )
    starter_dir = Path(
        r"\\10.69.1.194\development\bible-app\Sources\KJVStudyBible\Resources\StarterModules"
    )
    web_mod_dir.mkdir(parents=True, exist_ok=True)
    starter_dir.mkdir(parents=True, exist_ok=True)

    catalog = []
    for meta in CURATED_MODULES:
        zp = src_dir / meta["zip"]
        if not zp.exists():
            print(f"  [SKIP] Missing {zp.name}")
            continue
        out_sqmod = web_mod_dir / f"{meta['id']}.sqmod"
        entry = build_sqmod(zp, meta, out_sqmod)
        catalog.append(entry)
        if meta.get("starter"):
            shutil.copy2(out_sqmod, starter_dir / f"{meta['id']}.sqmod")

    cat_obj = {
        "schemaVersion": 1,
        "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "modules": catalog,
    }
    (web_mod_dir / "catalog.json").write_text(
        json.dumps(cat_obj, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    total_mb = sum(c["downloadBytes"] for c in catalog) / (1024 * 1024)
    print(f"\nDone! Built {len(catalog)} .sqmod modules ({total_mb:.2f} MB total) + catalog.json")


if __name__ == "__main__":
    main()
