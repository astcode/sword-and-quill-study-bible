import SwiftUI

public struct ScriptureWorkspaceView: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @State private var verseFrames: [Int: CGRect] = [:]
    @State private var unifiedNaturalHeight: CGFloat = 1200

    public var body: some View {
        ZStack {
            viewModel.theme.canvasBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopNavigationBar(viewModel: viewModel)

                ZStack(alignment: .trailing) {
                    GeometryReader { geo in
                        mainScrollWorkspace(totalWidth: geo.size.width)
                    }

                    if let popVerse = viewModel.popoverVerse {
                        VerseActionPopover(viewModel: viewModel, verse: popVerse)
                    }

                    if let previewRef = viewModel.previewCrossRef {
                        PassagePreviewPopup(viewModel: viewModel, ref: previewRef)
                    }

                    if viewModel.showMainMenu {
                        mainMenuOverlay
                    }

                    // Floating Pen Toolbox directly above Bottom Bar
                    if viewModel.showPenToolbox {
                        VStack {
                            Spacer()
                            FloatingPenToolbox(viewModel: viewModel)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Floating Zoom Reset Pill when zoomed in for fine writing
                    if viewModel.journalZoomScale > 1.01 {
                        VStack {
                            HStack {
                                Spacer()
                                HStack(spacing: 8) {
                                    Text(String(format: "Zoom %.1f×", viewModel.journalZoomScale))
                                        .font(.caption.weight(.semibold))
                                    Button("Reset 1×") {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            viewModel.setZoom(1.0)
                                        }
                                    }
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(viewModel.theme.accentBlue)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.theme.panelBackground.opacity(0.95))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(viewModel.theme.dividerColor, lineWidth: 1))
                                .shadow(radius: 6)
                                .padding(.trailing, viewModel.showStudyPanel ? 356 : 16)
                                .padding(.top, 12)
                            }
                            Spacer()
                        }
                    }

                    if let toast = viewModel.toastMessage {
                        VStack {
                            Text(toast)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.78))
                                .clipShape(Capsule())
                                .padding(.top, 12)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false)
                    }
                }

                BottomUtilityBar(viewModel: viewModel)
            }
        }
        .preferredColorScheme(viewModel.theme.preferredColorScheme)
        .sheet(isPresented: $viewModel.showScripturePicker) {
            ScripturePickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showSearchSheet) {
            SearchSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showSavedSheet) {
            SavedSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showNotesSheet) {
            NotesSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showViewSettings) {
            ViewSettingsSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.activeClipDraft) { draft in
            JournalClipEditorSheet(viewModel: viewModel, draft: draft)
        }
        .sheet(item: $viewModel.activeNotebookNote) { note in
            NotebookEditorSheet(viewModel: viewModel, note: note)
        }
        .sheet(isPresented: $viewModel.showHistorySheet) {
            ReadingHistorySheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showStickerSheet) {
            StickerLibrarySheet(viewModel: viewModel, targetLabel: viewModel.currentLocationTitle) { sticker in
                viewModel.placeStickerOnChapter(sticker)
            }
        }
        .sheet(item: $viewModel.activeShareSheetItem) { item in
            ActivityShareSheet(url: item.url)
        }
        .sheet(isPresented: $viewModel.showMarginOCRScanner) {
            MarginOCRScannerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showStudyDashboard) {
            StudyDashboardSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showNewStudySheet) {
            NewStudySheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showStudyTrailSheet) {
            StudyTrailSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showAddStudyLinkSheet) {
            StudyMarginLinkEditorSheet(viewModel: viewModel, existingLink: nil)
        }
        .sheet(item: $viewModel.editingStudyMarginLink) { link in
            StudyMarginLinkEditorSheet(viewModel: viewModel, existingLink: link)
        }
    }

    @ViewBuilder
    private func mainScrollWorkspace(totalWidth: CGFloat) -> some View {
        // Adaptive Layout: Landscape (>= 860pt) docks Left Study Desk side-by-side;
        // Portrait / Split View / Compact (< 860pt) presents Left Study Desk as a clean slide-over drawer.
        // CRITICAL: Never hide/resize the docked Left Panel based on zoomScale, so zooming 1x <-> 3.5x
        // magnifies the exact same unchanging coordinate space and Apple Pencil ink stays 100% pixel-locked!
        let useDockedLeftPanel = totalWidth >= 860
        let leftDrawerWidth: CGFloat = min(320, max(260, totalWidth * 0.36))
        let dockedLeftWidth: CGFloat = (useDockedLeftPanel && viewModel.showReferencePanel) ? min(300, max(240, totalWidth * 0.27)) : 0
        let leftDividerWidth: CGFloat = dockedLeftWidth > 0 ? 1 : 0
        let remainingWidth = max(280, totalWidth - dockedLeftWidth - leftDividerWidth)
        let innerDividerWidth: CGFloat = viewModel.showJournalPanel ? 1 : 0
        let usableInnerWidth = max(260, remainingWidth - innerDividerWidth)
        let scriptureWidth: CGFloat = {
            if !viewModel.showJournalPanel {
                return min(760, usableInnerWidth)
            }
            return floor(usableInnerWidth * (dockedLeftWidth > 0 ? 0.56 : 0.54))
        }()
        let journalWidth: CGFloat = viewModel.showJournalPanel ? max(140, usableInnerWidth - scriptureWidth) : 0
        let unifiedWidth: CGFloat = remainingWidth

        ZStack(alignment: .leading) {
            HStack(alignment: .top, spacing: 0) {
                // DOCKED LEFT PANEL (Wide iPad Landscape)
                if useDockedLeftPanel && viewModel.showReferencePanel {
                    LeftStudyDeskView(viewModel: viewModel)
                        .frame(width: dockedLeftWidth)
                        .frame(maxHeight: .infinity)
                        .clipped()
                    dashedVerticalDivider
                }

                // UNIFIED ZOOMABLE WRITING WORKSPACE: Center KJV Scripture + Right Journal Margin
                ZoomableCanvasScrollView(zoomScale: $viewModel.journalZoomScale, contentWidth: unifiedWidth) {
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .top, spacing: 0) {
                            if !viewModel.showJournalPanel {
                                Spacer(minLength: 0)
                            }

                            scriptureColumn(width: scriptureWidth)

                            if viewModel.showJournalPanel {
                                dashedVerticalDivider
                                journalMarginColumn(width: journalWidth)
                            } else {
                                Spacer(minLength: 0)
                            }
                        }

                        // Unified Apple Pencil Canvas (hidden in Reading Mode unless toggled on; ink preserved!)
                        if viewModel.shouldShowInkOverlay {
                            UnifiedBibleCanvas(viewModel: viewModel) { tapPoint in
                                handleFingerTapOnCanvas(tapPoint)
                            }

                            // Draggable Pinned Reference Chips — uses .offset() so hit-box is ONLY the tiny pill!
                            ForEach(viewModel.pinnedReferences) { pin in
                                DraggableReferenceChip(
                                    pin: pin,
                                    theme: viewModel.theme,
                                    onTap: { viewModel.openPinnedReference(pin) },
                                    onMove: { newPt in viewModel.movePinnedReference(id: pin.id, to: newPt) }
                                )
                            }

                            // Draggable Movable Study Clip Cards (trimmed excerpts + editable personal notes!)
                            ForEach(viewModel.journalClips) { clip in
                                DraggableClipCard(
                                    clip: clip,
                                    theme: viewModel.theme,
                                    onTap: { viewModel.startEditClip(clip) },
                                    onMove: { newPt in viewModel.moveJournalClip(id: clip.id, to: newPt) }
                                )
                            }

                            // Draggable Permanent Study Link + Margin Note Cards (links Bible ink back to a Study!)
                            ForEach(viewModel.chapterStudyLinks) { link in
                                DraggableStudyLinkCard(
                                    link: link,
                                    theme: viewModel.theme,
                                    onTap: { viewModel.editingStudyMarginLink = link },
                                    onMove: { newPt in
                                        var next = link
                                        next.posX = Double(newPt.x)
                                        next.posY = Double(newPt.y)
                                        viewModel.updateStudyMarginLink(next)
                                    }
                                )
                            }

                            // Draggable, Resizable, Rotatable Stickers on Bible & Margin Canvas
                            ForEach(viewModel.chapterStickers) { placed in
                                if let item = viewModel.stickerItem(for: placed.stickerId) {
                                    DraggablePlacedSticker(
                                        placed: placed,
                                        item: item,
                                        isSelected: viewModel.selectedChapterStickerId == placed.id,
                                        theme: viewModel.theme,
                                        onSelect: {
                                            viewModel.selectedChapterStickerId = (viewModel.selectedChapterStickerId == placed.id) ? nil : placed.id
                                        },
                                        onUpdate: { updated in
                                            viewModel.updateChapterSticker(updated)
                                        },
                                        onDelete: {
                                            viewModel.removeChapterSticker(id: placed.id)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .frame(width: unifiedWidth, alignment: .topLeading)
                    .coordinateSpace(name: "UnifiedCanvasSpace")
                    .onPreferenceChange(VerseFramePreferenceKey.self) { frames in
                        verseFrames = frames
                        let realVerses = frames.filter { $0.key > 0 }
                        viewModel.updateLayoutForInkReflow(
                            verseFrames: realVerses,
                            scriptureWidth: scriptureWidth,
                            canvasWidth: unifiedWidth
                        )
                    }
                }
            }

            // SLIDE-OVER LEFT STUDY DESK (iPad Portrait, Split View, Slide Over & Compact Widths)
            // Uses side-by-side HStack so the dim backdrop NEVER overlaps or steals scroll gestures from LeftStudyDeskView!
            if !useDockedLeftPanel && viewModel.showReferencePanel {
                HStack(spacing: 0) {
                    LeftStudyDeskView(viewModel: viewModel)
                        .frame(width: leftDrawerWidth)
                        .frame(maxHeight: .infinity)
                        .background(viewModel.theme.panelBackground)
                        .clipped()
                        .shadow(color: .black.opacity(0.25), radius: 14, x: 4)

                    Color.black.opacity(0.24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.toggleReferencePanel()
                            }
                        }
                }
                .zIndex(20)
                .transition(.move(edge: .leading))
            }
        }
    }

    // MARK: - Left Column (References)

    private func referenceColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(viewModel.referenceFilter.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(viewModel.theme.secondaryText)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.setShowAllReferencesExpanded(!viewModel.showAllReferencesExpanded)
                    }
                } label: {
                    Text(viewModel.showAllReferencesExpanded ? "Compact" : "All")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(viewModel.theme.accentBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(viewModel.theme.accentBlue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 20)

            ForEach(viewModel.verses) { verse in
                let refs = viewModel.crossRefsByVerse[verse.verse] ?? []
                let vNotes = viewModel.chapterNotesByVerse[verse.verse] ?? []
                let expanded = viewModel.isReferenceExpanded(for: verse.verse)

                VStack(alignment: .leading, spacing: 4) {
                    if !refs.isEmpty || !vNotes.isEmpty {
                        Text("v.\(verse.verse)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(viewModel.theme.secondaryText)
                    }

                    if viewModel.referenceFilter == .tsk || viewModel.referenceFilter == .all {
                        if expanded {
                            let groups = viewModel.groupedCrossReferences(for: verse.verse)
                            ForEach(groups, id: \.phrase) { group in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\"\(group.phrase)\"")
                                        .font(.system(size: 10, weight: .semibold, design: .serif))
                                        .italic()
                                        .foregroundStyle(viewModel.theme.secondaryText)
                                        .padding(.top, 2)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], alignment: .leading, spacing: 3) {
                                        ForEach(group.refs) { ref in
                                            Button {
                                                viewModel.openCrossRefPreview(ref)
                                            } label: {
                                                Text(ref.displayRef)
                                                    .font(.system(size: 11.5, design: .serif))
                                                    .foregroundStyle(viewModel.theme.accentBlue)
                                                    .lineLimit(1)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                            }
                            if !viewModel.showAllReferencesExpanded && refs.count > 3 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.toggleReferenceExpansion(for: verse.verse)
                                    }
                                } label: {
                                    Text("Show less ⌃")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(viewModel.theme.secondaryText)
                                        .padding(.top, 2)
                                }
                            }
                        } else {
                            ForEach(refs.prefix(3)) { ref in
                                Button {
                                    viewModel.openCrossRefPreview(ref)
                                } label: {
                                    Text(ref.displayRef)
                                        .font(.system(size: 13, design: .serif))
                                        .foregroundStyle(viewModel.theme.accentBlue)
                                        .lineLimit(1)
                                }
                            }
                            if refs.count > 3 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.toggleReferenceExpansion(for: verse.verse)
                                    }
                                } label: {
                                    Text("+\(refs.count - 3) more ⌄")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(viewModel.theme.accentBlue.opacity(0.85))
                                }
                            }
                        }
                    }

                    if viewModel.referenceFilter == .personal || viewModel.referenceFilter == .all {
                        ForEach(vNotes) { note in
                            Button {
                                viewModel.showNotesSheet = true
                            } label: {
                                Label(note.title, systemImage: "note.text")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: expanded ? 0 : estimatedVerseHeight(verse), alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    // MARK: - Center Column (KJV Scripture)

    private func scriptureColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chapter Heading (clean, no duplicate arrows)
            Text(viewModel.currentLocationTitle)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(viewModel.theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 16)

            // Verses
            ForEach(viewModel.verses) { verse in
                let highlight = viewModel.chapterHighlights[verse.verse]
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if viewModel.showVerseNumbers {
                        let hasLinkedNote = !(viewModel.chapterNotesByVerse[verse.verse] ?? []).isEmpty
                        HStack(spacing: 2) {
                            if hasLinkedNote {
                                Image(systemName: "note.text")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.orange)
                            }
                            Text("\(verse.verse)")
                                .font(.system(size: max(10, viewModel.fontSize * 0.56), weight: .regular, design: .rounded))
                                .foregroundStyle(viewModel.theme.secondaryText.opacity(0.8))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .frame(width: 34, alignment: .trailing)
                    }

                    Text(formattedVerseText(verse))
                        .lineSpacing(viewModel.lineSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Group {
                        if let hl = highlight {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(uiColor: UIColor(hex: hl.colorHex) ?? .systemYellow).opacity(0.24))
                                .padding(.horizontal, 10)
                        } else if viewModel.studyVerse?.id == verse.id && viewModel.showStudyPanel {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.theme.accentBlue.opacity(0.10))
                                .padding(.horizontal, 10)
                        }
                    }
                )
                .id("verse-\(verse.verse)")
                .contentShape(Rectangle())
                .onTapGesture {
                    if !viewModel.shouldShowInkOverlay {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            viewModel.openVersePopover(verse)
                        }
                    }
                }
                .background(
                    GeometryReader { vGeo in
                        Color.clear.preference(
                            key: VerseFramePreferenceKey.self,
                            value: [verse.verse: vGeo.frame(in: .named("UnifiedCanvasSpace"))]
                        )
                    }
                )
            }

            // Bottom Chapter Navigation (tracked via sentinel keys -1 / -2 so finger taps work through UnifiedBibleCanvas!)
            HStack {
                Button {
                    viewModel.previousChapter()
                } label: {
                    Label("Previous Chapter", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .background(
                    GeometryReader { bGeo in
                        Color.clear.preference(
                            key: VerseFramePreferenceKey.self,
                            value: [-1: bGeo.frame(in: .named("UnifiedCanvasSpace"))]
                        )
                    }
                )
                Spacer()
                Button {
                    viewModel.nextChapter()
                } label: {
                    Label("Next Chapter", systemImage: "chevron.right")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .background(
                    GeometryReader { bGeo in
                        Color.clear.preference(
                            key: VerseFramePreferenceKey.self,
                            value: [-2: bGeo.frame(in: .named("UnifiedCanvasSpace"))]
                        )
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 120)
        }
        .frame(width: width, alignment: .topLeading)
    }

    // MARK: - Right Column (Paper-like Journal Margin)

    private func journalMarginColumn(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            PaperPatternBackground(style: viewModel.paperStyle, lineColor: viewModel.theme.paperLineColor)

            VStack(spacing: 0) {
                Text("JOURNAL MARGIN")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(viewModel.theme.secondaryText)
                    .padding(.top, 14)
                Spacer()
            }
        }
        .frame(width: width)
        .frame(minHeight: max(900, CGFloat(viewModel.verses.count) * 72))
    }

    // MARK: - Helpers

    private var dashedVerticalDivider: some View {
        Rectangle()
            .fill(viewModel.theme.dividerColor.opacity(0.65))
            .frame(width: 1)
            .padding(.vertical, 10)
    }

    private func estimatedVerseHeight(_ verse: Verse) -> CGFloat {
        let lines = max(2, Int(ceil(Double(verse.text.count) / 42.0)))
        return CGFloat(lines) * CGFloat(viewModel.fontSize + viewModel.lineSpacing) + 12
    }

    private func formattedVerseText(_ verse: Verse) -> AttributedString {
        let baseFont = Font.system(size: viewModel.fontSize, weight: .regular, design: .serif)
        let italicFont = Font.system(size: viewModel.fontSize, weight: .regular, design: .serif).italic()
        let baseColor = viewModel.theme.primaryText
        let redColor = viewModel.theme.redLetterColor

        let source = (!verse.textMarked.isEmpty && (viewModel.showRedLetter || viewModel.showItalics))
            ? verse.textMarked
            : verse.text

        var result = AttributedString()
        var isItalic = false
        var isRed = false
        var idx = source.startIndex

        func appendSegment(_ seg: Substring) {
            guard !seg.isEmpty else { return }
            var piece = AttributedString(String(seg))
            piece.font = (isItalic && viewModel.showItalics) ? italicFont : baseFont
            piece.foregroundColor = (isRed && viewModel.showRedLetter) ? redColor : baseColor
            result.append(piece)
        }

        while idx < source.endIndex {
            if let lt = source[idx...].firstIndex(of: "<") {
                appendSegment(source[idx..<lt])
                if let gt = source[lt...].firstIndex(of: ">") {
                    let tag = source[lt...gt]
                    if tag == "<i>" { isItalic = true }
                    else if tag == "</i>" { isItalic = false }
                    else if tag == "<r>" { isRed = true }
                    else if tag == "</r>" { isRed = false }
                    idx = source.index(after: gt)
                } else {
                    appendSegment(source[lt...])
                    break
                }
            } else {
                appendSegment(source[idx...])
                break
            }
        }
        return result
    }

    private func handleFingerTapOnCanvas(_ point: CGPoint) {
        if viewModel.selectedChapterStickerId != nil {
            viewModel.selectedChapterStickerId = nil
            return
        }
        // Check bottom Previous Chapter (-1) and Next Chapter (-2) buttons first (expanded slightly for easy finger taps)
        if let prevRect = verseFrames[-1], prevRect.insetBy(dx: -8, dy: -8).contains(point) {
            viewModel.previousChapter()
            return
        }
        if let nextRect = verseFrames[-2], nextRect.insetBy(dx: -8, dy: -8).contains(point) {
            viewModel.nextChapter()
            return
        }
        if let hit = verseFrames.first(where: { $0.key > 0 && $0.value.contains(point) }) {
            if let verse = viewModel.verses.first(where: { $0.verse == hit.key }) {
                withAnimation(.easeInOut(duration: 0.16)) {
                    viewModel.openVersePopover(verse)
                }
            }
        }
    }

    // MARK: - Temporary Side Menu Drawer (Far-Left Hamburger)

    private var mainMenuOverlay: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sword & Quill Study Bible")
                        .font(.title3.weight(.bold).leading(.tight))
                        .foregroundStyle(viewModel.theme.primaryText)
                    Text("www.swordandquillbible.com · KJV Offline")
                        .font(.caption)
                        .foregroundStyle(viewModel.theme.secondaryText)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().overlay(viewModel.theme.dividerColor)

                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        menuButton("Scripture Picker", icon: "book") {
                            viewModel.showMainMenu = false
                            viewModel.showScripturePicker = true
                        }
                        menuButton("Search KJV & Strong's", icon: "magnifyingglass") {
                            viewModel.showMainMenu = false
                            viewModel.showSearchSheet = true
                        }
                        menuButton("Bookmarks & Highlights", icon: "bookmark") {
                            viewModel.showMainMenu = false
                            viewModel.showSavedSheet = true
                        }
                        menuButton("Personal Notes & Sermons", icon: "note.text") {
                            viewModel.showMainMenu = false
                            viewModel.showNotesSheet = true
                        }
                        menuButton("Reading History", icon: "clock.arrow.circlepath") {
                            viewModel.showMainMenu = false
                            viewModel.showHistorySheet = true
                        }
                        menuButton("Reading & Workspace View", icon: "slider.horizontal.3") {
                            viewModel.showMainMenu = false
                            viewModel.showViewSettings = true
                        }

                        Divider().overlay(viewModel.theme.dividerColor).padding(.vertical, 2)

                        menuButton("Export Chapter PDF", icon: "doc.richtext") {
                            viewModel.showMainMenu = false
                            viewModel.exportCurrentChapterPDF()
                        }
                        menuButton("Scan Margin Ink (OCR)", icon: "text.viewfinder") {
                            viewModel.showMainMenu = false
                            viewModel.showMarginOCRScanner = true
                        }
                        menuButton("Study Dashboard & Backup", icon: "chart.bar.doc.horizontal") {
                            viewModel.showMainMenu = false
                            viewModel.showStudyDashboard = true
                        }

                        Divider().overlay(viewModel.theme.dividerColor).padding(.vertical, 2)

                        Text("WORKSPACE MODES")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(viewModel.theme.secondaryText)
                        ForEach(WorkspaceMode.allCases) { mode in
                            menuButton(mode.rawValue, icon: mode.systemImage) {
                                viewModel.applyMode(mode)
                                viewModel.showMainMenu = false
                            }
                        }

                        Text("Thy word is a lamp unto my feet,\nand a light unto my path. — Ps. 119:105")
                            .font(.caption2.italic())
                            .foregroundStyle(viewModel.theme.secondaryText)
                            .padding(.top, 12)
                            .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
            }
            .frame(width: 280)
            .frame(maxHeight: .infinity)
            .background(viewModel.theme.panelBackground)
            .shadow(radius: 16)

            Color.black.opacity(0.32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showMainMenu = false
                    }
                }
        }
        .zIndex(30)
        .transition(.opacity)
    }

    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(viewModel.theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
    }
}

