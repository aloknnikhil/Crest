import AppKit
import SwiftUI

struct BrowserNativeTabSelectionTarget: NSViewRepresentable {
    let itemID: BrowserSelectionItemID
    let browser: BrowserStore
    let assignment: BrowserSpaceRuntimeAssignment

    func makeNSView(context: Context) -> TargetView { TargetView() }

    func updateNSView(_ view: TargetView, context: Context) {
        view.itemID = itemID
        view.browser = browser
        view.assignment = assignment
    }

    final class TargetView: NSView {
        private static let targets = NSHashTable<TargetView>.weakObjects()
        weak var browser: BrowserStore?
        var itemID: BrowserSelectionItemID?
        var tabID: UUID? {
            get { itemID?.tabID }
            set { itemID = newValue.map(BrowserSelectionItemID.tab) }
        }
        var assignment: BrowserSpaceRuntimeAssignment?

        override init(frame: NSRect) {
            super.init(frame: frame)
            Self.targets.add(self)
        }

        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        static func item(
            at windowPoint: NSPoint, in window: NSWindow, browser: BrowserStore,
            assignment: BrowserSpaceRuntimeAssignment
        ) -> BrowserSelectionItemID? {
            matching(browser: browser, assignment: assignment)
                .filter {
                    let point = $0.convert(windowPoint, from: nil)
                    return $0.window === window && $0.bounds.contains(point) && $0.visibleRect.contains(point)
                }
                // A split container also covers its children; the actual row wins.
                .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }?.itemID
        }

        /// The tab whose row lies at a point in the window among the rows
        /// inside `ancestor`, found from their native bounds alone.
        static func tab(at windowPoint: NSPoint, within ancestor: NSView) -> UUID? {
            guard let window = ancestor.window else { return nil }
            return targets.allObjects
                .filter {
                    $0.window === window && !$0.bounds.isEmpty && $0.isDescendant(of: ancestor)
                        && $0.bounds.contains($0.convert(windowPoint, from: nil))
                }
                .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }?.tabID
        }

        static func tab(
            at point: NSPoint, in window: NSWindow, browser: BrowserStore,
            assignment: BrowserSpaceRuntimeAssignment
        ) -> UUID? {
            item(at: point, in: window, browser: browser, assignment: assignment)?.tabID
        }

        private static func matching(
            browser: BrowserStore, assignment: BrowserSpaceRuntimeAssignment
        ) -> [TargetView] {
            targets.allObjects.filter {
                $0.browser === browser && $0.assignment == assignment && $0.window != nil
                    && !$0.isHiddenOrHasHiddenAncestor && !$0.bounds.isEmpty
            }
        }
    }
}
