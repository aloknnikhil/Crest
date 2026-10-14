import AppKit
import QuartzCore
import SwiftUI

/// The sidebar in an AppKit view of its own, which slides as one layer.
///
/// The window's layout keeps the sidebar where it rests. Showing it lands the
/// new content at once and brings the host's layer in from off the window;
/// hiding it carries the content it had out first and puts the collapsed
/// content in only once it has gone, so nothing inside changes as it travels.
struct BrowserSidebarSlideSurface<Content: View>: NSViewRepresentable {
    let presentation: BrowserSidebarPresentation
    let edge: HorizontalEdge
    /// Whether the sidebar leaves past the window's right side.
    let hidesTowardRight: Bool
    /// How far the sidebar travels to leave the window: its widest surface.
    let travel: CGFloat
    @ViewBuilder let content: Content

    private var pageEnvironment = SpacePageEnvironment()

    init(
        presentation: BrowserSidebarPresentation, edge: HorizontalEdge, hidesTowardRight: Bool, travel: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.edge = edge
        self.hidesTowardRight = hidesTowardRight
        self.travel = travel
        self.content = content()
    }

    func makeNSView(context: Context) -> BrowserSidebarSlideView<BrowserSidebarSlideRoot<Content>> {
        BrowserSidebarSlideView(frame: .zero)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: BrowserSidebarSlideView<BrowserSidebarSlideRoot<Content>>,
        context: Context
    ) -> CGSize? {
        // The shell sizes the sidebar; native fitting would walk its rows.
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func updateNSView(_ view: BrowserSidebarSlideView<BrowserSidebarSlideRoot<Content>>, context: Context) {
        let slide = context.transaction.sidebarSlide
        // A show or hide moves the whole sidebar; animating its content too
        // would lay every row out again each frame of the slide.
        let staysShown = view.showsSidebar == presentation.showsSidebar
        view.update(
            root: BrowserSidebarSlideRoot(
                content: content, presentation: presentation, edge: edge,
                animation: staysShown ? slide?.animation : nil, objects: pageEnvironment.objects),
            showsSidebar: presentation.showsSidebar,
            offset: hidesTowardRight ? travel : -travel,
            slide: slide)
    }
}

/// The sidebar's content as its own hosting view shows it.
struct BrowserSidebarSlideRoot<Content: View>: View {
    let content: Content
    let presentation: BrowserSidebarPresentation
    let edge: HorizontalEdge
    /// Carries a change between docked and floating across the content, which
    /// no longer hears the shell's animations.
    var animation: Animation?
    let objects: SpacePageObjects

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .leading ? .leading : .trailing)
            .animation(animation, value: presentation)
            .spacePageObjects(objects)
    }
}

@MainActor
final class BrowserSidebarSlideView<Root: View>: NSView {
    // MARK: - Static Variables

    private static var slideKey: String { "sidebarSlide" }

    // MARK: - Variables

    private var hostingView: NSHostingView<Root>?
    /// The content a hide puts in once the sidebar has left.
    private var pendingRoot: Root?
    private(set) var showsSidebar = true
    private var slideGeneration: UInt = 0

    // MARK: - Initializers

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    // MARK: - Actions - Presentation

    func update(root: Root, showsSidebar: Bool, offset: CGFloat, slide: BrowserSidebarSlide?) {
        guard let hostingView else {
            install(root)
            self.showsSidebar = showsSidebar
            self.hostingView?.isHidden = !showsSidebar
            return
        }
        guard showsSidebar != self.showsSidebar else {
            if pendingRoot != nil { pendingRoot = root } else { hostingView.rootView = root }
            return
        }
        self.showsSidebar = showsSidebar
        guard let slide, window != nil, let layer else {
            stopSliding()
            hostingView.rootView = root
            hostingView.isHidden = !showsSidebar
            return
        }
        let start = presentedOffset(hiddenAt: offset)
        stopSliding()
        if showsSidebar {
            hostingView.rootView = root
            hostingView.isHidden = false
        } else {
            pendingRoot = root
        }
        slideGeneration &+= 1
        let generation = slideGeneration
        let end = showsSidebar ? 0 : offset
        let spring = slide.spring("transform.translation.x", from: start, to: end)
        spring.isAdditive = true
        // A hide holds the sidebar off the window until its host is hidden.
        spring.fillMode = .forwards
        spring.isRemovedOnCompletion = showsSidebar
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.slideGeneration == generation else { return }
                self.finishSliding()
            }
        }
        layer.add(spring, forKey: Self.slideKey)
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The region around a hidden or narrower sidebar belongs to the page.
        let view = super.hitTest(point)
        return view === self ? nil : view
    }

    // MARK: - Mutators

    private func install(_ root: Root) {
        let hostingView = NSHostingView(rootView: root)
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = bounds
        addSubview(hostingView)
        self.hostingView = hostingView
    }

    /// Where the sidebar is drawn now, relative to where it rests.
    private func presentedOffset(hiddenAt offset: CGFloat) -> CGFloat {
        if layer?.animation(forKey: Self.slideKey) != nil, let presented = layer?.presentation() {
            return presented.transform.m41
        }
        return hostingView?.isHidden == true ? offset : 0
    }

    private func stopSliding() {
        slideGeneration &+= 1
        layer?.removeAnimation(forKey: Self.slideKey)
        if let pendingRoot {
            hostingView?.rootView = pendingRoot
            self.pendingRoot = nil
        }
    }

    private func finishSliding() {
        guard !showsSidebar else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostingView?.isHidden = true
        stopSliding()
        CATransaction.commit()
    }
}
