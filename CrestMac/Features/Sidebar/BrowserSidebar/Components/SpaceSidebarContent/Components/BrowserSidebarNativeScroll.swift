import AppKit
import SwiftUI

/// The tab list's scrolling, done by AppKit.
///
/// The list is the document of an `NSScrollView`, drawn by one hosting view.
/// Scrolling moves that already drawn document on the render server, where a
/// SwiftUI scroll view laid the list out and drew it again on every frame.
/// One hosting view moving costs SwiftUI almost nothing as long as nothing in
/// it measures where it stands in the window, so the rows' drag geometry
/// pauses while the list scrolls and measures again once it stops.
struct BrowserSidebarNativeScroll<Rows: View, Background: View>: NSViewRepresentable {
    let scroll: BrowserSidebarNativeScrollState
    @ViewBuilder let rows: Rows
    @ViewBuilder let background: Background

    private var pageEnvironment = SpacePageEnvironment()

    init(
        scroll: BrowserSidebarNativeScrollState, @ViewBuilder rows: () -> Rows,
        @ViewBuilder background: () -> Background
    ) {
        self.scroll = scroll
        self.rows = rows()
        self.background = background()
    }

    func makeNSView(context: Context) -> BrowserSidebarScrollView<Rows, Background> {
        BrowserSidebarScrollView(scroll: scroll, root: root)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: BrowserSidebarScrollView<Rows, Background>, context: Context
    ) -> CGSize? {
        // The sidebar sizes the list; fitting would lay out every row.
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func updateNSView(_ view: BrowserSidebarScrollView<Rows, Background>, context: Context) {
        view.update(root)
    }

    private var root: BrowserSidebarScrollDocument<Rows, Background> {
        BrowserSidebarScrollDocument(
            rows: rows, background: background, scroll: scroll, objects: pageEnvironment.objects)
    }
}

/// What the list's scrolling tells the views around it and inside it, and
/// the scroll they may ask for. Only values that change at a list's end or a
/// scroll's start and stop are observed; the offset itself never is.
@Observable
@MainActor
final class BrowserSidebarNativeScrollState {
    // MARK: - Variables

    /// Whether rows lie below the visible ones.
    fileprivate(set) var hasMoreBelow = false
    /// Whether the list is moving, which pauses the rows' drag geometry.
    fileprivate(set) var isScrolling = false
    /// Whether the document keeps its height while a tab is dragged. The
    /// lift's closing slot and opening gap change the rows' height on every
    /// frame of their animations, and resizing the document to follow would
    /// lay every row out again and move the scroll position under the drag.
    @ObservationIgnored var holdsHeight = false {
        didSet { if oldValue, !holdsHeight { heightReleased?() } }
    }
    @ObservationIgnored fileprivate var heightReleased: (() -> Void)?
    @ObservationIgnored fileprivate weak var view: NSScrollView?

    // MARK: - Actions - Scrolling

    /// Scrolls on by most of the visible height.
    func scrollTowardEnd() {
        guard let view, let document = view.documentView else { return }
        let clip = view.contentView
        let target = min(
            document.frame.height - clip.bounds.height, clip.bounds.origin.y + clip.bounds.height * 0.85)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            clip.animator().setBoundsOrigin(NSPoint(x: 0, y: max(0, target)))
        } completionHandler: {
            MainActor.assumeIsolated { view.reflectScrolledClipView(clip) }
        }
    }
}

/// The scrolled document: the rows at their own height, then the background
/// filling whatever of the visible height they leave.
struct BrowserSidebarScrollDocument<Rows: View, Background: View>: View {
    let rows: Rows
    let background: Background
    let scroll: BrowserSidebarNativeScrollState
    let objects: SpacePageObjects
    /// Set by the scroll view, which sizes the document from it.
    var rowsHeightChanged: (CGFloat) -> Void = { _ in }
    /// Set by the scroll view, whose hosting view finds the row under the
    /// pointer.
    var pointerRows: BrowserSidebarPointerRows?

