# Sword & Quill Study Bible

**A native, 100% offline, Apple Pencil–first King James Version (KJV) Study & Journaling Bible for iPad.**

> *"Thy word is a lamp unto my feet, and a light unto my path."* — Psalm 119:105  
> Website: **[www.swordandquillbible.com](https://www.swordandquillbible.com)**

---

## Philosophy

Most Bible apps treat Scripture like a web page and notes like tiny form fields. **Sword & Quill Study Bible** is built to feel like a **lifelong, deeply marked-up physical study Bible**—with crisp paper-like typography, natural Apple Pencil handwriting right over the text and in a wide journaling margin, deep offline reference tools, and full local ownership of your study data.

- **100% Offline & Private** — Zero accounts, zero telemetry, zero cloud lock-in. Every verse, cross-reference, Strong's entry, dictionary, map coordinate, and personal annotation lives locally on your iPad.
- **Immutable Reference vs. Personal Study** — The bundled KJV & reference library (`kjv_reference.sqlite`) is strictly read-only and separate from your lifelong personal study database (`Documents/user_study.sqlite`).

---

## Key Features

### 1. Scripture & Apple Pencil Journaling
- **Complete King James Version (KJV)** — All 66 books (`31,102` verses) with optional **Red-Letter** Words of Christ and *translator italics*.
- **Paper-Like Reading Themes** — Paper (Sepia), Light, and Dark modes with Ruled, Dot Grid, or Blank margin paper styles.
- **Unified Apple Pencil Canvas (`PencilKit`)** — Write, underline, circle, and sketch seamlessly across both Scripture and the right-hand Journal Margin with `.pencilOnly` palm rejection and `1×–3.5×` pinch/menu zoom.
- **Verse-Anchored Ink Reflow** — Apple Pencil strokes anchor to their nearest verse and column so changing font size, line spacing, or toggling panels keeps your handwriting aligned with Scripture.
- **Reading Mode** — Distraction-free reading that cleanly hides ink overlays while preserving every stroke intact.

### 2. Deep Offline Study Desk (Collapsible Left Panel)
- **Treasury of Scripture Knowledge (TSK)** — `305,923` cross-references grouped by phrase with non-pushy floating passage preview popups (`±2` context, Pin to Journal, Clip, Parallel, or Go).
- **Hebrew & Greek Interlinear + Strong's Concordance** — `425,452` original-language word rows (STEPBible `TAHOT`/`TAGNT`) linked to `14,197` Strong's Lexicon entries and full verse-occurrence lookups.
- **Classic Reference Dictionaries** — Contextual verse-aware lookups across:
  - **Webster's 1828 Dictionary** (`62,391` entries)
  - **Easton's Bible Dictionary** (`3,963` entries)
  - **Nave's Topical Bible** (`5,322` entries)
  - **Torrey's New Topical Textbook** (`628` entries)
- **Biblical Geography & Interactive Maps** — `1,335` biblical places and `8,707` verse links (OpenBible Geocoding Data) plotted on an interactive MapKit view (Satellite / Map / Terrain) with modern identifications, coordinates, distance from Jerusalem, and verse links.
- **Parallel Bible Reader** — Read and compare any second KJV passage side-by-side in the Left Study Desk.

### 3. Named Study Sessions ("Study Trails") & Permanent Bible Ink Links
- **Top-Right Study Trail Menu** — Create named studies (e.g., *"Born Again — John 3"*, *"Grace vs. Works"*) with a chosen starting passage, renameable anytime.
- **Automatic Study Trail** — Quietly records every passage visited (with time spent, deduplicated), cross-reference previewed, Strong's word inspected, place explored, highlight, and note—completely separate from general Reading History.
- **Permanent Bible Ink Links** — Drop draggable **Study Link + Margin Note** badges directly onto your permanent Bible canvas so months later you can jump straight from your Bible ink back into that Study Trail.

### 4. Sermon & Study Notebooks + On-Device OCR
- **Split, Handwriting, or Typed Notebooks** — Create Passage, Sermon, Study, Journal, or Chapter notebooks with Apple Pencil handwriting, typed outlines, and verse-range reference insertion (including ranges like `1 John 1:1-3`).
- **On-Device Handwriting-to-Text (`Vision`)** — Convert handwritten notebook pages or Bible margin ink into searchable typed text and auto-detected Scripture reference chips, 100% on-device.

### 5. Notability-Style Stickers
- **Built-in Bible Study Stickers** — 16 crisp vector study symbols (Cross, Crown, Spirit, Promise, Key Insight, Prayer, Faith, and more).
- **Custom Sticker Studio** — Sketch transparent PNG stickers with Apple Pencil, edit vector strokes later, or **Duplicate & Edit** any sticker (including built-in symbols and imported photos).
- **Photo Import & Cleanup** — Import images from Photos with live Apple Pencil/finger perimeter erasing, 1-tap on-device **Magic Cutout** (Vision foreground mask), **Drop White BG**, and auto-trimming.
- **Full Canvas Control** — Place on Bible pages or Notebooks with drag-to-move, corner drag-resize, rotation, and `0%–100%` persisted opacity (including a 1-tap `35%` preset for overlaying text).

### 6. Printable PDF Export, Study Dashboard & Atomic Backup/Restore
- **Printable / Shareable PDF Export** — Export any annotated Bible chapter (Scripture + Red-Letter + italics + highlights + Apple Pencil ink + stickers + study clips/notes) or any Sermon/Study Notebook as a clean, paginated US Letter PDF via the native iPad Share Sheet.
- **Study Dashboard** — Track Bible reading progress (`X / 1,189` chapters), study stats, most studied books, and deduplicated Reading History with time-spent tracking.
- **Atomic SQLite Backup & Restore** — Export a single self-contained `.sqlite` snapshot (`VACUUM INTO`) or restore from a backup file in Files with schema validation and automatic pre-restore safety snapshots.
- **Adaptive iPad Layout** — Full 3-column docked workspace in Landscape and smooth slide-over drawers in Portrait, Split View, and Compact widths.

---

## Project Structure

```text
bible-app/
├── Assets/AppIcon.png                  # 1024x1024 opaque app icon
├── Info.plist                          # App display name ("Sword & Quill")
├── Package.swift                       # Swift 6.0 / iOS 17+ package manifest
├── xtool.yml                           # xtool bundle & icon configuration
├── tools/
│   └── build_reference_db.py           # Deterministic SQLite builder for kjv_reference.sqlite
└── Sources/KJVStudyBible/
    ├── KJVStudyBibleApp.swift          # App entry point
    ├── Core/BibleModels.swift          # Domain models, themes, stickers, studies, ink anchors
    ├── Data/
    │   ├── ReferenceDatabase.swift     # Read-only SQLite3 access (KJV, TSK, Strong's, Dicts, Places)
    │   └── UserStudyDatabase.swift     # WAL-mode SQLite3 persistence & atomic backup/restore
    ├── State/
    │   └── BibleWorkspaceViewModel.swift # Workspace state, navigation, ink reflow, study trails
    ├── Annotation/
    │   ├── UnifiedBibleCanvas.swift    # PassthroughPKCanvasView (.pencilOnly + finger tap)
    │   └── ZoomableCanvasScrollView.swift # Native UIScrollView 1x-3.5x zoom wrapper
    ├── Export/
    │   └── StudyPDFExporter.swift      # US Letter PDF generator for chapters & notebooks
    └── UI/
        ├── TopNavigationBar.swift      # Clean icon-only top chrome + chapter nav + Study Trails
        ├── BottomUtilityBar.swift      # Icon-only utility bar + FloatingPenToolbox
        ├── ScriptureWorkspaceView.swift # Adaptive 3-panel & slide-over workspace
        ├── LeftStudyDeskView.swift     # TSK, Interlinear, Dictionaries, Parallel, Verse Popover
        ├── PlacesMapDeskView.swift     # Offline Biblical Geography & MapKit tab
        ├── NotebookEditorSheet.swift   # Split Typed/Pencil Notebook, Insert Ref, Reading History
        ├── StickerViews.swift          # Sticker Library, Creator Studio, Magic Cutout, Eraser
        ├── StudySessionsViews.swift    # New Study, Study Trail, Permanent Bible Ink Links
        ├── MarginOCRScannerSheet.swift # On-device Vision OCR for Bible margin ink
        ├── StudyDashboardSheet.swift   # Reading progress, study stats, backup & restore
        └── StudyOverlays.swift         # Scripture Picker, Unified Search, Saved, Notes, View Settings
```

---

## Building from Source

> **Note:** The compiled offline reference database (`Sources/KJVStudyBible/Resources/kjv_reference.sqlite`, ~96 MiB) is excluded from Git and deterministically built from local public-domain/open archives via `tools/build_reference_db.py`.

### 1. Build the Offline Reference Database
Place the source archives (`KJV.zip`, `tsk-bible-cross-references-main.zip`, `strongs-master.zip`, `webster1828.txt`, `STEPBible-Data-master.zip`, `Easton.zip`, `Nave.zip`, `Torrey.zip`, `Bible-Geocoding-Data-main.zip`) in `RESOURCES_DIR` (configured at the top of `tools/build_reference_db.py`), then run:

```bash
python3 tools/build_reference_db.py
```

### 2. Build & Deploy to iPad (Linux + `xtool` + `pymobiledevice3`)
```bash
xtool dev build
xtool install --usb xtool/KJVStudyBible.app
pymobiledevice3 developer dvt launch <BUNDLE_ID> --userspace
```

*(Also builds cleanly with standard SwiftPM / Xcode on macOS targeting iOS 17+.)*

---

## License & Data Attribution
- **KJV Scripture, TSK Cross-References, Strong's Concordance, Webster's 1828, Easton's, Nave's, Torrey's:** Public Domain.
- **Hebrew/Greek Interlinear (`TAHOT`/`TAGNT`):** STEPBible Data (CC BY 4.0).
- **Biblical Geography Coordinates:** OpenBible.info Bible Geocoding Data (CC BY 4.0).
