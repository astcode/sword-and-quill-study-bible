import SwiftUI

public struct BottomUtilityBar: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isCompact: Bool { hSizeClass == .compact }

    public var body: some View {
        HStack(spacing: isCompact ? 4 : 8) {
            toolbarItem(title: "Bible", icon: "book.closed", active: !viewModel.showStudyPanel) {
                viewModel.showStudyPanel = false
                viewModel.showPenToolbox = false
            }

            toolbarItem(title: "Saved", icon: "bookmark", active: viewModel.showSavedSheet) {
                viewModel.showSavedSheet = true
            }

            toolbarItem(title: "Notes", icon: "note.text", active: viewModel.showNotesSheet) {
                viewModel.showNotesSheet = true
            }

            toolbarItem(title: "Study", icon: "text.magnifyingglass", active: viewModel.showReferencePanel) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleReferencePanel()
                }
            }

            Spacer(minLength: isCompact ? 6 : 20)

            // Grouped Writing Controls: Pen + Undo + Redo + Zoom + Stickers (clean icon-only)
            HStack(spacing: isCompact ? 6 : 12) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        viewModel.showPenToolbox.toggle()
                    }
                } label: {
                    Image(systemName: viewModel.selectedTool.systemImage)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(viewModel.showPenToolbox ? viewModel.theme.accentBlue : viewModel.theme.primaryText)
                        .frame(width: 48, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(viewModel.theme.accentBlue.opacity(viewModel.showPenToolbox ? 0.16 : 0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(viewModel.theme.accentBlue.opacity(viewModel.showPenToolbox ? 0.8 : 0.35), lineWidth: 1.2)
                        )
                }
                .accessibilityLabel("Writing Tools")

                Button {
                    viewModel.triggerUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 42, height: 38)
                }
                .disabled(!viewModel.canUndo)
                .opacity(viewModel.canUndo ? 1.0 : 0.35)
                .accessibilityLabel("Undo")

                Button {
                    viewModel.triggerRedo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 42, height: 38)
                }
                .disabled(!viewModel.canRedo)
                .opacity(viewModel.canRedo ? 1.0 : 0.35)
                .accessibilityLabel("Redo")

                // Journal Zoom Control
                Menu {
                    Button("1× (Normal)") { withAnimation(.easeInOut(duration: 0.2)) { viewModel.setZoom(1.0) } }
                    Button("1.5× (Detail)") { withAnimation(.easeInOut(duration: 0.2)) { viewModel.setZoom(1.5) } }
                    Button("2× (Fine Writing)") { withAnimation(.easeInOut(duration: 0.2)) { viewModel.setZoom(2.0) } }
                    Button("3× (Micro Writing)") { withAnimation(.easeInOut(duration: 0.2)) { viewModel.setZoom(3.0) } }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: viewModel.journalZoomScale > 1.01 ? "minus.magnifyingglass" : "plus.magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                        if viewModel.journalZoomScale > 1.01 {
                            Text(String(format: "%.1f×", viewModel.journalZoomScale))
                                .font(.caption2.weight(.bold).monospacedDigit())
                        }
                    }
                    .foregroundStyle(viewModel.journalZoomScale > 1.01 ? viewModel.theme.accentBlue : viewModel.theme.primaryText)
                    .padding(.horizontal, viewModel.journalZoomScale > 1.01 ? 8 : 0)
                    .frame(minWidth: 42, minHeight: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(viewModel.journalZoomScale > 1.01 ? viewModel.theme.accentBlue.opacity(0.14) : Color.clear)
                    )
                }
                .accessibilityLabel("Zoom")

                // Notability-Style Stickers
                Button {
                    viewModel.showStickerSheet = true
                } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(viewModel.showStickerSheet ? viewModel.theme.accentBlue : viewModel.theme.primaryText)
                        .frame(width: 42, height: 38)
                }
                .accessibilityLabel("Stickers")
            }

            Spacer(minLength: isCompact ? 6 : 16)

            toolbarItem(
                title: "Read Aloud",
                icon: viewModel.isAudioBarVisible ? "speaker.wave.2.fill" : "speaker.wave.2",
                active: viewModel.isAudioBarVisible
            ) {
                if viewModel.isAudioBarVisible {
                    viewModel.stopChapterAudio()
                } else {
                    viewModel.startChapterAudio()
                }
            }

            Spacer(minLength: isCompact ? 6 : 16)

            toolbarItem(title: "View", icon: "slider.horizontal.3", active: viewModel.showViewSettings) {
                viewModel.showViewSettings = true
            }
        }
        .foregroundStyle(viewModel.theme.primaryText)
        .padding(.horizontal, isCompact ? 10 : 18)
        .padding(.vertical, 6)
        .background(viewModel.theme.chromeBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(viewModel.theme.dividerColor).frame(height: 1)
        }
    }

    private func toolbarItem(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? viewModel.theme.accentBlue : viewModel.theme.primaryText)
                .frame(width: 44, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(active ? viewModel.theme.accentBlue.opacity(0.12) : Color.clear)
                )
        }
        .accessibilityLabel(title)
    }
}