private struct VerseFramePreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct UnifiedHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 1200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DraggableReferenceChip: View {
    let pin: PinnedReference
    let theme: ReadingTheme
    let onTap: () -> Void
    let onMove: (CGPoint) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "book.closed")
                .font(.system(size: 10))
            Text(pin.label)
                .font(.system(size: 12.5, weight: .semibold, design: .serif))
        }
        .foregroundStyle(theme.accentBlue)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.panelBackground.opacity(isDragging ? 1.0 : 0.94))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(theme.accentBlue.opacity(isDragging ? 0.95 : 0.55), lineWidth: isDragging ? 1.6 : 1)
        )
        .shadow(color: .black.opacity(isDragging ? 0.28 : 0.14), radius: isDragging ? 6 : 3, y: isDragging ? 3 : 1)
        .offset(
            x: CGFloat(pin.posX) + dragOffset.width,
            y: CGFloat(pin.posY) + dragOffset.height
        )
        .onTapGesture {
            onTap()
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("UnifiedCanvasSpace"))
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let finalPt = CGPoint(
                        x: max(12, CGFloat(pin.posX) + value.translation.width),
                        y: max(12, CGFloat(pin.posY) + value.translation.height)
                    )
                    dragOffset = .zero
                    isDragging = false
                    onMove(finalPt)
                }
        )
    }
}

