import SwiftUI
import UIKit

// MARK: - Teacher / Pro Study Share Sheet (.sqstudy AirDrop, Classroom QR Code, Clickable Link, Printable Handout PDF)

public struct StudyShareSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @ObservedObject var store: StoreManager
    let study: StudySession
    @Environment(\.dismiss) private var dismiss

    @State private var authorName: String = ""
    @State private var includeMarginNotes: Bool = true
    @State private var shareFileItem: ShareSheetItem? = nil
    @State private var showFullScreenQR: Bool = false
    @State private var copiedLinkNotice: Bool = false

    public init(viewModel: BibleWorkspaceViewModel, study: StudySession) {
        self.viewModel = viewModel
        self._store = ObservedObject(wrappedValue: viewModel.storeManager)
        self.study = study
    }

    private var trailEntries: [StudyTrailEntry] {
        viewModel.studyDB.studyTrailEntries(studyId: study.id)
    }

    private var studyMarginLinks: [StudyMarginLink] {
        viewModel.studyDB.studyMarginLinks(studyId: study.id)
    }

    private var currentPackage: StudySharePackage {
        StudyPackageCodec.buildPackage(
            study: study,
            author: authorName,
            trail: trailEntries,
            marginLinks: studyMarginLinks,
            includeMarginNotes: includeMarginNotes
        )
    }

    private var startLabel: String {
        let b = viewModel.bookName(study.startBookId)
        return study.startVerse != nil ? "\(b) \(study.startChapter):\(study.startVerse!)" : "\(b) \(study.startChapter)"
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                if !store.isProUnlocked {
                    ClassroomProUpgradeView(store: store, theme: viewModel.theme, studyName: study.name)
                        .padding(16)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                    // Pro Feature Header Banner
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(viewModel.theme.accentBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 11))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Share Lesson & Classroom Tools")
                                    .font(.headline)
                                Text("PRO")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                            Text("Students, spouses, & classes always receive and import lessons for free.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        #if DEBUG
                        Button("Lock (Dev)") {
                            store.debugSimulateProUnlocked = false
                        }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        #endif
                    }
                    .padding(12)
                    .background(viewModel.theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(viewModel.theme.dividerColor, lineWidth: 1))

                    // Lesson Metadata & Options
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(study.name)
                                    .font(.title3.weight(.bold))
                                Text("Starts at \(startLabel) · \(trailEntries.count) trail items · \(studyMarginLinks.count) margin notes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        TextField("Your Name / Class (optional, e.g. Pastor Aaron)", text: $authorName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: authorName) { _, newVal in
                                viewModel.setTeacherAuthorName(newVal)
                            }

                        if !studyMarginLinks.isEmpty {
                            Toggle("Include my \(studyMarginLinks.count) Bible margin note(s) in this lesson", isOn: $includeMarginNotes)
                                .font(.subheadline)
                        }
                    }
                    .padding(14)
                    .background(viewModel.theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(viewModel.theme.dividerColor, lineWidth: 1))

                    // Classroom QR Code Card (100% Offline, Zero Server)
                    let qrResult = StudyPackageCodec.makeShareURL(package: currentPackage, compactForQR: true)
                    VStack(spacing: 12) {
                        HStack {
                            Label("Classroom QR Code", systemImage: "qrcode")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            if qrResult != nil {
                                Button {
                                    showFullScreenQR = true
                                } label: {
                                    Label("Full-Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        if let qrResult, let qrImg = StudyPackageCodec.generateQRImage(from: qrResult.url.absoluteString) {
                            Image(uiImage: qrImg)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 210, height: 210)
                                .padding(14)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)

                            Text(qrResult.wasTrimmedForQR
                                 ? "Point any iPad/iPhone camera at this QR code to import the core trail. For unlimited notes, use AirDrop / .sqstudy File below."
                                 : "Point any iPad or iPhone camera at this QR code to open & import the complete lesson directly into Sword & Quill.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(viewModel.theme.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(viewModel.theme.dividerColor, lineWidth: 1))

                    // Three Share Actions: AirDrop/.sqstudy File, Copy Link, Printable PDF Handout
                    VStack(spacing: 10) {
                        Button {
                            if let url = StudyPackageCodec.exportFile(package: currentPackage) {
                                shareFileItem = ShareSheetItem(url: url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "airplayaudio")
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("AirDrop / Text / Email (.sqstudy File)")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Full unlimited lesson package — recipients tap to import into Sword & Quill")
                                        .font(.caption2)
                                        .opacity(0.85)
                                }
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                            }
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.theme.accentBlue)

                        HStack(spacing: 10) {
                            Button {
                                if let res = StudyPackageCodec.makeShareURL(package: currentPackage, compactForQR: false) {
                                    UIPasteboard.general.string = res.url.absoluteString
                                    copiedLinkNotice = true
                                    viewModel.showToast("Copied clickable Study link")
                                }
                            } label: {
                                Label(copiedLinkNotice ? "Link Copied!" : "Copy Clickable Link", systemImage: copiedLinkNotice ? "checkmark" : "link")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                if let pdfURL = StudyPDFExporter.exportStudyTrailHandout(
                                    study: study,
                                    author: authorName,
                                    startLocationLabel: startLabel,
                                    entries: trailEntries,
                                    marginLinks: includeMarginNotes ? studyMarginLinks : [],
                                    bookNameLookup: { viewModel.bookName($0) }
                                ) {
                                    shareFileItem = ShareSheetItem(url: pdfURL)
                                }
                            } label: {
                                Label("Printable PDF Handout", systemImage: "doc.richtext")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                    }
                }
            }
            .navigationTitle("Share Study Lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                authorName = viewModel.teacherAuthorName
            }
            .sheet(item: $shareFileItem) { item in
                ActivityShareSheet(url: item.url)
            }
            .fullScreenCover(isPresented: $showFullScreenQR) {
                FullScreenClassroomQRView(
                    studyName: study.name,
                    author: authorName,
                    startLabel: startLabel,
                    qrPayload: StudyPackageCodec.makeShareURL(package: currentPackage, compactForQR: true)?.url.absoluteString ?? ""
                )
            }
        }
    }
}

