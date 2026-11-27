import SwiftUI

// MARK: - New Study Session Sheet (Name + Starting Passage)

public struct NewStudySheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var studyName: String = ""
    @State private var summaryNote: String = ""
    @State private var selectedBookId: Int = 43
    @State private var selectedChapter: Int = 3
    @State private var selectedVerseText: String = ""

    private var selectedBook: Book? {
        viewModel.books.first(where: { $0.id == selectedBookId })
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Study Details") {
                    TextField("Study Name (e.g. Born Again, Grace vs Works)", text: $studyName)
                        .font(.headline)
                    TextField("Optional Study Goal / Note", text: $summaryNote, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Starting Scripture") {
                    Picker("Book", selection: $selectedBookId) {
                        ForEach(viewModel.books) { b in
                            Text(b.name).tag(b.id)
                        }
                    }
                    .onChange(of: selectedBookId) { _, _ in
                        if let maxCh = selectedBook?.chapterCount, selectedChapter > maxCh {
                            selectedChapter = 1
                        }
                    }

                    let maxChapters = max(1, selectedBook?.chapterCount ?? 1)
                    Picker("Chapter", selection: $selectedChapter) {
                        ForEach(1...maxChapters, id: \.self) { ch in
                            Text("Chapter \(ch)").tag(ch)
                        }
                    }

                    TextField("Starting Verse (optional, e.g. 16)", text: $selectedVerseText)
                        .keyboardType(.numberPad)
                }

                Section {
                    Text("While this Study is active, Sword & Quill automatically records every passage, cross-reference, Strong's word, place, and note you explore into this Study Trail—separate from your general Reading History. You can rename it anytime and pin permanent links back to this Study right onto your Bible ink.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Study Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Study") {
                        let cleanName = studyName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let fallback = "\(selectedBook?.name ?? "Bible") \(selectedChapter) Study"
                        let vInt = Int(selectedVerseText.trimmingCharacters(in: .whitespacesAndNewlines))
                        viewModel.createAndStartStudy(
                            name: cleanName.isEmpty ? fallback : cleanName,
                            startBookId: selectedBookId,
                            startChapter: selectedChapter,
                            startVerse: vInt,
                            summaryNote: summaryNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                selectedBookId = viewModel.currentBookId
                selectedChapter = viewModel.currentChapter
            }
        }
    }
}

// MARK: - Study Trail Sheet (Timeline of Everything Explored + Rename + Link to Bible Ink)

