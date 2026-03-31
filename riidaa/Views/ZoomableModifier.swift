//
//  ZoomableModifier.swift
//  riidaa
//
//  UIKit gesture recognizers for simultaneous pinch + pan (Google Maps style)
//


#if os(iOS)

import SwiftUI
import UIKit

// MARK: - SwiftUI Modifier (public API unchanged)

struct ZoomableModifier: ViewModifier {
    let minZoomScale: CGFloat
    let doubleTapZoomScale: CGFloat
    var onInteraction: (() -> Void)?

    @State private var currentScale: CGFloat = 1
    @State private var currentOffset: CGSize = .zero
    @State private var contentSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background(alignment: .topLeading) {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentSize = proxy.size }
                        .onChange(of: proxy.size) { contentSize = $0 }
                }
            }
            .scaleEffect(currentScale, anchor: .zero)
            .offset(currentOffset)
            .clipped()
            // UIKit overlay handles all gestures: pinch, two-finger pan, single-finger pan (when zoomed), double-tap
            .overlay {
                ZoomPanGestureOverlay(
                    currentScale: $currentScale,
                    currentOffset: $currentOffset,
                    contentSize: $contentSize,
                    minZoomScale: minZoomScale,
                    doubleTapZoomScale: doubleTapZoomScale,
                    onInteraction: onInteraction
                )
            }
    }

    // MARK: - Double-tap to toggle zoom (removed — handled by UIKit overlay)

    private func clampOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
        let maxX = contentSize.width * (scale - 1)
        let maxY = contentSize.height * (scale - 1)
        return CGSize(
            width: min(max(offset.width, -maxX), 0),
            height: min(max(offset.height, -maxY), 0)
        )
    }
}

// MARK: - UIKit Gesture Overlay

private struct ZoomPanGestureOverlay: UIViewRepresentable {
    @Binding var currentScale: CGFloat
    @Binding var currentOffset: CGSize
    @Binding var contentSize: CGSize
    let minZoomScale: CGFloat
    let doubleTapZoomScale: CGFloat
    var onInteraction: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let twoFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = context.coordinator

