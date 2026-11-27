import SwiftUI

// MARK: - Study Library Manager (Search, Pin, Archive, & Deep Trail Search for Massive Study Collections)

public struct StudyLibrarySheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case active = "Active"
        case pinned = "Pinned"
        case archived = "Archived"
        case all = "All"
        var id: String { rawValue }
    }

    @State private var filter: LibraryFilter = .active
    @State private var searchQuery: String = ""
    @State private var trailCounts: [String: Int] = [:]
    @State private var linkCounts: [String: Int] = [:]
    @State private var trailMatchingStudyIds: Set<String> = []
    @State private var pendingDeleteStudy: StudySession? = nil

    private var displayedStudies: [StudySession] {
        let base: [StudySession]
        switch filter {
        case .active:
            base = viewModel.studySessions.filter { !viewModel.archivedStudyIds.contains($0.id) }
        case .pinned:
            base = viewModel.studySessions.filter { viewModel.pinnedStudyIds.contains($0.id) }
        case .archived:
            base = viewModel.studySessions.filter { viewModel.archivedStudyIds.contains($0.id) }
        case .all:
            base = viewModel.studySessions
        }

        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [StudySession]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { study in
                let bookName = viewModel.bookName(study.startBookId).lowercased()
                return study.name.lowercased().contains(q)
                    || study.summaryNote.lowercased().contains(q)
                    || bookName.contains(q)
                    || trailMatchingStudyIds.contains(study.id)
            }
        }

        // Pinned studies always float to the top, then most recently updated
        return filtered.sorted { a, b in
            let aPin = viewModel.pinnedStudyIds.contains(a.id)
            let bPin = viewModel.pinnedStudyIds.contains(b.id)
            if aPin != bPin { return aPin }
            return a.updatedAt > b.updatedAt
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // Deep Search Bar (searches titles, summaries, books, AND inside every study's trail!)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Search studies, topics, books, or trail items...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .onChange(of: searchQuery) { _, val in
                            let q = val.trimmingCharacters(in: .whitespacesAndNewlines)
                            trailMatchingStudyIds = q.isEmpty ? [] : viewModel.studyDB.studyIdsMatchingTrail(query: q)
                        }
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            trailMatchingStudyIds = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Active / Pinned / Archived / All Filter
                Picker("Filter", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                List {
                    if displayedStudies.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "books.vertical")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(emptyMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        ForEach(displayedStudies) { study in
                            studyRow(study)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Study Library (\(viewModel.studySessions.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                        viewModel.showNewStudySheet = true
                    } label: {
                        Label("New Study", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                trailCounts = viewModel.studyDB.studyTrailCounts()
                linkCounts = viewModel.studyDB.studyMarginLinkCounts()
            }
            .alert("Delete Study?", isPresented: Binding(
                get: { pendingDeleteStudy != nil },
                set: { if !$0 { pendingDeleteStudy = nil } }
            )) {
                Button("Cancel", role: .cancel) { pendingDeleteStudy = nil }
                Button("Delete", role: .destructive) {
                    if let target = pendingDeleteStudy {
                        viewModel.deleteStudy(target)
                        pendingDeleteStudy = nil
                    }
                }
            } message: {
                if let target = pendingDeleteStudy {
                    Text("This removes \"\(target.name)\", its study trail, and its study-layer notes. Your everyday Bible ink and notebooks stay untouched.")
                }
            }
        }
    }

    private var emptyMessage: String {
        if !searchQuery.isEmpty {
            return "No studies matched \"\(searchQuery)\"."
        }
        switch filter {
        case .active: return "No active studies yet. Tap + to start a Study Session."
        case .pinned: return "No pinned studies yet. Tap the star or swipe right on any study to pin your current series."
        case .archived: return "No archived studies. Swipe left on a completed study to archive it cleanly."
        case .all: return "No studies yet. Tap + to start your first Study Session."
        }
    }

    @ViewBuilder
    private func studyRow(_ study: StudySession) -> some View {
        let isActive = viewModel.activeStudy?.id == study.id
        let isPinned = viewModel.pinnedStudyIds.contains(study.id)
        let isArchived = viewModel.archivedStudyIds.contains(study.id)
        let tCount = trailCounts[study.id] ?? 0
        let lCount = linkCounts[study.id] ?? 0
        let startRef = "\(viewModel.bookName(study.startBookId)) \(study.startChapter)\(study.startVerse != nil ? ":\(study.startVerse!)" : "")"

        HStack(alignment: .top, spacing: 10) {
            Button {
                viewModel.activateStudy(study)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isPinned {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Text(study.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(isArchived ? .secondary : .primary)
                            .lineLimit(1)

                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(viewModel.theme.accentBlue)
                                .clipShape(Capsule())
                        }
                        if isArchived {
                            Text("ARCHIVED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.16))
                                .clipShape(Capsule())
                        }
                    }

                    if !study.summaryNote.isEmpty {
                        Text(study.summaryNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 10) {
                        Label(startRef, systemImage: "book.closed")
                        Label("\(tCount) items", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        if lCount > 0 {
                            Label("\(lCount) pins", systemImage: "pin")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Quick Pin + Share Buttons
            HStack(spacing: 8) {
                Button {
                    viewModel.togglePinStudy(study.id)
                } label: {
                    Image(systemName: isPinned ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(isPinned ? .orange : .secondary.opacity(0.6))
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                    viewModel.sharingStudy = study
                } label: {
                    Image(systemName: "qrcode")
                        .font(.subheadline)
                        .foregroundStyle(viewModel.theme.accentBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .leading) {
            Button {
                viewModel.togglePinStudy(study.id)
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "star.slash" : "star.fill")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeleteStudy = study
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                viewModel.toggleArchiveStudy(study.id)
            } label: {
                Label(isArchived ? "Unarchive" : "Archive", systemImage: isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(.indigo)
        }
    }
}
