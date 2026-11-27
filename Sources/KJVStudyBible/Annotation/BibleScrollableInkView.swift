import PencilKit
import SwiftUI
import UIKit

/// Native Apple WWDC PencilKit + Scrollable Content architecture:
/// - `PKCanvasView` itself is the single viewport-sized `UIScrollView` (~850×700pt), so PencilKit's
///   live Metal renderer NEVER hits the 8192px texture clamp on long chapters (e.g. John 1, Psalm 119).
/// - Background SwiftUI content (Scripture + Journal Margin) sits at index 0 behind the ink layer.
/// - Interactive overlay cards (Pinned Chips, Clips, Study Links, Stickers) sit in a passthrough layer
///   that only intercepts touches on actual cards, leaving all empty space to Apple Pencil & scrolling.
public struct BibleScrollableInkView<Background: View, Overlay: View>: UIViewRepresentable {
    @ObservedObject var viewModel: BibleWorkspaceViewModel
    let contentWidth: CGFloat
    let onFingerTapPoint: (CGPoint) -> Void
    let background: Background
    let overlay: Overlay

    public init(
        viewModel: BibleWorkspaceViewModel,
        contentWidth: CGFloat,
        onFingerTapPoint: @escaping (CGPoint) -> Void,
        @ViewBuilder background: () -> Background,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.viewModel = viewModel
        self.contentWidth = contentWidth
        self.onFingerTapPoint = onFingerTapPoint
        self.background = background()
        self.overlay = overlay()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    public func makeUIView(context: Context) -> ViewportPKCanvasView {
        let canvas = ViewportPKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = true
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 3.5
        canvas.bouncesZoom = true
        canvas.alwaysBounceHorizontal = false
        canvas.showsVerticalScrollIndicator = true
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.automaticallyAdjustsScrollIndicatorInsets = false
        canvas.delaysContentTouches = false
        canvas.canCancelContentTouches = true

        canvas.delegate = context.coordinator
        canvas.drawing = viewModel.chapterDrawing
        canvas.tool = viewModel.activePKTool
        canvas.drawingPolicy = viewModel.pencilOnly ? .pencilOnly : .anyInput
        canvas.onFingerTap = onFingerTapPoint

        // Background SwiftUI host (Scripture + Journal Margin) behind PencilKit ink
        let bgHost = UIHostingController(rootView: background)
        bgHost.safeAreaRegions = []
        bgHost.sizingOptions = []
        bgHost.view.backgroundColor = .clear
        bgHost.view.translatesAutoresizingMaskIntoConstraints = true
        bgHost.view.isUserInteractionEnabled = false
        canvas.insertSubview(bgHost.view, at: 0)

        // Interactive overlay host (Pinned Chips, Clips, Study Links, Stickers) in passthrough container
        let ovContainer = CardPassthroughContainer()
        ovContainer.backgroundColor = .clear
        ovContainer.translatesAutoresizingMaskIntoConstraints = true
        let ovHost = UIHostingController(rootView: overlay)
        ovHost.safeAreaRegions = []
        ovHost.sizingOptions = []
        ovHost.view.backgroundColor = .clear
        ovHost.view.translatesAutoresizingMaskIntoConstraints = true
        ovHost.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        ovContainer.addSubview(ovHost.view)
        ovContainer.hostedRootView = ovHost.view
        canvas.addSubview(ovContainer)

        let coord = context.coordinator
        coord.canvas = canvas
        coord.bgHost = bgHost
        coord.ovHost = ovHost
        coord.ovContainer = ovContainer
        coord.requestedWidth = contentWidth
        coord.appliedRevision = viewModel.drawingRevision
        coord.lastToolKey = currentToolKey()
        coord.lastPencilOnly = viewModel.pencilOnly

        canvas.onAttachToWindow = { [weak coord] in
            coord?.attachHostsIfNeeded()
        }
        canvas.onLayout = { [weak coord] in
            coord?.relayoutIfNeeded()
        }

        viewModel.onUndoRequest = { [weak canvas] in
            canvas?.undoManager?.undo()
        }
        viewModel.onRedoRequest = { [weak canvas] in
            canvas?.undoManager?.redo()
        }

        coord.relayoutIfNeeded()
        return canvas
    }

    private func currentToolKey() -> String {
        "\(viewModel.selectedTool.rawValue)|\(viewModel.selectedColor.hex)|\(viewModel.strokeWidth)|\(viewModel.inkOpacity)"
    }

    public func updateUIView(_ canvas: ViewportPKCanvasView, context: Context) {
        let coord = context.coordinator
        let chapterKey = "\(viewModel.currentBookId)-\(viewModel.currentChapter)"
        let didChangeChapter = coord.lastChapterKey != chapterKey
        coord.bgHost?.rootView = background
        coord.bgHost?.view.invalidateIntrinsicContentSize()
        coord.ovHost?.rootView = overlay
        coord.requestedWidth = contentWidth
        canvas.onFingerTap = onFingerTapPoint

        // Keep drawing visible only when ink overlay is enabled
        let showInk = viewModel.shouldShowInkOverlay
        canvas.drawingGestureRecognizer.isEnabled = showInk
        coord.ovContainer?.isHidden = !showInk

        let toolKey = currentToolKey()
        if coord.lastToolKey != toolKey {
            canvas.tool = viewModel.activePKTool
            coord.lastToolKey = toolKey
        }
        if coord.lastPencilOnly != viewModel.pencilOnly {
            canvas.drawingPolicy = viewModel.pencilOnly ? .pencilOnly : .anyInput
            coord.lastPencilOnly = viewModel.pencilOnly
        }

        if coord.appliedRevision != viewModel.drawingRevision || coord.lastShowInk != showInk || didChangeChapter {
            coord.isProgrammaticUpdate = true
            canvas.drawing = showInk ? viewModel.chapterDrawing : PKDrawing()
            canvas.undoManager?.removeAllActions()
            canvas.setNeedsDisplay()
            coord.appliedRevision = viewModel.drawingRevision
            coord.lastShowInk = showInk
            coord.isProgrammaticUpdate = false
            if didChangeChapter {
                coord.lastChapterKey = chapterKey
                canvas.setContentOffset(.zero, animated: false)
            }
            Task { @MainActor in
                if viewModel.canUndo { viewModel.canUndo = false }
                if viewModel.canRedo { viewModel.canRedo = false }
            }
        }

        coord.relayoutIfNeeded()
        if didChangeChapter {
            DispatchQueue.main.async { [weak coord] in
                coord?.relayoutIfNeeded()
            }
        }

        // Programmatic zoom changes from bottom bar zoom menu
        let targetZoom = viewModel.journalZoomScale
        if abs(canvas.zoomScale - targetZoom) > 0.02 && !coord.isUserZooming {
            canvas.setZoomScale(targetZoom, animated: true)
        }
    }

    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        let viewModel: BibleWorkspaceViewModel
        weak var canvas: ViewportPKCanvasView?
        var bgHost: UIHostingController<Background>?
        var ovHost: UIHostingController<Overlay>?
        var ovContainer: CardPassthroughContainer?

        var requestedWidth: CGFloat = 0
        private var lastAppliedWidth: CGFloat = 0
        private var lastAppliedHeight: CGFloat = 0
        var appliedRevision: Int = -1
        var isProgrammaticUpdate: Bool = false
        var isUserZooming: Bool = false
        var lastToolKey: String = ""
        var lastPencilOnly: Bool = true
        var lastShowInk: Bool = true
        var lastChapterKey: String = ""

        init(viewModel: BibleWorkspaceViewModel) {
            self.viewModel = viewModel
        }

        func attachHostsIfNeeded() {
            guard let canvas else { return }
            var responder: UIResponder? = canvas.next
            var parentVC: UIViewController? = nil
            while let r = responder {
                if let vc = r as? UIViewController {
                    parentVC = vc
                    break
                }
                responder = r.next
            }
            guard let vc = parentVC else { return }
            if let bg = bgHost, bg.parent == nil {
                vc.addChild(bg)
                bg.didMove(toParent: vc)
            }
            if let ov = ovHost, ov.parent == nil {
                vc.addChild(ov)
                ov.didMove(toParent: vc)
            }
        }

        func relayoutIfNeeded() {
            guard let canvas, let bgHost, let ovContainer, !isUserZooming else { return }
            // Never disturb layout mid-stroke
            let st = canvas.drawingGestureRecognizer.state
            guard st != .began && st != .changed else { return }

            let liveWidth = canvas.bounds.width > 100 ? canvas.bounds.width : requestedWidth
            guard liveWidth > 100 else { return }

            let scale = max(1.0, canvas.zoomScale)
            if scale > 1.01 && abs(lastAppliedWidth - liveWidth) <= 0.5 {
                syncChildTransforms(scale: scale)
                return
            }

            let fitting = bgHost.sizeThatFits(in: CGSize(width: liveWidth, height: .greatestFiniteMagnitude))
            let verseBottom = (viewModel.currentVerseFrames.values.map(\.maxY).max() ?? 0) + 180
            let targetHeight = max(fitting.height, verseBottom, canvas.bounds.height, 900)

            let desiredContentSize = CGSize(width: liveWidth * scale, height: targetHeight * scale)
            let frameChanged = abs(lastAppliedWidth - liveWidth) > 0.5 || abs(lastAppliedHeight - targetHeight) > 2
            let contentSizeDrifted = abs(canvas.contentSize.width - desiredContentSize.width) > 1 || abs(canvas.contentSize.height - desiredContentSize.height) > 1

            if frameChanged {
                bgHost.view.transform = .identity
                bgHost.view.frame = CGRect(x: 0, y: 0, width: liveWidth, height: targetHeight)

                ovContainer.transform = .identity
                ovContainer.frame = CGRect(x: 0, y: 0, width: liveWidth, height: targetHeight)
                ovHost?.view.frame = ovContainer.bounds

                // Keep bgHost behind PencilKit's ink layer and ovContainer above it
                if canvas.subviews.first !== bgHost.view {
                    canvas.sendSubviewToBack(bgHost.view)
                }
                if canvas.subviews.last !== ovContainer {
                    canvas.bringSubviewToFront(ovContainer)
                }

                syncChildTransforms(scale: scale)

                lastAppliedWidth = liveWidth
                lastAppliedHeight = targetHeight
            }
            if frameChanged || contentSizeDrifted {
                canvas.contentSize = desiredContentSize
            }
            canvas.showsHorizontalScrollIndicator = scale > 1.01
        }

        private func syncChildTransforms(scale: CGFloat) {
            guard let bgHost, let ovContainer else { return }
            let tf = scale <= 1.001 ? CGAffineTransform.identity : CGAffineTransform(scaleX: scale, y: scale)
            bgHost.view.transform = tf
            bgHost.view.frame.origin = .zero
            ovContainer.transform = tf
            ovContainer.frame.origin = .zero
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

        public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isUserZooming = true
        }

        public func scrollViewDidZoom(_ scrollView: UIScrollView) {
            syncChildTransforms(scale: max(1.0, scrollView.zoomScale))
            scrollView.showsHorizontalScrollIndicator = scrollView.zoomScale > 1.01
        }

        public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isUserZooming = false
            syncChildTransforms(scale: max(1.0, scale))
            scrollView.showsHorizontalScrollIndicator = scale > 1.01
            Task { @MainActor in
                if abs(self.viewModel.journalZoomScale - scale) > 0.02 {
                    self.viewModel.journalZoomScale = scale
                }
            }
        }
    }
}

