import PencilKit
import SwiftUI
import UIKit
import Vision

// MARK: - Full-Page Sermon / Study Notebook Editor (Typed + Apple Pencil + Insert Ref + Handwriting-to-Text)

public struct NotebookEditorSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    let note: UserNote
    @Environment(\.dismiss) private var dismiss

    enum EditorLayout: String, CaseIterable, Identifiable {
        case split = "Split"
        case handwriting = "Handwriting"
        case typed = "Typed"
        var id: String { rawValue }
    }

    @State private var noteType: NoteType = .sermon
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var drawing: PKDrawing = PKDrawing()
    @State private var layout: EditorLayout = .split
    @State private var selectedTool: WritingToolKind = .pen
    @State private var selectedColor: InkColorPreset = InkColorPreset.defaults[1]
    @State private var undoTrigger: Int = 0
    @State private var redoTrigger: Int = 0
    @State private var showInsertRefSheet: Bool = false
    @State private var showStickerSheet: Bool = false
    @State private var noteStickers: [PlacedSticker] = []
    @State private var selectedNoteStickerId: String? = nil
    @State private var pdfShareItem: ShareSheetItem? = nil
    @State private var isConvertingOCR: Bool = false
    @State private var ocrStatus: String? = nil

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Metadata Header
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Picker("Type", selection: $noteType) {
                            ForEach(NoteType.allCases) { t in Text(t.rawValue).tag(t) }
                        }
                        .pickerStyle(.segmented)

                        Picker("Layout", selection: $layout) {
                            ForEach(EditorLayout.allCases) { l in Text(l.rawValue).tag(l) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }

                    HStack(spacing: 8) {
                        TextField("Notebook Title", text: $title)
                            .font(.headline)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            showInsertRefSheet = true
                        } label: {
                            Label("Insert Ref", systemImage: "plus.square.on.square")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(viewModel.theme.accentBlue)

                        Button {
                            showStickerSheet = true
                        } label: {
                            Label("Stickers", systemImage: "sparkles.rectangle.stack")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(viewModel.theme.accentBlue)

                        if !drawing.strokes.isEmpty {
                            Button {
                                convertHandwritingToText()
                            } label: {
                                if isConvertingOCR {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Ink → Text", systemImage: "text.viewfinder")
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isConvertingOCR)
                        }

                        if let b = note.bookId, let c = note.chapter {
                            let refLabel = note.verse != nil
                                ? "\(viewModel.bookName(b)) \(c):\(note.verse!)"
                                : "\(viewModel.bookName(b)) \(c)"
                            Button {
                                saveCurrentNote()
                                viewModel.navigate(to: VerseRef(bookId: b, chapter: c, verse: note.verse))
                                dismiss()
                            } label: {
                                Label(refLabel, systemImage: "book.closed")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(viewModel.theme.accentBlue)
                        }
                    }

                    // Detected clickable Scripture references inside this notebook
                    let detectedRefs = viewModel.referenceDB.extractReferences(from: bodyText, limit: 10)
                    if !detectedRefs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("Refs:")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(detectedRefs) { ref in
                                    Button {
                                        saveCurrentNote()
                                        dismiss()
                                        viewModel.openCrossRefPreview(ref)
                                    } label: {
                                        Text(ref.displayRef)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(viewModel.theme.accentBlue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(viewModel.theme.accentBlue.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    if let status = ocrStatus {
                        HStack {
                            Text(status)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(viewModel.theme.accentBlue)
                            Spacer()
                        }
                    }
                }
                .padding(12)
                .background(viewModel.theme.chromeBackground)

                Divider()

                // Compact Writing Bar when handwriting is visible
                if layout != .typed {
                    HStack(spacing: 10) {
                        ForEach([WritingToolKind.pen, .pencil, .highlighter, .eraserVector]) { t in
                            Button {
                                selectedTool = t
                            } label: {
                                Label(t.rawValue, systemImage: t.systemImage)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(selectedTool == t ? viewModel.theme.accentBlue : .secondary)
                        }

                        Divider().frame(height: 18)

                        ForEach(InkColorPreset.defaults.prefix(5)) { preset in
                            Button {
                                selectedColor = preset
                            } label: {
                                Circle()
                                    .fill(preset.swiftUIColor)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == preset ? viewModel.theme.accentBlue : Color.clear, lineWidth: 2)
                                            .padding(-2)
                                    )
                            }
                        }

                        Spacer()

                        Button { undoTrigger += 1 } label: { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button { redoTrigger += 1 } label: { Image(systemName: "arrow.uturn.forward") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(viewModel.theme.panelBackground)
                    Divider()
                }

                // Editor Body
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        if layout == .typed || layout == .split {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TYPED NOTES & OUTLINE")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)
                                TextEditor(text: $bodyText)
                                    .font(.system(size: 16, design: .serif))
                                    .padding(.horizontal, 8)
                            }
                            .frame(width: layout == .split ? geo.size.width * 0.42 : geo.size.width)
                        }

                        if layout == .split {
                            Divider()
                        }

                        if layout == .handwriting || layout == .split {
                            ZStack(alignment: .topLeading) {
                                NotebookPaperLines(lineColor: viewModel.theme.paperLineColor)
                                NotebookPKCanvas(
                                    drawing: $drawing,
                                    tool: activePKTool,
                                    pencilOnly: viewModel.pencilOnly,
                                    undoTrigger: undoTrigger,
                                    redoTrigger: redoTrigger
                                )
                                ForEach(noteStickers) { placed in
                                    if let item = viewModel.stickerItem(for: placed.stickerId) {
                                        DraggablePlacedSticker(
                                            placed: placed,
                                            item: item,
                                            isSelected: selectedNoteStickerId == placed.id,
                                            theme: viewModel.theme,
                                            onSelect: {
                                                selectedNoteStickerId = (selectedNoteStickerId == placed.id) ? nil : placed.id
                                            },
                                            onUpdate: { updated in
                                                if let idx = noteStickers.firstIndex(where: { $0.id == updated.id }) {
                                                    noteStickers[idx] = updated
                                                }
                                                viewModel.studyDB.updatePlacedSticker(
                                                    id: updated.id,
                                                    posX: updated.posX,
                                                    posY: updated.posY,
                                                    width: updated.width,
                                                    height: updated.height,
                                                    rotation: updated.rotation,
                                                    opacity: updated.opacity
                                                )
                                            },
                                            onDelete: {
                                                viewModel.studyDB.deletePlacedSticker(id: placed.id)
                                                noteStickers.removeAll(where: { $0.id == placed.id })
                                                if selectedNoteStickerId == placed.id { selectedNoteStickerId = nil }
                                            }
                                        )
                                    }
                                }
                            }
                            .background(viewModel.theme.canvasBackground)
                            .frame(width: layout == .split ? geo.size.width * 0.58 : geo.size.width)
                        }
                    }
                }
            }
            .navigationTitle("Study Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        exportNotebookPDF()
                    } label: {
                        Label("PDF", systemImage: "square.and.arrow.up")
                    }

                    Button("Save") {
                        saveCurrentNote()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $pdfShareItem) { item in
                ActivityShareSheet(url: item.url)
            }
            .sheet(isPresented: $showInsertRefSheet) {
                InsertReferenceSheet(viewModel: viewModel) { insertedText in
                    if !bodyText.isEmpty && !bodyText.hasSuffix("\n") {
                        bodyText += "\n"
                    }
                    bodyText += insertedText + "\n"
                    if layout == .handwriting {
                        layout = .split
                    }
                }
            }
            .sheet(isPresented: $showStickerSheet) {
                StickerLibrarySheet(viewModel: viewModel, targetLabel: title.isEmpty ? "Notebook" : title) { sticker in
                    let offsetIndex = Double(noteStickers.count % 5)
                    let defaultSize: Double = sticker.kind == .symbol ? 64.0 : 88.0
                    let placed = viewModel.studyDB.addPlacedSticker(
                        stickerId: sticker.id,
                        targetType: "note",
                        targetKey: note.id,
                        posX: 60.0 + offsetIndex * 22.0,
                        posY: 60.0 + offsetIndex * 24.0,
                        width: defaultSize,
                        height: defaultSize,
                        rotation: 0
                    )
                    noteStickers.append(placed)
                    selectedNoteStickerId = placed.id
                    if layout == .typed {
                        layout = .split
                    }
                }
            }
            .onAppear {
                noteType = note.noteType
                title = note.title
                bodyText = note.body
                if let data = note.drawingData, let loaded = try? PKDrawing(data: data) {
                    drawing = loaded
                }
                noteStickers = viewModel.studyDB.placedStickers(targetType: "note", targetKey: note.id)
            }
        }
    }

    // MARK: - On-Device Apple Vision Handwriting-to-Text (Non-Destructive)

    private func exportNotebookPDF() {
        saveCurrentNote()
        let lookup = Dictionary(uniqueKeysWithValues: viewModel.stickerLibrary.map { ($0.id, $0) })
        let linked: String?
        if let b = note.bookId, let c = note.chapter {
            linked = note.verse != nil ? "\(viewModel.bookName(b)) \(c):\(note.verse!)" : "\(viewModel.bookName(b)) \(c)"
        } else {
            linked = nil
        }
        if let url = StudyPDFExporter.exportNotebook(
            noteType: noteType,
            title: title,
            linkedRefLabel: linked,
            bodyText: bodyText,
            drawing: drawing,
            placedStickers: noteStickers,
            stickerLookup: lookup
        ) {
            pdfShareItem = ShareSheetItem(url: url)
        }
    }

    private func convertHandwritingToText() {
        guard !drawing.strokes.isEmpty else { return }
        isConvertingOCR = true
        ocrStatus = "Recognizing handwriting on-device..."

        // Render strokes onto a crisp white background for high-accuracy Vision OCR
        let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
        let rendered = drawing.image(from: bounds, scale: 2.0)
        let renderer = UIGraphicsImageRenderer(size: rendered.size)
        let flatImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: rendered.size))
            rendered.draw(at: .zero)
        }
        guard let cgImage = flatImage.cgImage else {
            isConvertingOCR = false
            ocrStatus = "Could not render handwriting image."
            return
        }

        Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            var recognizedLines: [String] = []
            do {
                try handler.perform([request])
                if let observations = request.results {
                    for obs in observations {
                        if let top = obs.topCandidates(1).first?.string {
                            recognizedLines.append(top)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isConvertingOCR = false
                    self.ocrStatus = "Recognition error: \(error.localizedDescription)"
                }
                return
            }

            let joined = recognizedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                self.isConvertingOCR = false
                if joined.isEmpty {
                    self.ocrStatus = "No legible text recognized. Try larger or darker strokes."
                } else {
                    if !self.bodyText.isEmpty && !self.bodyText.hasSuffix("\n") {
                        self.bodyText += "\n\n"
                    }
                    self.bodyText += joined
                    if self.layout == .handwriting {
                        self.layout = .split
                    }
                    self.ocrStatus = "Converted \(recognizedLines.count) line(s) into Typed Notes (original ink kept)."
                }
            }
        }
    }

    private var activePKTool: PKTool {
        let color = selectedColor.uiColor
        switch selectedTool {
        case .pen: return PKInkingTool(.pen, color: color, width: 3.5)
        case .pencil: return PKInkingTool(.pencil, color: color, width: 5.0)
        case .marker: return PKInkingTool(.marker, color: color, width: 10.0)
        case .highlighter: return PKInkingTool(.marker, color: color.withAlphaComponent(0.38), width: 16.0)
        case .eraserVector: return PKEraserTool(.vector)
        case .eraserBitmap: return PKEraserTool(.bitmap)
        case .lasso: return PKLassoTool()
        }
    }

    private func saveCurrentNote() {
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(noteType.rawValue) Note"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let blob: Data? = drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
        let linkedVerse: Verse? = {
            if let b = note.bookId, let c = note.chapter, let v = note.verse {
                return Verse(id: 0, bookId: b, chapter: c, verse: v, text: "")
            }
            return nil
        }()
        viewModel.saveNote(
            id: note.id,
            type: noteType,
            title: finalTitle,
            body: bodyText,
            drawingData: blob,
            verse: linkedVerse
        )
    }
}

