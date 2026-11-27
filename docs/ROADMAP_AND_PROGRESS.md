# Sword & Quill Study Bible — Project Journey, Architecture & Roadmap

> **Living Project Log** — Last updated: November 27, 2026  
> **App:** Sword & Quill Study Bible (`iPadOS 17+`, Swift / SwiftUI / PencilKit, 100% Offline)  
> **Database Engine:** Custom Rust **MagQLite `v0.2.4`** (`Vendor/MagQLite.xcframework`)  
> **Website:** [https://swordandquillbible.com](https://swordandquillbible.com/) (Hostinger Git deploy from branch `website`)  
> **Repository:** `https://github.com/astcode/sword-and-quill-study-bible` (active development branch: `feat/magqlite`, release base: `main`)

---

## 1. Where We Started & What We Have Built (Completed Milestones)

### Milestone 1 — Core iPadOS KJV Study & Apple Pencil Journaling Workspace
- **3-Column Adaptive Workspace (`ScriptureWorkspaceView.swift`):**
  - **Left Study Desk:** Tabbed reference workspace (TSK Cross-References, Hebrew & Greek Interlinear / Strong’s, Classic Dictionaries, Interactive Biblical Places & Map, Parallel Bible).
  - **Center KJV Scripture:** Pure KJV with Red-Letter words of Christ, translator italics, verse highlighting categories, bookmarks, verse action popover, and Warm Paper / Crisp Light / Deep Dark themes.
  - **Right Wide-Margin Journal:** Apple Pencil–first `PKCanvasView` (`UnifiedBibleCanvas.swift` + `ZoomableCanvasScrollView.swift`) with pixel-locked zoom up to `3.5×`, Ruled / Dot-Grid / Blank paper styles, verse-anchored ink reflow, draggable Pinned Reference Chips, movable Study Clip Cards, custom & built-in Stickers (with Vision cutout), on-device Handwriting OCR, and Printable PDF export.
- **Workspace Layout Polish:**
  - Study Mode cleanly hides journal overlays so margin items never bleed onto Scripture.
  - Draggable Left-Panel Divider in Study Mode (persisted width, double-tap to reset) and locked canonical width in Journaling Mode so Apple Pencil ink stays 100% pixel-aligned.

### Milestone 2 — 100% Migration to Custom Rust MagQLite (`v0.2.1` → Hardened `v0.2.4`)
- **Zero-Dependency Native Engine:** Integrated `Vendor/MagQLite.xcframework` (`ios-arm64` + `ios-arm64-simulator`, `IPHONEOS_DEPLOYMENT_TARGET=17.0`, Swift 6 `Sendable` `MagQLiteConfig`).
- **Offline Reference Library (`kjv_reference.mql` + `.pages`, ~210 MiB, 855,000+ rows):**
  - 31,102 KJV verses (Red-Letter & Italics)
  - 425,452 Hebrew & Greek Interlinear words + Strong’s Exhaustive Concordance
  - 305,923 Treasury of Scripture Knowledge (TSK) Cross-References
  - 72,304 classic dictionary & topical entries (Webster’s 1828, Easton’s, Nave’s, Torrey’s)
  - 1,335 geocoded Biblical Places (OpenBible coordinates)
  - 16 single-column persisted B+Tree indexes using packed `bc_key`/`bcv_key` → sub-millisecond queries (`0.08 ms` single verse, `0.32 ms` Interlinear, `0.45 ms` chapter, `4.85 ms` TSK).
- **Personal Study Database (`user_study.mql`):**
  - Full migration from legacy SQLite with automatic silent backup (`user_study.sqlite.pre_magqlite.bak`) and zero data loss.
  - 1-click `BACKUP TO` portable `.mql` snapshots and dual-format restore (`.mql` + legacy `.sqlite`).
- **Upgraded to Hardened `MagQLite v0.2.4`** (`5e20d34`): SHA-256 verified, clean `atomic_flag` strip, zero API breaks, verified on physical iPad Pro.

### Milestone 3 — MagQLite-Powered Search & Spatial Geography
- **Uncapped Highlighted Bible Search + 100% Offline Meaning Search (`StudyOverlays.swift`, `ReferenceDatabase.swift`):**
  - 4 search modes: `Exact Word`, `Word Forms`, `Contains`, and **`Meaning`** (powered by 31,102 64-dim biblical semantic vectors + 12,019 vocab vectors using MagQLite `VECTOR(64)` `<=>` cosine distance — zero internet, zero cloud AI).
  - Canonical Genesis → Revelation ordering, zero 80-row cap, bold + yellow highlighter match rendering.
- **Spatial Nearby Biblical Places (`PlacesMapDeskView.swift`):**
  - Uses MagQLite `ST_WITHIN_KM` / `ST_DISTANCE_KM` to discover nearby biblical sites within `10 mi`, `25 mi`, or `50 mi` with 1-tap map flight.

### Milestone 4 — Deep Study Tools, Study Layers & Large-Library Organization
- **Tracing-Paper Study Layers & Study Trails (`StudySessionsViews.swift`):**
  - Named Study Sessions keep sermon/lesson ink, clips, and pins isolated from everyday Bible margins, with Permanent Study Margin Links back to Scripture.
- **Massive Study Organization (`StudyLibrarySheet.swift`):**
  - Full-text search across study titles, summaries, books, and trail entries; `Active` / `Pinned` / `Archived` / `All` tabs; Pin stars, Archive swipe, `Timeline` vs. `By Book` trail grouping, `★ Key` finding stars, and Global Personal Search integration.
- **Sermon Notebooks (`NotebookEditorSheet.swift`):**
  - Split Typed + Apple Pencil Handwriting editor, rich outline formatting, auto-detected clickable Scripture reference pills, Ink → Text OCR, and PDF export.
- **Reading Plans, Offline Audio & Memory Drills:**
  - `ReadingPlansSheet.swift` (1-Year Bible, 90-Day NT, 30-Day Gospels & Acts, 30-Day Psalms & Proverbs)
  - `BibleAudioPlayer.swift` (offline `AVSpeechSynthesizer` verse-by-verse reader with live highlighting, speed, voice picker, sleep timer)
  - `MemoryDrillsSheet.swift` (`Read`, `Fade 35%`, `Fade 70%`, `First Letter`, tap-to-peek, mastered tracking)

### Milestone 5 — Monetization (Track 1) & Public Website (Track 2)
- **Track 1 — StoreKit 2 Monetization (`StoreManager.swift`, `ProAndSupportViews.swift`):**
  - Free forever core Bible, reference library, journaling, and **free lesson import**.
  - One-time **$9.99 Classroom Sharing Pro** (`com.swordandquillbible.pro.classroom`) for projector-ready offline Classroom QR codes, `.sqstudy` AirDrop/email sharing, and printable US-Letter handouts.
  - Optional Support Tip Jar (`tip.coffee`, `tip.fuel`, `tip.supporter`).
- **Track 2 — Live Marketing & Support Website (`https://swordandquillbible.com/`):**
  - Deployed to Hostinger from orphan branch `website` (`627605e`) with `/`, `/privacy`, and `/support` (App Store Connect compliant).
  - Built `#if DEBUG`-only isolated `ShowcaseSeeder.swift` (`f93d9a0`) and captured 4 real Retina iPad Pro screenshots over USB (`Wide-Margin Journaling`, `Dark Mode & TSK`, `Biblical Maps & Places`, `Sermon Notebooks`).
  - Integrated hardware-framed Hero screenshot, interactive 4-tab Workspace Gallery, and full-resolution Lightbox.

---

## 2. Where We Are Right Now (Current Checkpoint)

- **iPad Pro:** Running `Sword & Quill` powered by hardened **`MagQLite v0.2.4`** (all personal notes & study data intact).
- **GitHub Branches:**
  - `feat/magqlite`: `5e20d34` (clean working tree, ready for next feature)
  - `website`: `627605e` (live on Hostinger `swordandquillbible.com`)
  - `main`: `e774ae7` (pre-MagQLite baseline — will merge `feat/magqlite` → `main` for v1.0 release)

---

## 3. What We Are Getting Ready to Build Next

### Phase A — e-Sword–Style Modular Library Manager & Commentaries *(NEXT UP)*
**Goal:** Give believers and pastors opt-in, zero-bloat access to classic verse-by-verse commentaries (and a future-proof format for extra Bible translations, dictionaries, and devotionals) without forcing theological bias or bloating the base app.

1. **Standardized `.sqmod` Module Format (MagQLite-backed):**
   - Self-contained `.mql` file (gzip-compressed as `.sqmod` for download) stored in `Application Support/KJVStudyBible/Modules/`.
   - Standardized `module_meta` table: `id`, `kind` (`commentary`, `bible`, `dictionary`, `devotional`), `title`, `abbr`, `author`, `description`, `copyright`, `version`, `size_bytes`.
   - Standardized `commentary_entries` table: `(id, book_id, chapter, verse_start, verse_end, bc_key, heading, body)` with persisted B+Tree index on `bc_key` for sub-millisecond verse/chapter lookups.
2. **Pre-Installed Removable Starter Module:**
   - Bundle **Matthew Henry’s Concise Commentary** (~5 MB) as a real removable/toggleable module so commentaries work 100% offline on Day 1, while Scripture-only readers can disable or remove it in 1 tap.
3. **1-Tap Offline Commentary Downloads (`swordandquillbible.com/modules/catalog.json`):**
   - Host free public-domain classics statically on Hostinger (migratable to Cloudflare R2 later via JSON URL change with zero app update):
     - **Matthew Henry’s Complete Commentary**
     - **Jamieson-Fausset-Brown (JFB) Commentary**
     - **Albert Barnes’ Notes on the Bible**
     - **John Gill’s Exposition of the Entire Bible**
     - **Spurgeon’s Treasury of David** (Psalms)
   - Support **AirDrop / Files sideloading** of custom `.sqmod` files (just like `.sqstudy`).
4. **In-App UI (`LibraryManagerSheet.swift` + `LeftStudyDeskView.swift`):**
   - **Library Manager** (accessible from Main Menu & Study Desk): Browse catalog, Download with progress bar, Enable/Disable toggle, Delete to reclaim storage, Import `.sqmod`.
   - **Commentary Tab in Left Study Desk:** Automatically appears when ≥1 commentary module is enabled (hides completely if none are enabled). Switch between installed commentaries, read verse- or chapter-synced notes, and tap **"Clip to Journal"** to drop any commentary quote straight into the Apple Pencil margin!

### Phase B — App Store v1.0 Launch Checklist
- Enroll / configure Apple Developer Account & App Store Connect record.
- Register Release Bundle ID and 4 StoreKit 2 Product IDs (`com.swordandquillbible.pro.classroom`, `tip.coffee`, `tip.fuel`, `tip.supporter`).
- Final Release build check (confirm `#if DEBUG` helpers like `ShowcaseSeeder` and `debugSimulateProUnlocked` are automatically stripped in Release).
- Merge `feat/magqlite` → `main`, tag `v1.0.0`, run TestFlight beta on physical iPad(s), upload App Store screenshots (using our verified USB capture pipeline!), and submit to App Store Review.

### Phase C — Post-Launch v1.1+ Ideas (Backlog)
- Additional `.sqmod` module types: **Extra Public-Domain Bible Translations** (ASV 1901, Geneva 1599, Darby, Young’s Literal, Reina-Valera 1909) for Parallel Bible & main reading, plus **Classic Devotionals** (Spurgeon’s *Morning & Evening*).
- **On-Device Neural Bible Narrator (Kokoro-82M, Apache 2.0, ~85 MB)** as an optional downloadable high-naturalness voice pack for Read-Aloud audio.
- Optional iCloud / encrypted sync research (only if requested — preserving 100% offline-first zero-account ethos).
