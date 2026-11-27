import PencilKit
import SwiftUI
import UIKit

/// A paper-like PKCanvasView overlay designed to sit seamlessly over Scripture + Journal Margin.
/// - Apple Pencil draws natively anywhere across Scripture and the Journal Margin.
/// - Finger panning passes through to the parent ScrollView for smooth chapter scrolling.
/// - Finger tap reports its location so tapping a verse opens contextual word/verse study.
public final class PassthroughPKCanvasView: PKCanvasView {
    public var onFingerTap: ((CGPoint) -> Void)?
    private var fingerTapRecognizer: UITapGestureRecognizer?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }

    private func commonSetup() {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        isScrollEnabled = false
        minimumZoomScale = 1.0
        maximumZoomScale = 1.0
        bouncesZoom = false
        bounces = false
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        isMultipleTouchEnabled = false
        contentInsetAdjustmentBehavior = .never
        automaticallyAdjustsScrollIndicatorInsets = false
        contentInset = .zero
        contentOffset = .zero
        panGestureRecognizer.isEnabled = false
        pinchGestureRecognizer?.isEnabled = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false

        let fingerTap = UITapGestureRecognizer(target: self, action: #selector(handleFingerTap(_:)))
        fingerTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        fingerTap.cancelsTouchesInView = true
        addGestureRecognizer(fingerTap)
        self.fingerTapRecognizer = fingerTap
        suppressPencilKitEditMenu()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        suppressPencilKitEditMenu()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Never mutate UIScrollView geometry while Apple Pencil is actively stroking!
        let strokeState = drawingGestureRecognizer.state
        guard strokeState != .began && strokeState != .changed else { return }
        if contentSize != bounds.size { contentSize = bounds.size }
        if contentInset != .zero { contentInset = .zero }
        if contentOffset != .zero { contentOffset = .zero }
    }

    public func suppressPencilKitEditMenu() {
        guard !(tool is PKLassoTool) else { return }
        var stack: [UIView] = [self]
        while let v = stack.popLast() {
            for interaction in v.interactions {
                let typeName = String(describing: type(of: interaction))
                if interaction is UIEditMenuInteraction || typeName.contains("EditMenu") || typeName.contains("Selection") {
                    v.removeInteraction(interaction)
                }
            }
            for gr in v.gestureRecognizers ?? [] {
                if gr === drawingGestureRecognizer || gr === fingerTapRecognizer { continue }
                let typeName = String(describing: type(of: gr))
                if gr is UITapGestureRecognizer || gr is UILongPressGestureRecognizer || typeName.contains("Selection") || typeName.contains("EditMenu") {
                    gr.isEnabled = false
                }
            }
            stack.append(contentsOf: v.subviews)
        }
    }

    public override var canBecomeFirstResponder: Bool {
        tool is PKLassoTool
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if tool is PKLassoTool {
            return super.canPerformAction(action, withSender: sender)
        }
        return false
    }

    @objc private func handleFingerTap(_ recognizer: UITapGestureRecognizer) {
        guard drawingPolicy == .pencilOnly else { return }
        let pt = recognizer.location(in: self)
        onFingerTap?(pt)
    }
}

public struct UnifiedBibleCanvas: UIViewRepresentable {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    var onFingerTapPoint: (CGPoint) -> Void

    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    public func makeUIView(context: Context) -> PassthroughPKCanvasView {
        let canvas = PassthroughPKCanvasView()
        canvas.delegate = context.coordinator
        let initialPolicy: PKCanvasViewDrawingPolicy = viewModel.pencilOnly ? .pencilOnly : .anyInput
        canvas.drawing = viewModel.chapterDrawing
        canvas.tool = viewModel.activePKTool
        canvas.drawingPolicy = initialPolicy
        canvas.onFingerTap = onFingerTapPoint
        context.coordinator.canvas = canvas
        context.coordinator.appliedRevision = viewModel.drawingRevision
        context.coordinator.lastToolKey = currentToolKey()
        context.coordinator.lastPencilOnly = viewModel.pencilOnly

        viewModel.onUndoRequest = { [weak canvas] in
            canvas?.undoManager?.undo()
        }
        viewModel.onRedoRequest = { [weak canvas] in
            canvas?.undoManager?.redo()
        }
        return canvas
    }

    private func currentToolKey() -> String {
        "\(viewModel.selectedTool.rawValue)|\(viewModel.selectedColor.hex)|\(viewModel.strokeWidth)|\(viewModel.inkOpacity)"
    }

    public func updateUIView(_ canvas: PassthroughPKCanvasView, context: Context) {
        let toolKey = currentToolKey()
        if context.coordinator.lastToolKey != toolKey {
            canvas.tool = viewModel.activePKTool
            context.coordinator.lastToolKey = toolKey
        }
        if context.coordinator.lastPencilOnly != viewModel.pencilOnly {
            canvas.drawingPolicy = viewModel.pencilOnly ? .pencilOnly : .anyInput
            context.coordinator.lastPencilOnly = viewModel.pencilOnly
        }
        canvas.onFingerTap = onFingerTapPoint

        if context.coordinator.appliedRevision != viewModel.drawingRevision {
            context.coordinator.isProgrammaticUpdate = true
            canvas.drawing = viewModel.chapterDrawing
            canvas.undoManager?.removeAllActions()
            context.coordinator.appliedRevision = viewModel.drawingRevision
            context.coordinator.isProgrammaticUpdate = false
            Task { @MainActor in
                if viewModel.canUndo { viewModel.canUndo = false }
                if viewModel.canRedo { viewModel.canRedo = false }
            }
        }
    }

    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        let viewModel: BibleWorkspaceViewModel
        weak var canvas: PassthroughPKCanvasView?
        var appliedRevision: Int = -1
        var isProgrammaticUpdate: Bool = false
        var lastToolKey: String = ""
        var lastPencilOnly: Bool = true

        init(viewModel: BibleWorkspaceViewModel) {
            self.viewModel = viewModel
        }

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isProgrammaticUpdate else { return }
            let snapshot = canvasView.drawing
            let canUndo = canvasView.undoManager?.canUndo ?? false
            let canRedo = canvasView.undoManager?.canRedo ?? false
            Task { @MainActor in
                viewModel.handleCanvasDrawingChanged(snapshot, canUndo: canUndo, canRedo: canRedo)
            }
        }
    }
}