public struct FloatingPenToolbox: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Writing Tools")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.theme.primaryText)

                if !viewModel.chapterDrawing.strokes.isEmpty {
                    Button {
                        viewModel.showPenToolbox = false
                        viewModel.showMarginOCRScanner = true
                    } label: {
                        Label("Scan Ink", systemImage: "text.viewfinder")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(viewModel.theme.accentBlue)
                    .padding(.leading, 6)
                }

                Spacer()
                Toggle(isOn: $viewModel.pencilOnly) {
                    Text("Apple Pencil Only")
                        .font(.caption)
                        .foregroundStyle(viewModel.theme.secondaryText)
                }
                .toggleStyle(.switch)
                .labelsHidden()
                Text(viewModel.pencilOnly ? "Pencil Only" : "Finger + Pencil")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(viewModel.pencilOnly ? .green : .orange)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.showPenToolbox = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(viewModel.theme.secondaryText)
                }
                .padding(.leading, 8)
            }

            // Tool selector row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WritingToolKind.allCases) { tool in
                        Button {
                            viewModel.selectedTool = tool
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tool.systemImage)
                                    .font(.caption)
                                Text(tool.rawValue)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(viewModel.selectedTool == tool ? viewModel.theme.accentBlue.opacity(0.2) : viewModel.theme.canvasBackground)
                            .foregroundStyle(viewModel.selectedTool == tool ? viewModel.theme.accentBlue : viewModel.theme.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(viewModel.selectedTool == tool ? viewModel.theme.accentBlue : viewModel.theme.dividerColor, lineWidth: 1)
                            )
                        }
                    }
                }
            }

            // Color swatches + Width + Opacity + Live Stroke Preview
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(InkColorPreset.defaults) { preset in
                        Button {
                            viewModel.selectedColor = preset
                        } label: {
                            Circle()
                                .fill(preset.swiftUIColor)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(viewModel.selectedColor == preset ? viewModel.theme.accentBlue : Color.clear, lineWidth: 2.5)
                                        .padding(-3)
                                )
                        }
                    }
                }

                Divider().frame(height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "Width %.1f pt", viewModel.strokeWidth))
                        .font(.caption2)
                        .foregroundStyle(viewModel.theme.secondaryText)
                    Slider(value: $viewModel.strokeWidth, in: 1...12, step: 0.5)
                        .frame(width: 110)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "Opacity %d%%", Int(viewModel.inkOpacity * 100)))
                        .font(.caption2)
                        .foregroundStyle(viewModel.theme.secondaryText)
                    Slider(value: $viewModel.inkOpacity, in: 0.2...1.0, step: 0.05)
                        .frame(width: 100)
                }

                // Live stroke preview
                Capsule()
                    .fill(viewModel.selectedColor.swiftUIColor.opacity(viewModel.inkOpacity))
                    .frame(width: 44, height: max(2, min(14, viewModel.strokeWidth)))
                    .padding(.horizontal, 6)
            }
        }
        .padding(14)
        .background(viewModel.theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(viewModel.theme.dividerColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
        .onChange(of: viewModel.pencilOnly) { _, _ in
            viewModel.persistAppearancePreferences()
        }
    }
}