public struct StudyTrailSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    enum TrailFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case passages = "Passages"
        case refs = "Refs"
        case words = "Words"
        case notes = "Notes"
        var id: String { rawValue }
    }

    @State private var filter: TrailFilter = .all
    @State private var editName: String = ""
    @State private var editSummary: String = ""
    @State private var showRenameArea: Bool = false
    @State private var showDeleteConfirm: Bool = false

    private var filteredEntries: [StudyTrailEntry] {
        switch filter {
        case .all: return viewModel.activeStudyTrail
        case .passages: return viewModel.activeStudyTrail.filter { $0.kind == .passage }
        case .refs: return viewModel.activeStudyTrail.filter { $0.kind == .crossRef }
        case .words: return viewModel.activeStudyTrail.filter { $0.kind == .strongs || $0.kind == .dictionary || $0.kind == .place }
        case .notes: return viewModel.activeStudyTrail.filter { $0.kind == .note || $0.kind == .clip || $0.kind == .highlight }
        }
    }

    public var body: some View {
        NavigationStack {
            if let study = viewModel.activeStudy {
                VStack(spacing: 0) {
                    // Study Header Card + Quick Actions
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(study.name)
                                    .font(.headline.weight(.bold))
                                Text("Started at \(viewModel.bookName(study.startBookId)) \(study.startChapter)\(study.startVerse != nil ? ":\(study.startVerse!)" : "") · \(viewModel.activeStudyTrail.count) trail items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(showRenameArea ? "Hide Edit" : "Rename") {
                                withAnimation { showRenameArea.toggle() }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !study.summaryNote.isEmpty && !showRenameArea {
                            Text(study.summaryNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if showRenameArea {
                            VStack(spacing: 8) {
                                TextField("Study Name", text: $editName)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Study Summary / Goal", text: $editSummary, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(2...3)
                                HStack {
                                    Button("Delete Study", role: .destructive) {
                                        showDeleteConfirm = true
                                    }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    Spacer()
                                    Button("Save Name & Note") {
                                        viewModel.renameStudy(id: study.id, newName: editName, summaryNote: editSummary)
                                        showRenameArea = false
                                    }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(viewModel.theme.accentBlue)
                                }
                            }
                            .padding(.top, 4)
                        }

                        HStack(spacing: 8) {
                            Button {
                                dismiss()
                                viewModel.showAddStudyLinkSheet = true
                            } label: {
                                Label("Pin Link to Bible Ink", systemImage: "pin.fill")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(viewModel.theme.accentBlue)

                            Button {
                                copyStudyTrailSummary(study)
                            } label: {
                                Label("Copy Trail", systemImage: "doc.on.doc")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()

                            Button("Exit Study") {
                                viewModel.exitActiveStudy()
                                dismiss()
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(14)
                    .background(viewModel.theme.chromeBackground)

                    Picker("Filter", selection: $filter) {
                        ForEach(TrailFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Divider()

                    List {
                        if filteredEntries.isEmpty {
                            Text("No items in this filter yet. Jump around Scripture, tap cross-refs, Strong's words, or places—everything is logged automatically!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(filteredEntries) { entry in
                            Button {
                                jumpToTrailEntry(entry)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: entry.kind.systemImage)
                                        .font(.subheadline)
                                        .foregroundStyle(viewModel.theme.accentBlue)
                                        .frame(width: 24, height: 24)
                                        .background(viewModel.theme.accentBlue.opacity(0.12))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(entry.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(viewModel.theme.primaryText)
                                            Text(entry.kind.rawValue)
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(viewModel.theme.accentBlue.opacity(0.10))
                                                .foregroundStyle(viewModel.theme.accentBlue)
                                                .clipShape(Capsule())
                                        }
                                        if !entry.detail.isEmpty {
                                            Text(entry.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    if !entry.formattedDuration.isEmpty {
                                        Text(entry.formattedDuration)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.deleteStudyTrailEntry(entry)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                .navigationTitle("Study Trail")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onAppear {
                    viewModel.flushCurrentChapterTime()
                    editName = study.name
                    editSummary = study.summaryNote
                }
                .alert("Delete Study?", isPresented: $showDeleteConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        viewModel.deleteStudy(study)
                        dismiss()
                    }
                } message: {
                    Text("This removes the \"\(study.name)\" study trail and its study link badges. Your permanent Bible ink, highlights, and notebooks remain untouched.")
                }
            } else {
                VStack(spacing: 12) {
                    Text("No active study session.")
                        .foregroundStyle(.secondary)
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func jumpToTrailEntry(_ entry: StudyTrailEntry) {
        dismiss()
        if entry.kind == .strongs, let sid = entry.refKey {
            if let b = entry.bookId, let c = entry.chapter {
                viewModel.navigate(to: VerseRef(bookId: b, chapter: c, verse: entry.verse))
            }
            viewModel.leftPanelTab = .strongs
            viewModel.showReferencePanel = true
            viewModel.selectStrongsId(sid)
            return
        }
        if let b = entry.bookId, let c = entry.chapter {
            viewModel.navigate(to: VerseRef(bookId: b, chapter: c, verse: entry.verse))
        }
    }

    private func copyStudyTrailSummary(_ study: StudySession) {
        var lines = ["Study: \(study.name)"]
        if !study.summaryNote.isEmpty { lines.append(study.summaryNote) }
        lines.append("")
        for entry in viewModel.activeStudyTrail.reversed() {
            let suffix = entry.detail.isEmpty ? "" : " — \(entry.detail)"
            lines.append("• [\(entry.kind.rawValue)] \(entry.title)\(suffix)")
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        viewModel.showToast("Copied Study Trail to clipboard")
    }
}

// MARK: - Add / Edit Permanent Bible Ink Study Link Sheet

public struct StudyMarginLinkEditorSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    let existingLink: StudyMarginLink?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStudyId: String = ""
    @State private var noteText: String = ""
    @State private var verseText: String = ""

    public var body: some View {
        NavigationStack {
            Form {
                if let existing = existingLink {
                    Section("Linked Study") {
                        HStack {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .foregroundStyle(viewModel.theme.accentBlue)
                            Text(existing.studyName)
                                .font(.headline)
                            Spacer()
                            if let targetStudy = viewModel.studySessions.first(where: { $0.id == existing.studyId }) {
                                Button("Open Study") {
                                    viewModel.activateStudy(targetStudy, jumpToLastPassage: false)
                                    dismiss()
                                    viewModel.showStudyTrailSheet = true
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(viewModel.theme.accentBlue)
                            }
                        }
                    }
                } else {
                    Section("Study to Link") {
                        if viewModel.studySessions.isEmpty {
                            Text("Create a Study first from the top-right Studies menu.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Study", selection: $selectedStudyId) {
                                ForEach(viewModel.studySessions) { s in
                                    Text(s.name).tag(s.id)
                                }
                            }
                        }
                    }
                }

                Section("Permanent Margin Note on \(viewModel.currentLocationTitle)") {
                    TextField("Verse # (optional)", text: $verseText)
                        .keyboardType(.numberPad)
                    TextEditor(text: $noteText)
                        .frame(minHeight: 110)
                        .font(.system(size: 15, design: .serif))
                }

                if let existing = existingLink {
                    Section {
                        Button("Remove Link from This Page", role: .destructive) {
                            viewModel.removeStudyMarginLink(id: existing.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingLink == nil ? "Link Study to Bible Ink" : "Study Link & Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingLink == nil ? "Pin to Bible" : "Save") {
                        if var existing = existingLink {
                            existing.noteText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                            viewModel.updateStudyMarginLink(existing)
                        } else if let study = viewModel.studySessions.first(where: { $0.id == selectedStudyId }) {
                            let vInt = Int(verseText.trimmingCharacters(in: .whitespacesAndNewlines))
                            viewModel.addStudyMarginLink(study: study, verse: vInt, noteText: noteText)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(existingLink == nil && selectedStudyId.isEmpty)
                }
            }
            .onAppear {
                if let existing = existingLink {
                    selectedStudyId = existing.studyId
                    noteText = existing.noteText
                    verseText = existing.verse.map(String.init) ?? ""
                } else {
                    selectedStudyId = viewModel.activeStudy?.id ?? viewModel.studySessions.first?.id ?? ""
                }
            }
        }
    }
}

// MARK: - Draggable Permanent Study Link Card (Strict .offset() Hit-Box on Bible Ink Canvas)

public struct DraggableStudyLinkCard: View {
    let link: StudyMarginLink
    let theme: ReadingTheme
    let onTap: () -> Void
    let onMove: (CGPoint) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(link.studyName)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                if let v = link.verse {
                    Text("v.\(v)")
                        .font(.caption2.weight(.semibold))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(Color(red: 0.56, green: 0.36, blue: 0.06))

            if !link.noteText.isEmpty {
                Text(link.noteText)
                    .font(.system(size: 11.5, design: .serif))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 210, alignment: .leading)
        .background(Color(red: 0.99, green: 0.95, blue: 0.84).opacity(theme == .dark ? 0.22 : 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.78, green: 0.56, blue: 0.18).opacity(0.75), lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if hypot(value.translation.width, value.translation.height) > 4 || isDragging {
                        isDragging = true
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if !isDragging && hypot(value.translation.width, value.translation.height) <= 6 {
                        dragOffset = .zero
                        onTap()
                    } else {
                        let nextX = max(8, link.posX + Double(value.translation.width))
                        let nextY = max(8, link.posY + Double(value.translation.height))
                        dragOffset = .zero
                        isDragging = false
                        onMove(CGPoint(x: nextX, y: nextY))
                    }
                }
        )
        .offset(x: link.posX + Double(dragOffset.width), y: link.posY + Double(dragOffset.height))
    }
}
