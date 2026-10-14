import SwiftUI

struct BrowserRootShell: View, BrowserChromeAnimating {
    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let shortcuts: BrowserShortcutStore?
    @Binding var storedSidebarWidth: Double
    var appearance = BrowserChromeAppearance()
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var downloadFeedback = BrowserMacDownloadFeedbackState()
    @State private var spacePagerPresentation = SpacePagerPresentation()

    private var sidebarEdge: HorizontalEdge { appearance.sidebarEdge(in: layoutDirection) }

    /// The sidebar's motion, unless Look and Feel turns it off.
    private func sidebarAnimation(_ animation: Animation) -> Animation? {
        BrowserDeviceAppearanceStore.shared.animatesSidebar ? chromeAnimation(animation) : nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            BrowserRootFullscreenContent(pages: model.pages) {
                standardContent
            }

            // The window's chrome belongs to the window, not to the chrome a
            // fullscreen page hides: taking it down would restore the window's
            // style while AppKit is carrying it into fullscreen.
            BrowserNativeWindowControlsBridge(
                isVisible: model.sidebarPresentation.showsWindowControls,
                sidebarPosition: appearance.sidebarOnRight ? 1 : 0,
                sidebarWidth: model.sidebarWidth
            )
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
            GeometryReader { proxy in
                let rect = anchor.map { proxy[$0] } ?? CGRect(origin: .zero, size: proxy.size)
                BrowserRootCommandPaletteLayer(
                    model: model,
                    shortcuts: shortcuts,
                    spaceSettingsPresentation: spaceSettingsPresentation,
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    contentInsets: BrowserChromeAppearance.contentInsets(
                        for: rect, in: proxy.size, direction: layoutDirection
                    )
                )
            }
        }
        // One per-window host answers for every row and tile in this shell,
        // so the sidebar reads it from here rather than being handed a value
        // per tab through the tree between them.
        .environment(downloadFeedback)
        .environment(\.browserChromeAppearance, appearance)
        .environment(\.spacePagerPresentation, spacePagerPresentation)
        .animation(chromeAnimation(CrestMotion.collection), value: appearance.sidebarOnRight)
        .animation(
            sidebarAnimation(
                model.isSidebarApproachingDock
                    ? CrestMotion.sidebarDockAttachment
                    : CrestMotion.sidebarMorph
            ),
            value: model.chrome.columnVisibility
        )
        .animation(
            sidebarAnimation(
                model.isSidebarApproachingDock
                    ? CrestMotion.sidebarDockAttachment
                    : model.isSidebarMorphing
                        ? CrestMotion.sidebarMorph
                        : CrestMotion.floatingPane
            ),
            value: model.isFloatingSidebarPresented
        )
        .animation(
            sidebarAnimation(CrestMotion.sidebarDockApproach),
            value: model.isSidebarApproachingDock
        )
        .modifier(BrowserRootPaletteAnimation(model: model, reduceMotion: reduceMotion))
        .onChange(
            of: model.chrome.utilityPresentation.isSidebarInteractionActive
        ) { _, isActive in
            model.sidebarInteractionChanged(
                isActive,
                reduceMotion: reduceMotion
            )
        }
        .modifier(BrowserRootPermissionObserver(model: model, reduceMotion: reduceMotion))
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: transientBrowsing.orphanedPeeks(in: model.browser), initial: true) {
            transientBrowsing.reconcilePeeks(in: model.browser)
        }
        .onChange(of: transientBrowsing.peekRequests, initial: true) {
            model.pages.retainPeekPages(for: transientBrowsing.peekRequests)
        }
    }

    private var sidebar: some View {
        BrowserSidebarSlideSurface(
            presentation: model.sidebarPresentation,
            edge: sidebarEdge,
            hidesTowardRight: appearance.sidebarOnRight,
            travel: BrowserSidebarPresentation.collapsed.surfaceWidth(for: model.sidebarWidth)
        ) {
            BrowserRootSidebarSurface(
                model: model,
                presentation: model.sidebarPresentation,
                width: model.sidebarWidth,
                edge: sidebarEdge,
                reduceTransparency: reduceTransparency,
                reduceMotion: reduceMotion
            ) {
                BrowserRootSidebarContent(
                    model: model,
                    spaceSettingsPresentation: spaceSettingsPresentation,
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    tabPromotionNamespace: tabPromotionNamespace
                )
            }
        }
        .frame(width: model.sidebarPresentation.surfaceWidth(for: model.sidebarWidth))
        .frame(maxHeight: .infinity)
        .zIndex(model.sidebarPresentation == .floating ? BrowserRootMetrics.floatingSidebarZIndex : 0)
    }

    private var standardContent: some View {
        ZStack(alignment: .leading) {
            BrowserRootShellBackdrop(browser: model.browser)

            // The page and sidebar land in their new places at once; their
            // AppKit views carry the slide on the render server.
            Group {
                BrowserSpacePageSurface(
                    model: model, transientBrowsing: transientBrowsing,
                    tabPromotionNamespace: tabPromotionNamespace, shortcuts: shortcuts, appearance: appearance,
                    reservedWidth: model.sidebarPresentation.reservedWidth(
                        for: model.sidebarWidth, whileApproachingDock: model.isSidebarApproachingDock)
                )
                .clipped()

                BrowserSidebarPageLayout(
                    presentation: model.sidebarPresentation,
                    width: model.sidebarWidth,
                    edge: sidebarEdge,
                    isApproachingDock: model.isSidebarApproachingDock
                ) {
                    // The page's place, which the command palette centres in.
                    Color.clear
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } sidebar: {
                    sidebar
                } controls: {
                    BrowserRootShellControls(
                        model: model, storedSidebarWidth: $storedSidebarWidth, sidebarEdge: sidebarEdge)
                }
            }
            .modifier(BrowserRootPaletteObscuring(chrome: model.chrome))
            .browserSidebarSlideTransaction()

            BrowserRootUtilityFanLayer(model: model, sidebarOnRight: appearance.sidebarOnRight)
                .zIndex(BrowserRootMetrics.utilityFanZIndex)

            BrowserMacDownloadFeedbackLayer(model: model, feedback: downloadFeedback)
                .zIndex(BrowserRootMetrics.utilityFanZIndex + 1)

            BrowserRootDragPreviewLayer(
                model: model,
                reduceMotion: reduceMotion
            )

            BrowserWindowFocusBridge(isWindowFocused: model.isWindowFocusedBinding)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if let notice = model.visibleNotice {
                BrowserNoticeView(notice: notice)
                    .id(notice)
            }
        }
    }

}

