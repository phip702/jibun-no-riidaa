//
//  ZoomableModifier.swift
//  riidaa
//
//  https://github.com/ryohey/Zoomable
//


#if os(iOS)

import SwiftUI

struct ZoomableModifier: ViewModifier {
    let minZoomScale: CGFloat
    let doubleTapZoomScale: CGFloat
    var onInteraction: (() -> Void)?

    @State private var lastTransform: CGAffineTransform = .identity
    @State private var transform: CGAffineTransform = .identity
    @State private var contentSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background(alignment: .topLeading) {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            contentSize = proxy.size
                        }
                }
            }
            .animatableTransformEffect(transform)
            .gesture(dragGesture, including: transform == .identity ? .subviews : .all)
            .modify { view in
                if #available(iOS 17.0, *) {
                    view.gesture(magnificationGesture)
                } else {
                    view.gesture(oldMagnificationGesture)
                }
            }
            .gesture(doubleTapGesture)
    }

    @available(iOS, introduced: 16.0, deprecated: 17.0)
    private var oldMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                onInteraction?()
                let zoomFactor = 0.5
                let scale = value * zoomFactor
                transform = lastTransform.scaledBy(x: scale, y: scale)
            }
            .onEnded { _ in
                onEndGesture()
            }
    }

    @available(iOS 17.0, *)
    private var magnificationGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                onInteraction?()
                let newTransform = CGAffineTransform.anchoredScale(
                    scale: value.magnification,
                    anchor: value.startAnchor.scaledBy(contentSize)
                )

                withAnimation(.interactiveSpring) {
                    transform = lastTransform.concatenating(newTransform)
                }
            }
            .onEnded { _ in
                onEndGesture()
            }
    }

    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                onInteraction?()
                guard contentSize.width > 0, contentSize.height > 0 else { return }

                if transform.isIdentity {
                    let anchor = value.location
                    let scale = doubleTapZoomScale
                    let viewportCenter = CGPoint(x: contentSize.width / 2, y: contentSize.height / 2)

                    // Scale, then translate so the double-tapped point lands at screen center.
                    var newTransform = CGAffineTransform(
                        a: scale, b: 0,
                        c: 0, d: scale,
                        tx: viewportCenter.x - anchor.x * scale,
                        ty: viewportCenter.y - anchor.y * scale
                    )
                    newTransform = limitTransform(newTransform)

                    withAnimation(.linear(duration: 0.15)) {
                        transform = newTransform
                        lastTransform = newTransform
                    }
                } else {
                    withAnimation(.linear(duration: 0.15)) {
                        transform = .identity
                        lastTransform = .identity
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                onInteraction?()
                withAnimation(.interactiveSpring) {
                    transform = lastTransform.translatedBy(
                        x: value.translation.width / transform.scaleX,
                        y: value.translation.height / transform.scaleY
                    )
                }
            }
            .onEnded { _ in
                onEndGesture()
            }
    }

    private func onEndGesture() {
        let newTransform = limitTransform(transform)

        withAnimation(.snappy(duration: 0.1)) {
            transform = newTransform
            lastTransform = newTransform
        }
    }

    private func limitTransform(_ transform: CGAffineTransform) -> CGAffineTransform {
        let scaleX = transform.scaleX
        let scaleY = transform.scaleY

        if scaleX < minZoomScale
            || scaleY < minZoomScale
        {
            return .identity
        }

        let maxX = contentSize.width * (scaleX - 1)
        let maxY = contentSize.height * (scaleY - 1)

        if transform.tx > 0
            || transform.tx < -maxX
            || transform.ty > 0
            || transform.ty < -maxY
        {
            let tx = min(max(transform.tx, -maxX), 0)
            let ty = min(max(transform.ty, -maxY), 0)
            var transform = transform
            transform.tx = tx
            transform.ty = ty
            return transform
        }

        return transform
    }
}

public extension View {
    @ViewBuilder
    func zoomable(
        minZoomScale: CGFloat = 1,
        doubleTapZoomScale: CGFloat = 2,
        onInteraction: (() -> Void)? = nil
    ) -> some View {
        modifier(ZoomableModifier(
            minZoomScale: minZoomScale,
            doubleTapZoomScale: doubleTapZoomScale,
            onInteraction: onInteraction
        ))
    }

//    @ViewBuilder
//    func zoomable(
//        minZoomScale: CGFloat = 1,
//        doubleTapZoomScale: CGFloat = 3,
//        outOfBoundsColor: Color = .clear
//    ) -> some View {
//        GeometryReader { proxy in
//            ZStack {
//                outOfBoundsColor
//                self.zoomable(
//                    minZoomScale: minZoomScale,
//                    doubleTapZoomScale: doubleTapZoomScale
//                )
//            }
//        }
//    }
}

private extension View {
    @ViewBuilder
    func modify(@ViewBuilder _ fn: (Self) -> some View) -> some View {
        fn(self)
    }

    @ViewBuilder
    func animatableTransformEffect(_ transform: CGAffineTransform) -> some View {
        scaleEffect(
            x: transform.scaleX,
            y: transform.scaleY,
            anchor: .zero
        )
        .offset(x: transform.tx, y: transform.ty)
    }
}

private extension UnitPoint {
    func scaledBy(_ size: CGSize) -> CGPoint {
        .init(
            x: x * size.width,
            y: y * size.height
        )
    }
}

private extension CGAffineTransform {
    static func anchoredScale(scale: CGFloat, anchor: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: anchor.x, y: anchor.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -anchor.x, y: -anchor.y)
    }

    var scaleX: CGFloat {
        sqrt(a * a + c * c)
    }

    var scaleY: CGFloat {
        sqrt(b * b + d * d)
    }
}

#endif
