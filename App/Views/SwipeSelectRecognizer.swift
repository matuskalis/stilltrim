import CleanupCore
import SwiftUI
import UIKit

/// Lets a finger swipe that starts sideways on a photo select the photos it crosses, like the Photos app, and leaves
/// every other drag to the list. A SwiftUI `DragGesture` on the grid, even as a simultaneous gesture, stops the list
/// from scrolling (measured on iOS 26.1, 1 Oct 2026), so this is a UIKit pan recognizer on the list's scroll view.
/// The list's own pan waits for it to fail, which it does at once for a drag that starts more down than across or
/// off a photo. Once it begins, the touches of the buttons under it are cancelled, so a swipe never also taps.
/// A finger near the top or bottom edge scrolls the list on, also while it is still, like the Photos app.
/// Points are in the space the photos report their frames in: the scroll view's content area, with the scroll
/// offset and the top safe area taken out.
struct SwipeSelectRecognizer: UIViewRepresentable {
    /// Whether a swipe that starts at this point selects (a photo is under it).
    let canBegin: (CGPoint) -> Bool
    /// The point the swipe started at, then where the finger is now.
    let began: (CGPoint, CGPoint) -> Void
    let moved: (CGPoint) -> Void
    let ended: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.handlers = self
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    /// Sits in the grid's background, which puts it inside the scroll view, and hands that scroll view over.
    private final class InstallerView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
            coordinator?.install(on: ancestor as? UIScrollView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var handlers: SwipeSelectRecognizer?
        private weak var scrollView: UIScrollView?
        private let pan = TouchDownPan()
        private var displayLink: CADisplayLink?
        private var lastTick: CFTimeInterval = 0

        override init() {
            super.init()
            pan.addTarget(self, action: #selector(panned))
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
        }

        func install(on scrollView: UIScrollView?) {
            guard let scrollView, scrollView !== self.scrollView else { return }
            uninstall()
            scrollView.addGestureRecognizer(pan)
            scrollView.panGestureRecognizer.require(toFail: pan)
            self.scrollView = scrollView
        }

        func uninstall() {
            stopAutoScroll()
            scrollView?.removeGestureRecognizer(pan)
            scrollView = nil
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView, let handlers else { return false }
            let velocity = pan.velocity(in: scrollView)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            return handlers.canBegin(placed(pan.touchDown, in: scrollView))
        }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView, let handlers else { return }
            let location = placed(recognizer.location(in: scrollView), in: scrollView)
            switch recognizer.state {
            case .began:
                handlers.began(placed(pan.touchDown, in: scrollView), location)
                startAutoScroll()
            case .changed:
                handlers.moved(location)
            case .ended, .cancelled, .failed:
                stopAutoScroll()
                handlers.ended()
            default: break
            }
        }

        private func startAutoScroll() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(autoScroll))
            lastTick = CACurrentMediaTime()
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopAutoScroll() {
            displayLink?.invalidate()
            displayLink = nil
        }

        /// Moves the list while the finger is in an edge zone, then re-reads the photo under the finger: the photos
        /// moved, the finger did not.
        @objc private func autoScroll(_ link: CADisplayLink) {
            guard let scrollView, let handlers else { return stopAutoScroll() }
            let elapsed = min(max(link.timestamp - lastTick, 0), 0.05)
            lastTick = link.timestamp
            let inset = scrollView.adjustedContentInset
            let fingerY = pan.location(in: scrollView).y - scrollView.contentOffset.y
            let speed = EdgeScroll.velocity(y: fingerY, top: inset.top, bottom: scrollView.bounds.height - inset.bottom)
            let lowest = -inset.top
            let highest = max(scrollView.contentSize.height - scrollView.bounds.height + inset.bottom, lowest)
            let target = min(max(scrollView.contentOffset.y + speed * elapsed, lowest), highest)
            guard speed != 0, target != scrollView.contentOffset.y else { return }
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: false)
            handlers.moved(placed(pan.location(in: scrollView), in: scrollView))
        }

        /// A point of the scroll view's bounds in the space the photos report their frames in.
        private func placed(_ point: CGPoint, in scrollView: UIScrollView) -> CGPoint {
            let inset = scrollView.adjustedContentInset
            return CGPoint(
                x: point.x - scrollView.contentOffset.x - inset.left,
                y: point.y - scrollView.contentOffset.y - inset.top)
        }
    }
}

/// A pan recognizer that remembers where the touch went down, before the movement that starts the pan.
private final class TouchDownPan: UIPanGestureRecognizer {
    private(set) var touchDown = CGPoint.zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view { touchDown = touch.location(in: view) }
        super.touchesBegan(touches, with: event)
    }
}
