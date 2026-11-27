#!/usr/bin/env python3
"""
Build 100% offline 64-dim biblical semantic embeddings (KJV + Nave's + Torrey's + Modern English bridges)
and store them natively in kjv_reference.mql using MagQLite's VECTOR(64) type and <=> cosine distance.
"""
import os
import re
import sqlite3
import sys
import time
from collections import defaultdict
from pathlib import Path

import numpy as np
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer

MAGQLITE_PY_DIR = r"o:\phpLaragon\www\aiplay\magqlite\packages\python"
MAGQLITE_DLL = r"o:\phpLaragon\www\aiplay\magqlite\target\release\magqlite_ffi.dll"
if os.path.isdir(MAGQLITE_PY_DIR):
    sys.path.insert(0, MAGQLITE_PY_DIR)

from magqlite import MagQLite

DIM = 64

# Book aliases for parsing Nave's / Torrey's verse citations
BOOK_ALIASES = {
    "gen": 1, "ge": 1, "exod": 2, "ex": 2, "lev": 3, "le": 3, "num": 4, "nu": 4, "deut": 5, "de": 5,
    "josh": 6, "jos": 6, "judg": 7, "jg": 7, "ruth": 8, "ru": 8, "1sam": 9, "1sa": 9, "2sam": 10, "2sa": 10,
    "1kgs": 11, "1ki": 11, "2kgs": 12, "2ki": 12, "1chr": 13, "1ch": 13, "2chr": 14, "2ch": 14,
    "ezra": 15, "ezr": 15, "neh": 16, "ne": 16, "esth": 17, "es": 17, "job": 18, "ps": 19, "psa": 19,
    "prov": 20, "pr": 20, "eccl": 21, "ec": 21, "song": 22, "so": 22, "isa": 23, "is": 23, "jer": 24, "je": 24,
    "lam": 25, "la": 25, "ezek": 26, "eze": 26, "dan": 27, "da": 27, "hos": 28, "ho": 28, "joel": 29, "joe": 29,
    "amos": 30, "am": 30, "obad": 31, "ob": 31, "jonah": 32, "jon": 32, "mic": 33, "mi": 33, "nah": 34, "na": 34,
    "hab": 35, "zeph": 36, "zep": 36, "hag": 37, "zech": 38, "zec": 38, "mal": 39,
    "matt": 40, "mt": 40, "mat": 40, "mark": 41, "mr": 41, "mk": 41, "luke": 42, "lu": 42, "lk": 42,
    "john": 43, "joh": 43, "jn": 43, "acts": 44, "ac": 44, "rom": 45, "ro": 45, "1cor": 46, "1co": 46,
    "2cor": 47, "2co": 47, "gal": 48, "ga": 48, "eph": 49, "phil": 50, "php": 50, "col": 51,
    "1thess": 52, "1th": 52, "2thess": 53, "2th": 53, "1tim": 54, "1ti": 54, "2tim": 55, "2ti": 55,
    "titus": 56, "tit": 56, "phlm": 57, "phm": 57, "heb": 58, "jas": 59, "jam": 59, "1pet": 60, "1pe": 60,
    "2pet": 61, "2pe": 61, "1john": 62, "1jo": 62, "1jn": 62, "2john": 63, "2jo": 63, "2jn": 63,
    "3john": 64, "3jo": 64, "3jn": 64, "jude": 65, "jud": 65, "rev": 66, "re": 66,
}

