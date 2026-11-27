import SwiftUI
import UIKit

private final class LayoutNotifyingScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    var onAttachToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onAttachToWindow?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// Native UIScrollView + UIHostingController container that provides:
/// - Smooth two-finger pinch-to-zoom (1.0x to 3.5x) AND programmatic zoom controls
/// - Finger-only panning/scrolling so Apple Pencil strokes go exclusively to PKCanvasView
/// - Crisp vector PencilKit coordinate preservation across zoom levels and panel toggles
public struct ZoomableCanvasScrollView<Content: View>: UIViewRepresentable {
    @Binding var zoomScale: CGFloat
    let contentWidth: CGFloat
    let content: Content

    public init(zoomScale: Binding<CGFloat>, contentWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self._zoomScale = zoomScale
        self.contentWidth = contentWidth
        self.content = content()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(zoomScale: $zoomScale)
    }

    public func makeUIView(context: Context) -> UIScrollView {
        let scrollView = LayoutNotifyingScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.5
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = false
        // Finger-only pan & pinch so Palm + Apple Pencil NEVER triggers pinch-to-zoom or scroll while writing!
        let directOnly = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.panGestureRecognizer.allowedTouchTypes = directOnly
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = directOnly

        let zoomContainer = UIView()
        zoomContainer.backgroundColor = .clear
        zoomContainer.translatesAutoresizingMaskIntoConstraints = true
        scrollView.addSubview(zoomContainer)

        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        host.sizingOptions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        zoomContainer.addSubview(host.view)

        context.coordinator.zoomContainer = zoomContainer
        context.coordinator.hostingController = host
        context.coordinator.scrollView = scrollView
        context.coordinator.requestedWidth = contentWidth

        scrollView.onAttachToWindow = { [weak coordinator = context.coordinator] in
            coordinator?.attachHostToNearestViewControllerIfNeeded()
        }
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.relayoutIfNeeded()
        }

        context.coordinator.relayoutIfNeeded()
        return scrollView
    }

    public func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = content
        context.coordinator.requestedWidth = contentWidth
        context.coordinator.relayoutIfNeeded()

        if abs(scrollView.zoomScale - zoomScale) > 0.02 && !context.coordinator.isUserZooming {
            scrollView.setZoomScale(zoomScale, animated: true)
            if zoomScale > 1.05 {
                let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
                let targetX = min(maxOffsetX, maxOffsetX * 0.85)
                scrollView.setContentOffset(CGPoint(x: targetX, y: scrollView.contentOffset.y), animated: true)
            } else {
                scrollView.setContentOffset(CGPoint(x: 0, y: scrollView.contentOffset.y), animated: true)
            }
        }
    }

    public final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var zoomScale: CGFloat
        var zoomContainer: UIView?
        var hostingController: UIHostingController<Content>?
        weak var scrollView: UIScrollView?
        var isUserZooming: Bool = false
        var requestedWidth: CGFloat = 0
        private var lastAppliedWidth: CGFloat = 0
        private var lastAppliedHeight: CGFloat = 0

        init(zoomScale: Binding<CGFloat>) {
            self._zoomScale = zoomScale
        }

        func attachHostToNearestViewControllerIfNeeded() {
            guard let host = hostingController, host.parent == nil, let scrollView else { return }
            var responder: UIResponder? = scrollView.next
            while let r = responder {
                if let vc = r as? UIViewController {
                    vc.addChild(host)
                    host.didMove(toParent: vc)
                    break
                }
                responder = r.next
            }
        }

        func relayoutIfNeeded() {
            guard let host = hostingController, let container = zoomContainer, let scrollView, !isUserZooming else { return }
            let liveWidth = scrollView.bounds.width > 100 ? scrollView.bounds.width : requestedWidth
            guard liveWidth > 100 else { return }

            let currentScale = scrollView.zoomScale
            // While zoomed in (> 1.01x), let UIScrollView own container's transform & frame
            // unless the viewport width itself changed (e.g. panel toggle or rotation).
            if currentScale > 1.01 && abs(lastAppliedWidth - liveWidth) <= 0.5 {
                scrollView.showsHorizontalScrollIndicator = true
                return
            }

            let fitting = host.sizeThatFits(in: CGSize(width: liveWidth, height: .greatestFiniteMagnitude))
            let targetHeight = max(fitting.height, scrollView.bounds.height, 900)

            if abs(lastAppliedWidth - liveWidth) > 0.5 || abs(lastAppliedHeight - targetHeight) > 2 {
                container.transform = .identity
                container.frame = CGRect(x: 0, y: 0, width: liveWidth, height: targetHeight)
                host.view.frame = container.bounds
                if currentScale > 1.01 {
                    container.transform = CGAffineTransform(scaleX: currentScale, y: currentScale)
                    container.frame.origin = .zero
                }
                scrollView.contentSize = CGSize(
                    width: currentScale <= 1.01 ? liveWidth : liveWidth * currentScale,
                    height: targetHeight * currentScale
                )
                if currentScale <= 1.01 && scrollView.contentOffset.x != 0 {
                    scrollView.contentOffset.x = 0
                }
                lastAppliedWidth = liveWidth
                lastAppliedHeight = targetHeight
            }
            scrollView.showsHorizontalScrollIndicator = currentScale > 1.01
        }

        public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            zoomContainer
        }

        public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isUserZooming = true
        }

        public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isUserZooming = false
            scrollView.showsHorizontalScrollIndicator = scale > 1.01
            if scale <= 1.01 {
                scrollView.contentOffset.x = 0
            }
            Task { @MainActor in
                if abs(self.zoomScale - scale) > 0.02 {
                    self.zoomScale = scale
                }
            }
        }
    }
}