private struct DraggableClipCard: View {
    let clip: JournalClipCard
    let theme: ReadingTheme
    let onTap: () -> Void
    let onMove: (CGPoint) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.accentBlue)
                Text(clip.sourceLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.accentBlue)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "pencil")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.secondaryText)
            }

            if !clip.excerpt.isEmpty {
                Text(clip.excerpt)
                    .font(.system(size: 12.5, design: .serif))
                    .italic()
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(6)
            }

            if !clip.userNote.isEmpty {
                Divider().overlay(theme.dividerColor)
                Text(clip.userNote)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(6)
            }
        }
        .padding(10)
        .frame(width: 220, alignment: .leading)
        .background(theme.panelBackground.opacity(isDragging ? 1.0 : 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.accentBlue.opacity(isDragging ? 0.95 : 0.45), lineWidth: isDragging ? 1.6 : 1)
        )
        .shadow(color: .black.opacity(isDragging ? 0.28 : 0.14), radius: isDragging ? 8 : 3, y: isDragging ? 4 : 2)
        .offset(
            x: CGFloat(clip.posX) + dragOffset.width,
            y: CGFloat(clip.posY) + dragOffset.height
        )
        .onTapGesture {
            onTap()
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("UnifiedCanvasSpace"))
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let finalPt = CGPoint(
                        x: max(12, CGFloat(clip.posX) + value.translation.width),
                        y: max(12, CGFloat(clip.posY) + value.translation.height)
                    )
                    dragOffset = .zero
                    isDragging = false
                    onMove(finalPt)
                }
        )
    }
}

private struct PaperPatternBackground: View {
    let style: JournalPaperStyle
    let lineColor: Color

    var body: some View {
        Canvas { context, size in
            switch style {
            case .plain:
                break
            case .ruled:
                let spacing: CGFloat = 30
                var y: CGFloat = 46
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 16, y: y))
                    path.addLine(to: CGPoint(x: size.width - 16, y: y))
                    context.stroke(path, with: .color(lineColor), lineWidth: 0.8)
                    y += spacing
                }
            case .dotGrid:
                let spacing: CGFloat = 24
                var y: CGFloat = 44
                while y < size.height {
                    var x: CGFloat = 20
                    while x < size.width - 12 {
                        let rect = CGRect(x: x, y: y, width: 1.8, height: 1.8)
                        context.fill(Path(ellipseIn: rect), with: .color(lineColor))
                        x += spacing
                    }
                    y += spacing
                }
            }
        }
        .allowsHitTesting(false)
    }
}
