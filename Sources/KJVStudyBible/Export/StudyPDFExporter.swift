import Foundation
import PencilKit
import SwiftUI
import UIKit

// MARK: - Printable / Shareable PDF Exporter (Annotated Bible Chapters & Sermon/Study Notebooks)

public enum StudyPDFExporter {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
    private static let marginX: CGFloat = 40
    private static let marginTop: CGFloat = 44
    private static let marginBottom: CGFloat = 44

    // MARK: - 1. Annotated Bible Chapter PDF

    public static func exportAnnotatedChapter(
        bookName: String,
        chapter: Int,
        verses: [Verse],
        highlights: [Int: UserHighlight],
        drawing: PKDrawing,
        canvasWidth: CGFloat,
        verseFrames: [Int: CGRect],
        pinnedRefs: [PinnedReference],
        clips: [JournalClipCard],
        chapterNotes: [UserNote],
        placedStickers: [PlacedSticker],
        stickerLookup: [String: StickerItem],
        showRedLetter: Bool,
        showItalics: Bool
    ) -> URL? {
        let safeName = "SwordAndQuill-\(bookName)-\(chapter)-KJV.pdf"
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        try? FileManager.default.removeItem(at: dest)

        let printableW = pageRect.width - marginX * 2
        let printableH = pageRect.height - marginTop - marginBottom
        let hasMarginContent = !drawing.strokes.isEmpty || !pinnedRefs.isEmpty || !clips.isEmpty || !placedStickers.isEmpty
        let scriptureColW: CGFloat = hasMarginContent ? floor(printableW * 0.62) : printableW
        let dividerX = marginX + scriptureColW + 8

        let meta: [String: Any] = [
            kCGPDFContextCreator as String: "Sword & Quill Study Bible (www.swordandquillbible.com)",
            kCGPDFContextTitle as String: "\(bookName) \(chapter) — Sword & Quill Study Bible"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = meta
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)

        do {
            try renderer.writePDF(to: dest) { ctx in
                var pageIndex = 1
                var cursorY = marginTop

                func beginNewPage(isFirst: Bool) {
                    ctx.beginPage()
                    drawPageFooter(ctx.cgContext, title: "\(bookName) \(chapter) · Sword & Quill Study Bible · swordandquillbible.com", pageNumber: pageIndex)
                    if isFirst {
                        let titleAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont(name: "Georgia-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20),
                            .foregroundColor: UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1.0)
                        ]
                        let subAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 9.5, weight: .medium),
                            .foregroundColor: UIColor.darkGray
                        ]
                        ("\(bookName) \(chapter)" as NSString).draw(at: CGPoint(x: marginX, y: marginTop), withAttributes: titleAttrs)
                        ("King James Version · Exported \(dateStr)" as NSString).draw(at: CGPoint(x: marginX, y: marginTop + 25), withAttributes: subAttrs)
                        cursorY = marginTop + 44
                        ctx.cgContext.setStrokeColor(UIColor(white: 0.78, alpha: 1.0).cgColor)
                        ctx.cgContext.setLineWidth(0.75)
                        ctx.cgContext.move(to: CGPoint(x: marginX, y: cursorY))
                        ctx.cgContext.addLine(to: CGPoint(x: pageRect.width - marginX, y: cursorY))
                        ctx.cgContext.strokePath()
                        cursorY += 12
                    } else {
                        cursorY = marginTop
                    }

                    if hasMarginContent {
                        // Subtle margin vertical divider and ruled lines
                        let cg = ctx.cgContext
                        cg.setStrokeColor(UIColor(white: 0.84, alpha: 1.0).cgColor)
                        cg.setLineWidth(0.6)
                        cg.move(to: CGPoint(x: dividerX, y: cursorY))
                        cg.addLine(to: CGPoint(x: dividerX, y: pageRect.height - marginBottom))
                        cg.strokePath()

                        cg.setStrokeColor(UIColor(white: 0.91, alpha: 1.0).cgColor)
                        var ly = cursorY + 18
                        while ly < pageRect.height - marginBottom {
                            cg.move(to: CGPoint(x: dividerX + 8, y: ly))
                            cg.addLine(to: CGPoint(x: pageRect.width - marginX, y: ly))
                            ly += 20
                        }
                        cg.strokePath()
                    }
                }

