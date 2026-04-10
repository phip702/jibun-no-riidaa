//
//  MangaPageView.swift
//  riidaa
//

#if os(iOS)
import UIKit

// MARK: - 1a. PageTransformState

/// Tracks the current scale and translation applied to the content view.
/// Translation is expressed as an offset from the view's center, so (0, 0)
/// means the content is perfectly centered.
struct PageTransformState {
    var scale: CGFloat
    var translation: CGPoint

    static let minScale: CGFloat = 1.0
    static let maxScale: CGFloat = 6.0
    static let doubleTapScale: CGFloat = 2.5

    static let identity = PageTransformState(scale: 1.0, translation: .zero)

    var isIdentity: Bool {
        scale == 1.0 && translation == .zero
    }

    init(scale: CGFloat = 1.0, translation: CGPoint = .zero) {
        self.scale = scale
        self.translation = translation
    }
}

// MARK: - 1b. TransformClamping

/// Pure static functions for computing valid transform states.
/// No UIKit dependencies — easy to unit-test.
enum TransformClamping {

    /// Clamps scale to [minScale, maxScale] and translation so the scaled
    /// content never reveals empty space beyond its edges.
    /// At minScale, forces translation to .zero (content stays centered).
    static func clamp(
        _ state: PageTransformState,
        contentSize: CGSize,
        viewSize: CGSize,
        bottomInset: CGFloat = 0
    ) -> PageTransformState {
        let s = min(max(state.scale, PageTransformState.minScale), PageTransformState.maxScale)

        // At minimum scale keep the content centered with no translation.
        guard s > PageTransformState.minScale else {
            return PageTransformState(scale: PageTransformState.minScale, translation: .zero)
        }

        // Maximum distance the center of a scaled content view can shift before
        // empty space appears on either side.
        let slackX = max(0, (contentSize.width  * s - viewSize.width)  / 2)
        let slackY = max(0, (contentSize.height * s - viewSize.height) / 2)

        let tx = min(max(state.translation.x, -slackX), slackX)
        // The image is laid out centered within (viewSize.height - bottomInset), so its
        // visual center sits s * bottomInset/2 above view.bounds.midY when scaled.
        // Allow extra positive-ty travel so the user can scroll the image top to y=0.
        let tyMax = slackY + s * bottomInset / 2
        let ty = min(max(state.translation.y, -slackY), tyMax)

        return PageTransformState(scale: s, translation: CGPoint(x: tx, y: ty))
    }

    /// Computes a new transform state after a scale change with a fixed focal point.
    ///
    /// Uses the Google-Maps focal-point formula:
    ///   F     = focalPoint - viewCenter          (focal offset from view center)
    ///   T_new = F - (F - T_old) * (s_new / s_old)
    ///
    /// This ensures the screen coordinate under `focalPoint` (e.g. the midpoint
    /// between two fingers) does not move as the scale changes.
    static func applyScale(
        newScale: CGFloat,
        focalPoint: CGPoint,
        viewCenter: CGPoint,
        currentState: PageTransformState,
        contentSize: CGSize,
        viewSize: CGSize,
        bottomInset: CGFloat = 0
    ) -> PageTransformState {
        let s_old = currentState.scale
        guard s_old > 0 else { return currentState }

        let s_new = min(max(newScale, PageTransformState.minScale), PageTransformState.maxScale)
        let ratio = s_new / s_old

        // Focal offset from the view's center point.
        let fx = focalPoint.x - viewCenter.x
        let fy = focalPoint.y - viewCenter.y

        let tx = fx - (fx - currentState.translation.x) * ratio
        let ty = fy - (fy - currentState.translation.y) * ratio

        let proposed = PageTransformState(scale: s_new, translation: CGPoint(x: tx, y: ty))
        return clamp(proposed, contentSize: contentSize, viewSize: viewSize, bottomInset: bottomInset)
    }
}

// MARK: - 1c. PageBoxOverlayView