// MARK: - Full-Screen Classroom QR Presenter (Great for AirPlay to TV / Projector)

private struct FullScreenClassroomQRView: View {
    let studyName: String
    let author: String
    let startLabel: String
    let qrPayload: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.gray)
                    }
                    .padding()
                }

                Spacer()

                VStack(spacing: 6) {
                    Text("SWORD & QUILL STUDY BIBLE")
                        .font(.caption.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(Color(red: 0.18, green: 0.38, blue: 0.62))
                    Text(studyName)
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                    Text(author.isEmpty ? "Starting at \(startLabel)" : "\(author) · Starting at \(startLabel)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                if let qrImg = StudyPackageCodec.generateQRImage(from: qrPayload) {
                    Image(uiImage: qrImg)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 380, maxHeight: 380)
                        .padding(20)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.black.opacity(0.12), lineWidth: 2)
                        )
                }

                Text("Point your iPad or iPhone Camera at the QR code to import this lesson.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}

// MARK: - Free Student / Recipient Import Preview Sheet

public struct ImportStudyPreviewSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    let package: StudySharePackage
    @Environment(\.dismiss) private var dismiss

    @State private var includeMarginNotes: Bool = true

    private var startLabel: String {
        let b = viewModel.bookName(package.startBookId)
        return package.startVerse != nil ? "\(b) \(package.startChapter):\(package.startVerse!)" : "\(b) \(package.startChapter)"
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.title2)
                            .foregroundStyle(viewModel.theme.accentBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(package.name)
                                .font(.title3.weight(.bold))
                            if let author = package.author {
                                Text("Shared by \(author) · Starts at \(startLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Starts at \(startLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let summary = package.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(viewModel.theme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(viewModel.theme.dividerColor, lineWidth: 1))

                if let marginNotes = package.marginNotes, !marginNotes.isEmpty {
                    Toggle("Also pin \(marginNotes.count) teacher margin note(s) to my Bible pages", isOn: $includeMarginNotes)
                        .font(.subheadline)
                        .padding(.horizontal, 4)
                }

                Text("INCLUDED IN THIS STUDY (\(package.entries.count) ITEMS)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                List(Array(package.entries.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10) {
                        let kind = StudyTrailKind(rawValue: item.k) ?? .passage
                        Image(systemName: kind.systemImage)
                            .foregroundStyle(viewModel.theme.accentBlue)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.t)
                                .font(.subheadline.weight(.semibold))
                            if let d = item.d, !d.isEmpty {
                                Text(d)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .listStyle(.plain)

                Text("Importing adds this Study to your Studies menu without altering any of your own personal Bible ink, highlights, or notes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .navigationTitle("Import Study Lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import & Start Study") {
                        viewModel.importStudyPackage(package, includeMarginNotes: includeMarginNotes)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
