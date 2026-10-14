import SwiftUI

struct BrowserSpacePageSurface: NSViewRepresentable {
    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let tabPromotionNamespace: Namespace.ID
    let shortcuts: BrowserShortcutStore?
    var appearance = BrowserChromeAppearance()
    /// The room the sidebar takes beside the page.
    var reservedWidth: CGFloat = 0

    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    private var pageEnvironment = SpacePageEnvironment()

    func makeNSView(context: Context) -> SpaceContentFrameView<SpaceContentPagerView<BrowserRootPageSurface>> {
        SpaceContentFrameView(content: SpaceContentPagerView(frame: .zero))
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: SpaceContentFrameView<SpaceContentPagerView<BrowserRootPageSurface>>,
        context: Context
    ) -> CGSize? {
        // The shell determines the content area; retained pages fill it.
        // Native fitting would walk every retained page's subtree, every
        // Settings row among them, whenever a page's scroll geometry changes.
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func updateNSView(_ view: SpaceContentFrameView<SpaceContentPagerView<BrowserRootPageSurface>>, context: Context) {
        let objects = pageEnvironment.objects
        view.update(
            reservedLeft: appearance.sidebarOnRight ? 0 : reservedWidth,
            reservedRight: appearance.sidebarOnRight ? reservedWidth : 0,
            slide: context.transaction.sidebarSlide)
        view.content.update(
            spaces: BrowserSidebarAccessPolicy.availableSpaces(in: model.browser),
            selectedSpaceID: model.browser.selectedSpaceID,
            lockedSpaceIDs: model.lockedSpaceIDs,
            layoutDirection: context.environment.layoutDirection,
            presentation: animatesSpacePages && !context.environment.accessibilityReduceMotion
                ? context.environment.spacePagerPresentation : nil
        ) { space, isSelected in
            SpacePageRoot(
                content: BrowserRootPageSurface(
                    model: model, space: space, isSelectedSpace: isSelected,
                    transientBrowsing: transientBrowsing,
                    tabPromotionNamespace: tabPromotionNamespace,
                    shortcuts: shortcuts,
                    appearance: appearance,
                    layoutDirection: context.environment.layoutDirection),
                assignment: BrowserSpaceRuntimeAssignment(space: space), objects: objects)
        }
    }

    static func dismantleNSView(
        _ view: SpaceContentFrameView<SpaceContentPagerView<BrowserRootPageSurface>>, coordinator: ()
    ) {
        view.content.disconnect()
    }
}
