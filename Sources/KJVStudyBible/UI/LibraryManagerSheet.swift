import SwiftUI
import UniformTypeIdentifiers

// MARK: - e-Sword–Style Modular Library Manager Sheet

public struct LibraryManagerSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @ObservedObject var moduleManager: ModuleManager
    @ObservedObject var kokoroManager: KokoroVoiceManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var showImportPicker: Bool = false

    public init(viewModel: BibleWorkspaceViewModel, moduleManager: ModuleManager) {
        self.viewModel = viewModel
        self.moduleManager = moduleManager
        self.kokoroManager = viewModel.audioPlayer.kokoroManager
    }

    private var filteredRemote: [StudyModuleManifest] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = moduleManager.remoteCatalog
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(q)
            || $0.author.lowercased().contains(q)
            || $0.description.lowercased().contains(q)
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                // Status Banner
                if let msg = moduleManager.statusMessage {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(msg)
                                .font(.subheadline)
                            Spacer()
                            Button("Dismiss") {
                                moduleManager.statusMessage = nil
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }

                // Studio Neural Audio Narrators (Fast Piper VITS + Optional Kokoro-82M)
                Section {
                    ForEach(NeuralPackID.allCases) { pack in
                        let installed = kokoroManager.isInstalled(pack)
                        let downloading = kokoroManager.downloadingPack == pack

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(pack.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(pack.badgeText)
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(viewModel.theme.accentBlue.opacity(0.14))
                                            .foregroundStyle(viewModel.theme.accentBlue)
                                            .clipShape(Capsule())
                                    }
                                    Text(pack.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if installed {
                                        Text("Installed · \(kokoroManager.formattedDiskSize(for: pack)) on disk · Ready in Read Aloud")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.green)
                                    } else {
                                        Text("Optional download (\(pack.approxDownloadSize)) · 100% offline")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if downloading {
                                    Button("Cancel", role: .destructive) {
                                        kokoroManager.cancelDownload()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else if installed {
                                    Button(role: .destructive) {
                                        kokoroManager.removeVoicePack(pack)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.borderless)
                                    .padding(.top, 4)
                                } else {
                                    Button {
                                        kokoroManager.startDownload(pack)
                                    } label: {
                                        Label("Get", systemImage: "arrow.down.circle.fill")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(viewModel.theme.accentBlue)
                                    .disabled(kokoroManager.isDownloading)
                                }
                            }

                            if downloading {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: kokoroManager.downloadProgress)
                                        .tint(viewModel.theme.accentBlue)
                                    Text(kokoroManager.statusText ?? "Downloading… \(Int(kokoroManager.downloadProgress * 100))%")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if let err = kokoroManager.errorMessage {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("On-Device Neural Audio (Optional)")
                } footer: {
                    Text("Fast Neural Narrators (Ryan & Lessac) synthesize each verse in ~0.25s with zero pauses on all iPads.")
                }

                // Installed Modules
                Section {
                    if moduleManager.installedModules.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No commentary modules installed")
                                .font(.subheadline.weight(.semibold))
                            Text("Download free classic commentaries below, or keep a pure Scripture-only workspace — it's completely up to you.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(moduleManager.installedModules) { mod in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(mod.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(mod.abbr)
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(viewModel.theme.accentBlue.opacity(0.14))
                                            .foregroundStyle(viewModel.theme.accentBlue)
                                            .clipShape(Capsule())
                                    }
                                    Text("\(mod.author) · \(mod.entryCount.formatted()) entries · \(moduleManager.formattedDiskSize(for: mod.id))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { moduleManager.isEnabled(mod.id) },
                                    set: { enabled in
                                        moduleManager.setEnabled(mod.id, enabled: enabled)
                                        viewModel.syncCommentarySelection()
                                    }
                                ))
                                .labelsHidden()

                                Button(role: .destructive) {
                                    moduleManager.removeModule(mod.id)
                                    viewModel.syncCommentarySelection()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Installed Modules (\(moduleManager.installedModules.count))")
                } footer: {
                    Text("Disable or delete any module anytime. When no commentaries are enabled, the Commentary tab hides automatically.")
                }

                // Free Classic Commentaries Catalog
                Section {
                    if moduleManager.isLoadingCatalog && moduleManager.remoteCatalog.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading classic commentary catalog…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if let err = moduleManager.catalogError, moduleManager.remoteCatalog.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Retry Catalog") {
                                Task { await moduleManager.fetchCatalog() }
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(filteredRemote) { remote in
                            let installed = moduleManager.isInstalled(remote.id)
                            let downloading = moduleManager.downloadingModuleIds.contains(remote.id)

                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(remote.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(remote.formattedDownloadSize)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    Text(remote.author)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(viewModel.theme.accentBlue)
                                    Text(remote.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                if downloading {
                                    ProgressView()
                                        .padding(.top, 4)
                                } else if installed {
                                    Label("Installed", systemImage: "checkmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.green)
                                        .padding(.top, 4)
                                } else {
                                    Button {
                                        Task {
                                            await moduleManager.downloadAndInstall(remote)
                                            viewModel.syncCommentarySelection()
                                        }
                                    } label: {
                                        Label("Get", systemImage: "arrow.down.circle.fill")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(viewModel.theme.accentBlue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    HStack {
                        Text("Free Public-Domain Commentaries")
                        Spacer()
                        if !moduleManager.isLoadingCatalog {
                            Button("Refresh") {
                                Task { await moduleManager.fetchCatalog() }
                            }
                            .font(.caption2.weight(.semibold))
                        }
                    }
                } footer: {
                    Text("Downloaded modules are stored locally on your iPad and work 100% offline forever.")
                }

                // Import Custom .sqmod
                Section {
                    Button {
                        showImportPicker = true
                    } label: {
                        Label("Import .sqmod File from Files / AirDrop", systemImage: "square.and.arrow.down.on.square")
                            .font(.subheadline.weight(.medium))
                    }
                } header: {
                    Text("Custom Modules")
                }
            }
            .searchable(text: $searchText, prompt: "Filter commentaries (Henry, Gill, Barnes, Spurgeon…)")
            .navigationTitle("Library & Commentaries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if moduleManager.remoteCatalog.isEmpty {
                    await moduleManager.fetchCatalog()
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.data, .item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    moduleManager.importLocalSQMod(url: url)
                    viewModel.syncCommentarySelection()
                }
            }
        }
    }
}
