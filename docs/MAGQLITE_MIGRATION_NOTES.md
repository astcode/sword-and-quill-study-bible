# MagQLite Integration & Migration Plan

**Branch:** eat/magqlite (branched off main at commit e774ae7)
**Goal:** Evaluate and integrate our custom zero-dependency Rust database (https://github.com/astcode/MagQLite) into **Sword & Quill Study Bible** without risking main or user study data.

---

## 1. Where the Built Files Go
- **iOS Static Framework:** Vendor/MagQLite.xcframework
  - Built on macos-latest (or Windows cross-compile) with --features full and IPHONEOS_DEPLOYMENT_TARGET=17.0
  - Contains ios-arm64/libmagqlite_ffi.a, Headers/magqlite.h, Headers/module.modulemap (CMagQLite)
- **Swift Wrapper:** Sources/KJVStudyBible/Data/MagQLite.swift

## 2. Why This Is Easy to Swap Later (No Lock-In)
- All SQLite calls in Sword & Quill are isolated in just **2 files**:
  1. Sources/KJVStudyBible/Data/ReferenceDatabase.swift (read-only KJV, Strong's, TSK, Webster 1828, Easton/Nave/Torrey, Biblical Places)
  2. Sources/KJVStudyBible/Data/UserStudyDatabase.swift (highlights, notes, Apple Pencil ink, stickers, Study Trails)
- None of the SwiftUI views, PencilKit canvas, PDF exporter, or Classroom Sharing need to change.
- **Zero-loss upgrade for existing SQLite users:** Because iOS includes sqlite3 natively, a future MagQLite release can automatically detect an existing user_study.sqlite on first launch, migrate all rows into user_study.mql in ~1 second, verify row counts, and keep user_study.sqlite.bak as a safety backup.

## 3. Staged Rollout Strategy
1. **Phase 1 — Read-Only Reference Bible (kjv_reference.mql) First (Zero Risk):**
   - Convert 	ools/build_reference_db.py to build kjv_reference.mql (with paged_storage = true for O(1) open and low iPad RAM).
   - Swap ReferenceDatabase.swift on eat/magqlite and benchmark head-to-head against SQLite on physical iPad Pro (launch time, RAM, chapter-flip speed, FTS_MATCH/BM25 search, ST_WITHIN_KM spatial map queries).
   - Unlock future MagQLite-exclusive features like offline **semantic/vector Bible search** (ector module).
2. **Phase 2 — Personal Soak-Test of UserStudyDatabase (user_study.mql):**
   - Handle large binary blobs (PKDrawing ink, sticker PNGs, WYSIWYG RTF) efficiently (either via raw binary C FFI helpers or storing blobs as files in Application Support/ with metadata in MagQLite).
   - Verify 1-click BACKUP TO export/restore in StudyDashboardSheet.
   - Daily-drive on Aaron's iPad for 2+ weeks (including force-quitting mid-write, backup/restore, and schema upgrades) before trusting it with App Store users' personal notes.
3. **Phase 3 — Production Decision:**
   - Ship either **Full MagQLite** (once soak-tested) or a **Hybrid** (MagQLite for Reference + Semantic/Spatial Search, SQLite for User Notes) for v1.0.

## 4. Technical Checklist for MagQLite Build
- [ ] Compiled with --features full (ts,spatial,vector,jsonb,timeseries,rls,auth,crypto)
- [ ] IPHONEOS_DEPLOYMENT_TARGET=17.0 for arch64-apple-ios
- [ ] Confirmed Data ↔ BLOB handling in MagQLite.swift / magqlite-ffi
- [ ] Confirmed single-file BACKUP TO behavior when paged_storage = true
- [ ] Desktop magqlite CLI or Python wrapper available to build kjv_reference.mql