/// Transparent UIView placed over a text box in image coordinates.
/// Handles its own tap and long-press gesture recognizers so hit testing
/// works naturally after any CGAffineTransform applied to the parent contentView.
final class PageBoxOverlayView: UIView {

    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.25
        addGestureRecognizer(longPress)
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began else { return }
        onLongPress?()
    }
}

// MARK: - 1d. MangaPageViewController

/// One page of the manga reader.
///
/// View hierarchy (all added in viewDidLoad):
///   view          — full bounds, owns all gesture recognizers
///   └── contentView  — receives CGAffineTransform + center offset for zoom/pan
///       ├── imageView   — UIImageView, aspect-fit sized and centered
///       └── [PageBoxOverlayView] × N  — text-box hit areas in contentView coords
///
/// Because the box overlays are subviews of contentView, UIKit automatically
/// transforms their hit-test rects along with the content — no manual coordinate
/// remapping is required at tap time.
final class MangaPageViewController: UIViewController, UIGestureRecognizerDelegate {

    // MARK: Callbacks (set by container before configure is called)

    /// Called when the zoom level crosses the identity threshold.
    /// Container uses this to gate UIPageViewController paging.
    var onZoomChanged: ((Bool) -> Void)?

    var onLineTapped: ((String) -> Void)?
    var onLineTranslate: ((String) -> Void)?
    var onInteraction: (() -> Void)?
    var onBackgroundTap: (() -> Void)?

    /// Bottom inset in points — keeps the image above the floating parser sheet.
    var bottomInset: CGFloat = 0

    // MARK: Style properties (applied during rebuildBoxOverlays / rebuildBoxStyles)

    var showBoxBackground: Bool = false
    var boxBackgroundColor: UIColor = .clear
    var showBoxBorder: Bool = false
    var boxBorderColor: UIColor = .clear
    var boxBorderWidth: CGFloat = 1.0
    var boxPadding: CGFloat = 0.0

    // MARK: Private state

    private let contentView = UIView()
    private let imageView   = UIImageView()

    /// The size of the aspect-fit image rect inside contentView at scale 1.
    /// Used by TransformClamping to compute slack.
    private var contentSize: CGSize = .zero

    /// Live transform state — updated on every gesture change.
    private var transformState = PageTransformState.identity

    /// Snapshots taken at the start of each gesture so deltas can be applied cleanly.
    private var pinchStartState = PageTransformState.identity
    private var panStartState   = PageTransformState.identity

    /// Tracks the pan translation seen in the previous .changed event so we can apply
    /// incremental deltas rather than absolute-from-start deltas.  Using incrementals
    /// makes simultaneous pinch + pan compose correctly (pinch moves the base state
    /// that panStartState captured, so absolute deltas invert the direction).
    private var lastPanTranslation: CGPoint = .zero

    /// Centroid of the two fingers at the moment the pinch gesture began.
    /// Used as the fixed scale anchor so that finger translation adds directly
    /// to the content offset in the same direction as a single-finger pan.
    private var pinchStartCentroid: CGPoint = .zero

    /// Whether we have already fired onZoomChanged(true) for the current zoom session.
    private var reportedZoomed = false

    /// Boxes for the current page, stored so layoutContent() can reposition them
    /// after viewDidLayoutSubviews fires with the final correct bounds.
    private var currentBoxes: [PageBoxModel] = []

    // Gesture recognizers stored as properties so the delegate can identify them.
    private var pinchGR:         UIPinchGestureRecognizer!
    private var panGR:           UIPanGestureRecognizer!
    private var doubleTapGR:     UITapGestureRecognizer!
    private var backgroundTapGR: UITapGestureRecognizer!

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds   = true