                // Track where each verse landed on PDF pages so we can map ink & stickers accurately
                struct PDFVersePlacement {
                    let pageIndex: Int
                    let rect: CGRect
                }
                var pdfVerseMap: [Int: PDFVersePlacement] = [:]

                beginNewPage(isFirst: true)

                for verse in verses {
                    let attr = makeVerseAttributedString(
                        verse: verse,
                        fontSize: 11.5,
                        showRedLetter: showRedLetter,
                        showItalics: showItalics
                    )
                    let textBounds = attr.boundingRect(
                        with: CGSize(width: scriptureColW - 8, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    let blockH = ceil(textBounds.height) + 7

                    if cursorY + blockH > pageRect.height - marginBottom {
                        pageIndex += 1
                        beginNewPage(isFirst: false)
                    }

                    let drawRect = CGRect(x: marginX + 4, y: cursorY + 2, width: scriptureColW - 8, height: ceil(textBounds.height) + 2)
                    if let hl = highlights[verse.verse], let hlColor = UIColor(hex: hl.colorHex) {
                        let pillRect = CGRect(x: marginX, y: cursorY, width: scriptureColW, height: blockH - 2)
                        let path = UIBezierPath(roundedRect: pillRect, cornerRadius: 4)
                        ctx.cgContext.setFillColor(hlColor.withAlphaComponent(0.24).cgColor)
                        ctx.cgContext.addPath(path.cgPath)
                        ctx.cgContext.fillPath()
                    }
                    attr.draw(in: drawRect)
                    pdfVerseMap[verse.verse] = PDFVersePlacement(pageIndex: pageIndex, rect: drawRect)
                    cursorY += blockH
                }

                // Appendix Section 1: Apple Pencil Ink Snapshot (clean, legible full-chapter handwriting sheet)
                if !drawing.strokes.isEmpty {
                    let inkBounds = drawing.bounds.insetBy(dx: -18, dy: -18)
                    if inkBounds.width > 2 && inkBounds.height > 2 {
                        let refW = max(canvasWidth, inkBounds.maxX + 20)
                        let scaleToPage = min(1.0, printableW / max(1, refW))
                        let scaledH = inkBounds.height * scaleToPage
                        let slicePageH = printableH - 36
                        let slices = max(1, Int(ceil(scaledH / slicePageH)))

                        for s in 0..<slices {
                            pageIndex += 1
                            ctx.beginPage()
                            drawPageFooter(ctx.cgContext, title: "\(bookName) \(chapter) · Handwritten Margin & Ink Notes", pageNumber: pageIndex)
                            drawSectionHeader(
                                s == 0 ? "Apple Pencil Handwriting & Margin Ink" : "Apple Pencil Handwriting (Continued)",
                                at: CGPoint(x: marginX, y: marginTop)
                            )
                            let contentTop = marginTop + 26
                            let sliceSrcH = slicePageH / scaleToPage
                            let srcRect = CGRect(
                                x: max(0, inkBounds.minX),
                                y: inkBounds.minY + CGFloat(s) * sliceSrcH,
                                width: inkBounds.width,
                                height: min(sliceSrcH, inkBounds.maxY - (inkBounds.minY + CGFloat(s) * sliceSrcH))
                            )
                            if srcRect.height > 1 {
                                let inkImg = drawing.image(from: srcRect, scale: 2.0)
                                let destW = srcRect.width * scaleToPage
                                let destH = srcRect.height * scaleToPage
                                inkImg.draw(in: CGRect(x: marginX, y: contentTop, width: destW, height: destH))

                                // Composite stickers whose Y falls within this vertical slice
                                for st in placedStickers {
                                    guard let item = stickerLookup[st.stickerId] else { continue }
                                    let stY = CGFloat(st.posY)
                                    if stY >= srcRect.minY - 80 && stY <= srcRect.maxY + 20 {
                                        let dx = marginX + (CGFloat(st.posX) - srcRect.minX) * scaleToPage
                                        let dy = contentTop + (stY - srcRect.minY) * scaleToPage
                                        let dw = CGFloat(st.width) * scaleToPage
                                        let dh = CGFloat(st.height) * scaleToPage
                                        drawSticker(item: item, in: CGRect(x: dx, y: dy, width: dw, height: dh), opacity: st.opacity, rotation: st.rotation, cg: ctx.cgContext)
                                    }
                                }
                            }
                        }
                    }
                }

                // Appendix Section 2: Study Clips, Pinned References & Chapter Notes
                if !pinnedRefs.isEmpty || !clips.isEmpty || !chapterNotes.isEmpty {
                    pageIndex += 1
                    ctx.beginPage()
                    drawPageFooter(ctx.cgContext, title: "\(bookName) \(chapter) · Study Notes & References", pageNumber: pageIndex)
                    var y = marginTop
                    drawSectionHeader("Study Notes, Clips & Pinned References", at: CGPoint(x: marginX, y: y))
                    y += 28

                    func ensureSpace(_ needed: CGFloat) {
                        if y + needed > pageRect.height - marginBottom {
                            pageIndex += 1
                            ctx.beginPage()
                            drawPageFooter(ctx.cgContext, title: "\(bookName) \(chapter) · Study Notes & References", pageNumber: pageIndex)
                            y = marginTop
                        }
                    }

                    if !pinnedRefs.isEmpty {
                        let labels = pinnedRefs.map(\.label).joined(separator: "  ·  ")
                        let pinAttr = makeNoteParagraph(heading: "Pinned References", body: labels)
                        let h = ceil(pinAttr.boundingRect(with: CGSize(width: printableW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 12
                        ensureSpace(h)
                        pinAttr.draw(in: CGRect(x: marginX, y: y, width: printableW, height: h))
                        y += h + 6
                    }

                    for clip in clips {
                        let body = clip.userNote.isEmpty ? clip.excerpt : "\(clip.excerpt)\nNote: \(clip.userNote)"
                        let attr = makeNoteParagraph(heading: "Clip · \(clip.sourceLabel)", body: body)
                        let h = ceil(attr.boundingRect(with: CGSize(width: printableW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 12
                        ensureSpace(h)
                        attr.draw(in: CGRect(x: marginX, y: y, width: printableW, height: h))
                        y += h + 6
                    }

                    for note in chapterNotes {
                        let title = note.title.isEmpty ? note.noteType.rawValue : "\(note.noteType.rawValue) · \(note.title)"
                        let attr = makeNoteParagraph(heading: title, body: note.body)
                        let h = ceil(attr.boundingRect(with: CGSize(width: printableW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 12
                        ensureSpace(h)
                        attr.draw(in: CGRect(x: marginX, y: y, width: printableW, height: h))
                        y += h + 6
                    }
                }
            }
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - 2. Sermon / Study Notebook PDF

    public static func exportNotebook(
        noteType: NoteType,
        title: String,
        linkedRefLabel: String?,
        bodyText: String,
        richBodyRTF: Data? = nil,
        drawing: PKDrawing,
        placedStickers: [PlacedSticker],
        stickerLookup: [String: StickerItem]
    ) -> URL? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = cleanTitle.isEmpty ? "\(noteType.rawValue)-Notebook" : cleanTitle
        let safeName = baseName
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") + ".pdf"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        try? FileManager.default.removeItem(at: dest)

        let printableW = pageRect.width - marginX * 2
        let printableH = pageRect.height - marginTop - marginBottom
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Sword & Quill Study Bible (www.swordandquillbible.com)",
            kCGPDFContextTitle as String: cleanTitle.isEmpty ? noteType.rawValue : cleanTitle
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)

        do {
            try renderer.writePDF(to: dest) { ctx in
                var pageIndex = 1
                ctx.beginPage()
                drawPageFooter(ctx.cgContext, title: "\(noteType.rawValue) · \(cleanTitle.isEmpty ? "Untitled" : cleanTitle)", pageNumber: pageIndex)

                var y = marginTop
                let badge = linkedRefLabel != nil ? "\(noteType.rawValue.uppercased())  ·  \(linkedRefLabel!)  ·  \(dateStr)" : "\(noteType.rawValue.uppercased())  ·  \(dateStr)"
                (badge as NSString).draw(at: CGPoint(x: marginX, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: UIColor(red: 0.18, green: 0.38, blue: 0.62, alpha: 1.0)
                ])
                y += 16

                let titleStr = cleanTitle.isEmpty ? "Untitled \(noteType.rawValue) Note" : cleanTitle
                let titleAttr = NSAttributedString(string: titleStr, attributes: [
                    .font: UIFont(name: "Georgia-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1.0)
                ])
                let titleH = ceil(titleAttr.boundingRect(with: CGSize(width: printableW, height: 100), options: [.usesLineFragmentOrigin], context: nil).height)
                titleAttr.draw(in: CGRect(x: marginX, y: y, width: printableW, height: titleH))
                y += titleH + 10

                ctx.cgContext.setStrokeColor(UIColor(white: 0.78, alpha: 1.0).cgColor)
                ctx.cgContext.setLineWidth(0.75)
                ctx.cgContext.move(to: CGPoint(x: marginX, y: y))
                ctx.cgContext.addLine(to: CGPoint(x: pageRect.width - marginX, y: y))
                ctx.cgContext.strokePath()
                y += 14

                // Paginated Typed / WYSIWYG Rich Notes
                if let rtf = richBodyRTF,
                   let loaded = try? NSMutableAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
                   loaded.length > 0 {
                    // Normalize ink color for crisp white paper printing while keeping headings/bold/italic/underline/indents
                    loaded.addAttribute(.foregroundColor, value: UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1.0), range: NSRange(location: 0, length: loaded.length))
                    let fullStr = loaded.string as NSString
                    var loc = 0
                    while loc < fullStr.length {
                        let lineRange = fullStr.lineRange(for: NSRange(location: loc, length: 0))
                        let sub = loaded.attributedSubstring(from: lineRange)
                        let h = ceil(sub.boundingRect(with: CGSize(width: printableW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 4
                        if y + h > pageRect.height - marginBottom {
                            pageIndex += 1
                            ctx.beginPage()
                            drawPageFooter(ctx.cgContext, title: "\(noteType.rawValue) · \(titleStr)", pageNumber: pageIndex)
                            y = marginTop
                        }
                        sub.draw(in: CGRect(x: marginX, y: y, width: printableW, height: h))
                        y += h
                        loc = NSMaxRange(lineRange)
                    }
                    y += 16
                } else {
                    let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedBody.isEmpty {
                        let paragraphs = trimmedBody.components(separatedBy: "\n")
                        let pStyle = NSMutableParagraphStyle()
                        pStyle.lineSpacing = 4
                        let bodyAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont(name: "Georgia", size: 12) ?? UIFont.systemFont(ofSize: 12),
                            .foregroundColor: UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1.0),
                            .paragraphStyle: pStyle
                        ]
                        for para in paragraphs {
                            let line = para.isEmpty ? " " : para
                            let attr = NSAttributedString(string: line, attributes: bodyAttrs)
                            let h = ceil(attr.boundingRect(with: CGSize(width: printableW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 4
                            if y + h > pageRect.height - marginBottom {
                                pageIndex += 1
                                ctx.beginPage()
                                drawPageFooter(ctx.cgContext, title: "\(noteType.rawValue) · \(titleStr)", pageNumber: pageIndex)
                                y = marginTop
                            }
                            attr.draw(in: CGRect(x: marginX, y: y, width: printableW, height: h))
                            y += h
                        }
                        y += 16
                    }
                }

                // Handwritten Canvas + Placed Notebook Stickers
                if !drawing.strokes.isEmpty || !placedStickers.isEmpty {
                    var contentBounds = drawing.bounds
                    for st in placedStickers {
                        let r = CGRect(x: st.posX, y: st.posY, width: st.width, height: st.height)
                        contentBounds = contentBounds.isEmpty ? r : contentBounds.union(r)
                    }
                    let padded = contentBounds.insetBy(dx: -20, dy: -20)
                    let scale = min(1.0, printableW / max(1, padded.width))
                    let scaledH = padded.height * scale

                    if y + min(scaledH + 30, 180) > pageRect.height - marginBottom {
                        pageIndex += 1
                        ctx.beginPage()
                        drawPageFooter(ctx.cgContext, title: "\(noteType.rawValue) · \(titleStr)", pageNumber: pageIndex)
                        y = marginTop
                    }

                    drawSectionHeader("Handwritten Notes & Stickers", at: CGPoint(x: marginX, y: y))
                    y += 24

                    let availableH = (pageRect.height - marginBottom) - y
                    let firstSliceSrcH = availableH / scale
                    var srcY = padded.minY

                    while srcY < padded.maxY {
                        let sliceH = (srcY == padded.minY) ? firstSliceSrcH : (printableH / scale)
                        let actualSrcH = min(sliceH, padded.maxY - srcY)
                        let srcRect = CGRect(x: padded.minX, y: srcY, width: padded.width, height: actualSrcH)
                        let destH = actualSrcH * scale
                        let destW = padded.width * scale

                        // Light ruled lines behind handwriting
                        let cg = ctx.cgContext
                        cg.setStrokeColor(UIColor(white: 0.90, alpha: 1.0).cgColor)
                        cg.setLineWidth(0.5)
                        var ly = y + 20
                        while ly < y + destH {
                            cg.move(to: CGPoint(x: marginX, y: ly))
                            cg.addLine(to: CGPoint(x: pageRect.width - marginX, y: ly))
                            ly += 24
                        }
                        cg.strokePath()

                        if !drawing.strokes.isEmpty {
                            let img = drawing.image(from: srcRect, scale: 2.0)
                            img.draw(in: CGRect(x: marginX, y: y, width: destW, height: destH))
                        }

                        for st in placedStickers {
                            guard let item = stickerLookup[st.stickerId] else { continue }
                            let stY = CGFloat(st.posY)
                            if stY >= srcRect.minY - 60 && stY <= srcRect.maxY + 20 {
                                let dx = marginX + (CGFloat(st.posX) - srcRect.minX) * scale
                                let dy = y + (stY - srcRect.minY) * scale
                                drawSticker(item: item, in: CGRect(x: dx, y: dy, width: CGFloat(st.width) * scale, height: CGFloat(st.height) * scale), opacity: st.opacity, rotation: st.rotation, cg: cg)
                            }
                        }

                        srcY += actualSrcH
                        if srcY < padded.maxY {
                            pageIndex += 1
                            ctx.beginPage()
                            drawPageFooter(ctx.cgContext, title: "\(noteType.rawValue) · \(titleStr)", pageNumber: pageIndex)
                            y = marginTop
                        }
                    }
                }
            }
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - 3. Printable Study Trail Classroom Handout PDF

    public static func exportStudyTrailHandout(
        study: StudySession,
        author: String?,
        startLocationLabel: String,
        entries: [StudyTrailEntry],
        marginLinks: [StudyMarginLink],
        bookNameLookup: (Int) -> String
    ) -> URL? {
        let safe = study.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("SwordAndQuill-Handout-\(safe.isEmpty ? "Study" : safe).pdf")
        try? FileManager.default.removeItem(at: dest)

        let printableW = pageRect.width - marginX * 2
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Sword & Quill Study Bible (www.swordandquillbible.com)",
            kCGPDFContextTitle as String: "\(study.name) — Study Handout"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)

        do {
            try renderer.writePDF(to: dest) { ctx in
                var pageIndex = 1
                ctx.beginPage()
                drawPageFooter(ctx.cgContext, title: "\(study.name) · Sword & Quill Study Bible · swordandquillbible.com", pageNumber: pageIndex)
                var y = marginTop

                let subtitle = (author?.isEmpty == false)
                    ? "STUDY HANDOUT  ·  BY \(author!.uppercased())  ·  \(dateStr)"
                    : "STUDY HANDOUT  ·  \(dateStr)"
                (subtitle as NSString).draw(at: CGPoint(x: marginX, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: UIColor(red: 0.18, green: 0.38, blue: 0.62, alpha: 1.0)
                ])
                y += 16

                let titleAttr = NSAttributedString(string: study.name, attributes: [
                    .font: UIFont(name: "Georgia-Bold", size: 22) ?? UIFont.boldSystemFont(ofSize: 22),
                    .foregroundColor: UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1.0)
                ])
                let titleH = ceil(titleAttr.boundingRect(with: CGSize(width: printableW, height: 100), options: [.usesLineFragmentOrigin], context: nil).height)
                titleAttr.draw(in: CGRect(x: marginX, y: y, width: printableW, height: titleH))
                y += titleH + 4

                ("Starting Passage: \(startLocationLabel)" as NSString).draw(at: CGPoint(x: marginX, y: y), withAttributes: [
                    .font: UIFont(name: "Georgia-Italic", size: 11.5) ?? UIFont.italicSystemFont(ofSize: 11.5),
                    .foregroundColor: UIColor.darkGray
                ])
                y += 20

                if !study.summaryNote.isEmpty {
                    let sumAttr = makeNoteParagraph(heading: "Study Overview", body: study.summaryNote)
                    let sh = ceil(sumAttr.boundingRect(with: CGSize(width: printableW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 10
                    sumAttr.draw(in: CGRect(x: marginX, y: y, width: printableW, height: sh))
                    y += sh + 6
                }

                ctx.cgContext.setStrokeColor(UIColor(white: 0.78, alpha: 1.0).cgColor)
                ctx.cgContext.setLineWidth(0.75)
                ctx.cgContext.move(to: CGPoint(x: marginX, y: y))
                ctx.cgContext.addLine(to: CGPoint(x: pageRect.width - marginX, y: y))
                ctx.cgContext.strokePath()
                y += 14

                func ensureSpace(_ needed: CGFloat) {
                    if y + needed > pageRect.height - marginBottom {
                        pageIndex += 1
                        ctx.beginPage()
                        drawPageFooter(ctx.cgContext, title: "\(study.name) · Sword & Quill Study Bible · swordandquillbible.com", pageNumber: pageIndex)
                        y = marginTop
                    }
                }

                drawSectionHeader("Study Trail (\(entries.count) Items)", at: CGPoint(x: marginX, y: y))
                y += 22

                for (idx, entry) in entries.reversed().enumerated() {
                    let heading = "\(idx + 1). [\(entry.kind.rawValue)]  \(entry.title)"
                    let body = entry.detail.isEmpty ? " " : entry.detail
                    let attr = makeNoteParagraph(heading: heading, body: body)
                    let h = ceil(attr.boundingRect(with: CGSize(width: printableW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 6
                    ensureSpace(h)
                    attr.draw(in: CGRect(x: marginX, y: y, width: printableW, height: h))
                    y += h + 4
                }

                if !marginLinks.isEmpty {
                    ensureSpace(44)
                    y += 10
                    drawSectionHeader("Key Bible Margin Notes", at: CGPoint(x: marginX, y: y))
                    y += 22
                    for link in marginLinks {
                        let ref = "\(bookNameLookup(link.bookId)) \(link.chapter)\(link.verse != nil ? ":\(link.verse!)" : "")"
                        let attr = makeNoteParagraph(heading: ref, body: link.noteText.isEmpty ? "(Linked to this study)" : link.noteText)
                        let h = ceil(attr.boundingRect(with: CGSize(width: printableW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 8
                        ensureSpace(h)
                        attr.draw(in: CGRect(x: marginX, y: y, width: printableW, height: h))
                        y += h + 4
                    }
                }
            }
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - Drawing Helpers

    private static func drawPageFooter(_ cg: CGContext, title: String, pageNumber: Int) {
        let footerY = pageRect.height - 28
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5),
            .foregroundColor: UIColor.gray
        ]
        (title as NSString).draw(at: CGPoint(x: marginX, y: footerY), withAttributes: attrs)
        let pStr = "Page \(pageNumber)" as NSString
        let pSize = pStr.size(withAttributes: attrs)
        pStr.draw(at: CGPoint(x: pageRect.width - marginX - pSize.width, y: footerY), withAttributes: attrs)
    }

    private static func drawSectionHeader(_ title: String, at origin: CGPoint) {
        (title.uppercased() as NSString).draw(at: origin, withAttributes: [
            .font: UIFont.systemFont(ofSize: 9.5, weight: .bold),
            .foregroundColor: UIColor(red: 0.18, green: 0.38, blue: 0.62, alpha: 1.0)
        ])
    }

    private static func makeNoteParagraph(heading: String, body: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: heading + "\n", attributes: [
            .font: UIFont.systemFont(ofSize: 10.5, weight: .bold),
            .foregroundColor: UIColor(red: 0.18, green: 0.38, blue: 0.62, alpha: 1.0)
        ]))
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = 3
        out.append(NSAttributedString(string: body, attributes: [
            .font: UIFont(name: "Georgia", size: 11) ?? UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1.0),
            .paragraphStyle: pStyle
        ]))
        return out
    }

    private static func makeVerseAttributedString(verse: Verse, fontSize: CGFloat, showRedLetter: Bool, showItalics: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let numFont = UIFont.systemFont(ofSize: fontSize * 0.72, weight: .regular)
        out.append(NSAttributedString(string: "\(verse.verse)  ", attributes: [
            .font: numFont,
            .foregroundColor: UIColor(red: 0.18, green: 0.38, blue: 0.62, alpha: 0.85)
        ]))

        let baseFont = UIFont(name: "Georgia", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let italicFont = UIFont(name: "Georgia-Italic", size: fontSize) ?? UIFont.italicSystemFont(ofSize: fontSize)
        let baseColor = UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1.0)
        let redColor = UIColor(red: 0.64, green: 0.14, blue: 0.14, alpha: 1.0)

        let source = (!verse.textMarked.isEmpty && (showRedLetter || showItalics)) ? verse.textMarked : verse.text
        var isItalic = false
        var isRed = false
        var idx = source.startIndex

        func appendSeg(_ seg: Substring) {
            guard !seg.isEmpty else { return }
            out.append(NSAttributedString(string: String(seg), attributes: [
                .font: (isItalic && showItalics) ? italicFont : baseFont,
                .foregroundColor: (isRed && showRedLetter) ? redColor : baseColor
            ]))
        }

        while idx < source.endIndex {
            if let lt = source[idx...].firstIndex(of: "<") {
                appendSeg(source[idx..<lt])
                if let gt = source[lt...].firstIndex(of: ">") {
                    let tag = source[lt...gt]
                    if tag == "<i>" { isItalic = true }
                    else if tag == "</i>" { isItalic = false }
                    else if tag == "<r>" { isRed = true }
                    else if tag == "</r>" { isRed = false }
                    idx = source.index(after: gt)
                } else {
                    appendSeg(source[lt...])
                    break
                }
            } else {
                appendSeg(source[idx...])
                break
            }
        }

        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = 3
        out.addAttribute(.paragraphStyle, value: pStyle, range: NSRange(location: 0, length: out.length))
        return out
    }

    private static func drawSticker(item: StickerItem, in rect: CGRect, opacity: Double, rotation: Double, cg: CGContext) {
        let img: UIImage?
        if item.kind == .symbol {
            img = StickerLibrarySheet.renderSymbolStickerImage(item, side: max(120, rect.width * 2))
        } else if let data = item.imageData {
            img = UIImage(data: data)
        } else {
            img = nil
        }
        guard let img else { return }
        cg.saveGState()
        cg.setAlpha(CGFloat(max(0, min(1, opacity))))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: CGFloat(rotation * .pi / 180.0))
        img.draw(in: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
        cg.restoreGState()
    }
}

// MARK: - Native iPad Share Sheet Wrapper for On-Demand PDF Export

public struct ShareSheetItem: Identifiable {
    public let id = UUID()
    public let url: URL
}

public struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
