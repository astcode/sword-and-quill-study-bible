import SwiftUI
import UniformTypeIdentifiers

// MARK: - Study Dashboard & Atomic Backup / Restore

public struct StudyDashboardSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var stats: StudyDashboardStats? = nil
    @State private var showFileImporter: Bool = false
    @State private var pendingRestoreURL: URL? = nil
    @State private var showRestoreConfirm: Bool = false
    @State private var backupShareItem: ShareSheetItem? = nil
    @State private var feedbackMessage: String? = nil
    @State private var feedbackIsError: Bool = false

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Banner
                    HStack(spacing: 14) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(viewModel.theme.accentBlue)
                            .frame(width: 54, height: 54)
                            .background(viewModel.theme.accentBlue.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sword & Quill Study Bible")
                                .font(.title3.weight(.bold))
                            Text("www.swordandquillbible.com · 100% Offline Personal Study")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(viewModel.theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(viewModel.theme.dividerColor, lineWidth: 1))

                    if let st = stats {
                        // Reading Progress Card
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("BIBLE READING & STUDY PROGRESS")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(st.uniqueChaptersVisited) / 1,189 Chapters")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(viewModel.theme.accentBlue)
                            }
                            let pct = min(1.0, Double(st.uniqueChaptersVisited) / 1189.0)
                            ProgressView(value: pct)
                                .tint(viewModel.theme.accentBlue)
                            Text(String(format: "%.1f%% of the King James Bible visited on this iPad", pct * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(viewModel.theme.panelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(viewModel.theme.dividerColor, lineWidth: 1))

                        // Study Stats Grid
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                            statCard("Ink Chapters", value: "\(st.chaptersWithInk)", icon: "pencil.tip", tint: viewModel.theme.accentBlue)
                            statCard("Highlights", value: "\(st.highlightedVerses)", icon: "highlighter", tint: .orange)
                            statCard("Notebooks", value: "\(st.notebookCount)", icon: "note.text", tint: .purple)
                            statCard("Bookmarks", value: "\(st.bookmarkCount)", icon: "bookmark.fill", tint: .red)
                            statCard("Journal Clips", value: "\(st.clipCount)", icon: "scissors", tint: .teal)
                            statCard("Pinned Refs", value: "\(st.pinnedRefCount)", icon: "pin.fill", tint: .indigo)
                            statCard("Custom Stickers", value: "\(st.customStickerCount)", icon: "sparkles.rectangle.stack", tint: .pink)
                            statCard("Chapters Read", value: "\(st.uniqueChaptersVisited)", icon: "book.pages", tint: .green)
                        }

                        // Most Studied Books
                        if !st.topBooks.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("MOST STUDIED BOOKS")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
                                    ForEach(st.topBooks) { item in
                                        Button {
                                            viewModel.navigate(to: VerseRef(bookId: item.bookId, chapter: 1, verse: 1))
                                            dismiss()
                                        } label: {
                                            HStack {
                                                Text(viewModel.bookName(item.bookId))
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(viewModel.theme.primaryText)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text("\(item.itemCount)")
                                                    .font(.caption.weight(.bold).monospacedDigit())
                                                    .foregroundStyle(viewModel.theme.accentBlue)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 2)
                                                    .background(viewModel.theme.accentBlue.opacity(0.12))
                                                    .clipShape(Capsule())
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(viewModel.theme.canvasBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(viewModel.theme.dividerColor, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(14)
                            .background(viewModel.theme.panelBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(viewModel.theme.dividerColor, lineWidth: 1))
                        }
                    }

                    // Backup & Restore Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LIFELONG STUDY BACKUP & RESTORE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("Your Apple Pencil ink, highlights, Sermon Notebooks, stickers, clips, and bookmarks live in a single local SQLite file. Export anytime to Files, iCloud Drive, or AirDrop—or restore a previous backup below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let msg = feedbackMessage {
                            Text(msg)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(feedbackIsError ? .red : .green)
                                .padding(.vertical, 2)
                        }

                        HStack(spacing: 10) {
                            Button {
                                if let url = viewModel.prepareBackupExport() {
                                    backupShareItem = ShareSheetItem(url: url)
                                    feedbackMessage = "Backup snapshot created."
                                    feedbackIsError = false
                                } else {
                                    feedbackMessage = "Could not create backup snapshot."
                                    feedbackIsError = true
                                }
                            } label: {
                                Label("Export Backup (.sqlite)", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .buttonStyle(.borderedProminent)
                            .tint(viewModel.theme.accentBlue)

                            Button {
                                showFileImporter = true
                            } label: {
                                Label("Restore from Backup", systemImage: "arrow.counterclockwise.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(14)
                    .background(viewModel.theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(viewModel.theme.dividerColor, lineWidth: 1))

                    // Sword & Quill Pro & Support the Builder Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            Text("SUPPORT SWORD & QUILL")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("PRO ACTIVE (DEV)")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .clipShape(Capsule())
                        }
                        Text("God's Word, Apple Pencil journaling, and receiving shared lessons are always free and ad-free. Classroom Sharing (.sqstudy packages, Classroom QR Codes, & Printable Handout PDFs) and optional App Store Tips help support ongoing independent development of Sword & Quill.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(viewModel.theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(viewModel.theme.dividerColor, lineWidth: 1))
                }
                .padding(16)
            }
            .navigationTitle("Study Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                stats = viewModel.studyDB.studyDashboardStats()
            }
            .sheet(item: $backupShareItem) { item in
                ActivityShareSheet(url: item.url)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.data, .item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        pendingRestoreURL = url
                        showRestoreConfirm = true
                    }
                case .failure(let err):
                    feedbackMessage = "Could not open file: \(err.localizedDescription)"
                    feedbackIsError = true
                }
            }
            .alert("Restore Study Backup?", isPresented: $showRestoreConfirm) {
                Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
                Button("Restore Backup", role: .destructive) {
                    if let url = pendingRestoreURL {
                        performRestore(from: url)
                    }
                }
            } message: {
                Text("This replaces your current local ink, notes, highlights, and stickers with the selected backup file. A safety snapshot is created automatically first.")
            }
        }
    }

    private func performRestore(from url: URL) {
        do {
            try viewModel.restoreFromBackup(url: url)
            stats = viewModel.studyDB.studyDashboardStats()
            feedbackMessage = "Backup restored successfully! All study data has been refreshed."
            feedbackIsError = false
        } catch {
            feedbackMessage = error.localizedDescription
            feedbackIsError = true
        }
        pendingRestoreURL = nil
    }

    private func statCard(_ label: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                Spacer()
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(viewModel.theme.primaryText)
            }
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(viewModel.theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(viewModel.theme.dividerColor, lineWidth: 1))
    }
}
