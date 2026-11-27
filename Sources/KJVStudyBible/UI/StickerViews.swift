import CoreImage
import PencilKit
import PhotosUI
import SwiftUI
import UIKit
import Vision

// MARK: - Sticker Artwork Renderer

public struct StickerArtworkView: View {
    let item: StickerItem
    let size: CGSize

    public var body: some View {
        switch item.kind {
        case .symbol:
            let sym = item.symbolName ?? "star.fill"
            let side = min(size.width, size.height)
            ZStack {
                Circle()
                    .fill(item.tintColor.opacity(0.16))
                    .overlay(
                        Circle()
                            .stroke(item.tintColor.opacity(0.65), lineWidth: max(1.5, side * 0.032))
                    )
                Image(systemName: sym)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(item.tintColor)
                    .padding(side * 0.24)
            }
            .frame(width: size.width, height: size.height)
        case .drawn, .imported:
            if let data = item.imageData, let uiImg = UIImage(data: data) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(width: size.width, height: size.height)
            }
        }
    }
}

// MARK: - Draggable, Corner-Resizable, Opacity-Controlled Placed Sticker (Strict .offset() Hit-Box)

public struct DraggablePlacedSticker: View {
    let placed: PlacedSticker
    let item: StickerItem
    let isSelected: Bool
    let theme: ReadingTheme
    let onSelect: () -> Void
    let onUpdate: (PlacedSticker) -> Void
    let onDelete: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGFloat = 0
    @State private var liveOpacity: Double = 1.0
    @State private var isDraggingBody: Bool = false

    public var body: some View {
        let currentW = max(28, min(360, placed.width + Double(resizeDelta)))
        let currentH = max(28, min(360, placed.height + Double(resizeDelta)))
        let displayOpacity = isSelected ? liveOpacity : placed.opacity

        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                // Sticker Artwork + Relaxed Drag/Tap Surface
                ZStack {
                    StickerArtworkView(item: item, size: CGSize(width: currentW, height: currentH))
                        .opacity(displayOpacity)
                        .rotationEffect(.degrees(placed.rotation))
                        .shadow(color: .black.opacity(isSelected ? 0.16 : 0.06), radius: isSelected ? 6 : 2, y: 1)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.accentBlue, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: currentW + 14, height: currentH + 14)
                    }
                }
                .padding(8)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let dist = hypot(value.translation.width, value.translation.height)
                            if dist > 4 || isDraggingBody {
                                isDraggingBody = true
                                dragOffset = value.translation
                            }
                        }
                        .onEnded { value in
                            let dist = hypot(value.translation.width, value.translation.height)
                            if !isDraggingBody && dist <= 6 {
                                dragOffset = .zero
                                onSelect()
                            } else {
                                var next = placed
                                next.posX = max(4, placed.posX + Double(value.translation.width))
                                next.posY = max(4, placed.posY + Double(value.translation.height))
                                dragOffset = .zero
                                isDraggingBody = false
                                onUpdate(next)
                            }
                        }
                )

                // Tactile Corner Resize Handle (drag diagonally to grow/shrink smoothly!)
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(theme.accentBlue)
                            .frame(width: 28, height: 28)
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(4)
                    .contentShape(Circle())
                    .offset(x: 6, y: 6)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let delta = (value.translation.width + value.translation.height) * 0.75
                                resizeDelta = delta
                            }
                            .onEnded { value in
                                let delta = (value.translation.width + value.translation.height) * 0.75
                                var next = placed
                                next.width = max(28, min(360, placed.width + Double(delta)))
                                next.height = max(28, min(360, placed.height + Double(delta)))
                                resizeDelta = 0
                                onUpdate(next)
                            }
                    )
                }
            }

            // Floating Controls when Selected (Opacity 0-100%, Rotate, Delete, Done)
            if isSelected {
                VStack(alignment: .leading, spacing: 6) {
                    // Opacity Slider Row (0% - 100%)
                    HStack(spacing: 8) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.accentBlue)
                        Slider(value: $liveOpacity, in: 0.0...1.0, step: 0.01) { editing in
                            if !editing {
                                var next = placed
                                next.opacity = liveOpacity
                                onUpdate(next)
                            }
                        }
                        .frame(width: 128)
                        .tint(theme.accentBlue)
                        Text("\(Int(round(liveOpacity * 100)))%")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                            .frame(width: 36, alignment: .trailing)
                    }

                    // Quick Actions Row
                    HStack(spacing: 8) {
                        Button {
                            var next = placed
                            next.rotation -= 15
                            onUpdate(next)
                        } label: {
                            Image(systemName: "rotate.left")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 26, height: 24)
                        }
                        .buttonStyle(.plain)

                        Button {
                            var next = placed
                            next.rotation += 15
                            onUpdate(next)
                        } label: {
                            Image(systemName: "rotate.right")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 26, height: 24)
                        }
                        .buttonStyle(.plain)

                        Divider().frame(height: 14)

                        Button {
                            liveOpacity = 0.35
                            var next = placed
                            next.opacity = 0.35
                            onUpdate(next)
                        } label: {
                            Text("35%")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(theme.accentBlue.opacity(0.12))
                                .foregroundStyle(theme.accentBlue)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            liveOpacity = 1.0
                            var next = placed
                            next.opacity = 1.0
                            onUpdate(next)
                        } label: {
                            Text("100%")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(theme.accentBlue.opacity(0.12))
                                .foregroundStyle(theme.accentBlue)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Divider().frame(height: 14)

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 26, height: 24)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onSelect()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(theme.accentBlue)
                                .frame(width: 26, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.panelBackground.opacity(0.97))
                .foregroundStyle(theme.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.dividerColor, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            }
        }
        .offset(x: placed.posX + Double(dragOffset.width), y: placed.posY + Double(dragOffset.height))
        .onAppear {
            liveOpacity = placed.opacity
        }
        .onChange(of: placed.opacity) { _, newVal in
            liveOpacity = newVal
        }
    }
}