    var body: some View {
        VStack(spacing: 0) {
            rows
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    rowsHeightChanged($0)
                }
            background
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.browserSidebarReorderGeometryPaused, scroll.isScrolling)
        .environment(\.browserSidebarPointerRows, pointerRows)
        .spacePageObjects(objects)
    }
}

@MainActor
final class BrowserSidebarScrollView<Rows: View, Background: View>: NSScrollView {
    // MARK: - Types

    /// Top-down coordinates, so a document that grows or shrinks keeps its
    /// first rows where they were.
    private final class Document: NSView {
        override var isFlipped: Bool { true }
    }

    // MARK: - Static Variables

    /// How long after the last movement the list counts as still, and its rows
    /// measure themselves again.
    private static var settleDelay: Duration { .milliseconds(120) }
    /// How much a held document grows at once, so a drag resizes it rarely.
    private static var heldGrowthStep: CGFloat { 160 }

    // MARK: - Variables

    private let scroll: BrowserSidebarNativeScrollState
    private let hostingView: BrowserSidebarScrollHostingView<BrowserSidebarScrollDocument<Rows, Background>>
    private let document = Document()
    private var rowsHeight: CGFloat = 0
    private var boundsObserver: NSObjectProtocol?
    private var settleTask: Task<Void, Never>?
    /// Each pointer move hit tests the rows several times; they are walked once.
    private var hitCache = BrowserPointerHitCache()
    /// What a pointer move last found over one row, kept while the pointer
    /// stays over it. SwiftUI walks every row to answer a hit test, and
    /// within a row the answer stays the same until something is pressed,
    /// the list moves or its rows change.
    private var rowHit: (row: UUID?, view: NSView?)?

    // MARK: - Initializers

    init(scroll: BrowserSidebarNativeScrollState, root: BrowserSidebarScrollDocument<Rows, Background>) {
        self.scroll = scroll
        hostingView = BrowserSidebarScrollHostingView(rootView: root)
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .allowed
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsetsZero
        contentView.drawsBackground = false
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.autoresizingMask = [.width, .height]
        document.addSubview(hostingView)
        documentView = document
        hostingView.rootView = measured(root)
        scroll.view = self
        scroll.heightReleased = { [weak self] in self?.resizeDocument() }
        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.contentMoved() }
        }
    }

    required init?(coder: NSCoder) { nil }

    isolated deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        settleTask?.cancel()
    }

    // MARK: - Actions - Updates

    func update(_ root: BrowserSidebarScrollDocument<Rows, Background>) {
        rowHit = nil
        hostingView.rootView = measured(root)
    }

    override func layout() {
        super.layout()
        resizeDocument()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // While the list moves on its own, AppKit asks on every step what lies
        // under the pointer to choose its cursor. The rows are passing by and
        // take no pointer until it stops, so the list answers for them. A
        // click still reaches the row under it.
        let event = NSApp.currentEvent
        if event?.type == .mouseMoved, hostingView.pointerRows.gate.isNarrowed, let superview {
            let row = BrowserNativeTabSelectionTarget.TargetView.tab(
                at: superview.convert(point, to: nil), within: hostingView)
            if let rowHit, rowHit.row == row, rowHit.view.map({ $0.isDescendant(of: self) }) ?? true {
                return rowHit.view
            }
            let view = hitCache.hitTest(point, in: self) { super.hitTest(point) }
            rowHit = (row, view)
            return view
        }
        rowHit = nil
        if Self.isPress(event) {
            hostingView.pointerWillPress()
        } else if hostingView.defersUpdates, !Self.isPointerButtonEvent(event) {
            return frame.contains(point) ? self : nil
        } else if NSEvent.pressedMouseButtons != 0 {
            // A drag, from here or elsewhere, may end over any row.
            hostingView.pointerRows.narrow(false)
        }
        return hitCache.hitTest(point, in: self) { super.hitTest(point) }
    }

    private static func isPress(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: true
        default: false
        }
    }

    private static func isPointerButtonEvent(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
            .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            true
        default: false
        }
    }

    // MARK: - Mutators

    private func measured(
        _ root: BrowserSidebarScrollDocument<Rows, Background>
    ) -> BrowserSidebarScrollDocument<Rows, Background> {
        var root = root
        root.pointerRows = hostingView.pointerRows
        root.rowsHeightChanged = { [weak self] height in
            guard let self, self.rowsHeight != height else { return }
            self.rowHit = nil
            self.rowsHeight = height
            self.resizeDocument()
        }
        return root
    }

    /// The document is the list's width and the taller of its rows and the
    /// visible height, so the background below the rows always reaches the
    /// bottom and nothing scrolls when the rows fit.
    private func resizeDocument() {
        var height = max(rowsHeight, contentView.bounds.height)
        if scroll.holdsHeight {
            // Never shrink under a drag, and grow in steps.
            let current = document.frame.height
            height =
                height <= current
                ? current : (height / Self.heldGrowthStep).rounded(.up) * Self.heldGrowthStep
        }
        let size = NSSize(width: contentView.bounds.width, height: height)
        if document.frame.size != size { document.setFrameSize(size) }
        updateEnd()
    }

    private func contentMoved() {
        rowHit = nil
        updateEnd()
        if !scroll.isScrolling { scroll.isScrolling = true }
        hostingView.defersUpdates = !scroll.holdsHeight
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.settleDelay) } catch { return }
            guard let self else { return }
            scroll.isScrolling = false
            hostingView.defersUpdates = false
            // Rows have passed under a resting pointer.
            hostingView.followPointer(to: window?.mouseLocationOutsideOfEventStream)
        }
    }

    private func updateEnd() {
        let more = rowsHeight > contentView.bounds.maxY + 1
        if scroll.hasMoreBelow != more { scroll.hasMoreBelow = more }
    }
}

