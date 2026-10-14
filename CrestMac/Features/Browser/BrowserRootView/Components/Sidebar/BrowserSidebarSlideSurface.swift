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
        view.update(
            root: BrowserSidebarSlideRoot(content: content, edge: edge, objects: pageEnvironment.objects),
            presentation: presentation,
            offset: hidesTowardRight ? travel : -travel,
            slide: context.transaction.sidebarSlide)
    }
}

/// The sidebar's content as its own hosting view shows it.
struct BrowserSidebarSlideRoot<Content: View>: View {
    let content: Content
    let edge: HorizontalEdge
    let objects: SpacePageObjects

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .leading ? .leading : .trailing)
            .spacePageObjects(objects)
    }
}

@MainActor
final class BrowserSidebarSlideView<Root: View>: NSView {
    // MARK: - Static Variables

    private static var slideKey: String { "sidebarSlide" }
    private static var restyleKey: String { "sidebarRestyle" }

    // MARK: - Variables

    private var hostingView: NSHostingView<Root>?
    /// The content a hide puts in once the sidebar has left.
    private var pendingRoot: Root?
    private var presentation: BrowserSidebarPresentation?
    private var showsSidebar: Bool { presentation?.showsSidebar ?? true }
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

    func update(
        root: Root, presentation: BrowserSidebarPresentation, offset: CGFloat, slide: BrowserSidebarSlide?
    ) {
        let previous = self.presentation
        self.presentation = presentation
        let showsSidebar = presentation.showsSidebar
        guard let hostingView, let previous else {
            install(root)
            self.hostingView?.isHidden = !showsSidebar
            return
        }
        guard showsSidebar != previous.showsSidebar else {
            if pendingRoot != nil {
                pendingRoot = root
            } else if presentation != previous, let slide, window != nil {
                restyle(hostingView, to: root, over: slide)
            } else {
                hostingView.rootView = root
            }
            return
        }
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

    /// Moves a shown sidebar between docked and floating. The content lands in
    /// its new style at once and Core Animation fades between the two, since
    /// animating the style itself would lay every row out again each frame.
    private func restyle(_ hostingView: NSHostingView<Root>, to root: Root, over slide: BrowserSidebarSlide) {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = slide.duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        layer?.add(fade, forKey: Self.restyleKey)
        hostingView.rootView = root
        hostingView.layoutSubtreeIfNeeded()
        CATransaction.commit()
    }

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
