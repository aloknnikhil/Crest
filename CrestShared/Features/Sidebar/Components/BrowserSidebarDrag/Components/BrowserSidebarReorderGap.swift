import SwiftUI

/// The single vacant slot under a lifted item. Its real height participates in
/// layout, so surrounding rows and folder surfaces settle around the drop.
struct BrowserSidebarReorderGap: View {
    let height: CGFloat

    /// The slot takes the shape of a layer where it stands.
    @Environment(\.sidebarLayerDepth) private var depth

    /// How the gap and the rows around it move to a new target: smoothly,
    /// except while the list scrolls under the lift, when the gap follows the
    /// pointer through rows passing faster than it could slide.
    static func motion(in state: BrowserSidebarReorderState, reduceMotion: Bool) -> Animation? {
        state.isScrollingUnderLift ? nil : CrestMotion.dragSource.unlessReducingMotion(reduceMotion)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth), style: .continuous)
            .fill(.primary.opacity(0.035))
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .padding(.vertical, CrestSpacing.extraSmall)
            .frame(height: height)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