// MARK: - Sticker Editor Request (Create, Edit Existing, or Duplicate & Edit)

public struct StickerEditorRequest: Identifiable {
    public let id = UUID()
    public let sourceItem: StickerItem?
    public let isDuplicate: Bool
}

// MARK: - Sticker Library Sheet (Insert, Create with Apple Pencil, Edit, Duplicate, Import from Photos)

public struct StickerLibrarySheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    let targetLabel: String
    let onInsert: (StickerItem) -> Void
    @Environment(\.dismiss) private var dismiss

    enum FilterTab: String, CaseIterable, Identifiable {
        case all = "All"
        case bible = "Bible Study"
        case drawn = "My Drawn"
        case imported = "Imported"
        var id: String { rawValue }
    }

    @State private var selectedTab: FilterTab = .all
    @State private var editorRequest: StickerEditorRequest? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var importError: String? = nil

    private var filteredStickers: [StickerItem] {
        switch selectedTab {
        case .all: return viewModel.stickerLibrary
        case .bible: return viewModel.stickerLibrary.filter { $0.kind == .symbol }
        case .drawn: return viewModel.stickerLibrary.filter { $0.kind == .drawn }
        case .imported: return viewModel.stickerLibrary.filter { $0.kind == .imported }
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Action Bar: Draw New Sticker + Import from Photos
                HStack(spacing: 10) {
                    Button {
                        editorRequest = StickerEditorRequest(sourceItem: nil, isDuplicate: false)
                    } label: {
                        Label("Draw Sticker", systemImage: "pencil.and.outline")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.theme.accentBlue)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Import Photo", systemImage: "photo.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(.bordered)
                    .tint(viewModel.theme.accentBlue)

                    Spacer()

                    Text("Tap to place on \(targetLabel) · ••• to edit or duplicate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(viewModel.theme.chromeBackground)

                Picker("Category", selection: $selectedTab) {
                    ForEach(FilterTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if let err = importError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }

                Divider()

                if filteredStickers.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 38))
                            .foregroundStyle(.secondary)
                        Text(selectedTab == .drawn
                             ? "No hand-drawn stickers yet. Tap \"Draw Sticker\" to sketch one with Apple Pencil!"
                             : selectedTab == .imported
                             ? "No imported stickers yet. Tap \"Import Photo\" to add PNGs or images from Photos."
                             : "No stickers found.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 136), spacing: 14)], spacing: 14) {
                            ForEach(filteredStickers) { item in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        onInsert(item)
                                        dismiss()
                                    } label: {
                                        VStack(spacing: 8) {
                                            StickerArtworkView(item: item, size: CGSize(width: 64, height: 64))
                                            Text(item.name)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(viewModel.theme.primaryText)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 8)
                                        .background(viewModel.theme.panelBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(viewModel.theme.dividerColor, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Menu {
                                        Button {
                                            onInsert(item)
                                            dismiss()
                                        } label: {
                                            Label("Insert on \(targetLabel)", systemImage: "plus.circle")
                                        }

                                        if item.kind != .symbol {
                                            Button {
                                                editorRequest = StickerEditorRequest(sourceItem: item, isDuplicate: false)
                                            } label: {
                                                Label("Edit Sticker", systemImage: "pencil")
                                            }
                                        }

                                        Button {
                                            editorRequest = StickerEditorRequest(sourceItem: item, isDuplicate: true)
                                        } label: {
                                            Label("Duplicate & Edit", systemImage: "plus.square.on.square")
                                        }

                                        if item.kind != .symbol {
                                            Divider()
                                            Button(role: .destructive) {
                                                viewModel.deleteStickerFromLibrary(item)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.secondary)
                                            .background(Circle().fill(viewModel.theme.panelBackground))
                                    }
                                    .padding(5)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editorRequest) { req in
                StickerCreatorSheet(
                    viewModel: viewModel,
                    sourceItem: req.sourceItem,
                    isDuplicate: req.isDuplicate
                ) { saved, shouldInsert in
                    selectedTab = .drawn
                    if shouldInsert {
                        onInsert(saved)
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await importSelectedPhoto(newItem)
                }
            }
        }
    }

    private func importSelectedPhoto(_ photoItem: PhotosPickerItem) async {
        do {
            guard let rawData = try await photoItem.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: rawData),
                  let pngData = Self.normalizedStickerPNG(from: uiImage, maxDimension: 512) else {
                await MainActor.run {
                    importError = "Could not load selected image."
                    selectedPhotoItem = nil
                }
                return
            }
            await MainActor.run {
                let count = viewModel.stickerLibrary.filter { $0.kind == .imported }.count + 1
                let saved = viewModel.saveCustomSticker(
                    name: "Sticker \(count)",
                    kind: .imported,
                    category: "Imported",
                    imageData: pngData
                )
                importError = nil
                selectedTab = .imported
                selectedPhotoItem = nil
                editorRequest = StickerEditorRequest(sourceItem: saved, isDuplicate: false)
            }
        } catch {
            await MainActor.run {
                importError = "Import failed: \(error.localizedDescription)"
                selectedPhotoItem = nil
            }
        }
    }

    public static func normalizedStickerPNG(from image: UIImage, maxDimension: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0 && size.height > 0 else { return nil }
        let ratio = min(1.0, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: max(1, floor(size.width * ratio)), height: max(1, floor(size.height * ratio)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return scaled.pngData()
    }

    nonisolated public static func renderSymbolStickerImage(_ item: StickerItem, side: CGFloat = 360) -> UIImage? {
        let sym = item.symbolName ?? "star.fill"
        let uiColor = item.tintHex.flatMap { UIColor(hex: $0) } ?? UIColor.systemBlue
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let circleRect = CGRect(x: 16, y: 16, width: side - 32, height: side - 32)
            cg.setFillColor(uiColor.withAlphaComponent(0.16).cgColor)
            cg.fillEllipse(in: circleRect)
            cg.setStrokeColor(uiColor.withAlphaComponent(0.65).cgColor)
            cg.setLineWidth(10)
            cg.strokeEllipse(in: circleRect)

            let cfg = UIImage.SymbolConfiguration(pointSize: side * 0.42, weight: .semibold)
            if let symImg = UIImage(systemName: sym, withConfiguration: cfg)?.withTintColor(uiColor, renderingMode: .alwaysOriginal) {
                let sSize = symImg.size
                let aspect = min((side * 0.50) / max(1, sSize.width), (side * 0.50) / max(1, sSize.height))
                let w = sSize.width * aspect
                let h = sSize.height * aspect
                symImg.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
            }
        }
    }
}

// MARK: - Apple Pencil Sticker Creator / Editor Studio (Draw + Image Perimeter Eraser + Magic Cutout)

public struct StickerCreatorSheet: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    let sourceItem: StickerItem?
    let isDuplicate: Bool
    let onCompleted: (StickerItem, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    enum StudioMode: String, CaseIterable, Identifiable {
        case draw = "Draw Ink"
        case eraseImage = "Erase Image"
        var id: String { rawValue }
    }

    @State private var stickerName: String = ""
    @State private var drawing: PKDrawing = PKDrawing()
    @State private var baseImage: UIImage? = nil
    @State private var baseImageHistory: [UIImage] = []
    @State private var studioMode: StudioMode = .draw
    @State private var eraserBrushSize: Double = 26.0
    @State private var liveErasePoints: [CGPoint] = []
    @State private var isProcessingCutout: Bool = false
    @State private var studioStatus: String? = nil

    @State private var loadRevision: Int = 0
    @State private var selectedTool: WritingToolKind = .pen
    @State private var selectedColor: InkColorPreset = InkColorPreset.defaults[1]
    @State private var strokeWidth: Double = 5.0
    @State private var undoTrigger: Int = 0
    @State private var redoTrigger: Int = 0

    private let canvasSide: CGFloat = 440

    private var isEditingExisting: Bool {
        sourceItem != nil && !isDuplicate
    }

    private var navTitle: String {
        if isEditingExisting { return "Edit Sticker" }
        if isDuplicate { return "Duplicate & Edit Sticker" }
        return "Create Custom Sticker"
    }

    private var activePKTool: PKTool {
        switch selectedTool {
        case .pen: return PKInkingTool(.pen, color: selectedColor.uiColor, width: CGFloat(strokeWidth))
        case .pencil: return PKInkingTool(.pencil, color: selectedColor.uiColor, width: CGFloat(strokeWidth * 1.4))
        case .marker: return PKInkingTool(.marker, color: selectedColor.uiColor, width: CGFloat(strokeWidth * 2.2))
        case .highlighter: return PKInkingTool(.marker, color: selectedColor.uiColor.withAlphaComponent(0.45), width: CGFloat(strokeWidth * 3.0))
        case .eraserVector: return PKEraserTool(.vector)
        case .eraserBitmap: return PKEraserTool(.bitmap)
        case .lasso: return PKLassoTool()
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Sticker Name (e.g. Dove, Banner, Arrow)", text: $stickerName)
                        .textFieldStyle(.roundedBorder)

                    if baseImage != nil {
                        Picker("Mode", selection: $studioMode) {
                            ForEach(StudioMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                    }

                    Button("Clear Ink") {
                        drawing = PKDrawing()
                        loadRevision += 1
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(drawing.strokes.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // Mode-specific Tool Bar
                if baseImage != nil && studioMode == .eraseImage {
                    HStack(spacing: 10) {
                        Button {
                            runMagicCutout()
                        } label: {
                            if isProcessingCutout {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Magic Cutout", systemImage: "wand.and.stars")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(viewModel.theme.accentBlue)
                        .disabled(isProcessingCutout)

                        Button {
                            removeWhiteBackground()
                        } label: {
                            Label("Drop White BG", systemImage: "square.dashed")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Divider().frame(height: 20)

                        HStack(spacing: 6) {
                            Image(systemName: "eraser.fill")
                                .font(.caption)
                                .foregroundStyle(viewModel.theme.accentBlue)
                            Text("Brush \(Int(eraserBrushSize))pt")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Slider(value: $eraserBrushSize, in: 8...64, step: 2)
                                .frame(width: 110)
                        }

                        Spacer()

                        Button {
                            if let prev = baseImageHistory.popLast() {
                                baseImage = prev
                            }
                        } label: {
                            Label("Undo Erase", systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(baseImageHistory.isEmpty)
                    }
                    .padding(.horizontal, 16)
                } else {
                    HStack(spacing: 10) {
                        ForEach([WritingToolKind.pen, .marker, .pencil, .eraserVector]) { t in
                            Button {
                                selectedTool = t
                            } label: {
                                Label(t.rawValue, systemImage: t.systemImage)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(selectedTool == t ? viewModel.theme.accentBlue : .secondary)
                        }

                        Divider().frame(height: 20)

                        ForEach(InkColorPreset.defaults) { preset in
                            Button {
                                selectedColor = preset
                            } label: {
                                Circle()
                                    .fill(preset.swiftUIColor)
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == preset ? viewModel.theme.accentBlue : Color.clear, lineWidth: 2)
                                            .padding(-2)
                                    )
                            }
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text(String(format: "%.0fpt", strokeWidth))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Slider(value: $strokeWidth, in: 2...16, step: 1)
                                .frame(width: 90)
                        }

                        Button { undoTrigger += 1 } label: { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button { redoTrigger += 1 } label: { Image(systemName: "arrow.uturn.forward") }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                }

                // Square Transparent-Grid Sticker Canvas (440x440)
                ZStack {
                    CheckerboardCanvasBackground()

                    // Editable Raster Image Layer with 60fps Live Erase Preview
                    if let bg = baseImage {
                        ZStack {
                            Image(uiImage: bg)
                                .resizable()
                                .frame(width: canvasSide, height: canvasSide)

                            if !liveErasePoints.isEmpty {
                                Path { path in
                                    if let first = liveErasePoints.first {
                                        path.move(to: first)
                                        if liveErasePoints.count == 1 {
                                            path.addLine(to: CGPoint(x: first.x + 0.5, y: first.y + 0.5))
                                        } else {
                                            for pt in liveErasePoints.dropFirst() {
                                                path.addLine(to: pt)
                                            }
                                        }
                                    }
                                }
                                .stroke(Color.black, style: StrokeStyle(lineWidth: CGFloat(eraserBrushSize), lineCap: .round, lineJoin: .round))
                                .blendMode(.destinationOut)
                            }
                        }
                        .compositingGroup()
                        .allowsHitTesting(false)
                    }

                    // Apple Pencil Ink Layer
                    StickerCreatorPKCanvas(
                        drawing: $drawing,
                        loadRevision: loadRevision,
                        tool: activePKTool,
                        undoTrigger: undoTrigger,
                        redoTrigger: redoTrigger
                    )
                    .allowsHitTesting(studioMode == .draw || baseImage == nil)

                    // Direct Perimeter Image Eraser Overlay (works with Apple Pencil or finger!)
                    if baseImage != nil && studioMode == .eraseImage {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        liveErasePoints.append(value.location)
                                    }
                                    .onEnded { _ in
                                        commitEraseStroke()
                                    }
                            )
                    }
                }
                .frame(width: canvasSide, height: canvasSide)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(viewModel.theme.accentBlue.opacity(0.45), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                .padding(.horizontal, 16)

                if let status = studioStatus {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(viewModel.theme.accentBlue)
                } else {
                    Text(baseImage != nil && studioMode == .eraseImage
                         ? "Swipe with Apple Pencil or finger to erase edges cleanly, or tap Magic Cutout / Drop White BG."
                         : isEditingExisting
                         ? "Edit strokes or name — saving updates this sticker everywhere it's used."
                         : isDuplicate
                         ? "Customize this copy with Apple Pencil — your original sticker stays untouched."
                         : "Draw with Apple Pencil or finger — background stays transparent when saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 10)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if isEditingExisting {
                        Button("Save Changes") {
                            saveSticker(insertAfter: false)
                        }
                        .fontWeight(.semibold)
                        .disabled(drawing.strokes.isEmpty && baseImage == nil)
                    } else {
                        Button("Save Only") {
                            saveSticker(insertAfter: false)
                        }
                        .disabled(drawing.strokes.isEmpty && baseImage == nil)

                        Button(isDuplicate ? "Save Copy & Insert" : "Save & Insert") {
                            saveSticker(insertAfter: true)
                        }
                        .fontWeight(.semibold)
                        .disabled(drawing.strokes.isEmpty && baseImage == nil)
                    }
                }
            }
            .onAppear {
                loadInitialSourceIfNeeded()
            }
        }
    }

    private func loadInitialSourceIfNeeded() {
        guard let src = sourceItem else { return }
        stickerName = isDuplicate ? "\(src.name) Copy" : src.name
        if let rawDrawing = src.drawingData, let loaded = try? PKDrawing(data: rawDrawing) {
            drawing = loaded
            baseImage = nil
            studioMode = .draw
            loadRevision += 1
        } else if let imgData = src.imageData, let uiImg = UIImage(data: imgData) {
            baseImage = Self.fitImageIntoSquareCanvas(uiImg, side: canvasSide)
            studioMode = .eraseImage
        } else if src.kind == .symbol, let symImg = StickerLibrarySheet.renderSymbolStickerImage(src) {
            baseImage = Self.fitImageIntoSquareCanvas(symImg, side: canvasSide)
            studioMode = .draw
        }
    }

    // MARK: - Raster Image Eraser & One-Tap Cutout Helpers

    private static func fitImageIntoSquareCanvas(_ image: UIImage, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            let maxBox = side - 36
            let scale = min(maxBox / max(1, image.size.width), maxBox / max(1, image.size.height))
            let w = image.size.width * scale
            let h = image.size.height * scale
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
    }

    private func commitEraseStroke() {
        guard let current = baseImage, !liveErasePoints.isEmpty else {
            liveErasePoints = []
            return
        }
        let points = liveErasePoints
        liveErasePoints = []
        baseImageHistory.append(current)
        if baseImageHistory.count > 20 { baseImageHistory.removeFirst() }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasSide, height: canvasSide), format: format)
        let updated = renderer.image { ctx in
            current.draw(in: CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
            let cg = ctx.cgContext
            cg.setBlendMode(.clear)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setLineWidth(CGFloat(eraserBrushSize))
            cg.beginPath()
            cg.move(to: points[0])
            if points.count == 1 {
                cg.addLine(to: CGPoint(x: points[0].x + 0.5, y: points[0].y + 0.5))
            } else {
                for pt in points.dropFirst() {
                    cg.addLine(to: pt)
                }
            }
            cg.strokePath()
        }
        baseImage = updated
        studioStatus = nil
    }

    private func removeWhiteBackground() {
        guard let current = baseImage, let cgImg = current.cgImage else { return }
        baseImageHistory.append(current)
        if baseImageHistory.count > 20 { baseImageHistory.removeFirst() }

        let width = cgImg.width
        let height = cgImg.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: width, height: height))

        for i in stride(from: 0, to: rawData.count, by: 4) {
            let a = rawData[i + 3]
            if a == 0 { continue }
            let r = rawData[i]
            let g = rawData[i + 1]
            let b = rawData[i + 2]
            if r > 235 && g > 235 && b > 235 {
                rawData[i] = 0
                rawData[i + 1] = 0
                rawData[i + 2] = 0
                rawData[i + 3] = 0
            }
        }
        if let outCG = ctx.makeImage() {
            baseImage = UIImage(cgImage: outCG, scale: current.scale, orientation: .up)
            studioStatus = "Removed white background — you can still touch up edges with the eraser."
        }
    }

    private func runMagicCutout() {
        guard let current = baseImage, let cgImg = current.cgImage else { return }
        isProcessingCutout = true
        studioStatus = "Lifting subject from background on-device..."
        let snapshot = current
        Task.detached(priority: .userInitiated) {
            if #available(iOS 17.0, *) {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
                do {
                    try handler.perform([request])
                    if let obs = request.results?.first {
                        let maskBuffer = try obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
                        let inputCI = CIImage(cgImage: cgImg)
                        let maskCI = CIImage(cvPixelBuffer: maskBuffer)
                        let filter = CIFilter(name: "CIBlendWithMask")
                        filter?.setValue(inputCI, forKey: kCIInputImageKey)
                        filter?.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
                        filter?.setValue(maskCI, forKey: kCIInputMaskImageKey)
                        let ciContext = CIContext()
                        if let outCI = filter?.outputImage,
                           let outCG = ciContext.createCGImage(outCI, from: inputCI.extent) {
                            let resultImg = UIImage(cgImage: outCG, scale: snapshot.scale, orientation: .up)
                            await MainActor.run {
                                self.baseImageHistory.append(snapshot)
                                if self.baseImageHistory.count > 20 { self.baseImageHistory.removeFirst() }
                                self.baseImage = resultImg
                                self.isProcessingCutout = false
                                self.studioStatus = "Cutout complete! Use the eraser brush for any fine edge touch-ups."
                            }
                            return
                        }
                    }
                } catch {
                    // Fall through to helpful message
                }
            }
            await MainActor.run {
                self.isProcessingCutout = false
                self.studioStatus = "No distinct subject found — try Drop White BG or swipe edges with the Eraser."
            }
        }
    }

    private static func trimTransparentPadding(from image: UIImage) -> UIImage {
        guard let cgImg = image.cgImage else { return image }
        let width = cgImg.width
        let height = cgImg.height
        let bytesPerRow = width * 4
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = 0, maxY = 0
        var found = false
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                if rawData[rowStart + x * 4 + 3] > 8 {
                    found = true
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard found else { return image }
        let pad = 12
        let rx = max(0, minX - pad)
        let ry = max(0, minY - pad)
        let rw = min(width - rx, (maxX - minX + 1) + pad * 2)
        let rh = min(height - ry, (maxY - minY + 1) + pad * 2)
        guard let cropped = cgImg.cropping(to: CGRect(x: rx, y: ry, width: rw, height: rh)) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    private func renderCompositeImage() -> UIImage? {
        if let bg = baseImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2.0
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasSide, height: canvasSide), format: format)
            let combined = renderer.image { _ in
                bg.draw(in: CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
                if !drawing.strokes.isEmpty {
                    let inkImg = drawing.image(from: CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide), scale: 2.0)
                    inkImg.draw(in: CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
                }
            }
            return Self.trimTransparentPadding(from: combined)
        } else {
            guard !drawing.strokes.isEmpty else { return nil }
            let cropRect = drawing.bounds.insetBy(dx: -16, dy: -16)
            guard cropRect.width > 1 && cropRect.height > 1 else { return nil }
            return drawing.image(from: cropRect, scale: 2.0)
        }
    }

    private func saveSticker(insertAfter: Bool) {
        guard let rendered = renderCompositeImage(),
              let pngData = StickerLibrarySheet.normalizedStickerPNG(from: rendered, maxDimension: 512) else { return }

        let cleanName = stickerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "My Sticker \(viewModel.stickerLibrary.filter { $0.kind == .drawn }.count + 1)"
        let finalName = cleanName.isEmpty ? fallbackName : cleanName
        let drawingBlob: Data? = (baseImage == nil && !drawing.strokes.isEmpty) ? drawing.dataRepresentation() : nil

        if isEditingExisting, let src = sourceItem {
            if let updated = viewModel.updateCustomSticker(id: src.id, name: finalName, imageData: pngData, drawingData: drawingBlob) {
                onCompleted(updated, insertAfter)
            }
        } else {
            let item = viewModel.saveCustomSticker(
                name: finalName,
                kind: .drawn,
                category: "My Drawn",
                imageData: pngData,
                drawingData: drawingBlob
            )
            onCompleted(item, insertAfter)
        }
        dismiss()
    }
}

private struct CheckerboardCanvasBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 16
            let rows = Int(ceil(size.height / tile))
            let cols = Int(ceil(size.width / tile))
            for r in 0..<rows {
                for c in 0..<cols {
                    let isEven = (r + c).isMultiple(of: 2)
                    let rect = CGRect(x: CGFloat(c) * tile, y: CGFloat(r) * tile, width: tile, height: tile)
                    ctx.fill(Path(rect), with: .color(isEven ? Color.white : Color.gray.opacity(0.12)))
                }
            }
        }
    }
}

private struct StickerCreatorPKCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let loadRevision: Int
    let tool: PKTool
    let undoTrigger: Int
    let redoTrigger: Int

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = tool
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        context.coordinator.lastLoadRevision = loadRevision
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        uiView.tool = tool
        if context.coordinator.lastLoadRevision != loadRevision {
            context.coordinator.lastLoadRevision = loadRevision
            context.coordinator.isApplyingExternal = true
            uiView.drawing = drawing
            context.coordinator.isApplyingExternal = false
        }
        if context.coordinator.lastUndo != undoTrigger {
            context.coordinator.lastUndo = undoTrigger
            uiView.undoManager?.undo()
        }
        if context.coordinator.lastRedo != redoTrigger {
            context.coordinator.lastRedo = redoTrigger
            uiView.undoManager?.redo()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: StickerCreatorPKCanvas
        var lastLoadRevision: Int = -1
        var lastUndo: Int = 0
        var lastRedo: Int = 0
        var isApplyingExternal = false

        init(parent: StickerCreatorPKCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternal else { return }
            parent.drawing = canvasView.drawing
        }
    }
}
