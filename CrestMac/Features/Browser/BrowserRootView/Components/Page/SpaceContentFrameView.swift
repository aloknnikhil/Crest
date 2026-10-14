import AppKit
import QuartzCore

/// Lays the page out beside the sidebar, filling the window otherwise.
///
/// A sidebar slide moves the page on the render server. The page takes its
/// final place at once but keeps the wider of its two widths while it
/// travels, cut to the width it shows as it goes, and takes its final width
/// as the slide ends. The web view is resized once rather than every frame.
@MainActor
final class SpaceContentFrameView<Content: NSView>: NSView {
    // MARK: - Static Variables

    private static var slideKey: String { "sidebarSlide" }

    // MARK: - Variables

    let content: Content
    /// The room the sidebar takes on the window's left and right.
    private var reserved = (left: CGFloat(0), right: CGFloat(0))
    private var slideGeneration: UInt = 0
    private var isSliding = false
    private var lastSize = CGSize.zero

    private var restingFrame: CGRect {
        CGRect(
            x: reserved.left, y: 0, width: max(0, bounds.width - reserved.left - reserved.right),
            height: bounds.height)
    }

    // MARK: - Initializers

    init(content: Content) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        setAccessibilityElement(false)
        addSubview(content)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    // MARK: - Actions - Layout

    func update(reservedLeft left: CGFloat, reservedRight right: CGFloat, slide: BrowserSidebarSlide?) {
        guard left != reserved.left || right != reserved.right else { return }
        let start = presentedFrame
        reserved = (left, right)
        let end = restingFrame
        guard let slide, window != nil, let layer = content.layer, !start.isEmpty, !end.isEmpty else {
            settle()
            return
        }
        stopSliding()
        slideGeneration &+= 1
        let generation = slideGeneration
        isSliding = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.frame = CGRect(
            x: end.minX, y: end.minY, width: max(content.frame.width, end.width), height: end.height)
        let mask = CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        mask.anchorPoint = .zero
        mask.frame = CGRect(x: 0, y: 0, width: end.width, height: content.bounds.height)
        layer.mask = mask
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.slideGeneration == generation else { return }
                self.settle()
            }
        }
        let travel = slide.spring("transform.translation.x", from: start.minX - end.minX, to: 0)
        travel.isAdditive = true
        layer.add(travel, forKey: Self.slideKey)
        mask.add(slide.spring("bounds.size.width", from: start.width, to: end.width), forKey: Self.slideKey)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        if lastSize != bounds.size {
            lastSize = bounds.size
            settle()
        } else if !isSliding, content.frame != restingFrame {
            content.frame = restingFrame
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The sidebar's room belongs to the sidebar even where it is clear.
        guard content.frame.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    // MARK: - Mutators

    /// Where the page is drawn now, part way through a slide or at rest.
    private var presentedFrame: CGRect {
        guard isSliding, let presented = content.layer?.presentation() else { return content.frame }
        let width = content.layer?.mask?.presentation()?.bounds.width ?? content.frame.width
        return CGRect(
            x: content.frame.minX + presented.transform.m41, y: content.frame.minY, width: width,
            height: content.frame.height)
    }

    private func stopSliding() {
        slideGeneration &+= 1
        isSliding = false
        content.layer?.removeAnimation(forKey: Self.slideKey)
        content.layer?.mask = nil
    }

    private func settle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stopSliding()
        if content.frame != restingFrame { content.frame = restingFrame }
        CATransaction.commit()
    }
}
