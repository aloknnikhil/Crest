import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// A tooltip for a control repeated down a long list, such as a sidebar row's.
///
/// On the Mac SwiftUI's `help` answers every scroll step by hit testing the
/// whole list for the tooltip under the pointer, which with many rows costs
/// more than a frame. AppKit's own tooltip is tied to the view that shows it
/// and moves with it for nothing, so the Mac uses that. A nil text shows none.
struct CrestHelpModifier: ViewModifier {
    let text: LocalizedStringResource?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text {
            #if os(macOS)
                content.background {
                    CrestNativeHelp(text: String(localized: text))
                        .accessibilityHidden(true)
                }
            #else
                content.help(Text(text))
            #endif
        } else {
            content
        }
    }
}

extension View {
    /// The tooltip for a control repeated down a long list. See
    /// `CrestHelpModifier`.
    func crestHelp(_ text: LocalizedStringResource?) -> some View {
        modifier(CrestHelpModifier(text: text))
    }
}

#if os(macOS)
    /// AppKit's tooltip over the control's bounds. It takes no pointer, so the
    /// control under it still answers every click and hover.
    private struct CrestNativeHelp: NSViewRepresentable {
        let text: String

        func makeNSView(context: Context) -> HelpView { HelpView() }

        func updateNSView(_ view: HelpView, context: Context) {
            if view.toolTip != text { view.toolTip = text }
        }

        final class HelpView: NSView {
            override func hitTest(_ point: NSPoint) -> NSView? { nil }
        }
    }
#endif
