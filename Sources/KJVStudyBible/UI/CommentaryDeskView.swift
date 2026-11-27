import SwiftUI

// MARK: - Verse-Locked & Chapter-Synced Commentary Desk (Left Study Desk Tab)

public struct CommentaryDeskView: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @ObservedObject var moduleManager: ModuleManager

    @State private var filterToFocusedVerse: Bool = false

    private var enabledModules: [StudyModuleManifest] {
        moduleManager.enabledCommentaries
    }

    private var activeModule: StudyModuleManifest? {
        if let id = viewModel.selectedCommentaryModuleId,
           let match = enabledModules.first(where: { $0.id == id }) {
            return match
        }
        return enabledModules.first
    }

    private var focusedVerseNum: Int? {
        guard let sv = viewModel.studyVerse,
              sv.bookId == viewModel.currentBookId,
              sv.chapter == viewModel.currentChapter else { return nil }
        return sv.verse
    }

    private var displayedEntries: [CommentaryEntry] {
        let all = viewModel.chapterCommentaryEntries
        guard filterToFocusedVerse, let v = focusedVerseNum else { return all }
        let matching = all.filter { $0.covers(verse: v) || $0.verseFrom == 0 }
        return matching.isEmpty ? all : matching
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Module Switcher Bar + Library Manager shortcut
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(enabledModules) { mod in
                            let isSelected = (activeModule?.id == mod.id)
                            Button {
                                viewModel.selectCommentaryModule(mod.id)
                            } label: {
                                Text(mod.shortTitle)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? viewModel.theme.accentBlue : viewModel.theme.canvasBackground)
                                    .foregroundStyle(isSelected ? Color.white : viewModel.theme.primaryText)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(isSelected ? Color.clear : viewModel.theme.dividerColor, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    viewModel.showLibraryManager = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(viewModel.theme.accentBlue)
                }
                .accessibilityLabel("Manage Commentaries")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(viewModel.theme.chromeBackground)

            Divider().overlay(viewModel.theme.dividerColor)

            // Chapter & Verse Lock Subheader
            HStack(spacing: 8) {
                Text(viewModel.currentLocationTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(viewModel.theme.primaryText)

                if let v = focusedVerseNum {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            filterToFocusedVerse.toggle()
                        }
                    } label: {
                        Label(filterToFocusedVerse ? "v.\(v) Only" : "Focus v.\(v)", systemImage: "scope")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(filterToFocusedVerse ? viewModel.theme.accentBlue : viewModel.theme.accentBlue.opacity(0.14))
                            .foregroundStyle(filterToFocusedVerse ? Color.white : viewModel.theme.accentBlue)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Text("\(displayedEntries.count) \(displayedEntries.count == 1 ? "note" : "notes")")
                    .font(.caption2)
                    .foregroundStyle(viewModel.theme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider().overlay(viewModel.theme.dividerColor.opacity(0.6))

            // Entries List
            if enabledModules.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "books.vertical")
                        .font(.largeTitle)
                        .foregroundStyle(viewModel.theme.secondaryText)
                    Text("No Commentaries Enabled")
                        .font(.headline)
                        .foregroundStyle(viewModel.theme.primaryText)
                    Text("Add free classic commentaries like Matthew Henry, John Gill, Barnes, or JFB in Library Manager.")
                        .font(.caption)
                        .foregroundStyle(viewModel.theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button {
                        viewModel.showLibraryManager = true
                    } label: {
                        Label("Open Library Manager", systemImage: "arrow.down.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.theme.accentBlue)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if displayedEntries.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No entry in \(activeModule?.shortTitle ?? "this commentary") for \(viewModel.currentLocationTitle).")
                        .font(.caption)
                        .foregroundStyle(viewModel.theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button("Get More Commentaries") {
                        viewModel.showLibraryManager = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.theme.accentBlue)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(displayedEntries) { entry in
                                let isFocused = focusedVerseNum.map { entry.covers(verse: $0) } ?? false
                                commentaryCard(entry: entry, isFocused: isFocused)
                                    .id(entry.id)
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: focusedVerseNum) { _, newV in
                        guard let v = newV,
                              let target = displayedEntries.first(where: { $0.covers(verse: v) }) else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(target.id, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func commentaryCard(entry: CommentaryEntry, isFocused: Bool) -> some View {
        let modLabel = activeModule?.shortTitle ?? "Commentary"
        let citedRefs = viewModel.referenceDB.extractReferences(from: entry.body, limit: 10)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.verseRangeLabel)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isFocused ? viewModel.theme.accentBlue : viewModel.theme.accentBlue.opacity(0.14))
                    .foregroundStyle(isFocused ? Color.white : viewModel.theme.accentBlue)
                    .clipShape(Capsule())

                Spacer()

                Button {
                    let source = "\(modLabel) · \(viewModel.currentLocationTitle) (\(entry.verseRangeLabel))"
                    viewModel.startClipToJournal(sourceLabel: source, text: String(entry.body.prefix(360)))
                } label: {
                    Label("Clip", systemImage: "scissors")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(viewModel.theme.accentBlue)
                }
                .buttonStyle(.plain)
            }

            Text(entry.body)
                .font(.system(size: viewModel.studyDeskFontSize, design: .serif))
                .foregroundStyle(viewModel.theme.primaryText)
                .lineSpacing(max(3, viewModel.studyDeskFontSize * 0.28))
                .textSelection(.enabled)

            if !citedRefs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(citedRefs) { ref in
                            Button {
                                viewModel.openCrossRefPreview(ref)
                            } label: {
                                Text(ref.displayRef)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(viewModel.theme.accentBlue)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(viewModel.theme.accentBlue.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(11)
        .background(viewModel.theme.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? viewModel.theme.accentBlue : viewModel.theme.dividerColor, lineWidth: isFocused ? 1.5 : 1)
        )
    }
}