/// The list's hosting view, which stays as drawn while the list moves.
///
/// SwiftUI follows a hosting view's place in its window, so every scroll step
/// asks this one to update. That request climbs to the window's own hosting
/// view, which lays the whole window out again, and here it hit tests every
/// row's hover, tooltip and button once more; with many rows that costs more
/// than a frame. Scrolling only moves what is already drawn, so while the
/// list moves on its own the request waits, and it is made once as soon as the
/// list stops. A drag keeps every update, since its gap and lifted row move
/// inside the list, and so does any change of size.
@MainActor
final class BrowserSidebarScrollHostingView<Content: View>: NSHostingView<Content> {
    // MARK: - Variables

    /// The row under the pointer, the only one SwiftUI hit tests.
    let pointerRows = BrowserSidebarPointerRows()

    var defersUpdates = false {
        didSet {
            guard oldValue, !defersUpdates, owesUpdate else { return }
            owesUpdate = false
            needsUpdateConstraints = true
            needsLayout = true
        }
    }
    private var owesUpdate = false
    private var laidOutSize: NSSize?

    override var needsUpdateConstraints: Bool {
        get { super.needsUpdateConstraints }
        set {
            if newValue, defersUpdates {
                owesUpdate = true
            } else {
                super.needsUpdateConstraints = newValue
            }
        }
    }

    // MARK: - Actions - Pointer

    /// Hands the pointer to the row at a window location, found from the
    /// rows' native bounds, or to none.
    func followPointer(to windowPoint: NSPoint?) {
        if NSEvent.pressedMouseButtons != 0 {
            pointerRows.narrow(false)
            return
        }
        pointerRows.narrow(true)
        pointerRows.pointerMoved(
            to: windowPoint.flatMap { BrowserNativeTabSelectionTarget.TargetView.tab(at: $0, within: self) })
    }

    /// Opens every row to a press before it is hit tested, since the pointer
    /// may not have moved over its row first, as in an inactive window or a
    /// list that changed under it, and a held button may drag across rows.
    func pointerWillPress() {
        guard pointerRows.narrow(false) else { return }
        defersUpdates = false
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func mouseEntered(with event: NSEvent) {
        followPointer(to: event.locationInWindow)
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        followPointer(to: event.locationInWindow)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        followPointer(to: nil)
        super.mouseExited(with: event)
    }

    // MARK: - Actions - Layout

    override func layout() {
        if defersUpdates, laidOutSize == bounds.size {
            owesUpdate = true
            return
        }
        laidOutSize = bounds.size
        super.layout()
    }
}