        // contentView fills the frame; its transform provides zoom/pan.
        contentView.frame = view.bounds
        contentView.autoresizingMask = []   // managed manually in layoutContent
        contentView.backgroundColor = .clear
        view.addSubview(contentView)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)

        setupGestureRecognizers()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Don't reset contentView.transform mid-gesture — doing so causes a visible snap
        // (the "zoom stops" bug).  Layout will re-run once the gesture ends.
        let gestureActive = (pinchGR?.state == .began || pinchGR?.state == .changed)
                         || (panGR?.state  == .began || panGR?.state  == .changed)
        guard !gestureActive else { return }
        layoutContent()
    }

    // MARK: - Gesture recognizer setup

    private func setupGestureRecognizers() {
        // Pinch — zoom with centroid focal point
        pinchGR = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGR.delegate = self
        view.addGestureRecognizer(pinchGR)

        // Pan — pan when zoomed; no-op at scale 1 (UIPageViewController owns that swipe)
        panGR = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGR.minimumNumberOfTouches = 1
        panGR.maximumNumberOfTouches = 2
        panGR.delegate = self
        view.addGestureRecognizer(panGR)

        // Double-tap — zoom toggle
        doubleTapGR = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGR.numberOfTapsRequired = 2
        doubleTapGR.delegate = self
        view.addGestureRecognizer(doubleTapGR)

        // Single tap on background — dismiss popup/parser
        backgroundTapGR = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        backgroundTapGR.numberOfTapsRequired = 1
        backgroundTapGR.require(toFail: doubleTapGR)
        backgroundTapGR.delegate = self
        view.addGestureRecognizer(backgroundTapGR)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // At scale 1, let UIPageViewController's scroll view own horizontal swipes.
        // If panGR began here and then no-op'd in handlePan, it would have already
        // consumed the touch, preventing UIPageViewController from seeing the swipe.
        if gestureRecognizer === panGR {
            return transformState.scale > 1.01
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // Allow pinch and pan to fire together so the user can zoom and reposition
        // in one fluid motion.
        let pair: Set<UIGestureRecognizer> = [pinchGR, panGR]
        return pair.contains(gestureRecognizer) && pair.contains(other)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // Prevent the background tap from double-firing when the user taps a box.
        // The box's own UITapGestureRecognizer handles the event instead.
        guard gestureRecognizer === backgroundTapGR else { return true }
        let point = touch.location(in: view)
        for overlay in contentView.subviews.compactMap({ $0 as? PageBoxOverlayView }) {
            let frameInView = overlay.convert(overlay.bounds, to: view)
            if frameInView.contains(point) { return false }
        }
        return true
    }

    // MARK: - Gesture handlers

    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        switch gr.state {
        case .began:
            pinchStartState = transformState
            // Capture the two-finger centroid so .changed can use it as a fixed
            // scale anchor and compute pan translation from it.
            if gr.numberOfTouches >= 2 {
                let t0 = gr.location(ofTouch: 0, in: view)
                let t1 = gr.location(ofTouch: 1, in: view)
                pinchStartCentroid = CGPoint(x: (t0.x + t1.x) / 2, y: (t0.y + t1.y) / 2)
            }
            onInteraction?()
            // If already zoomed, disable page turns at the START of the gesture.
            // Never do this inside .changed — mutating dataSource mid-gesture causes
            // UIKit to cancel the active recogniser (the "zoom ceiling" bug).
            if transformState.scale > 1.0 { setZoomed(true) }

        case .changed:
            guard gr.numberOfTouches >= 2 else { return }
            let t0 = gr.location(ofTouch: 0, in: view)
            let t1 = gr.location(ofTouch: 1, in: view)
            let centroid = CGPoint(x: (t0.x + t1.x) / 2, y: (t0.y + t1.y) / 2)

            // Anchor the scale at the INITIAL centroid so that moving both fingers
            // together does not invert the pan direction.  The formula
            //   T_new = curr_centroid - (start_centroid - T_start) * ratio
            // ensures the content point under the start centroid ends up under the
            // current centroid — identical semantics to single-finger dragging.
            let scaleState = TransformClamping.applyScale(
                newScale: pinchStartState.scale * gr.scale,
                focalPoint: pinchStartCentroid,
                viewCenter: CGPoint(x: view.bounds.midX, y: view.bounds.midY),
                currentState: pinchStartState,
                contentSize: contentSize,
                viewSize: view.bounds.size,
                bottomInset: bottomInset
            )
            let dx = centroid.x - pinchStartCentroid.x
            let dy = centroid.y - pinchStartCentroid.y
            let proposed = PageTransformState(
                scale: scaleState.scale,
                translation: CGPoint(
                    x: scaleState.translation.x + dx,
                    y: scaleState.translation.y + dy
                )
            )
            transformState = TransformClamping.clamp(
                proposed,
                contentSize: contentSize,
                viewSize: view.bounds.size,
                bottomInset: bottomInset
            )
            applyTransform()
            // Do NOT call setZoomed here — see .began comment above.

        case .ended, .cancelled, .failed:
            if transformState.scale < PageTransformState.minScale + 0.01 {
                animateToIdentity()
            } else {
                // Pinch ended while still zoomed — keep page turns disabled so a
                // subsequent single-finger pan isn't intercepted by UIPageViewController.
                setZoomed(true)
            }

        default:
            break
        }
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        switch gr.state {
        case .began:
            panStartState = transformState
            lastPanTranslation = .zero
            onInteraction?()

        case .changed:
            // Only pan when zoomed; at scale 1 UIPageViewController handles the swipe.
            guard transformState.scale > 1.01 else { return }
            // When pinch is active it owns all two-finger movement (scale + pan).
            // Letting panGR also fire would double-apply the centroid delta.
            guard pinchGR.state != .began && pinchGR.state != .changed else { return }
            // Incremental delta: add only what moved since the last .changed event.
            // Using absolute-from-start deltas breaks when pinch simultaneously
            // modifies transformState, making panStartState stale → wrong direction.
            let current = gr.translation(in: view)
            let delta = CGPoint(x: current.x - lastPanTranslation.x,
                                y: current.y - lastPanTranslation.y)
            lastPanTranslation = current
            // Pan sensitivity multiplier (1.0 = default). We'll expose this
            // as a variable so it can be tweaked later. Use a scale-aware
            // adjustment so drags move less when the content is zoomed in.
            let panSensitivity: CGFloat = 0.85
            // Make pan feel faster when zoomed by scaling the finger delta
            // by the current zoom level. A `panSensitivity` > 1 further
            // amplifies the movement; keep at 1.0 for a natural mapping.
            let adjustedDelta = CGPoint(
                x: delta.x * panSensitivity * transformState.scale,
                y: delta.y * panSensitivity * transformState.scale
            )

            let proposed = PageTransformState(
                scale: transformState.scale,  // preserve whatever scale pinch set
                translation: CGPoint(
                    x: transformState.translation.x + adjustedDelta.x,
                    y: transformState.translation.y + adjustedDelta.y
                )
            )
            transformState = TransformClamping.clamp(
                proposed,
                contentSize: contentSize,
                viewSize: view.bounds.size,
                bottomInset: bottomInset
            )
            applyTransform()

        case .ended, .cancelled, .failed:
            break

        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
        onInteraction?()
        if transformState.scale > 1.01 {
            animateToIdentity()
        } else {
            let tapPoint = gr.location(in: view)
            let viewCenter = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            let tapOffset = CGPoint(x: tapPoint.x - viewCenter.x, y: tapPoint.y - viewCenter.y)
            let newScale = PageTransformState.doubleTapScale
            let ratio = newScale / max(transformState.scale, 0.0001)

            // Recenter the double-tapped content point to the screen center.
            let proposed = PageTransformState(
                scale: newScale,
                translation: CGPoint(
                    x: (transformState.translation.x - tapOffset.x) * ratio,
                    y: (transformState.translation.y - tapOffset.y) * ratio
                )
            )
            let newState = TransformClamping.clamp(
                proposed,
                contentSize: contentSize,
                viewSize: view.bounds.size,
                bottomInset: bottomInset
            )
            animateTo(newState)
            setZoomed(true)
        }
    }

    @objc private func handleBackgroundTap() {
        onBackgroundTap?()
    }

    // MARK: - Transform application

    private func applyTransform(animated: Bool = false) {
        let s  = transformState.scale
        let tx = transformState.translation.x
        let ty = transformState.translation.y

        let block = {
            self.contentView.transform = CGAffineTransform(scaleX: s, y: s)
            self.contentView.center = CGPoint(
                x: self.view.bounds.midX + tx,
                y: self.view.bounds.midY + ty
            )
        }

        if animated {
            UIView.animate(withDuration: 0.2, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState],
                           animations: block)
        } else {
            block()
        }
    }

    private func animateTo(_ state: PageTransformState) {
        transformState = state
        applyTransform(animated: true)
    }

    private func animateToIdentity() {
        transformState = .identity
        applyTransform(animated: true)
        if reportedZoomed {
            reportedZoomed = false
            onZoomChanged?(false)
        }
    }

    private func setZoomed(_ isZoomed: Bool) {
        guard isZoomed != reportedZoomed else { return }
        reportedZoomed = isZoomed
        onZoomChanged?(isZoomed)
    }

    // MARK: - Layout

    private func layoutContent() {
        // Reset transform before measuring so frame math is in identity space.
        contentView.transform = .identity
        contentView.frame = view.bounds

        guard let img = imageView.image else {
            contentSize = .zero
            return
        }

        let vW = view.bounds.width
        // Subtract bottomInset so the aspect-fit image stays above the parser sheet.
        let vH = view.bounds.height - bottomInset
        let imgW = img.size.width
        let imgH = img.size.height
        guard imgW > 0, imgH > 0 else { return }

        let fitScale = min(vW / imgW, vH / imgH)
        let fittedW = imgW * fitScale
        let fittedH = imgH * fitScale

        imageView.frame = CGRect(
            x: (vW - fittedW) / 2,
            y: (vH - fittedH) / 2,
            width: fittedW,
            height: fittedH
        )
        contentSize = CGSize(width: fittedW, height: fittedH)

        // Re-clamp and reapply in case the view was resized (e.g. rotation).
        transformState = TransformClamping.clamp(
            transformState,
            contentSize: contentSize,
            viewSize: view.bounds.size,
            bottomInset: bottomInset
        )
        applyTransform()

        // Reposition box overlays using the same bounds used for imageView above.
        // This must be called here (not only in configure) because viewDidLayoutSubviews
        // fires after viewWillAppear, giving us the final correct view.bounds only here.
        if !currentBoxes.isEmpty {
            rebuildBoxOverlays(boxes: currentBoxes)
        }
    }

    // MARK: - Public configuration API

    /// Reset zoom, load the page image, and rebuild all text-box overlays.
    func configure(page: MangaPageModel, boxes: [PageBoxModel]) {
        transformState = .identity
        reportedZoomed = false
        applyTransform()

        imageView.image = page.getImage()
        currentBoxes = boxes
        // layoutContent() will call rebuildBoxOverlays(boxes: currentBoxes) at its end,
        // using the same view.bounds used to position imageView.
        layoutContent()
    }

    /// Rebuild all text-box overlay views from scratch.
    /// Called when the page changes or when the layout is finalized.
    func rebuildBoxOverlays(boxes: [PageBoxModel]) {
        currentBoxes = boxes  // keep stored copy in sync when called externally
        // Remove existing overlays.
        contentView.subviews
            .compactMap { $0 as? PageBoxOverlayView }
            .forEach { $0.removeFromSuperview() }

        guard contentSize != .zero, let img = imageView.image else { return }

        let imgW = img.size.width
        let imgH = img.size.height
        guard imgW > 0, imgH > 0 else { return }

        // Must use the same effective height as layoutContent so boxes align to the image.
        let vW = view.bounds.width
        let vH = view.bounds.height - bottomInset
        let fitScale = min(vW / imgW, vH / imgH)
        let originX = (vW - imgW * fitScale) / 2
        let originY = (vH - imgH * fitScale) / 2

        for box in boxes {
            let overlay = PageBoxOverlayView()
            let bx = CGFloat(box.x)
            let by = CGFloat(box.y)
            let bw = CGFloat(box.width)
            let bh = CGFloat(box.height)

            overlay.frame = CGRect(
                x: originX + bx * fitScale - boxPadding / 2,
                y: originY + by * fitScale - boxPadding / 2,
                width:  bw * fitScale + boxPadding,
                height: bh * fitScale + boxPadding
            )

            if box.rotation != 0 {
                overlay.transform = CGAffineTransform(rotationAngle: CGFloat(box.rotation) * .pi / 180)
            }

            applyStyle(to: overlay)

            let text = box.text
            overlay.onTap       = { [weak self] in self?.onLineTapped?(text) }
            overlay.onLongPress = { [weak self] in self?.onLineTranslate?(text) }

            contentView.addSubview(overlay)
        }
    }

    /// Update only visual style on existing overlays — no repositioning, no zoom reset.
    /// Called when the user changes box appearance settings.
    func rebuildBoxStyles() {
        for overlay in contentView.subviews.compactMap({ $0 as? PageBoxOverlayView }) {
            applyStyle(to: overlay)
        }
    }

    private func applyStyle(to overlay: PageBoxOverlayView) {
        overlay.backgroundColor          = showBoxBackground ? boxBackgroundColor : .clear
        overlay.layer.borderColor        = showBoxBorder ? boxBorderColor.cgColor : UIColor.clear.cgColor
        overlay.layer.borderWidth        = showBoxBorder ? boxBorderWidth : 0
    }
}

