import SwiftUI

// MARK: - Contextual Study Panel (Strong's, Webster's 1828, TSK Preview, Verse Actions)

public struct StudyPanelOverlay: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @State private var noteTitle: String = ""
    @State private var noteBody: String = ""
    @State private var noteType: NoteType = .passage
    @State private var showNoteComposer: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(headerTitle)
                    .font(.caption.weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(viewModel.theme.secondaryText)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showStudyPanel = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(viewModel.theme.secondaryText)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().overlay(viewModel.theme.dividerColor)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let ref = viewModel.previewCrossRef {
                        crossRefPreviewSection(ref)
                    } else if let verse = viewModel.studyVerse {
                        verseActionsSection(verse)
                        wordChipsSection(verse)
                        if let word = viewModel.studyWord {
                            wordStudySection(word)
                        }
                        verseCrossRefsSection(verse)
                    } else {
                        Text("Tap any verse with your finger to explore Strong's Concordance, Webster's 1828 Dictionary, cross-references, highlights, and notes.")
                            .font(.subheadline)
                            .foregroundStyle(viewModel.theme.secondaryText)
                    }
                }
                .padding(16)
            }
        }
        .background(viewModel.theme.panelBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(viewModel.theme.dividerColor).frame(width: 1)
        }
    }

    private var headerTitle: String {
        if viewModel.previewCrossRef != nil { return "CROSS-REFERENCE PREVIEW" }
        if viewModel.studyWord != nil { return "WORD STUDY · STRONG'S & WEBSTER 1828" }
        return "SCRIPTURE STUDY"
    }

    @ViewBuilder
    private func crossRefPreviewSection(_ ref: CrossReference) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.displayRef)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(viewModel.theme.accentBlue)
                if !ref.phrase.isEmpty {
                    Text("Linked phrase: \"\(ref.phrase)\"")
                        .font(.caption)
                        .foregroundStyle(viewModel.theme.secondaryText)
                }
            }

            // Complete Passage (all verses in range, plus optional ±2 context without leaving your chapter)
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.previewCrossRefVerses.isEmpty {
                    Text("Passage text unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(viewModel.theme.secondaryText)
                } else {
                    ForEach(viewModel.previewCrossRefVerses) { v in
                        let isCore = v.verse >= ref.toVerseStart && v.verse <= max(ref.toVerseStart, ref.toVerseEnd)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(v.verse)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isCore ? viewModel.theme.accentBlue : viewModel.theme.secondaryText)
                                .frame(width: 22, alignment: .trailing)
                            Text(v.text)
                                .font(.system(size: 15.5, design: .serif))
                                .foregroundStyle(isCore ? viewModel.theme.primaryText : viewModel.theme.secondaryText)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(12)
            .background(viewModel.theme.canvasBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Stay in current study: expand context, pin ref to journal, or remove pin
            HStack(spacing: 8) {
                Button {
                    viewModel.toggleCrossRefContext()
                } label: {
                    Label(
                        viewModel.previewCrossRefShowContext ? "Exact Passage" : "Show ±2 Context",
                        systemImage: "text.alignleft"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)

                if let pinnedId = viewModel.activePinnedRefId {
                    Button(role: .destructive) {
                        viewModel.removePinnedReference(id: pinnedId)
                        viewModel.activePinnedRefId = nil
                        viewModel.previewCrossRef = nil
                        viewModel.showStudyPanel = false
                    } label: {
                        Label("Remove Pin", systemImage: "trash")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        viewModel.pinCrossReference(ref)
                    } label: {
                        Label("Pin to Journal", systemImage: "pin")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider().overlay(viewModel.theme.dividerColor)

            // Optional: navigate to the new passage (Back arrow returns here)
            Button {
                viewModel.navigate(to: VerseRef(bookId: ref.toBook, chapter: ref.toChapter, verse: ref.toVerseStart))
                viewModel.previewCrossRef = nil
                viewModel.activePinnedRefId = nil
            } label: {
                Label("Go to \(ref.toBookName) \(ref.toChapter):\(ref.toVerseStart)", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.theme.accentBlue)
        }
    }

    @ViewBuilder
    private func verseActionsSection(_ verse: Verse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(viewModel.bookName(verse.bookId)) \(verse.chapter):\(verse.verse)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(viewModel.theme.primaryText)

            // Semantic Highlights
            HStack(spacing: 8) {
                ForEach(HighlightPreset.defaults) { preset in
                    Button {
                        viewModel.applyHighlight(verse: verse, preset: preset)
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("Highlight \(preset.name)")
                }
                if viewModel.chapterHighlights[verse.verse] != nil {
                    Button("Clear") {
                        viewModel.removeHighlight(verse: verse)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            // Quick Actions
            HStack(spacing: 8) {
                Button {
                    viewModel.addBookmark(for: verse)
                } label: {
                    Label("Bookmark", systemImage: "bookmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    showNoteComposer.toggle()
                    if noteTitle.isEmpty {
                        noteTitle = "\(viewModel.bookName(verse.bookId)) \(verse.chapter):\(verse.verse)"
                    }
                } label: {
                    Label("Note", systemImage: "square.and.pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.copyVerseToClipboard(verse)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if showNoteComposer {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Type", selection: $noteType) {
                        ForEach(NoteType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Title", text: $noteTitle)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $noteBody)
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(viewModel.theme.dividerColor))
                    HStack {
                        Spacer()
                        Button("Cancel") { showNoteComposer = false }
                            .buttonStyle(.bordered)
                        Button("Save Note") {
                            viewModel.saveNote(type: noteType, title: noteTitle, body: noteBody, verse: verse)
                            noteTitle = ""
                            noteBody = ""
                            showNoteComposer = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(10)
                .background(viewModel.theme.canvasBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func wordChipsSection(_ verse: Verse) -> some View {
        let words = verse.text.split(separator: " ").map(String.init)
        VStack(alignment: .leading, spacing: 6) {
            Text("TAP A WORD TO STUDY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(viewModel.theme.secondaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, rawWord in
                    let clean = rawWord.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                    if !clean.isEmpty {
                        Button {
                            viewModel.openWordStudy(word: clean, in: verse)
                        } label: {
                            Text(clean)
                                .font(.caption.weight(viewModel.studyWord?.lowercased() == clean.lowercased() ? .bold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(
                                    viewModel.studyWord?.lowercased() == clean.lowercased()
                                        ? viewModel.theme.accentBlue.opacity(0.22)
                                        : viewModel.theme.canvasBackground
                                )
                                .foregroundStyle(viewModel.theme.primaryText)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wordStudySection(_ word: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(viewModel.theme.dividerColor)
            Text("\"\(word)\"")
                .font(.title3.weight(.bold))
                .foregroundStyle(viewModel.theme.primaryText)

            // Strong's Concordance
            VStack(alignment: .leading, spacing: 8) {
                Text("STRONG'S CONCORDANCE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(viewModel.theme.secondaryText)
                if viewModel.studyStrongsResults.isEmpty {
                    Text("No direct Strong's match for \"\(word)\".")
                        .font(.caption)
                        .foregroundStyle(viewModel.theme.secondaryText)
                } else {
                    ForEach(viewModel.studyStrongsResults.prefix(5)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.lemma)
                                    .font(.title3)
                                Text("\(entry.strongsId) · \(entry.translit)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(viewModel.theme.accentBlue)
                            }
                            if !entry.definition.isEmpty {
                                Text(entry.definition)
                                    .font(.caption)
                                    .foregroundStyle(viewModel.theme.primaryText)
                            }
                            if !entry.kjvUsage.isEmpty {
                                Text("KJV: \(entry.kjvUsage)")
                                    .font(.caption2)
                                    .foregroundStyle(viewModel.theme.secondaryText)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(viewModel.theme.canvasBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            // Webster's 1828 Dictionary
            VStack(alignment: .leading, spacing: 8) {
                Text("WEBSTER'S 1828 DICTIONARY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(viewModel.theme.secondaryText)
                if viewModel.studyWebsterResults.isEmpty {
                    Text("No 1828 Dictionary entry found for \"\(word)\".")
                        .font(.caption)
                        .foregroundStyle(viewModel.theme.secondaryText)
                } else {
                    ForEach(viewModel.studyWebsterResults) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.headword.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(viewModel.theme.accentBlue)
                            Text(entry.definition)
                                .font(.caption)
                                .foregroundStyle(viewModel.theme.primaryText)
                                .lineLimit(10)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(viewModel.theme.canvasBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func verseCrossRefsSection(_ verse: Verse) -> some View {
        let refs = viewModel.crossRefsByVerse[verse.verse] ?? []
        let groups = viewModel.groupedCrossReferences(for: verse.verse)
        if !refs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(viewModel.theme.dividerColor)
                Text("TREASURY OF SCRIPTURE KNOWLEDGE (\(refs.count))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(viewModel.theme.secondaryText)
                ForEach(groups, id: \.phrase) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\"\(group.phrase)\"")
                            .font(.caption.weight(.semibold))
                            .italic()
                            .foregroundStyle(viewModel.theme.secondaryText)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(group.refs) { ref in
                                Button {
                                    viewModel.openCrossRefPreview(ref)
                                } label: {
                                    Text(ref.displayRef)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(viewModel.theme.accentBlue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(viewModel.theme.canvasBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Structured Scripture Navigation Picker (Testament -> Book -> Chapter -> Optional Verse)

public struct ScripturePickerSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTestament: String = "NT"
    @State private var selectedBookId: Int = 43
    @State private var selectedChapter: Int = 3

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Testament", selection: $selectedTestament) {
                    Text("Old Testament").tag("OT")
                    Text("New Testament").tag("NT")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                HStack(alignment: .top, spacing: 14) {
                    // Books
                    List(filteredBooks) { book in
                        Button {
                            selectedBookId = book.id
                            selectedChapter = 1
                        } label: {
                            HStack {
                                Text(book.name)
                                    .font(.body.weight(selectedBookId == book.id ? .bold : .regular))
                                Spacer()
                                Text("\(book.chapterCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(selectedBookId == book.id ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                    .listStyle(.plain)
                    .frame(width: 220)

                    Divider()

                    // Chapters + Optional Verses
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let book = viewModel.books.first(where: { $0.id == selectedBookId }) {
                                HStack {
                                    Text("CHAPTER — \(book.name.uppercased())")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Open \(book.name) \(selectedChapter)") {
                                        viewModel.navigate(to: VerseRef(bookId: selectedBookId, chapter: selectedChapter, verse: nil))
                                        dismiss()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                                    ForEach(1...book.chapterCount, id: \.self) { ch in
                                        Button {
                                            selectedChapter = ch
                                        } label: {
                                            Text("\(ch)")
                                                .font(.subheadline.weight(selectedChapter == ch ? .bold : .regular))
                                                .frame(maxWidth: .infinity, minHeight: 38)
                                                .background(selectedChapter == ch ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }

                                let vCount = viewModel.referenceDB.verseCount(bookId: selectedBookId, chapter: selectedChapter)
                                if vCount > 0 {
                                    Text("VERSE — \(book.name.uppercased()) \(selectedChapter) (OPTIONAL)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 6)

                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                                        ForEach(1...vCount, id: \.self) { v in
                                            Button {
                                                viewModel.navigate(to: VerseRef(bookId: selectedBookId, chapter: selectedChapter, verse: v))
                                                dismiss()
                                            } label: {
                                                Text("\(v)")
                                                    .font(.caption)
                                                    .frame(maxWidth: .infinity, minHeight: 32)
                                                    .background(Color.secondary.opacity(0.1))
                                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.trailing, 12)
                    }
                }
            }
            .padding(.top, 10)
            .navigationTitle("Select Scripture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                selectedBookId = viewModel.currentBookId
                selectedChapter = viewModel.currentChapter
                selectedTestament = viewModel.currentBook?.testament ?? "NT"
            }
        }
    }

    private var filteredBooks: [Book] {
        viewModel.books.filter { $0.testament == selectedTestament }
    }
}

// MARK: - Search Sheet (Words, Phrases, References, Strong's Numbers)

public struct SearchSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var results: [SearchResult] = []
    @State private var personalHits: [PersonalSearchHit] = []
    @State private var strongsHit: StrongsEntry? = nil
    @State private var currentBookOnly: Bool = false
    @State private var matchMode: ScriptureSearchMode = .exact

    public var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack {
                    TextField("Search KJV, Strong's, Notes, Clips, Bookmarks...", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { runSearch() }
                    Button("Search") { runSearch() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Match Mode", selection: $matchMode) {
                        ForEach(ScriptureSearchMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: matchMode) { _, _ in runSearch() }

                    Text(matchModeHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Toggle("Search only in \(viewModel.currentBook?.name ?? "current book")", isOn: $currentBookOnly)
                    .font(.caption)
                    .padding(.horizontal)
                    .onChange(of: currentBookOnly) { _, _ in runSearch() }

                List {
                    if !personalHits.isEmpty {
                        Section("Your Personal Study (\(personalHits.count))") {
                            ForEach(personalHits) { hit in
                                Button {
                                    if let sid = hit.studyId, let study = viewModel.studySessions.first(where: { $0.id == sid }) {
                                        dismiss()
                                        viewModel.activateStudy(study)
                                        if let b = hit.bookId, let c = hit.chapter {
                                            viewModel.navigate(to: VerseRef(bookId: b, chapter: c, verse: hit.verse))
                                        }
                                    } else if let nid = hit.noteId, let note = viewModel.notes.first(where: { $0.id == nid }) {
                                        dismiss()
                                        viewModel.openExistingNotebook(note)
                                    } else if let b = hit.bookId, let c = hit.chapter {
                                        viewModel.navigate(to: VerseRef(bookId: b, chapter: c, verse: hit.verse))
                                        dismiss()
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(hit.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Text(hit.kind)
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.16))
                                                .clipShape(Capsule())
                                        }
                                        if !hit.snippet.isEmpty {
                                            Text(hit.snippet)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if let s = strongsHit {
                        Section("Strong's Concordance") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(s.strongsId) · \(s.lemma) (\(s.translit))")
                                    .font(.headline)
                                Text(s.definition)
                                    .font(.subheadline)
                                if !s.kjvUsage.isEmpty {
                                    Text("KJV: \(s.kjvUsage)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("Scripture Results (\(results.count.formatted()))") {
                        ForEach(results) { item in
                            Button {
                                viewModel.navigate(to: VerseRef(bookId: item.bookId, chapter: item.chapter, verse: item.verse))
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.referenceLabel)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                    Text(highlightedText(item.text))
                                        .font(.system(size: 15, design: .serif))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search KJV & Study Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var matchModeHint: String {
        switch matchMode {
        case .exact:
            return "Exact whole word only (e.g. \"sin\" matches sin, not sins or sinner)"
        case .wordStartsWith:
            return "Words starting with term (e.g. \"sin\" matches sin, sins, sinner, sinful, sinned)"
        case .contains:
            return "Anywhere inside a word (e.g. \"sin\" also matches blessing, missing)"
        case .meaning:
            return "Offline AI vector search by concept (e.g. \"comfort when grieving\", \"wisdom about money\")"
        }
    }

    private func highlightedText(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = .primary
        let tokens = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return attr }

        for tok in tokens {
            let escaped = NSRegularExpression.escapedPattern(for: tok)
            let pattern: String
            switch matchMode {
            case .exact:
                pattern = "\\b\(escaped)\\b"
            case .wordStartsWith, .meaning:
                pattern = "\\b\(escaped)[A-Za-z0-9]*"
            case .contains:
                pattern = escaped
            }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsRange = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: nsRange) {
                if let strRange = Range(match.range, in: text),
                   let attrRange = Range(strRange, in: attr) {
                    attr[attrRange].font = .system(size: 15, weight: .bold, design: .serif)
                    attr[attrRange].backgroundColor = Color.yellow.opacity(0.45)
                }
            }
        }
        return attr
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        strongsHit = viewModel.referenceDB.lookupStrongs(id: trimmed)
        personalHits = viewModel.studyDB.searchPersonalStudy(query: trimmed, limit: 25)
        results = viewModel.referenceDB.searchScripture(
            query: trimmed,
            scopeBookId: currentBookOnly ? viewModel.currentBookId : nil,
            matchMode: matchMode,
            limit: nil
        )
    }
}

// MARK: - Saved (Bookmarks & Highlights), Notes, and View Settings Sheets

public struct SavedSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newCollectionName: String = ""
    @State private var editingLabels: Bool = false
    @State private var labelDrafts: [String: String] = [:]

    public var body: some View {
        NavigationStack {
            List {
                // Topical Collections
                Section("Topical Collections (\(viewModel.collections.count))") {
                    HStack {
                        TextField("New collection (e.g. Promises, Prayer)", text: $newCollectionName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            viewModel.createCollection(name: newCollectionName)
                            newCollectionName = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    ForEach(viewModel.collections) { col in
                        let items = viewModel.studyDB.items(inCollection: col.id)
                        DisclosureGroup {
                            if items.isEmpty {
                                Text("Tap any verse in Scripture → Add to Collection.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(items) { item in
                                Button {
                                    viewModel.navigate(to: VerseRef(bookId: item.bookId, chapter: item.chapter, verse: item.verse))
                                    dismiss()
                                } label: {
                                    Text("\(viewModel.bookName(item.bookId)) \(item.chapter):\(item.verse)")
                                        .font(.subheadline)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(viewModel.theme.accentBlue)
                                Text(col.name).font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.deleteCollection(col)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                // Bookmarks
                Section("Bookmarks (\(viewModel.bookmarks.count))") {
                    if viewModel.bookmarks.isEmpty {
                        Text("No bookmarks yet. Tap any verse to bookmark it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.bookmarks) { bm in
                        Button {
                            viewModel.navigate(to: VerseRef(bookId: bm.bookId, chapter: bm.chapter, verse: bm.verse))
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "bookmark.fill").foregroundStyle(.orange)
                                Text(bm.label)
                                Spacer()
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.deleteBookmark(bm)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                // Highlights + Customizable Labels
                Section {
                    if viewModel.allHighlights.isEmpty {
                        Text("No highlights yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.allHighlights) { hl in
                        Button {
                            viewModel.navigate(to: VerseRef(bookId: hl.bookId, chapter: hl.chapter, verse: hl.verse))
                            dismiss()
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(uiColor: UIColor(hex: hl.colorHex) ?? .systemYellow))
                                    .frame(width: 14, height: 14)
                                Text("\(viewModel.bookName(hl.bookId)) \(hl.chapter):\(hl.verse)")
                                Spacer()
                                Text(hl.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Highlights (\(viewModel.allHighlights.count))")
                        Spacer()
                        Button(editingLabels ? "Done Editing" : "Customize Labels") {
                            if editingLabels {
                                for (id, val) in labelDrafts {
                                    viewModel.renameHighlightCategory(id: id, newName: val)
                                }
                            } else {
                                labelDrafts = Dictionary(uniqueKeysWithValues: viewModel.highlightCategories.map { ($0.id, $0.name) })
                            }
                            editingLabels.toggle()
                        }
                        .font(.caption)
                    }
                }

                if editingLabels {
                    Section("Highlight Color Labels") {
                        ForEach(viewModel.highlightCategories) { cat in
                            HStack {
                                Circle().fill(cat.color).frame(width: 16, height: 16)
                                TextField(cat.name, text: Binding(
                                    get: { labelDrafts[cat.id] ?? cat.name },
                                    set: { labelDrafts[cat.id] = $0 }
                                ))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Passages & Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

public struct NotesSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            List {
                Section("Create New Notebook (Typed + Apple Pencil)") {
                    HStack(spacing: 8) {
                        ForEach([NoteType.sermon, .study, .journal]) { t in
                            Button {
                                dismiss()
                                viewModel.openNewNotebook(type: t, verse: viewModel.studyVerse ?? viewModel.verses.first)
                            } label: {
                                Label(t.rawValue, systemImage: "plus.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                Section("Your Notebooks & Notes (\(viewModel.notes.count))") {
                    if viewModel.notes.isEmpty {
                        Text("No notebooks yet. Create a Sermon, Study, or Journal notebook above.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.notes) { note in
                        Button {
                            dismiss()
                            viewModel.openExistingNotebook(note)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(note.title).font(.headline)
                                    Spacer()
                                    if note.drawingData != nil {
                                        Image(systemName: "pencil.tip")
                                            .font(.caption)
                                            .foregroundStyle(viewModel.theme.accentBlue)
                                    }
                                    Text(note.noteType.rawValue)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                                if let b = note.bookId, let c = note.chapter {
                                    Text(note.verse != nil ? "\(viewModel.bookName(b)) \(c):\(note.verse!)" : "\(viewModel.bookName(b)) \(c)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(viewModel.theme.accentBlue)
                                }
                                if !note.body.isEmpty {
                                    Text(note.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.deleteNote(note)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Notebooks & Sermon Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

public struct ViewSettingsSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            Form {
                Section("Reading Theme & Scripture Text") {
                    Picker("Theme", selection: $viewModel.theme) {
                        ForEach(ReadingTheme.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Red-Letter Words of Christ", isOn: $viewModel.showRedLetter)
                    Toggle("Translator-Supplied Italics", isOn: $viewModel.showItalics)
                    Toggle("Show Verse Numbers", isOn: $viewModel.showVerseNumbers)
                }

                Section("Workspace Mode & Panels") {
                    Picker("Mode", selection: Binding(
                        get: { viewModel.workspaceMode },
                        set: { viewModel.applyMode($0) }
                    )) {
                        ForEach(WorkspaceMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    Toggle("Show Reference Panel (Left)", isOn: Binding(
                        get: { viewModel.showReferencePanel },
                        set: { _ in viewModel.toggleReferencePanel() }
                    ))
                    Toggle("Show Journal Margin (Right)", isOn: Binding(
                        get: { viewModel.showJournalPanel },
                        set: { _ in viewModel.toggleJournalPanel() }
                    ))
                    Toggle("Show Overlapping Ink in Reading Mode", isOn: $viewModel.showInkInReadingMode)
                }

                Section("Journal Paper Style") {
                    Picker("Paper", selection: $viewModel.paperStyle) {
                        ForEach(JournalPaperStyle.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Typography") {
                    VStack(alignment: .leading) {
                        Text("Font Size: \(Int(viewModel.fontSize)) pt")
                        Slider(value: $viewModel.fontSize, in: 14...28, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("Line Spacing: \(Int(viewModel.lineSpacing)) pt")
                        Slider(value: $viewModel.lineSpacing, in: 4...16, step: 1)
                    }
                }
            }
            .navigationTitle("Reading & Workspace View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.persistAppearancePreferences()
                        dismiss()
                    }
                }
            }
        }
    }
}

public struct JournalClipEditorSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    let draft: ClipDraft
    @Environment(\.dismiss) private var dismiss

    @State private var excerptText: String = ""
    @State private var userNoteText: String = ""

    public var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Text(draft.sourceLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(viewModel.theme.accentBlue)
                }

                Section {
                    TextEditor(text: $excerptText)
                        .font(.system(size: 15, design: .serif))
                        .frame(minHeight: 110)
                    HStack {
                        Text("Trim or edit to keep just the words you want.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !excerptText.isEmpty {
                            Button("Clear") { excerptText = "" }
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Clipped Excerpt")
                }

                Section("Your Personal Note (Optional)") {
                    TextEditor(text: $userNoteText)
                        .font(.body)
                        .frame(minHeight: 90)
                }

                if let existingId = draft.editingCardId {
                    Section {
                        Button(role: .destructive) {
                            viewModel.removeJournalClip(id: existingId)
                            dismiss()
                        } label: {
                            Label("Remove Clip from Journal", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle(draft.editingCardId == nil ? "Clip to Journal" : "Edit Journal Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.editingCardId == nil ? "Add to Journal" : "Save") {
                        viewModel.saveClipDraft(
                            sourceLabel: draft.sourceLabel,
                            excerpt: excerptText,
                            userNote: userNoteText,
                            editingCardId: draft.editingCardId
                        )
                        dismiss()
                    }
                    .disabled(excerptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                              userNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                excerptText = draft.initialExcerpt
                userNoteText = draft.initialNote
            }
        }
    }
}