/// Viewport-sized PKCanvasView subclass with finger tap forwarding and edit-menu suppression.
public final class ViewportPKCanvasView: PKCanvasView {
    public var onFingerTap: ((CGPoint) -> Void)?
    public var onLayout: (() -> Void)?
    public var onAttachToWindow: (() -> Void)?
    private var fingerTapRecognizer: UITapGestureRecognizer?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }

    private func setupGestures() {
        let fingerTap = UITapGestureRecognizer(target: self, action: #selector(handleFingerTap(_:)))
        fingerTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        fingerTap.cancelsTouchesInView = false
        addGestureRecognizer(fingerTap)
        self.fingerTapRecognizer = fingerTap
        suppressEditMenu()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onAttachToWindow?()
            suppressEditMenu()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
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

    private func suppressEditMenu() {
        guard !(tool is PKLassoTool) else { return }
        var stack: [UIView] = [self]
        while let v = stack.popLast() {
            for interaction in v.interactions {
                let name = String(describing: type(of: interaction))
                if interaction is UIEditMenuInteraction || name.contains("EditMenu") || name.contains("Selection") {
                    v.removeInteraction(interaction)
                }
            }
            for gr in v.gestureRecognizers ?? [] {
                if gr === drawingGestureRecognizer || gr === fingerTapRecognizer || gr === panGestureRecognizer || gr === pinchGestureRecognizer { continue }
                let name = String(describing: type(of: gr))
                if gr is UITapGestureRecognizer || gr is UILongPressGestureRecognizer || name.contains("Selection") || name.contains("EditMenu") {
                    gr.isEnabled = false
                }
            }
            stack.append(contentsOf: v.subviews)
        }
    }

    @objc private func handleFingerTap(_ recognizer: UITapGestureRecognizer) {
        guard drawingPolicy == .pencilOnly else { return }
        let ptInCanvas = recognizer.location(in: self)
        // Convert scrolled/zoomed point into unscaled 1x UnifiedCanvasSpace coordinates
        let scale = max(1.0, zoomScale)
        let unscaled = CGPoint(x: ptInCanvas.x / scale, y: ptInCanvas.y / scale)
        onFingerTap?(unscaled)
    }
}

/// Transparent container that lets empty-area touches (and ALL Apple Pencil touches) pass through to PKCanvasView,
/// while still allowing fingers to tap & drag Pinned Chips, Clip Cards, Study Links, and Stickers.
public final class CardPassthroughContainer: UIView {
    weak var hostedRootView: UIView?

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01 else { return nil }
        guard let hit = super.hitTest(point, with: event) else { return nil }
        if hit === self || hit === hostedRootView {
            return nil
        }
        return hit
    }
}