// MARK: - 1f. MangaReaderContainerViewController

/// Hosts a UIPageViewController with scroll-style transitions, giving the same
/// continuous side-by-side page-turn animation as the previous TabView pager.
///
/// Page turning is gated by the zoom state of the current page VC:
///   zoomed in  → pageVC.dataSource = nil   (UIPageViewController disables its swipe)
///   zoomed out → pageVC.dataSource = self  (paging re-enabled)
final class MangaReaderContainerViewController: UIViewController,
                                                UIPageViewControllerDataSource,
                                                UIPageViewControllerDelegate {

    // MARK: Configuration

    var pages: [MangaPageModel] = []
    var isLTR: Bool = true

    // Callbacks forwarded from child page VCs
    var onLineTapped:    ((String) -> Void)?
    var onLineTranslate: ((String) -> Void)?
    var onInteraction:   (() -> Void)?
    var onBackgroundTap: (() -> Void)?

    /// Bottom inset passed down to each page VC so image layout leaves room for the parser sheet.
    var bottomInset: CGFloat = 0

    // Called after a user-driven page turn animation completes
    var onPageChanged: ((Int) -> Void)?

    // Style props applied to every page VC
    var showBoxBackground: Bool     = false
    var boxBackgroundColor: UIColor = .clear
    var showBoxBorder: Bool         = false
    var boxBorderColor: UIColor     = .clear
    var boxBorderWidth: CGFloat     = 1.0
    var boxPadding: CGFloat         = 0.0

    // MARK: Private

    private(set) var pageVC = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )

    /// Current logical page index into `pages`.
    private(set) var currentIndex: Int = 0


    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        pageVC.dataSource = self
        pageVC.delegate   = self
        addChild(pageVC)
        pageVC.view.frame = view.bounds
        pageVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pageVC.view)
        pageVC.didMove(toParent: self)
        pageVC.view.clipsToBounds = true

        // UIPageViewController nests UIScrollView → UIView at least two levels deep,
        // all with white backgrounds by default. Recurse to clear them all.
        clearBackgrounds(pageVC.view)
    }

    private func clearBackgrounds(_ v: UIView) {
        v.backgroundColor = .clear
        for sub in v.subviews { clearBackgrounds(sub) }
    }

    // MARK: - Public API

    /// Jump to a page index. `animated` should be false for picker-driven changes.
    func setPage(_ index: Int, animated: Bool) {
        guard pages.indices.contains(index) else { return }
        let direction: UIPageViewController.NavigationDirection =
            index >= currentIndex ? .forward : .reverse
        currentIndex = index
        let vc = makePageVC(for: index)
        pageVC.setViewControllers([vc], direction: direction, animated: animated)
        // UIPageViewController creates its internal UIScrollView lazily on the first
        // setViewControllers call — clear backgrounds now that the scroll view exists.
        clearBackgrounds(pageVC.view)
    }

    /// Update style props on the currently visible page VC without rebuilding.
    func updateStyleOnVisiblePage() {
        guard let vc = pageVC.viewControllers?.first as? MangaPageViewController else { return }
        applyStyle(to: vc)
        vc.rebuildBoxStyles()
    }

    // MARK: - Factory

    private func makePageVC(for index: Int) -> MangaPageViewController {
        let vc = MangaPageViewController()
        vc.pageIndex = index
        applyStyle(to: vc)
        wireCallbacks(to: vc)
        // Image is loaded in viewWillAppear of MangaPageViewController (lazy).
        vc.pendingPage  = pages[index]
        vc.pendingBoxes = pages[index].getBoxes()
        return vc
    }

    private func applyStyle(to vc: MangaPageViewController) {
        vc.showBoxBackground = showBoxBackground
        vc.boxBackgroundColor = boxBackgroundColor
        vc.showBoxBorder      = showBoxBorder
        vc.boxBorderColor     = boxBorderColor
        vc.boxBorderWidth     = boxBorderWidth
        vc.boxPadding         = boxPadding
        vc.bottomInset        = bottomInset
    }

    private func wireCallbacks(to vc: MangaPageViewController) {
        vc.onLineTapped    = { [weak self] t in self?.onLineTapped?(t) }
        vc.onLineTranslate = { [weak self] t in self?.onLineTranslate?(t) }
        vc.onInteraction   = { [weak self] in self?.onInteraction?() }
        vc.onBackgroundTap = { [weak self] in self?.onBackgroundTap?() }
        vc.onZoomChanged   = { [weak self] isZoomed in
            // Set dataSource=nil/self at gesture boundaries (not mid-.changed),
            // so UIPageViewController's internal pan gesture is disabled while
            // zoomed — preventing it from intercepting single-finger pans.
            self?.pageVC.dataSource = isZoomed ? nil : self
        }
    }

    // MARK: - UIPageViewControllerDataSource

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let current = viewController as? MangaPageViewController else { return nil }
        let prevIndex = current.pageIndex - 1
        guard pages.indices.contains(prevIndex) else { return nil }
        return makePageVC(for: prevIndex)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let current = viewController as? MangaPageViewController else { return nil }
        let nextIndex = current.pageIndex + 1
        guard pages.indices.contains(nextIndex) else { return nil }
        return makePageVC(for: nextIndex)
    }

    // MARK: - UIPageViewControllerDelegate

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let vc = pageViewController.viewControllers?.first as? MangaPageViewController
        else { return }
        currentIndex = vc.pageIndex
        onPageChanged?(currentIndex)
    }
}

