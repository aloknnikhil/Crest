import QuartzCore
import SwiftUI

/// A sidebar show, hide or dock that Core Animation runs.
///
/// SwiftUI animating the sidebar's offset and the page's width lays the whole
/// window out again every frame, every row and native view in it included. A
/// slide instead lands the window's layout at once and moves the sidebar's and
/// page's own layers on the render server, so the main thread does no work
/// while they travel.
struct BrowserSidebarSlide: Equatable, Sendable {
    // MARK: - Static Variables

    /// The shell's sidebar motions and the springs that match them.
    private static var motions: [(animation: Animation, duration: TimeInterval)] {
        [
            (CrestMotion.sidebarMorph, CrestMotion.sidebarMorphTransition),
            (CrestMotion.sidebarDockApproach, CrestMotion.sidebarDockApproachTransition),
            (CrestMotion.sidebarDockAttachment, CrestMotion.sidebarDockAttachmentTransition),
            (CrestMotion.floatingPane, CrestMotion.floatingPaneTransition),
        ]
    }

    // MARK: - Variables

    /// The SwiftUI animation the shell asked for, which the sidebar's own
    /// content still uses for the changes inside it.
    let animation: Animation
    let duration: TimeInterval

    // MARK: - Initializers

    /// The slide a shell update carries, or nil when its change lands at once.
    init?(_ transaction: Transaction) {
        guard !transaction.disablesAnimations, let animation = transaction.animation,
            let motion = Self.motions.first(where: { $0.animation == animation })
        else { return nil }
        self.animation = animation
        duration = motion.duration
    }

    // MARK: - Actions

    /// The spring that carries `keyPath` from one value to another.
    func spring(_ keyPath: String, from: CGFloat, to: CGFloat) -> CASpringAnimation {
        let spring = CASpringAnimation(perceptualDuration: duration, bounce: 0)
        spring.keyPath = keyPath
        spring.fromValue = from
        spring.toValue = to
        spring.duration = spring.settlingDuration
        return spring
    }
}

extension Transaction {
    /// The sidebar slide an update carries once the shell has taken its
    /// animation away from the layout the slide moves.
    @Entry var sidebarSlide: BrowserSidebarSlide? = nil
}

extension View {
    /// Hands each update's sidebar motion to the AppKit views that run it and
    /// lands this layout without animating it.
    func browserSidebarSlideTransaction() -> some View {
        transaction { transaction in
            transaction.sidebarSlide = BrowserSidebarSlide(transaction)
            transaction.animation = nil
        }
    }
}