// MARK: - Insert Reference Picker (Bible Verse, Strong's, or 1828/Easton/Nave/Torrey)

private struct InsertReferenceSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    enum InsertTab: String, CaseIterable, Identifiable {
        case scripture = "Bible Passage"
        case strongs = "Strong's"
        case dictionary = "Dictionaries & Topics"
        var id: String { rawValue }
    }

    @State private var tab: InsertTab = .scripture
    @State private var query: String = ""
    @State private var dictSource: StudyDictionarySource = .webster1828
    @State private var verseResults: [SearchResult] = []
    @State private var strongsResults: [StrongsEntry] = []
    @State private var dictResults: [StudyDictionaryEntry] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("Source", selection: $tab) {
                    ForEach(InsertTab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if tab == .dictionary {
                    Picker("Book", selection: $dictSource) {
                        ForEach(StudyDictionarySource.allCases) { s in Text(s.rawValue).tag(s) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: dictSource) { _, _ in runLookup() }
                }

                HStack {
                    TextField(placeholderText, text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { runLookup() }
                    Button("Search") { runLookup() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                List {
                    switch tab {
                    case .scripture:
                        if verseResults.count > 1,
                           let first = verseResults.first,
                           let last = verseResults.last,
                           verseResults.allSatisfy({ $0.bookId == first.bookId && $0.chapter == first.chapter }) {
                            let rangeRef = "\(first.bookName) \(first.chapter):\(first.verse)–\(last.verse)"
                            Section("Whole Passage (\(verseResults.count) verses)") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(rangeRef)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(viewModel.theme.accentBlue)
                                    HStack(spacing: 8) {
                                        Button("Insert Ref [\(rangeRef)]") {
                                            onInsert("[\(rangeRef)]")
                                            dismiss()
                                        }
                                        .font(.caption.weight(.medium))
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button("Insert All \(verseResults.count) Verses") {
                                            let combined = verseResults.map { "\($0.verse) \($0.text)" }.joined(separator: " ")
                                            onInsert("\"\(combined)\" — \(rangeRef) (KJV)")
                                            dismiss()
                                        }
                                        .font(.caption.weight(.medium))
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        ForEach(verseResults) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.referenceLabel)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(viewModel.theme.accentBlue)
                                Text(item.text)
                                    .font(.system(size: 14, design: .serif))
                                HStack(spacing: 8) {
                                    Button("Insert Ref Only") {
                                        onInsert("[\(item.referenceLabel)]")
                                        dismiss()
                                    }
                                    .font(.caption.weight(.medium))
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Insert Quote + Ref") {
                                        onInsert("\"\(item.text)\" — \(item.referenceLabel) (KJV)")
                                        dismiss()
                                    }
                                    .font(.caption.weight(.medium))
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                    case .strongs:
                        ForEach(strongsResults) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(entry.strongsId) · \(entry.lemma) (\(entry.translit))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(viewModel.theme.accentBlue)
                                Text(entry.definition)
                                    .font(.caption)
                                Button("Insert Strong's Entry") {
                                    onInsert("[Strong's \(entry.strongsId) · \(entry.lemma) (\(entry.translit))]: \(entry.definition)")
                                    dismiss()
                                }
                                .font(.caption.weight(.medium))
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                        }

                    case .dictionary:
                        ForEach(dictResults) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(entry.source.rawValue) · \(entry.headword.uppercased())")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(viewModel.theme.accentBlue)
                                Text(entry.body)
                                    .font(.caption)
                                    .lineLimit(4)
                                Button("Insert Excerpt") {
                                    let trimmed = entry.body.count > 280 ? String(entry.body.prefix(280)) + "…" : entry.body
                                    onInsert("[\(entry.source.rawValue) · \(entry.headword)]: \(trimmed)")
                                    dismiss()
                                }
                                .font(.caption.weight(.medium))
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(.top, 10)
            .navigationTitle("Insert Reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private var placeholderText: String {
        switch tab {
        case .scripture: return "e.g. John 3:16, Rom 8:28, born again"
        case .strongs: return "e.g. G25, H430, grace"
        case .dictionary: return "e.g. grace, faith, atonement, Nicodemus"
        }
    }

    private func runLookup() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        switch tab {
        case .scripture:
            verseResults = viewModel.referenceDB.searchScripture(query: q, scopeBookId: nil, limit: 25)
        case .strongs:
            strongsResults = viewModel.referenceDB.searchStrongs(word: q, testament: nil, limit: 15)
        case .dictionary:
            dictResults = viewModel.referenceDB.searchStudyDictionary(source: dictSource, query: q, limit: 15)
        }
    }
}

private struct NotebookPKCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let tool: PKTool
    let pencilOnly: Bool
    let undoTrigger: Int
    let redoTrigger: Int

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.tool = tool
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        context.coordinator.lastUndo = undoTrigger
        context.coordinator.lastRedo = redoTrigger
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.tool = tool
        canvas.drawingPolicy = pencilOnly ? .pencilOnly : .anyInput
        if context.coordinator.lastUndo != undoTrigger {
            context.coordinator.lastUndo = undoTrigger
            canvas.undoManager?.undo()
        }
        if context.coordinator.lastRedo != redoTrigger {
            context.coordinator.lastRedo = redoTrigger
            canvas.undoManager?.redo()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        var lastUndo: Int = 0
        var lastRedo: Int = 0

        init(drawing: Binding<PKDrawing>) { self._drawing = drawing }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let snap = canvasView.drawing
            Task { @MainActor in self.drawing = snap }
        }
    }
}

private struct NotebookPaperLines: View {
    let lineColor: Color

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 34
            while y < size.height {
                var p = Path()
                p.move(to: CGPoint(x: 16, y: y))
                p.addLine(to: CGPoint(x: size.width - 16, y: y))
                ctx.stroke(p, with: .color(lineColor), lineWidth: 0.8)
                y += 30
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Reading History Sheet

public struct ReadingHistorySheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            List {
                if viewModel.readingHistory.isEmpty {
                    Text("No reading history yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.readingHistory) { item in
                    let isCurrent = (item.id == viewModel.activeHistoryRowId)
                    Button {
                        viewModel.navigate(to: VerseRef(bookId: item.bookId, chapter: item.chapter, verse: item.verse))
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isCurrent ? "book.fill" : "clock.arrow.circlepath")
                                .foregroundStyle(viewModel.theme.accentBlue)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.verse != nil
                                     ? "\(viewModel.bookName(item.bookId)) \(item.chapter):\(item.verse!)"
                                     : "\(viewModel.bookName(item.bookId)) \(item.chapter)")
                                    .font(.body.weight(isCurrent ? .semibold : .regular))
                                    .foregroundStyle(viewModel.theme.primaryText)

                                if !item.formattedVisitedAt.isEmpty {
                                    Text(item.formattedVisitedAt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            HStack(spacing: 5) {
                                if isCurrent {
                                    Text("Active")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(viewModel.theme.accentBlue)
                                        .clipShape(Capsule())
                                }
                                Text(item.formattedDuration)
                                    .font(.caption.monospacedDigit().weight(.medium))
                                    .foregroundStyle(viewModel.theme.secondaryText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(viewModel.theme.panelBackground)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(viewModel.theme.dividerColor, lineWidth: 0.8))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Reading History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if !viewModel.readingHistory.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) {
                            viewModel.clearReadingHistory()
                        }
                    }
                }
            }
            .onAppear {
                viewModel.flushCurrentChapterTime()
            }
        }
    }
}