# Modern English -> KJV concept bridges so modern queries map cleanly into KJV vector space
MODERN_BRIDGES = {
    "anxiety": ["careful", "fear", "afraid", "troubled", "peace", "heart", "thought", "casting", "care"],
    "anxious": ["careful", "fear", "afraid", "troubled", "peace", "heart", "care"],
    "worry": ["careful", "thought", "troubled", "fear", "afraid", "care", "peace"],
    "worried": ["careful", "thought", "troubled", "fear", "afraid", "care"],
    "stress": ["troubled", "burden", "heavy", "rest", "peace", "weary", "care"],
    "stressed": ["troubled", "burden", "heavy", "rest", "peace", "weary"],
    "grief": ["mourn", "sorrow", "weep", "weeping", "comfort", "broken", "tears", "heaviness"],
    "grieving": ["mourn", "mourning", "sorrow", "weep", "comfort", "broken", "tears"],
    "depression": ["cast", "down", "heavy", "faint", "despair", "sorrow", "broken", "soul", "comfort"],
    "depressed": ["cast", "down", "heavy", "faint", "despair", "sorrow", "broken", "soul"],
    "lonely": ["forsake", "alone", "desolate", "comfort", "presence", "never", "leave"],
    "loneliness": ["forsake", "alone", "desolate", "comfort", "never", "leave"],
    "money": ["riches", "mammon", "wealth", "silver", "gold", "covet", "treasure", "poor", "borrow"],
    "finances": ["riches", "wealth", "treasure", "covet", "steward", "tithe", "give", "poor"],
    "debt": ["borrow", "borrower", "lender", "owe", "debtor", "pay", "riches"],
    "marriage": ["husband", "wife", "marry", "married", "flesh", "bride", "love", "covenant"],
    "spouse": ["husband", "wife", "marry", "love", "help"],
    "forgiving": ["forgive", "forgiven", "forgiving", "pardon", "mercy", "trespass", "reconcile"],
    "forgiveness": ["forgive", "forgiven", "remission", "pardon", "mercy", "iniquity", "sins"],
    "healing": ["heal", "healed", "health", "infirmity", "sick", "disease", "physician", "whole"],
    "illness": ["sick", "sickness", "disease", "infirmity", "heal", "healed"],
    "guidance": ["guide", "direct", "path", "paths", "way", "wisdom", "counsel", "lead", "steps"],
    "direction": ["guide", "direct", "path", "way", "lead", "steps", "wisdom"],
    "decision": ["wisdom", "counsel", "understanding", "direct", "path", "ask"],
    "temptation": ["tempt", "tempted", "temptation", "lust", "flesh", "overcome", "escape", "sin"],
    "addiction": ["bondage", "lust", "flesh", "temperance", "free", "overcome", "servant", "sin"],
    "tired": ["weary", "faint", "rest", "strength", "renew", "burden", "heavy"],
    "exhausted": ["weary", "faint", "rest", "strength", "renew", "burden"],
    "strength": ["strength", "strong", "mighty", "power", "courage", "weak", "renew"],
    "courage": ["courage", "strong", "afraid", "fear", "bold", "dismayed", "heart"],
    "anger": ["anger", "angry", "wrath", "fierce", "slow", "meek", "gentle", "strife"],
    "pride": ["pride", "proud", "haughty", "humble", "humility", "lowly", "exalt"],
    "humility": ["humble", "humility", "lowly", "meek", "proud", "pride", "grace"],
    "patience": ["patience", "patient", "wait", "waiting", "endure", "longsuffering", "steadfast"],
    "suffering": ["suffer", "suffering", "affliction", "tribulation", "trial", "endure", "comfort"],
    "persecution": ["persecute", "persecuted", "tribulation", "suffer", "enemies", "blessed"],
    "salvation": ["salvation", "save", "saved", "grace", "faith", "believe", "blood", "cross", "redemption"],
    "gospel": ["gospel", "glad", "tidings", "preach", "salvation", "christ", "believe", "grace"],
    "heaven": ["heaven", "everlasting", "eternal", "kingdom", "mansions", "glory", "throne"],
    "hell": ["hell", "fire", "destruction", "perish", "judgment", "everlasting", "wrath"],
    "prayer": ["pray", "prayer", "prayers", "supplication", "ask", "seek", "knock", "intercession"],
    "worship": ["worship", "praise", "sing", "thanksgiving", "glory", "magnify", "bless"],
    "gratitude": ["thanks", "thanksgiving", "thankful", "praise", "bless", "rejoice"],
    "thankful": ["thanks", "thanksgiving", "thankful", "praise", "rejoice"],
    "parenting": ["children", "train", "child", "father", "mother", "provoke", "nurture", "rod"],
    "family": ["house", "household", "children", "father", "mother", "husband", "wife", "honour"],
    "friendship": ["friend", "friends", "companion", "brother", "love", "iron", "counsel"],
    "work": ["labour", "diligent", "hand", "work", "slothful", "faithful", "serve", "reward"],
    "leadership": ["shepherd", "elder", "bishop", "rule", "servant", "humble", "example", "flock"],
    "repentance": ["repent", "repentance", "turn", "confess", "forgive", "sin", "contrite"],
    "love": ["love", "charity", "loved", "beloved", "kind", "compassion", "mercy"],
    "hope": ["hope", "anchor", "expectation", "trust", "faith", "promise", "wait"],
    "peace": ["peace", "rest", "still", "quiet", "calm", "comfort", "keep"],
    "joy": ["joy", "rejoice", "glad", "gladness", "delight", "merry", "cheer"],
    "happy": ["blessed", "joy", "rejoice", "glad", "gladness", "delight"],
    "wisdom": ["wisdom", "wise", "understanding", "knowledge", "prudence", "counsel", "fear"],
    "truth": ["truth", "true", "word", "light", "way", "faithful"],
    "enemies": ["enemy", "enemies", "hate", "curse", "bless", "forgive", "pray", "love"],
    "creation": ["created", "beginning", "heaven", "earth", "made", "formed", "word"],
}

