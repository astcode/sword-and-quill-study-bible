#if DEBUG
import Foundation
import PencilKit
import SwiftUI
import UIKit

@MainActor
extension BibleWorkspaceViewModel {
    /// Populates an isolated, throwaway showcase database when launched with
    /// `SWORDQUILL_SHOWCASE=<hero|dark|places|notebook|qr>` for crisp App Store / website screenshots.
    /// Never modifies the user's real `Documents/user_study.mql`.
    func applyDebugShowcase(mode: String) {
        UIApplication.shared.isIdleTimerDisabled = true
        toastMessage = nil

        switch mode.lowercased() {
        case "tour":
            runShowcaseTour()
        case "hero":
            setupHeroShowcase()
        case "dark":
            setupDarkShowcase()
        case "places":
            setupPlacesShowcase()
        case "notebook":
            setupNotebookShowcase()
        case "qr":
            setupQRShowcase()
        default:
            setupHeroShowcase()
        }
    }

    private func runShowcaseTour() {
        setupHeroShowcase()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            activeNotebookNote = nil
            sharingStudy = nil
            setupDarkShowcase()

            try? await Task.sleep(for: .seconds(8))
            setupPlacesShowcase()

            try? await Task.sleep(for: .seconds(9))
            setupNotebookShowcase()

            try? await Task.sleep(for: .seconds(8))
            activeNotebookNote = nil
            setupQRShowcase()
        }
    }

    // MARK: - Scene 1: Hero (Warm Paper · 3-Column Journaling — John 14:1–6)

    private func setupHeroShowcase() {
        theme = .paperSepia
        paperStyle = .ruled
        fontSize = 18.5
        lineSpacing = 7.5
        showRedLetter = true
        showItalics = true
        showVerseNumbers = true
        showReferencePanel = true
        showJournalPanel = true
        workspaceMode = .journaling
        leftPanelWidth = 0

        let session = seedGraceStudySession()
        activeStudy = session
        activeStudyTrail = studyDB.studyTrailEntries(studyId: session.id)

        navigate(to: VerseRef(bookId: 43, chapter: 14, verse: nil), pushHistory: true)

        // Highlights: v.1 Promise Gold, v.6 Grace Study Blue
        if let v1 = verses.first(where: { $0.verse == 1 }) {
            studyDB.setHighlight(bookId: 43, chapter: 14, verse: 1, colorHex: "#C6A645", category: "Promise")
            _ = v1
        }
        if let v6 = verses.first(where: { $0.verse == 6 }) {
            studyDB.setHighlight(bookId: 43, chapter: 14, verse: 6, colorHex: "#5A96E3", category: "Grace")
            openLeftStudy(tab: .strongs, for: v6)
            selectStrongsId("G3598")
        }
        chapterHighlights = studyDB.highlights(bookId: 43, chapter: 14)

        // Wait briefly for SwiftUI to report exact verse frames, then place margin items & Apple Pencil ink pixel-accurately!
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            let marginX = max(440.0, Double(currentScriptureWidth) + 22.0)
            let v1Rect = currentVerseFrames[1] ?? CGRect(x: 16, y: 78, width: 410, height: 68)
            let v6Rect = currentVerseFrames[6] ?? CGRect(x: 16, y: 405, width: 410, height: 86)

            // 1. Pinned Reference Chips
            let pin1 = PinnedReference(
                id: "showcase-pin-1",
                bookId: 43, chapter: 14,
                targetBookId: 19, targetChapter: 23, targetVerseStart: 4, targetVerseEnd: 4,
                label: "Ps 23:4",
                posX: marginX + 68,
                posY: Double(v1Rect.minY) + 20,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            let pin2 = PinnedReference(
                id: "showcase-pin-2",
                bookId: 43, chapter: 14,
                targetBookId: 44, targetChapter: 4, targetVerseStart: 12, targetVerseEnd: 12,
                label: "Acts 4:12",
                posX: marginX + 195,
                posY: Double(v1Rect.minY) + 20,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            studyDB.upsertPinnedReference(pin1, studyId: session.id)
            studyDB.upsertPinnedReference(pin2, studyId: session.id)

            // 2. Journal Clip Card (centered cleanly inside the Journal Margin)
            let clip = JournalClipCard(
                id: "showcase-clip-1",
                bookId: 43, chapter: 14,
                sourceLabel: "Strong's G3598 · ὁδός (hodós)",
                excerpt: "Not merely a road shown, but the living Way Himself — direct access to the Father through Christ.",
                userNote: "Connect to Heb 10:19–20 — “a new and living way.”",
                posX: marginX + 34,
                posY: Double(v1Rect.maxY) + 74,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            studyDB.upsertJournalClip(clip, studyId: session.id)

            // 3. Permanent Study Link Card (neatly tucked below v.6 ink callout)
            let link = StudyMarginLink(
                id: "showcase-link-1",
                studyId: session.id,
                studyName: session.name,
                bookId: 43, chapter: 14, verse: 6,
                noteText: "Sunday School Lesson 4 · Three-fold claim of Christ",
                posX: marginX + 26,
                posY: Double(v6Rect.maxY) + 18,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            studyDB.upsertStudyMarginLink(link)

            // 4. Subtle Sticker in upper right margin
            if let starSticker = stickerLibrary.first(where: { $0.symbolName?.contains("book") == true }) ?? stickerLibrary.first {
                _ = studyDB.addPlacedSticker(
                    stickerId: starSticker.id,
                    targetType: "study_chapter",
                    targetKey: "\(session.id)-43-14",
                    posX: marginX + 238,
                    posY: Double(v1Rect.minY) + 22,
                    width: 44,
                    height: 44,
                    rotation: -6
                )
            }

            // 5. Crisp Apple Pencil PKDrawing Annotations (bracket + curved arrow + underline + margin star)
            let drawing = ShowcaseInkBuilder.buildHeroAnnotations(
                v1Rect: v1Rect,
                v6Rect: v6Rect,
                marginX: CGFloat(marginX),
                isDark: false
            )
            handleCanvasDrawingChanged(drawing, canUndo: false, canRedo: false)
            reloadActiveChapterLayer()
            toastMessage = nil
        }
    }

    // MARK: - Scene 2: Dark Mode · 3-Column Study & Journaling (John 1:1–5)

    private func setupDarkShowcase() {
        theme = .dark
        paperStyle = .dotGrid
        fontSize = 18.5
        lineSpacing = 7.5
        showRedLetter = true
        showItalics = true
        showVerseNumbers = true
        showReferencePanel = true
        showJournalPanel = true
        workspaceMode = .journaling
        leftPanelWidth = 0
        activeStudy = nil

        navigate(to: VerseRef(bookId: 43, chapter: 1, verse: nil), pushHistory: true)
        leftPanelTab = .crossRefs
        expandedReferenceVerses = [1]

        studyDB.setHighlight(bookId: 43, chapter: 1, verse: 1, colorHex: "#C6A645", category: "Promise")
        studyDB.setHighlight(bookId: 43, chapter: 1, verse: 4, colorHex: "#5A96E3", category: "Grace")
        chapterHighlights = studyDB.highlights(bookId: 43, chapter: 1)
        if let v1 = verses.first(where: { $0.verse == 1 }) {
            studyVerse = v1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            let marginX = max(440.0, Double(currentScriptureWidth) + 22.0)
            let v1Rect = currentVerseFrames[1] ?? CGRect(x: 16, y: 78, width: 410, height: 68)
            let v4Rect = currentVerseFrames[4] ?? CGRect(x: 16, y: 260, width: 410, height: 64)

            let pin1 = PinnedReference(
                id: "showcase-dark-pin-1",
                bookId: 43, chapter: 1,
                targetBookId: 1, targetChapter: 1, targetVerseStart: 1, targetVerseEnd: 1,
                label: "Gen 1:1",
                posX: marginX + 70,
                posY: Double(v1Rect.minY) + 20,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            let pin2 = PinnedReference(
                id: "showcase-dark-pin-2",
                bookId: 43, chapter: 1,
                targetBookId: 58, targetChapter: 1, targetVerseStart: 2, targetVerseEnd: 3,
                label: "Heb 1:2–3",
                posX: marginX + 190,
                posY: Double(v1Rect.minY) + 20,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            studyDB.upsertPinnedReference(pin1, studyId: "")
            studyDB.upsertPinnedReference(pin2, studyId: "")

            let clip = JournalClipCard(
                id: "showcase-dark-clip-1",
                bookId: 43, chapter: 1,
                sourceLabel: "Strong's G3056 · λόγος (Lógos)",
                excerpt: "The eternal Word — co-existent with God and fully God before creation began.",
                userNote: "John echoes Genesis 1:1 intentionally: Christ is Creator, Life, and Light.",
                posX: marginX + 34,
                posY: Double(v1Rect.maxY) + 54,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            studyDB.upsertJournalClip(clip, studyId: "")

            let drawing = ShowcaseInkBuilder.buildHeroAnnotations(
                v1Rect: v1Rect,
                v6Rect: v4Rect,
                marginX: CGFloat(marginX),
                isDark: true
            )
            handleCanvasDrawingChanged(drawing, canUndo: false, canRedo: false)
            reloadActiveChapterLayer()
            toastMessage = nil
        }
    }

    // MARK: - Scene 3: Interactive Biblical Geography & Nearby Places Map (John 4)

    private func setupPlacesShowcase() {
        theme = .paperSepia
        fontSize = 18.5
        lineSpacing = 7.5
        showRedLetter = true
        showItalics = true
        showReferencePanel = true
        showJournalPanel = false
        workspaceMode = .study
        leftPanelWidth = 480
        activeStudy = nil

        navigate(to: VerseRef(bookId: 43, chapter: 4, verse: nil), pushHistory: true)
        leftPanelTab = .places
        studyDB.setHighlight(bookId: 43, chapter: 4, verse: 14, colorHex: "#5A96E3", category: "Grace")
        chapterHighlights = studyDB.highlights(bookId: 43, chapter: 4)
        toastMessage = nil
    }

    // MARK: - Scene 4: Rich Sermon Outline Notebook + Apple Pencil Sketch

    private func setupNotebookShowcase() {
        theme = .paperSepia
        showReferencePanel = true
        showJournalPanel = true
        workspaceMode = .journaling
        navigate(to: VerseRef(bookId: 43, chapter: 14, verse: nil), pushHistory: true)

        let body = """
        THE WAY, THE TRUTH, AND THE LIFE
        Text: John 14:1–6 · Upper Room Discourse

        I. The Comfort of a Settled Heart (John 14:1–3)
           • "Let not your heart be troubled" — peace anchored in a Person, not circumstances.
           • See Psalm 23:4 and Philippians 4:7 for the promise of God's sustaining presence.
           • Christ prepares an eternal dwelling ("many mansions") and promises His return.

        II. The Exclusive & Compassionate Claim (John 14:6)
           • THE WAY (ὁδός, G3598) — Direct access to the Father (Hebrews 10:19–20).
           • THE TRUTH (ἀλήθεια, G225) — The full revelation of God's character (John 1:14).
           • THE LIFE (ζωή, G2222) — Eternal life imparted by grace through faith (Acts 4:12).

        III. Application for This Week
           • Rest in Christ's finished promise rather than anxious striving.
           • Share the hope of John 14:6 with gentleness and clarity.
        """

        let sketch = ShowcaseInkBuilder.buildNotebookDiagram()
        let note = UserNote(
            id: "showcase-sermon-john14",
            noteType: .sermon,
            title: "The Way, the Truth & the Life — John 14:1–6",
            body: body,
            richBodyRTF: nil,
            drawingData: sketch.dataRepresentation(),
            bookId: 43,
            chapter: 14,
            verse: 6,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        studyDB.saveNote(
            id: note.id,
            noteType: note.noteType,
            title: note.title,
            body: note.body,
            richBodyRTF: nil,
            drawingData: note.drawingData,
            bookId: 43,
            chapter: 14,
            verse: 6
        )
        notes = studyDB.allNotes()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            activeNotebookNote = note
            toastMessage = nil
        }
    }

    // MARK: - Scene 5: Offline Classroom QR Code Share Sheet

    private func setupQRShowcase() {
        theme = .paperSepia
        showReferencePanel = true
        showJournalPanel = true
        workspaceMode = .journaling
        storeManager.debugSimulateProUnlocked = true
        teacherAuthorName = "Pastor Aaron"

        let session = seedGraceStudySession()
        activeStudy = session
        activeStudyTrail = studyDB.studyTrailEntries(studyId: session.id)
        navigate(to: VerseRef(bookId: 43, chapter: 14, verse: 6), pushHistory: true)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            sharingStudy = session
            toastMessage = nil
        }
    }

    // MARK: - Shared Study Session Seed

    private func seedGraceStudySession() -> StudySession {
        let session = studyDB.createStudySession(
            name: "The Way, the Truth & the Life",
            startBookId: 43,
            startChapter: 14,
            startVerse: 6,
            summaryNote: "Sunday School Series · Exploring Christ's Upper Room promise across John 14, Hebrews 10, and Acts 4."
        )
        _ = studyDB.appendStudyTrailEntry(studyId: session.id, kind: .passage, title: "John 14:1–6", detail: "Upper Room promise of peace and the Father's house", bookId: 43, chapter: 14, verse: 1)
        _ = studyDB.appendStudyTrailEntry(studyId: session.id, kind: .strongs, title: "Strong's G3598 · ὁδός (hodós)", detail: "The Way — a road, journey, or manner of access to God", bookId: 43, chapter: 14, verse: 6, refKey: "G3598")
        _ = studyDB.appendStudyTrailEntry(studyId: session.id, kind: .crossRef, title: "Hebrews 10:19–20", detail: "By a new and living way, which he hath consecrated for us", bookId: 58, chapter: 10, verse: 20)
        _ = studyDB.appendStudyTrailEntry(studyId: session.id, kind: .crossRef, title: "Acts 4:12", detail: "Neither is there salvation in any other", bookId: 44, chapter: 4, verse: 12)
        _ = studyDB.appendStudyTrailEntry(studyId: session.id, kind: .crossRef, title: "Psalm 23:4", detail: "I will fear no evil: for thou art with me", bookId: 19, chapter: 23, verse: 4)
        _ = studyDB.appendStudyTrailEntry(studyId: session.id, kind: .note, title: "Sermon Outline: Three-Fold Claim", detail: "Way (Access) · Truth (Revelation) · Life (Regeneration)", bookId: 43, chapter: 14, verse: 6)
        studySessions = studyDB.allStudySessions()
        return session
    }
}

// MARK: - Procedural Natural-Looking Apple Pencil Ink Builder

private enum ShowcaseInkBuilder {
    static func buildHeroAnnotations(v1Rect: CGRect, v6Rect: CGRect, marginX: CGFloat, isDark: Bool) -> PKDrawing {
        var strokes: [PKStroke] = []

        let blueInk = PKInk(.pen, color: isDark
            ? UIColor(red: 0.533, green: 0.702, blue: 0.922, alpha: 1.0)
            : UIColor(red: 0.165, green: 0.365, blue: 0.615, alpha: 1.0))
        let crimsonInk = PKInk(.pen, color: isDark
            ? UIColor(red: 0.920, green: 0.455, blue: 0.455, alpha: 1.0)
            : UIColor(red: 0.680, green: 0.180, blue: 0.180, alpha: 1.0))
        let goldMarker = PKInk(.marker, color: UIColor(red: 0.776, green: 0.651, blue: 0.271, alpha: 0.38))

        // 1. Graceful curly margin bracket alongside v.6 (or v.4 in dark mode)
        let bx = marginX - 10
        let topY = v6Rect.minY + 6
        let botY = v6Rect.maxY - 6
        let midY = (topY + botY) * 0.5
        strokes.append(smoothStroke(points: [
            CGPoint(x: bx - 6, y: topY),
            CGPoint(x: bx + 2, y: topY + 6),
            CGPoint(x: bx + 2, y: midY - 8),
            CGPoint(x: bx + 9, y: midY),
            CGPoint(x: bx + 2, y: midY + 8),
            CGPoint(x: bx + 2, y: botY - 6),
            CGPoint(x: bx - 6, y: botY)
        ], ink: blueInk, width: 2.8))

        // 2. Curved callout arrow from bracket into the ruled margin
        let arrowEndX = marginX + 44
        let arrowEndY = midY - 6
        strokes.append(smoothStroke(points: [
            CGPoint(x: bx + 11, y: midY),
            CGPoint(x: marginX + 18, y: midY - 4),
            CGPoint(x: arrowEndX, y: arrowEndY)
        ], ink: crimsonInk, width: 2.4))
        // Arrowhead
        strokes.append(smoothStroke(points: [
            CGPoint(x: arrowEndX - 10, y: arrowEndY - 6),
            CGPoint(x: arrowEndX + 1, y: arrowEndY),
            CGPoint(x: arrowEndX - 9, y: arrowEndY + 7)
        ], ink: crimsonInk, width: 2.4))

        // 3. Hand-drawn star in the margin beside v.1
        let sx = marginX + 20
        let sy = v1Rect.minY + 20
        strokes.append(handStar(center: CGPoint(x: sx, y: sy), radius: 10, ink: crimsonInk))

        // 4. Clean hand-lettered ink phrase in the margin beside v.6: "THE WAY" / "TRUTH + LIFE"
        let textStartX = marginX + 54
        let textY = midY - 18
        strokes.append(contentsOf: handWord("THE WAY", origin: CGPoint(x: textStartX, y: textY), height: 15, ink: crimsonInk, width: 3.0))
        // Hand-drawn gold highlight beneath "THE WAY"
        strokes.append(smoothStroke(points: [
            CGPoint(x: textStartX - 2, y: textY + 19),
            CGPoint(x: textStartX + 48, y: textY + 17.5),
            CGPoint(x: textStartX + 102, y: textY + 18.5)
        ], ink: goldMarker, width: 7.0))
        strokes.append(contentsOf: handWord("TRUTH + LIFE", origin: CGPoint(x: textStartX, y: textY + 27), height: 13, ink: blueInk, width: 2.8))

        // 5. Subtle hand-drawn underline on the first line of v.6
        strokes.append(smoothStroke(points: [
            CGPoint(x: v6Rect.minX + 52, y: v6Rect.minY + 28),
            CGPoint(x: v6Rect.minX + 150, y: v6Rect.minY + 29.5),
            CGPoint(x: v6Rect.minX + 250, y: v6Rect.minY + 28.0)
        ], ink: crimsonInk, width: 1.9))

        return PKDrawing(strokes: strokes)
    }

    static func buildNotebookDiagram() -> PKDrawing {
        var strokes: [PKStroke] = []
        let blueInk = PKInk(.pen, color: UIColor(red: 0.165, green: 0.365, blue: 0.615, alpha: 1.0))
        let crimsonInk = PKInk(.pen, color: UIColor(red: 0.680, green: 0.180, blue: 0.180, alpha: 1.0))
        let goldMarker = PKInk(.marker, color: UIColor(red: 0.776, green: 0.651, blue: 0.271, alpha: 0.36))

        // Title highlight + hand-lettered header
        strokes.append(smoothStroke(points: [
            CGPoint(x: 36, y: 44), CGPoint(x: 150, y: 42), CGPoint(x: 265, y: 44)
        ], ink: goldMarker, width: 14))
        strokes.append(contentsOf: handWord("JOHN 14:6", origin: CGPoint(x: 42, y: 34), height: 18, ink: crimsonInk, width: 2.6))

        // Three connected pillars: WAY -> TRUTH -> LIFE
        let labels = [("1. WAY", "ACCESS"), ("2. TRUTH", "LIGHT"), ("3. LIFE", "GRACE")]
        for (idx, pair) in labels.enumerated() {
            let y = CGFloat(92 + idx * 82)
            // Rounded hand-drawn box
            strokes.append(handBox(rect: CGRect(x: 38, y: y, width: 145, height: 48), ink: blueInk))
            strokes.append(contentsOf: handWord(pair.0, origin: CGPoint(x: 54, y: y + 15), height: 15, ink: blueInk, width: 2.2))

            // Arrow to right meaning
            strokes.append(smoothStroke(points: [
                CGPoint(x: 192, y: y + 24),
                CGPoint(x: 215, y: y + 23),
                CGPoint(x: 236, y: y + 24)
            ], ink: crimsonInk, width: 2.2))
            strokes.append(smoothStroke(points: [
                CGPoint(x: 228, y: y + 18),
                CGPoint(x: 237, y: y + 24),
                CGPoint(x: 228, y: y + 30)
            ], ink: crimsonInk, width: 2.2))

            strokes.append(contentsOf: handWord(pair.1, origin: CGPoint(x: 250, y: y + 16), height: 14, ink: crimsonInk, width: 2.1))
        }

        return PKDrawing(strokes: strokes)
    }

    // MARK: - Low-Level Stroke Primitives

    private static func smoothStroke(points: [CGPoint], ink: PKInk, width: CGFloat) -> PKStroke {
        let sampled = densify(points: points, stepsPerSegment: 8)
        let pkPoints = sampled.enumerated().map { idx, pt in
            // Slight natural taper at start and end
            let t = Double(idx) / Double(max(1, sampled.count - 1))
            let taper: CGFloat = (t < 0.08 || t > 0.92) ? 0.78 : 1.0
            let w = width * taper
            return PKStrokePoint(
                location: pt,
                timeOffset: TimeInterval(idx) * 0.008,
                size: CGSize(width: w, height: w),
                opacity: 1.0,
                force: 1.0,
                azimuth: 0.4,
                altitude: 1.1
            )
        }
        let path = PKStrokePath(controlPoints: pkPoints, creationDate: Date())
        return PKStroke(ink: ink, path: path)
    }

    private static func densify(points: [CGPoint], stepsPerSegment: Int) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        var out: [CGPoint] = []
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(points.count - 1, i + 2)]
            for s in 0..<stepsPerSegment {
                let t = CGFloat(s) / CGFloat(stepsPerSegment)
                out.append(catmullRom(p0, p1, p2, p3, t: t))
            }
        }
        out.append(points.last!)
        return out
    }

    private static func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: CGFloat) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t
        let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
        let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
        return CGPoint(x: x, y: y)
    }

    private static func handBox(rect: CGRect, ink: PKInk) -> PKStroke {
        let pts = [
            CGPoint(x: rect.minX + 4, y: rect.minY),
            CGPoint(x: rect.maxX - 4, y: rect.minY + 1),
            CGPoint(x: rect.maxX, y: rect.minY + 6),
            CGPoint(x: rect.maxX - 1, y: rect.maxY - 5),
            CGPoint(x: rect.maxX - 6, y: rect.maxY),
            CGPoint(x: rect.minX + 5, y: rect.maxY - 1),
            CGPoint(x: rect.minX, y: rect.maxY - 6),
            CGPoint(x: rect.minX + 1, y: rect.minY + 5),
            CGPoint(x: rect.minX + 5, y: rect.minY + 1)
        ]
        return smoothStroke(points: pts, ink: ink, width: 2.2)
    }

    private static func handStar(center: CGPoint, radius: CGFloat, ink: PKInk) -> PKStroke {
        var pts: [CGPoint] = []
        let order = [0, 2, 4, 1, 3, 0]
        for idx in order {
            let angle = -CGFloat.pi / 2 + CGFloat(idx) * (2 * .pi / 5)
            pts.append(CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        }
        return smoothStroke(points: pts, ink: ink, width: 2.0)
    }

    /// Clean architectural/hand-printed stroke font for crisp, legible Apple Pencil margin notes.
    private static func handWord(_ text: String, origin: CGPoint, height h: CGFloat, ink: PKInk, width: CGFloat) -> [PKStroke] {
        var result: [PKStroke] = []
        var cursorX = origin.x
        let w = h * 0.62
        let gap = h * 0.28

        for ch in text.uppercased() {
            let strokes = glyphStrokes(ch)
            for poly in strokes {
                let mapped = poly.map { pt in
                    CGPoint(x: cursorX + pt.x * w, y: origin.y + pt.y * h)
                }
                result.append(smoothStroke(points: mapped, ink: ink, width: width))
            }
            cursorX += (ch == " " ? w * 0.55 : (ch == "I" || ch == "1" || ch == ":" || ch == "." ? w * 0.45 : w)) + gap
        }
        return result
    }

    private static func glyphStrokes(_ ch: Character) -> [[CGPoint]] {
        switch ch {
        case "A": return [[CGPoint(x: 0.0, y: 1.0), CGPoint(x: 0.5, y: 0.0), CGPoint(x: 1.0, y: 1.0)], [CGPoint(x: 0.18, y: 0.66), CGPoint(x: 0.82, y: 0.64)]]
        case "C": return [[CGPoint(x: 0.92, y: 0.18), CGPoint(x: 0.5, y: 0.0), CGPoint(x: 0.06, y: 0.5), CGPoint(x: 0.5, y: 1.0), CGPoint(x: 0.95, y: 0.82)]]
        case "E": return [[CGPoint(x: 0.88, y: 0.04), CGPoint(x: 0.08, y: 0.04), CGPoint(x: 0.08, y: 0.96), CGPoint(x: 0.92, y: 0.96)], [CGPoint(x: 0.08, y: 0.5), CGPoint(x: 0.76, y: 0.48)]]
        case "F": return [[CGPoint(x: 0.9, y: 0.04), CGPoint(x: 0.1, y: 0.04), CGPoint(x: 0.1, y: 0.98)], [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.78, y: 0.48)]]
        case "G": return [[CGPoint(x: 0.9, y: 0.16), CGPoint(x: 0.48, y: 0.0), CGPoint(x: 0.06, y: 0.5), CGPoint(x: 0.48, y: 1.0), CGPoint(x: 0.92, y: 0.78), CGPoint(x: 0.92, y: 0.54), CGPoint(x: 0.54, y: 0.54)]]
        case "H": return [[CGPoint(x: 0.08, y: 0.02), CGPoint(x: 0.08, y: 0.98)], [CGPoint(x: 0.92, y: 0.02), CGPoint(x: 0.92, y: 0.98)], [CGPoint(x: 0.08, y: 0.5), CGPoint(x: 0.92, y: 0.48)]]
        case "I": return [[CGPoint(x: 0.25, y: 0.04), CGPoint(x: 0.25, y: 0.96)]]
        case "J": return [[CGPoint(x: 0.78, y: 0.04), CGPoint(x: 0.78, y: 0.74), CGPoint(x: 0.46, y: 0.98), CGPoint(x: 0.08, y: 0.80)]]
        case "L": return [[CGPoint(x: 0.1, y: 0.04), CGPoint(x: 0.1, y: 0.96), CGPoint(x: 0.92, y: 0.94)]]
        case "N": return [[CGPoint(x: 0.08, y: 0.96), CGPoint(x: 0.08, y: 0.04), CGPoint(x: 0.92, y: 0.96), CGPoint(x: 0.92, y: 0.04)]]
        case "O": return [[CGPoint(x: 0.5, y: 0.02), CGPoint(x: 0.06, y: 0.5), CGPoint(x: 0.5, y: 0.98), CGPoint(x: 0.94, y: 0.5), CGPoint(x: 0.5, y: 0.02)]]
        case "R": return [[CGPoint(x: 0.1, y: 0.98), CGPoint(x: 0.1, y: 0.04), CGPoint(x: 0.76, y: 0.08), CGPoint(x: 0.86, y: 0.28), CGPoint(x: 0.72, y: 0.48), CGPoint(x: 0.1, y: 0.52)], [CGPoint(x: 0.48, y: 0.52), CGPoint(x: 0.94, y: 0.98)]]
        case "S": return [[CGPoint(x: 0.88, y: 0.14), CGPoint(x: 0.48, y: 0.02), CGPoint(x: 0.12, y: 0.24), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.88, y: 0.74), CGPoint(x: 0.48, y: 0.98), CGPoint(x: 0.1, y: 0.84)]]
        case "T": return [[CGPoint(x: 0.04, y: 0.05), CGPoint(x: 0.96, y: 0.04)], [CGPoint(x: 0.5, y: 0.05), CGPoint(x: 0.48, y: 0.98)]]
        case "U": return [[CGPoint(x: 0.1, y: 0.04), CGPoint(x: 0.1, y: 0.76), CGPoint(x: 0.5, y: 0.98), CGPoint(x: 0.9, y: 0.76), CGPoint(x: 0.9, y: 0.04)]]
        case "W": return [[CGPoint(x: 0.04, y: 0.04), CGPoint(x: 0.26, y: 0.96), CGPoint(x: 0.5, y: 0.36), CGPoint(x: 0.74, y: 0.96), CGPoint(x: 0.96, y: 0.04)]]
        case "Y": return [[CGPoint(x: 0.06, y: 0.04), CGPoint(x: 0.5, y: 0.52), CGPoint(x: 0.94, y: 0.04)], [CGPoint(x: 0.5, y: 0.52), CGPoint(x: 0.5, y: 0.98)]]
        case "1": return [[CGPoint(x: 0.28, y: 0.06), CGPoint(x: 0.28, y: 0.96)]]
        case "2": return [[CGPoint(x: 0.12, y: 0.22), CGPoint(x: 0.52, y: 0.02), CGPoint(x: 0.88, y: 0.24), CGPoint(x: 0.1, y: 0.96), CGPoint(x: 0.92, y: 0.95)]]
        case "3": return [[CGPoint(x: 0.14, y: 0.14), CGPoint(x: 0.55, y: 0.02), CGPoint(x: 0.86, y: 0.24), CGPoint(x: 0.44, y: 0.48), CGPoint(x: 0.88, y: 0.74), CGPoint(x: 0.5, y: 0.98), CGPoint(x: 0.12, y: 0.86)]]
        case "4": return [[CGPoint(x: 0.74, y: 0.96), CGPoint(x: 0.74, y: 0.04), CGPoint(x: 0.08, y: 0.64), CGPoint(x: 0.94, y: 0.64)]]
        case "6": return [[CGPoint(x: 0.82, y: 0.10), CGPoint(x: 0.36, y: 0.06), CGPoint(x: 0.1, y: 0.56), CGPoint(x: 0.46, y: 0.98), CGPoint(x: 0.88, y: 0.74), CGPoint(x: 0.54, y: 0.46), CGPoint(x: 0.12, y: 0.60)]]
        case "+": return [[CGPoint(x: 0.5, y: 0.24), CGPoint(x: 0.5, y: 0.78)], [CGPoint(x: 0.2, y: 0.51), CGPoint(x: 0.8, y: 0.51)]]
        case ":": return [[CGPoint(x: 0.24, y: 0.30), CGPoint(x: 0.28, y: 0.34)], [CGPoint(x: 0.24, y: 0.74), CGPoint(x: 0.28, y: 0.78)]]
        case ".": return [[CGPoint(x: 0.24, y: 0.86), CGPoint(x: 0.30, y: 0.90)]]
        default: return []
        }
    }
}
#endif