/// Tab selection is observed here so the ordinary shell's inputs stay stable
/// when only the page occupying it changes.
private struct BrowserRootFullscreenContent<Content: View>: View {
    let pages: BrowserPagePool
    @ViewBuilder let content: Content

    var body: some View {
        if let page = pages.activePage, page.isContentFullscreen {
            BrowserPlatformWebView(
                page: page,
                isPageActive: true,
                focusRestorationGate: .suppressed
            )
            .environment(\.browserPagePresentationWindowID, pages.windowID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea()
        } else {
            content
        }
    }
}

private struct BrowserRootPermissionObserver: ViewModifier {
    let model: BrowserRootModel
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content.onChange(of: model.pages.activePage?.sitePermissionRequests.current?.id) {
            if model.pages.activePage?.sitePermissionRequests.current != nil {
                model.presentFloatingSidebar(reduceMotion: reduceMotion)
            }
        }
    }
}

// MARK: - Observers

// The shell's body reads only what moves the sidebar, so a tab switch, a Space
// switch, focus or the palette re-evaluates the small views below rather than
// the window's root and every input it hands down.

/// The backdrop follows the shown Space by itself.
private struct BrowserRootShellBackdrop: View {
    let browser: BrowserStore

    var body: some View {
        BrowserRootBackdrop(space: browser.shownSpace, spaces: browser.availableSpaces)
    }
}

/// The sidebar's surface, which reads the shown Space and the palette itself.
/// Its presentation and width come from the shell, since the sidebar's host
/// decides when a hide lets the collapsed content in.
private struct BrowserRootSidebarSurface<Content: View>: View {
    let model: BrowserRootModel
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let edge: HorizontalEdge
    let reduceTransparency: Bool
    let reduceMotion: Bool
    @ViewBuilder let content: Content

    var body: some View {
        BrowserRootSidebarSurfaceLayer(
            presentation: presentation,
            width: width,
            edge: edge,
            space: model.browser.shownSpace,
            reduceTransparency: reduceTransparency,
            spaces: model.browser.availableSpaces,
            hoverChanged: { [model, reduceMotion] in
                model.sidebarSurfaceHoverChanged($0, reduceMotion: reduceMotion)
            },
            slidesItself: false
        ) {
            content
        }
        .background {
            BrowserSidebarPointerNavigation(
                isSidebarVisible: presentation.showsSidebar && !model.chrome.isCommandPalettePresented,
                perform: model.handleAuxiliaryMouseAction,
                navigationTargets: { [pages = model.pages] in pages.livePages },
                activeTarget: { [pages = model.pages] in pages.activePage }
            )
        }
    }
}

/// The page and sidebar stop taking input while the palette covers them.
private struct BrowserRootPaletteObscuring: ViewModifier {
    let chrome: BrowserChromeState

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!chrome.isCommandPalettePresented)
            .accessibilityHidden(chrome.isCommandPalettePresented)
    }
}

/// Animates the window's changes as the palette opens and closes. Whether it
/// is shown depends on the selected tab, which changes far more often.
private struct BrowserRootPaletteAnimation: ViewModifier {
    let model: BrowserRootModel
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content.animation(
            BrowserCommandSurfaceMorph.commandPaletteAnimation(reduceMotion: reduceMotion),
            value: model.isCommandPaletteShown
        )
    }
}