        let oneFingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleOneFingerPan(_:)))
        oneFingerPan.minimumNumberOfTouches = 1
        oneFingerPan.maximumNumberOfTouches = 1
        oneFingerPan.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2

        // Store references so we can identify our own recognizers
        context.coordinator.pinchRecognizer = pinch
        context.coordinator.twoFingerPanRecognizer = twoFingerPan
        context.coordinator.oneFingerPanRecognizer = oneFingerPan

        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(twoFingerPan)
        view.addGestureRecognizer(oneFingerPan)
        view.addGestureRecognizer(doubleTap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: - Coordinator (UIKit gesture handling)

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ZoomPanGestureOverlay

        // References to our own recognizers
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var twoFingerPanRecognizer: UIPanGestureRecognizer?
        weak var oneFingerPanRecognizer: UIPanGestureRecognizer?

        // State at gesture start
        private var startScale: CGFloat = 1
        private var startOffset: CGSize = .zero
        private var pinchAnchor: CGPoint? = nil

        init(parent: ZoomPanGestureOverlay) {
            self.parent = parent
        }

        // Only allow OUR pinch and two-finger pan to work simultaneously with each other.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let isPinchOrTwoFingerPan = gestureRecognizer === pinchRecognizer || gestureRecognizer === twoFingerPanRecognizer
            let otherIsPinchOrTwoFingerPan = otherGestureRecognizer === pinchRecognizer || otherGestureRecognizer === twoFingerPanRecognizer
            return isPinchOrTwoFingerPan && otherIsPinchOrTwoFingerPan
        }

        // Single-finger pan only begins when zoomed in; otherwise it fails
        // and the touch passes through to TabView for page turning.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === oneFingerPanRecognizer {
                return parent.currentScale > parent.minZoomScale
            }
            return true
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            parent.onInteraction?()

            switch recognizer.state {
            case .began:
                startScale = parent.currentScale
                startOffset = parent.currentOffset
                // Anchor = pinch center in the view, converted to content coordinates
                let locationInView = recognizer.location(in: recognizer.view)
                pinchAnchor = CGPoint(
                    x: (locationInView.x - parent.currentOffset.width) / parent.currentScale,
                    y: (locationInView.y - parent.currentOffset.height) / parent.currentScale
                )

            case .changed:
                guard let anchor = pinchAnchor else { return }
                let newScale = startScale * recognizer.scale

                // Anchored zoom: keep anchor point fixed on screen
                let newOffset = CGSize(
                    width: startOffset.width + anchor.x * startScale * (1 - recognizer.scale),
                    height: startOffset.height + anchor.y * startScale * (1 - recognizer.scale)
                )

                parent.currentScale = max(newScale, 0.5) // Allow slight under-zoom, snap back on end
                parent.currentOffset = newOffset

            case .ended, .cancelled:
                pinchAnchor = nil
                snapIfNeeded()

            default:
                break
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            parent.onInteraction?()

            switch recognizer.state {
            case .began:
                startOffset = parent.currentOffset

            case .changed:
                let translation = recognizer.translation(in: recognizer.view)
                parent.currentOffset = CGSize(
                    width: startOffset.width + translation.x,
                    height: startOffset.height + translation.y
                )

            case .ended, .cancelled:
                snapIfNeeded()

            default:
                break
            }
        }

        @objc func handleOneFingerPan(_ recognizer: UIPanGestureRecognizer) {
            parent.onInteraction?()

            switch recognizer.state {
            case .began:
                startOffset = parent.currentOffset

            case .changed:
                let translation = recognizer.translation(in: recognizer.view)
                parent.currentOffset = CGSize(
                    width: startOffset.width + translation.x,
                    height: startOffset.height + translation.y
                )

            case .ended, .cancelled:
                snapIfNeeded()

            default:
                break
            }
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            parent.onInteraction?()
            let location = recognizer.location(in: recognizer.view)

            if parent.currentScale > parent.minZoomScale {
                withAnimation(.linear(duration: 0.15)) {
                    parent.currentScale = 1
                    parent.currentOffset = .zero
                }
            } else {
                // Convert tap location to content coordinates
                let contentX = (location.x - parent.currentOffset.width) / parent.currentScale
                let contentY = (location.y - parent.currentOffset.height) / parent.currentScale
                let s = parent.doubleTapZoomScale

                // Center the tapped content point in the viewport, then clamp to bounds
                let viewCenter = CGPoint(
                    x: parent.contentSize.width / 2,
                    y: parent.contentSize.height / 2
                )
                let newOffset = CGSize(
                    width: viewCenter.x - contentX * s,
                    height: viewCenter.y - contentY * s
                )
                let maxX = parent.contentSize.width * (s - 1)
                let maxY = parent.contentSize.height * (s - 1)
                let clampedOffset = CGSize(
                    width: min(max(newOffset.width, -maxX), 0),
                    height: min(max(newOffset.height, -maxY), 0)
                )
                withAnimation(.linear(duration: 0.15)) {
                    parent.currentScale = s
                    parent.currentOffset = clampedOffset
                }
            }
        }

        private func snapIfNeeded() {
            let scale = parent.currentScale
            let offset = parent.currentOffset
            let contentSize = parent.contentSize
            let minScale = parent.minZoomScale

            if scale < minScale {
                withAnimation(.snappy(duration: 0.1)) {
                    parent.currentScale = 1
                    parent.currentOffset = .zero
                }
            } else {
                let maxX = contentSize.width * (scale - 1)
                let maxY = contentSize.height * (scale - 1)
                let clampedOffset = CGSize(
                    width: min(max(offset.width, -maxX), 0),
                    height: min(max(offset.height, -maxY), 0)
                )
                if clampedOffset != offset {
                    withAnimation(.snappy(duration: 0.1)) {
                        parent.currentOffset = clampedOffset
                    }
                }
            }
        }
    }
}

// MARK: - Public extension

public extension View {
    @ViewBuilder
    func zoomable(
        minZoomScale: CGFloat = 1,
        doubleTapZoomScale: CGFloat = 2.5,
        onInteraction: (() -> Void)? = nil
    ) -> some View {
        modifier(ZoomableModifier(
            minZoomScale: minZoomScale,
            doubleTapZoomScale: doubleTapZoomScale,
            onInteraction: onInteraction
        ))
    }
}

#endif