REF_RE = re.compile(r"\b([1-3]?\s?[A-Za-z]{2,10})\.?\s+(\d{1,3}):(\d{1,3})")


def fmt_vec(arr: np.ndarray) -> str:
    return "[" + ",".join(f"{x:.4f}" for x in arr) + "]"


def build_vectors(sqlite_path: Path, mql_path: Path):
    t0 = time.perf_counter()
    src = sqlite3.connect(f"file:{sqlite_path}?mode=ro", uri=True)
    cur = src.cursor()

    print("Loading 31,102 KJV verses...", flush=True)
    cur.execute("SELECT id, book_id, chapter, verse, text_plain FROM verses ORDER BY id")
    verses = cur.fetchall()
    bcv_to_idx = {(b, c, v): i for i, (_id, b, c, v, _t) in enumerate(verses)}

    print("Enriching with Nave's & Torrey's topical mappings...", flush=True)
    verse_topics = defaultdict(list)
    cur.execute("SELECT headword, body FROM study_dictionaries WHERE source IN ('nave', 'torrey')")
    for headword, body in cur.fetchall():
        topic = headword.lower().strip()
        for m in REF_RE.finditer(body):
            bk = m.group(1).replace(" ", "").lower()
            bid = BOOK_ALIASES.get(bk)
            if bid:
                idx = bcv_to_idx.get((bid, int(m.group(2)), int(m.group(3))))
                if idx is not None:
                    verse_topics[idx].append(topic)

    docs = []
    for i, (_id, _b, _c, _v, text) in enumerate(verses):
        topics = verse_topics.get(i)
        if topics:
            docs.append(text + " " + " ".join(topics[:8]))
        else:
            docs.append(text)
    src.close()

    print(f"Fitting TF-IDF + {DIM}-dim TruncatedSVD on {len(docs):,} enriched verses...", flush=True)
    vectorizer = TfidfVectorizer(
        max_features=12000,
        sublinear_tf=True,
        stop_words="english",
        token_pattern=r"(?u)\b[a-zA-Z]{2,}\b",
    )
    X = vectorizer.fit_transform(docs)
    svd = TruncatedSVD(n_components=DIM, random_state=42)
    verse_embs = svd.fit_transform(X).astype(np.float32)

    # L2 normalize verse vectors
    norms = np.linalg.norm(verse_embs, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    verse_embs = verse_embs / norms

    # Word embeddings in the exact same 64-dim SVD space: svd.components_.T (n_vocab x DIM)
    vocab = vectorizer.vocabulary_
    idf = vectorizer.idf_
    word_matrix = svd.components_.T.astype(np.float32)  # shape (n_vocab, DIM)

    # Build word -> (vec, idf) table + modern English bridges
    word_rows = []
    word_vec_map = {}
    for w, idx in vocab.items():
        v = word_matrix[idx]
        n = float(np.linalg.norm(v))
        if n > 0:
            v_norm = v / n
            word_vec_map[w] = v_norm
            word_rows.append((w, v_norm, float(idf[idx])))

    # Add/override modern concept bridges (weighted average of target KJV concept vectors)
    existing_words = {w for w, _, _ in word_rows}
    for modern_word, targets in MODERN_BRIDGES.items():
        vecs = [word_vec_map[t] for t in targets if t in word_vec_map]
        if not vecs:
            continue
        avg = np.mean(vecs, axis=0).astype(np.float32)
        if modern_word in word_vec_map and modern_word not in {"tired", "stress", "careful"}:
            avg = 0.85 * avg + 0.15 * word_vec_map[modern_word]
        n = float(np.linalg.norm(avg))
        if n > 0:
            avg = avg / n
            if modern_word in existing_words:
                word_rows = [(w, avg if w == modern_word else v, idf_v) for w, v, idf_v in word_rows]
            else:
                word_rows.append((modern_word, avg, 5.5))
                existing_words.add(modern_word)

    print(f"Computed {len(verse_embs):,} verse vectors + {len(word_rows):,} semantic vocab words in {time.perf_counter()-t0:.1f}s.", flush=True)

    # Write into kjv_reference.mql
    lib_path = MAGQLITE_DLL if os.path.exists(MAGQLITE_DLL) else None
    cfg = {"paged_storage": True, "durability": "off", "auto_checkpoint_frames": 0, "buffer_pool_pages": 4096}
    with MagQLite(str(mql_path), config=cfg, lib_path=lib_path) as db:
        db.query("DROP TABLE IF EXISTS verse_vectors;")
        db.query("DROP TABLE IF EXISTS semantic_vocab;")
        db.query(f"CREATE TABLE verse_vectors (verse_id INT NOT NULL, book_id INT NOT NULL, emb VECTOR({DIM}) NOT NULL);")
        db.query(f"CREATE TABLE semantic_vocab (word TEXT NOT NULL, emb VECTOR({DIM}) NOT NULL, idf FLOAT NOT NULL);")

        ts = time.perf_counter()
        batch_size = 500
        for start in range(0, len(verses), batch_size):
            end = min(start + batch_size, len(verses))
            vals = ", ".join(
                f"({verses[i][0]}, {verses[i][1]}, '{fmt_vec(verse_embs[i])}')"
                for i in range(start, end)
            )
            db.query(f"INSERT INTO verse_vectors (verse_id, book_id, emb) VALUES {vals};")
            if end % 10000 == 0 or end == len(verses):
                print(f"  verse_vectors: {end:,}/{len(verses):,} ({time.perf_counter()-ts:.1f}s)", flush=True)

        ts2 = time.perf_counter()
        for start in range(0, len(word_rows), batch_size):
            end = min(start + batch_size, len(word_rows))
            vals = ", ".join(
                f"('{word_rows[i][0].replace(chr(39), chr(39)*2)}', '{fmt_vec(word_rows[i][1])}', {word_rows[i][2]:.4f})"
                for i in range(start, end)
            )
            db.query(f"INSERT INTO semantic_vocab (word, emb, idf) VALUES {vals};")
        print(f"  [OK] semantic_vocab: {len(word_rows):,} words in {time.perf_counter()-ts2:.2f}s", flush=True)

        db.query("CREATE INDEX idx_semvocab_word ON semantic_vocab (word);")
        db.query("CREATE INDEX idx_versevec_book ON verse_vectors (book_id);")
        db.query("CHECKPOINT;")
        print(f"CHECKPOINT complete! Total elapsed: {time.perf_counter()-t0:.1f}s", flush=True)

        # Quick live smoke test of 5 real meaning queries!
        print("\n=== Live Semantic Meaning Search Test (MagQLite VECTOR(64) <=>) ===", flush=True)
        for q in ["anxiety and worry", "comfort when grieving", "forgiving my enemies", "wisdom about money", "strength when tired"]:
            tq = time.perf_counter()
            q_words = re.findall(r"[a-zA-Z]{2,}", q.lower())
            q_vec = np.zeros(DIM, dtype=np.float32)
            hits = 0
            for w in q_words:
                r = db.query_params("SELECT emb, idf FROM semantic_vocab WHERE word = ? LIMIT 1;", [w])
                if r["rows"]:
                    raw_emb = r["rows"][0][0]
                    w_idf = float(r["rows"][0][1])
                    arr = np.array(raw_emb if isinstance(raw_emb, list) else [float(x) for x in str(raw_emb).strip("[]").split(",")], dtype=np.float32)
                    q_vec += arr * w_idf
                    hits += 1
            n = float(np.linalg.norm(q_vec))
            if n > 0:
                q_vec /= n
            vec_lit = fmt_vec(q_vec)
            res = db.query(f"SELECT verse_id, emb <=> '{vec_lit}' AS dist FROM verse_vectors ORDER BY dist ASC LIMIT 5;")
            dt = (time.perf_counter() - tq) * 1000
            print(f"\nQuery: '{q}' ({hits} vocab hits) in {dt:.1f} ms:", flush=True)
            for vid, dist in res["rows"]:
                vr = db.query_params("SELECT book_id, chapter, verse, text_plain FROM verses WHERE id = ? LIMIT 1;", [int(vid)])
                if vr["rows"]:
                    b, c, v, txt = vr["rows"][0]
                    print(f"  dist={float(dist):.3f} | Book {b} {c}:{v} — {txt[:95]}", flush=True)


if __name__ == "__main__":
    src_arg = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"\\10.69.1.194\development\bible-app\Sources\KJVStudyBible\Resources\kjv_reference.sqlite")
    mql_arg = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"C:\Users\Aaron Thomas\.gemini\antigravity\brain\5d25c776-1065-47e4-98b1-900cf357550b\scratch\mql_build\kjv_reference.mql")
    build_vectors(src_arg, mql_arg)