// MARK: - Lazy-load extension on MangaPageViewController

extension MangaPageViewController {
    /// Storage for deferred page data — set by the container, consumed in viewWillAppear.
    var pageIndex: Int {
        get { objc_getAssociatedObject(self, &Keys.index) as? Int ?? 0 }
        set { objc_setAssociatedObject(self, &Keys.index, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var pendingPage: MangaPageModel? {
        get { objc_getAssociatedObject(self, &Keys.page) as? MangaPageModel }
        set { objc_setAssociatedObject(self, &Keys.page, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var pendingBoxes: [PageBoxModel] {
        get { objc_getAssociatedObject(self, &Keys.boxes) as? [PageBoxModel] ?? [] }
        set { objc_setAssociatedObject(self, &Keys.boxes, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private enum Keys {
        static var index = "pageIndex"
        static var page  = "pendingPage"
        static var boxes = "pendingBoxes"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Load image the first time this VC becomes visible — avoids loading
        // adjacent pages that may never be shown.
        if let page = pendingPage {
            configure(page: page, boxes: pendingBoxes)
            pendingPage = nil
        }
    }
}

// MARK: - 1g. MangaReaderContainerView (SwiftUI bridge)

import SwiftUI

/// SwiftUI wrapper around MangaReaderContainerViewController.
/// Drop this into MangaReader in place of the single-page TabView ForEach.
struct MangaReaderContainerView: UIViewControllerRepresentable {

    var pages: [MangaPageModel]
    @Binding var currentPage: Int
    var isLTR: Bool

    // Callbacks
    var onLineTapped:    ((String) -> Void)?
    var onLineTranslate: ((String) -> Void)?
    var onInteraction:   (() -> Void)?
    var onBackgroundTap: (() -> Void)?

    // Box style props
    var showBoxBackground: Bool
    var boxBackgroundColor: UIColor
    var showBoxBorder: Bool
    var boxBorderColor: UIColor
    var boxBorderWidth: CGFloat
    var boxPadding: CGFloat

    /// Bottom inset — reserves space for the floating parser sheet.
    var bottomInset: CGFloat

    // MARK: Coordinator

    final class Coordinator {
        var lastPage: Int = -1
        fileprivate var lastStyle = BoxStyleSnapshot()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> MangaReaderContainerViewController {
        let container = MangaReaderContainerViewController()
        container.pages = pages
        container.isLTR = isLTR
        applyStyle(to: container)
        wireCallbacks(to: container, context: context)
        container.onPageChanged = { index in
            // Push page changes caused by user swipe back to SwiftUI state.
            DispatchQueue.main.async { currentPage = index }
        }
        // Show the initial page without animation.
        // loadViewIfNeeded triggers viewDidLoad exactly once — calling viewDidLoad()
        // directly would cause UIKit to call it again, creating duplicate child VCs.
        container.loadViewIfNeeded()
        container.setPage(currentPage, animated: false)
        context.coordinator.lastPage  = currentPage
        context.coordinator.lastStyle = BoxStyleSnapshot(self)
        return container
    }

    func updateUIViewController(_ container: MangaReaderContainerViewController, context: Context) {
        // Always keep callbacks fresh (closures capture SwiftUI state).
        wireCallbacks(to: container, context: context)
        container.isLTR = isLTR

        let newStyle = BoxStyleSnapshot(self)
        let pageChanged  = currentPage != context.coordinator.lastPage
        let styleChanged = newStyle != context.coordinator.lastStyle

        if pageChanged {
            // External change (wheel picker) — navigate without animation.
            container.pages = pages
            applyStyle(to: container)
            container.setPage(currentPage, animated: false)
            context.coordinator.lastPage  = currentPage
            context.coordinator.lastStyle = newStyle
        } else if styleChanged {
            applyStyle(to: container)
            container.updateStyleOnVisiblePage()
            context.coordinator.lastStyle = newStyle
        }
    }

    // MARK: Helpers

    private func applyStyle(to container: MangaReaderContainerViewController) {
        container.showBoxBackground = showBoxBackground
        container.boxBackgroundColor = boxBackgroundColor
        container.showBoxBorder      = showBoxBorder
        container.boxBorderColor     = boxBorderColor
        container.boxBorderWidth     = boxBorderWidth
        container.boxPadding         = boxPadding
        container.bottomInset        = bottomInset
    }

    private func wireCallbacks(
        to container: MangaReaderContainerViewController,
        context: Context
    ) {
        container.onLineTapped    = onLineTapped
        container.onLineTranslate = onLineTranslate
        container.onInteraction   = onInteraction
        container.onBackgroundTap = onBackgroundTap
    }
}

// MARK: - BoxStyleSnapshot (change detection)

/// Equatable value snapshot of the 6 box style properties.
/// Used to detect settings changes without triggering a full page rebuild.
fileprivate struct BoxStyleSnapshot: Equatable {
    var showBackground: Bool
    var background: UIColor
    var showBorder: Bool
    var border: UIColor
    var borderWidth: CGFloat
    var padding: CGFloat

    init() {
        showBackground = false; background = .clear
        showBorder = false; border = .clear
        borderWidth = 0; padding = 0
    }

    init(_ v: MangaReaderContainerView) {
        showBackground = v.showBoxBackground
        background     = v.boxBackgroundColor
        showBorder     = v.showBoxBorder
        border         = v.boxBorderColor
        borderWidth    = v.boxBorderWidth
        padding        = v.boxPadding
    }
}

#endif
