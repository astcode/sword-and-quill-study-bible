import SwiftUI

// MARK: - Blue Letter Bible–Style Verse Action Popover

public struct VerseActionPopover: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    let verse: Verse
    @State private var showNoteComposer: Bool = false
    @State private var noteType: NoteType = .passage
    @State private var noteTitle: String = ""
    @State private var noteBody: String = ""

    public var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        viewModel.popoverVerse = nil
                    }
                }

            VStack(spacing: 0) {
                // Header bar (BLB style)
                HStack {
                    Text("\(viewModel.bookName(verse.bookId)) \(verse.chapter):\(verse.verse)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            viewModel.popoverVerse = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(viewModel.theme.accentBlue)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // STUDY SECTION
                        sectionHeader("STUDY")
                        actionRow("Cross-References", icon: "arrow.triangle.branch", detail: "\(viewModel.crossRefsByVerse[verse.verse]?.count ?? 0)") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.openLeftStudy(tab: .crossRefs, for: verse)
                            }
                        }
                        actionRow("Interlinear & Strong's", icon: "character.book.closed") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.openLeftStudy(tab: .strongs, for: verse)
                            }
                        }
                        actionRow("Dictionaries", icon: "text.book.closed") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.openLeftStudy(tab: .dictionary, for: verse, dictionarySource: .webster1828)
                            }
                        }
                        actionRow("Topical Study", icon: "books.vertical") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.openLeftStudy(tab: .dictionary, for: verse, dictionarySource: .nave)
                            }
                        }
                        if viewModel.moduleManager.hasEnabledCommentaries {
                            actionRow("Commentaries", icon: "text.quote", detail: "\(viewModel.moduleManager.enabledCommentaries.count)") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.openLeftStudy(tab: .commentary, for: verse)
                                }
                            }
                        }
                        actionRow("Places & Map", icon: "map", detail: "\(viewModel.chapterPlaces.count)") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.openLeftStudy(tab: .places, for: verse)
                            }
                        }
                        actionRow("Parallel Bible", icon: "book.pages") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.openLeftStudy(tab: .parallel, for: verse)
                            }
                        }

                        // ANNOTATIONS SECTION
                        sectionHeader("ANNOTATIONS & NOTEBOOKS")
                        actionRow("Open in Sermon / Study Notebook", icon: "note.text.badge.plus") {
                            viewModel.popoverVerse = nil
                            viewModel.openNewNotebook(type: .sermon, verse: verse)
                        }
                        if let active = viewModel.activeStudy {
                            actionRow("Link to Study \"\(active.name)\" + Note", icon: "book.pages.fill") {
                                viewModel.popoverVerse = nil
                                viewModel.showAddStudyLinkSheet = true
                            }
                        }
                        if let existingNotes = viewModel.chapterNotesByVerse[verse.verse], !existingNotes.isEmpty {
                            ForEach(existingNotes) { linked in
                                actionRow("Linked: \(linked.title)", icon: "note.text") {
                                    viewModel.popoverVerse = nil
                                    viewModel.openExistingNotebook(linked)
                                }
                            }
                        }
                        actionRow("Add Bookmark", icon: "bookmark") {
                            viewModel.addBookmark(for: verse)
                            viewModel.popoverVerse = nil
                        }
                        if !viewModel.collections.isEmpty {
                            Menu {
                                ForEach(viewModel.collections) { col in
                                    Button(col.name) {
                                        viewModel.addVerseToCollection(verse, collection: col)
                                        viewModel.popoverVerse = nil
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.subheadline)
                                        .foregroundStyle(viewModel.theme.accentBlue)
                                        .frame(width: 22)
                                    Text("Add to Collection")
                                        .font(.subheadline)
                                        .foregroundStyle(viewModel.theme.primaryText)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(viewModel.theme.secondaryText)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            Divider().padding(.leading, 48)
                        }
                        actionRow("Pin \"\(viewModel.bookName(verse.bookId)) \(verse.chapter):\(verse.verse)\" to Journal", icon: "pin") {
                            let book = viewModel.referenceDB.book(id: verse.bookId)
                            let ref = CrossReference(
                                id: verse.id,
                                fromBook: viewModel.currentBookId,
                                fromChapter: viewModel.currentChapter,
                                fromVerse: verse.verse,
                                phrase: "",
                                toBook: verse.bookId,
                                toChapter: verse.chapter,
                                toVerseStart: verse.verse,
                                toVerseEnd: verse.verse,
                                toBookAbbr: book?.abbr ?? "Book \(verse.bookId)",
                                toBookName: book?.name ?? "Book \(verse.bookId)"
                            )
                            viewModel.pinCrossReference(ref)
                            viewModel.popoverVerse = nil
                        }
                        actionRow("Copy Verse to Clipboard", icon: "doc.on.doc") {
                            viewModel.copyVerseToClipboard(verse)
                            viewModel.popoverVerse = nil
                        }

                        if showNoteComposer {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("Type", selection: $noteType) {
                                    ForEach(NoteType.allCases) { t in Text(t.rawValue).tag(t) }
                                }
                                .pickerStyle(.segmented)
                                TextField("Title", text: $noteTitle)
                                    .textFieldStyle(.roundedBorder)
                                TextEditor(text: $noteBody)
                                    .frame(height: 80)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(viewModel.theme.dividerColor))
                                HStack {
                                    Spacer()
                                    Button("Cancel") { showNoteComposer = false }
                                        .buttonStyle(.bordered)
                                    Button("Save Note") {
                                        viewModel.saveNote(type: noteType, title: noteTitle, body: noteBody, verse: verse)
                                        viewModel.popoverVerse = nil
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            .padding(12)
                            .background(viewModel.theme.canvasBackground)
                        }

                        // HIGHLIGHTS SECTION (BLB-style named color bars)
                        sectionHeader("HIGHLIGHTS")
                        if viewModel.chapterHighlights[verse.verse] != nil {
                            Button {
                                viewModel.removeHighlight(verse: verse)
                                viewModel.popoverVerse = nil
                            } label: {
                                HStack {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                    Text("Remove Highlight")
                                        .font(.subheadline)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                            }
                            Divider()
                        }

                        ForEach(viewModel.highlightCategories) { preset in
                            Button {
                                viewModel.applyHighlight(verse: verse, preset: preset)
                                viewModel.popoverVerse = nil
                            } label: {
                                HStack {
                                    Text(preset.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(viewModel.theme.primaryText)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(viewModel.theme.secondaryText)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(preset.color.opacity(0.32))
                            }
                            Divider()
                        }
                    }
                }
            }
            .frame(width: 340)
            .frame(maxHeight: 560)
            .background(viewModel.theme.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(viewModel.theme.dividerColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 22, y: 8)
        }
        .transition(.opacity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(viewModel.theme.secondaryText)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 5)
    }

    private func actionRow(_ title: String, icon: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(viewModel.theme.accentBlue)
                        .frame(width: 22)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(viewModel.theme.primaryText)
                    Spacer()
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(viewModel.theme.secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(viewModel.theme.canvasBackground)
                            .clipShape(Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(viewModel.theme.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            Divider().padding(.leading, 48)
        }
    }
}

// MARK: - Left Study Desk (TSK, Strong's, Webster 1828, Parallel Bible Reader)

public struct LeftStudyDeskView: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @State private var manualStrongsQuery: String = ""
    @State private var manualWebsterQuery: String = ""
    @State private var showParallelPicker: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header with Tab Bar + Close button
            HStack(spacing: 6) {
                let visibleTabs = LeftPanelTab.allCases.filter { tab in
                    tab != .commentary || viewModel.moduleManager.hasEnabledCommentaries
                }
                ForEach(visibleTabs) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.leftPanelTab = tab
                        }
                    } label: {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(viewModel.leftPanelTab == tab ? viewModel.theme.accentBlue.opacity(0.2) : Color.clear)
                            .foregroundStyle(viewModel.leftPanelTab == tab ? viewModel.theme.accentBlue : viewModel.theme.secondaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .accessibilityLabel(tab.rawValue)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleReferencePanel()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(viewModel.theme.secondaryText)
                        .frame(width: 26, height: 28)
                }
                .accessibilityLabel("Close Study Panel")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(viewModel.theme.panelBackground)

            Divider().overlay(viewModel.theme.dividerColor)

            // Active Tab Content
            switch viewModel.leftPanelTab {
            case .crossRefs:
                tskTabView
            case .strongs:
                strongsTabView
            case .dictionary:
                websterTabView
            case .commentary:
                CommentaryDeskView(viewModel: viewModel, moduleManager: viewModel.moduleManager)
            case .places:
                PlacesMapDeskView(viewModel: viewModel)
            case .parallel:
                parallelBibleTabView
            }
        }
        .background(viewModel.theme.panelBackground.opacity(0.65))
        .sheet(isPresented: $showParallelPicker) {
            ParallelScripturePickerSheet(viewModel: viewModel)
        }
    }

    // MARK: Tab 1 — TSK Cross-References

    private var tskTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let activeVerse = viewModel.studyVerse ?? viewModel.verses.first
                if let verse = activeVerse {
                    let refs = viewModel.crossRefsByVerse[verse.verse] ?? []
                    let groups = viewModel.groupedCrossReferences(for: verse.verse)

                    HStack {
                        Text("TSK — \(viewModel.bookName(verse.bookId)) \(verse.chapter):\(verse.verse)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(viewModel.theme.primaryText)
                        Spacer()
                        Text("\(refs.count) refs")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(viewModel.theme.secondaryText)
                    }

                    if refs.isEmpty {
                        Text("No TSK cross-references for this verse. Tap any verse in Scripture to inspect its cross-references.")
                            .font(.caption)
                            .foregroundStyle(viewModel.theme.secondaryText)
                    } else {
                        ForEach(groups, id: \.phrase) { group in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\"\(group.phrase)\"")
                                    .font(.caption.weight(.semibold))
                                    .italic()
                                    .foregroundStyle(viewModel.theme.secondaryText)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 5)], alignment: .leading, spacing: 5) {
                                    ForEach(group.refs) { ref in
                                        Button {
                                            viewModel.openCrossRefPreview(ref)
                                        } label: {
                                            Text(ref.displayRef)
                                                .font(.system(size: 12, weight: .medium, design: .serif))
                                                .foregroundStyle(viewModel.theme.accentBlue)
                                                .padding(.horizontal, 7)
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
            .padding(12)
        }
        .onAppear {
            if viewModel.studyDictionaryResults.isEmpty {
                viewModel.loadContextualDictionaryForActiveVerse()
            }
        }
    }

    @ViewBuilder
    private func crossRefReaderCard(_ ref: CrossReference) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ref.displayRef)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(viewModel.theme.accentBlue)
                Spacer()
                Button {
                    viewModel.previewCrossRef = nil
                    viewModel.activePinnedRefId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(viewModel.theme.secondaryText)
                }
            }

            if !ref.phrase.isEmpty {
                Text("Phrase: \"\(ref.phrase)\"")
                    .font(.caption2)
                    .foregroundStyle(viewModel.theme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.previewCrossRefVerses) { v in
                    let isCore = v.verse >= ref.toVerseStart && v.verse <= max(ref.toVerseStart, ref.toVerseEnd)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(v.verse)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isCore ? viewModel.theme.accentBlue : viewModel.theme.secondaryText)
                            .frame(width: 20, alignment: .trailing)
                        Text(v.text)
                            .font(.system(size: 14.5, design: .serif))
                            .foregroundStyle(isCore ? viewModel.theme.primaryText : viewModel.theme.secondaryText)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(10)
            .background(viewModel.theme.canvasBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 6) {
                Button(viewModel.previewCrossRefShowContext ? "Exact" : "±2 Context") {
                    viewModel.toggleCrossRefContext()
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)

                if let pinnedId = viewModel.activePinnedRefId {
                    Button("Remove Pin", role: .destructive) {
                        viewModel.removePinnedReference(id: pinnedId)
                        viewModel.activePinnedRefId = nil
                        viewModel.previewCrossRef = nil
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        viewModel.pinCrossReference(ref)
                    } label: {
                        Label("Pin", systemImage: "pin")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    let text = viewModel.previewCrossRefVerses.map(\.text).joined(separator: " ")
                    viewModel.startClipToJournal(sourceLabel: ref.displayRef, text: text)
                } label: {
                    Label("Clip", systemImage: "scissors")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Button("Parallel") {
                    viewModel.navigateParallel(bookId: ref.toBook, chapter: ref.toChapter)
                    viewModel.leftPanelTab = .parallel
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
            }

            Button {
                viewModel.navigate(to: VerseRef(bookId: ref.toBook, chapter: ref.toChapter, verse: ref.toVerseStart))
                viewModel.previewCrossRef = nil
                viewModel.activePinnedRefId = nil
            } label: {
                Label("Go to \(ref.toBookName) \(ref.toChapter):\(ref.toVerseStart)", systemImage: "arrow.right.circle.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.theme.accentBlue)

            Divider().overlay(viewModel.theme.dividerColor)
        }
    }

    // MARK: Tab 2 — Interlinear Greek/Hebrew & Strong's Concordance

    private var strongsTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    TextField("Strong's (G25, H430, grace)", text: $manualStrongsQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit { runManualStrongs() }
                    Button("Go") { runManualStrongs() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                }

                // Selected Strong's Lexicon Card (from tapping any Strong's badge in the Interlinear!)
                if let entry = viewModel.selectedStrongsEntry {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.lemma).font(.title3.weight(.semibold))
                            Text("\(entry.strongsId) · \(entry.translit)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(viewModel.theme.accentBlue)
                            Spacer()
                            Button {
                                viewModel.selectedStrongsEntry = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(viewModel.theme.secondaryText)
                            }
                        }
                        if !entry.pronunciation.isEmpty {
                            Text("Pronunciation: \(entry.pronunciation)")
                                .font(.caption2)
                                .foregroundStyle(viewModel.theme.secondaryText)
                        }
                        if !entry.derivation.isEmpty {
                            Text(entry.derivation)
                                .font(.caption2)
                                .foregroundStyle(viewModel.theme.secondaryText)
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

                        HStack(spacing: 8) {
                            Button {
                                let clipBody = [entry.definition, entry.kjvUsage.isEmpty ? nil : "KJV: \(entry.kjvUsage)"]
                                    .compactMap { $0 }
                                    .joined(separator: " — ")
                                viewModel.startClipToJournal(
                                    sourceLabel: "Strong's \(entry.strongsId) (\(entry.translit))",
                                    text: clipBody
                                )
                            } label: {
                                Label("Clip to Journal", systemImage: "scissors")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                        .padding(.top, 2)

                        if !viewModel.strongsOccurrences.isEmpty {
                            Divider().overlay(viewModel.theme.dividerColor)
                            Text("SCRIPTURE OCCURRENCES (\(viewModel.strongsOccurrences.count)\(viewModel.strongsOccurrences.count == 30 ? "+" : ""))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(viewModel.theme.secondaryText)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 5)], alignment: .leading, spacing: 5) {
                                ForEach(viewModel.strongsOccurrences) { occ in
                                    Button {
                                        let bk = viewModel.referenceDB.book(id: occ.bookId)
                                        let xref = CrossReference(
                                            id: occ.id,
                                            fromBook: occ.bookId,
                                            fromChapter: occ.chapter,
                                            fromVerse: occ.verse,
                                            phrase: "\(entry.strongsId) (\(entry.translit))",
                                            toBook: occ.bookId,
                                            toChapter: occ.chapter,
                                            toVerseStart: occ.verse,
                                            toVerseEnd: occ.verse,
                                            toBookAbbr: bk?.abbr ?? occ.bookName,
                                            toBookName: occ.bookName
                                        )
                                        viewModel.openCrossRefPreview(xref)
                                    } label: {
                                        Text("\(viewModel.referenceDB.book(id: occ.bookId)?.abbr ?? occ.bookName) \(occ.chapter):\(occ.verse)")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(viewModel.theme.accentBlue)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(viewModel.theme.canvasBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(viewModel.theme.accentBlue.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(viewModel.theme.accentBlue.opacity(0.35), lineWidth: 1))
                }

                // Manual Strong's Search Results (if user searched)
                if !viewModel.studyStrongsResults.isEmpty {
                    ForEach(viewModel.studyStrongsResults) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.lemma).font(.title3)
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

                // Word-by-Word Interlinear Table (BLB-style!)
                if let verse = viewModel.studyVerse ?? viewModel.verses.first {
                    let isOT = viewModel.referenceDB.book(id: verse.bookId)?.testament == "OT"
                    HStack {
                        Text("\(isOT ? "HEBREW" : "GREEK") INTERLINEAR — \(viewModel.bookName(verse.bookId).uppercased()) \(verse.chapter):\(verse.verse)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(viewModel.theme.secondaryText)
                        Spacer()
                    }

                    if viewModel.interlinearWords.isEmpty {
                        Button("Load Interlinear for \(viewModel.bookName(verse.bookId)) \(verse.chapter):\(verse.verse)") {
                            viewModel.loadInterlinearForActiveVerse()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                    } else {
                        // Full Original Text Banner
                        let joinedOriginal = viewModel.interlinearWords.map(\.originalText).joined(separator: " ")
                        Text(joinedOriginal)
                            .font(.system(size: isOT ? 19 : 16, design: .serif))
                            .foregroundStyle(viewModel.theme.primaryText)
                            .multilineTextAlignment(isOT ? .trailing : .leading)
                            .frame(maxWidth: .infinity, alignment: isOT ? .trailing : .leading)
                            .padding(10)
                            .background(viewModel.theme.canvasBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Word-by-word rows
                        VStack(spacing: 6) {
                            ForEach(viewModel.interlinearWords) { w in
                                HStack(alignment: .center, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(w.gloss)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(viewModel.theme.primaryText)
                                        if !w.morph.isEmpty {
                                            Text(w.morph)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(viewModel.theme.secondaryText)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    if !w.strongsId.isEmpty {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                viewModel.selectStrongsId(w.strongsId)
                                            }
                                        } label: {
                                            Text(w.strongsId)
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(viewModel.selectedStrongsEntry?.strongsId == w.strongsId ? .white : viewModel.theme.accentBlue)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 4)
                                                .background(viewModel.selectedStrongsEntry?.strongsId == w.strongsId ? viewModel.theme.accentBlue : viewModel.theme.accentBlue.opacity(0.14))
                                                .clipShape(Capsule())
                                        }
                                    }

                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(w.originalText)
                                            .font(.system(size: isOT ? 17 : 14, weight: .medium, design: .serif))
                                            .foregroundStyle(viewModel.theme.primaryText)
                                        Text(w.translit)
                                            .font(.caption2)
                                            .italic()
                                            .foregroundStyle(viewModel.theme.secondaryText)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(viewModel.theme.canvasBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .onAppear {
            if viewModel.interlinearWords.isEmpty {
                viewModel.loadInterlinearForActiveVerse()
            }
        }
    }

    private func runManualStrongs() {
        let q = manualStrongsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        viewModel.studyWord = q
        viewModel.studyStrongsResults = viewModel.referenceDB.searchStrongs(word: q, testament: nil, limit: 10)
    }

    // MARK: Tab 3 — Dictionaries & Topical Library (Webster 1828, Easton, Nave, Torrey)

    private var websterTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Source", selection: $viewModel.selectedDictionarySource) {
                    ForEach(StudyDictionarySource.allCases) { src in
                        Text(src.rawValue).tag(src)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedDictionarySource) { _, newSrc in
                    let q = manualWebsterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !q.isEmpty {
                        viewModel.runDictionaryLookup(query: q, source: newSrc)
                    } else {
                        viewModel.loadContextualDictionaryForActiveVerse(source: newSrc)
                    }
                }

                HStack {
                    if let verse = viewModel.studyVerse ?? viewModel.verses.first, viewModel.studyWord == nil {
                        Text("\(viewModel.selectedDictionarySource.fullName) · \(viewModel.bookName(verse.bookId)) \(verse.chapter):\(verse.verse)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(viewModel.theme.accentBlue)
                    } else {
                        Text(viewModel.selectedDictionarySource.fullName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(viewModel.theme.secondaryText)
                    }
                    Spacer()
                    if viewModel.studyWord != nil || !manualWebsterQuery.isEmpty {
                        Button("Verse Context") {
                            manualWebsterQuery = ""
                            viewModel.loadContextualDictionaryForActiveVerse()
                        }
                        .font(.caption2.weight(.semibold))
                    }
                }

                HStack(spacing: 6) {
                    TextField("Search \(viewModel.selectedDictionarySource.rawValue) (e.g. grace, faith, prayer)", text: $manualWebsterQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit { runManualWebster() }
                    Button("Go") { runManualWebster() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                }

                if let verse = viewModel.studyVerse ?? viewModel.verses.first {
                    wordChipGrid(for: verse, targetTab: .dictionary)
                }

                if viewModel.studyDictionaryResults.isEmpty {
                    Text("Tap any word above or search to explore Webster's 1828 Dictionary, Easton's Bible Dictionary, Nave's Topical Bible, and Torrey's Topical Textbook — 100% offline.")
                        .font(.caption)
                        .foregroundStyle(viewModel.theme.secondaryText)
                } else {
                    ForEach(viewModel.studyDictionaryResults) { entry in
                        let linkedRefs = entry.source == .webster1828 ? [] : viewModel.referenceDB.extractReferences(from: entry.body, limit: 16)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.headword.uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(viewModel.theme.accentBlue)
                                Spacer()
                                Button {
                                    viewModel.startClipToJournal(
                                        sourceLabel: "\(entry.source.rawValue) · \(entry.headword)",
                                        text: entry.body
                                    )
                                } label: {
                                    Label("Clip", systemImage: "scissors")
                                        .font(.caption2.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            Text(entry.body)
                                .font(.system(size: 13.5, design: .serif))
                                .foregroundStyle(viewModel.theme.primaryText)
                                .lineSpacing(3)

                            if !linkedRefs.isEmpty {
                                Divider().overlay(viewModel.theme.dividerColor)
                                Text("REFERENCED VERSES")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(viewModel.theme.secondaryText)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 4)], alignment: .leading, spacing: 4) {
                                    ForEach(linkedRefs) { ref in
                                        Button {
                                            viewModel.openCrossRefPreview(ref)
                                        } label: {
                                            Text(ref.displayRef)
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(viewModel.theme.accentBlue)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(viewModel.theme.panelBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(viewModel.theme.canvasBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(12)
        }
        .onAppear {
            if viewModel.studyDictionaryResults.isEmpty {
                viewModel.loadContextualDictionaryForActiveVerse()
            }
        }
    }

    private func runManualWebster() {
        let q = manualWebsterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        viewModel.runDictionaryLookup(query: q)
    }

    @ViewBuilder
    private func wordChipGrid(for verse: Verse, targetTab: LeftPanelTab) -> some View {
        let words = verse.text.split(separator: " ").map(String.init)
        VStack(alignment: .leading, spacing: 5) {
            Text("WORDS IN \(viewModel.bookName(verse.bookId).uppercased()) \(verse.chapter):\(verse.verse)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(viewModel.theme.secondaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 5)], alignment: .leading, spacing: 5) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, rawWord in
                    let clean = rawWord.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                    if !clean.isEmpty {
                        Button {
                            manualWebsterQuery = clean
                            viewModel.runDictionaryLookup(query: clean)
                        } label: {
                            Text(clean)
                                .font(.caption2.weight(viewModel.studyWord?.lowercased() == clean.lowercased() ? .bold : .regular))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
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

    // MARK: Tab 4 — Parallel Bible Reader (Gospel Harmony / Acts & Epistles Study)

    private var parallelBibleTabView: some View {
        VStack(spacing: 0) {
            // Parallel Chapter Header Bar
            HStack(spacing: 6) {
                Button {
                    viewModel.parallelPreviousChapter()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .frame(width: 24, height: 24)
                }

                Spacer()

                Button {
                    showParallelPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.parallelLocationTitle)
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(viewModel.theme.accentBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.theme.canvasBackground)
                    .clipShape(Capsule())
                }

                Spacer()

                Button {
                    viewModel.parallelNextChapter()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .frame(width: 24, height: 24)
                }
            }
            .foregroundStyle(viewModel.theme.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider().overlay(viewModel.theme.dividerColor)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.parallelVerses) { verse in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(verse.verse)")
                                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                                .foregroundStyle(viewModel.theme.secondaryText.opacity(0.8))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(width: 26, alignment: .trailing)
                            Text(verse.text)
                                .font(.system(size: max(14, viewModel.fontSize - 3), design: .serif))
                                .foregroundStyle(viewModel.theme.primaryText)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                viewModel.openVersePopover(verse)
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Lightweight Dismissible Passage Preview Popup (Tap Outside to Close)

public struct PassagePreviewPopup: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    let ref: CrossReference

    public var body: some View {
        ZStack {
            // Tap anywhere outside the popup to dismiss immediately without losing your study!
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.dismissCrossRefPreview()
                    }
                }

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ref.displayRef) (KJV)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(viewModel.theme.accentBlue)
                        if !ref.phrase.isEmpty {
                            Text(ref.phrase)
                                .font(.caption)
                                .foregroundStyle(viewModel.theme.secondaryText)
                        }
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.dismissCrossRefPreview()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(viewModel.theme.secondaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(viewModel.theme.dividerColor)

                // Complete Passage Text
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.previewCrossRefVerses) { v in
                            let isCore = v.verse >= ref.toVerseStart && v.verse <= max(ref.toVerseStart, ref.toVerseEnd)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(v.verse)")
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundStyle(isCore ? viewModel.theme.accentBlue.opacity(0.85) : viewModel.theme.secondaryText.opacity(0.75))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: 28, alignment: .trailing)
                                Text(v.text)
                                    .font(.system(size: 16.5, design: .serif))
                                    .foregroundStyle(isCore ? viewModel.theme.primaryText : viewModel.theme.secondaryText)
                                    .lineSpacing(5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 340)

                Divider().overlay(viewModel.theme.dividerColor)

                // Compact Action Bar (single-line buttons, zero word-wrapping)
                HStack(spacing: 8) {
                    Button(viewModel.previewCrossRefShowContext ? "Exact" : "±2 Context") {
                        viewModel.toggleCrossRefContext()
                    }
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let pinnedId = viewModel.activePinnedRefId {
                        Button("Remove Pin", role: .destructive) {
                            viewModel.removePinnedReference(id: pinnedId)
                            viewModel.dismissCrossRefPreview()
                        }
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button {
                            viewModel.pinCrossReference(ref)
                        } label: {
                            Label("Pin", systemImage: "pin")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        let text = viewModel.previewCrossRefVerses.map(\.text).joined(separator: " ")
                        viewModel.dismissCrossRefPreview()
                        viewModel.startClipToJournal(sourceLabel: ref.displayRef, text: text)
                    } label: {
                        Label("Clip", systemImage: "scissors")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Parallel") {
                        viewModel.navigateParallel(bookId: ref.toBook, chapter: ref.toChapter)
                        viewModel.leftPanelTab = .parallel
                        viewModel.showReferencePanel = true
                        viewModel.dismissCrossRefPreview()
                    }
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer(minLength: 6)

                    Button {
                        viewModel.navigate(to: VerseRef(bookId: ref.toBook, chapter: ref.toChapter, verse: ref.toVerseStart))
                        viewModel.dismissCrossRefPreview()
                    } label: {
                        Label("Go", systemImage: "arrow.right.circle.fill")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(viewModel.theme.accentBlue)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(width: 580)
            .background(viewModel.theme.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(viewModel.theme.dividerColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.32), radius: 24, y: 8)
        }
        .transition(.opacity)
    }
}

private struct ParallelScripturePickerSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTestament: String = "NT"
    @State private var selectedBookId: Int = 40

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("Testament", selection: $selectedTestament) {
                    Text("Old Testament").tag("OT")
                    Text("New Testament").tag("NT")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                HStack(alignment: .top) {
                    List(viewModel.books.filter { $0.testament == selectedTestament }) { book in
                        Button {
                            selectedBookId = book.id
                        } label: {
                            HStack {
                                Text(book.name)
                                    .font(.body.weight(selectedBookId == book.id ? .bold : .regular))
                                Spacer()
                                Text("\(book.chapterCount)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(selectedBookId == book.id ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                    .listStyle(.plain)
                    .frame(width: 210)

                    Divider()

                    ScrollView {
                        if let book = viewModel.books.first(where: { $0.id == selectedBookId }) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                                ForEach(1...book.chapterCount, id: \.self) { ch in
                                    Button {
                                        viewModel.navigateParallel(bookId: book.id, chapter: ch)
                                        dismiss()
                                    } label: {
                                        Text("\(ch)")
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                            .background(Color.secondary.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Parallel Passage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear {
                selectedBookId = viewModel.parallelBookId
                selectedTestament = viewModel.referenceDB.book(id: viewModel.parallelBookId)?.testament ?? "NT"
            }
        }
    }
}
