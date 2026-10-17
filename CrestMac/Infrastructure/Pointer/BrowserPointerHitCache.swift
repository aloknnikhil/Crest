import AppKit

/// One hit test per pointer move for a view whose hit test is costly.
///
/// A single mouse move asks the same view the same question several times:
/// the window's hover, its cursor and a nested hosting view's own hover each
/// hit test the point. The answer a view gives is the one a fresh hit test
/// would give for that move, so it is kept for the rest of the move and asked
/// again for anything else, including the next move. AppKit chooses where a
/// scroll gesture goes by hit testing, so the view kept is always the one
/// truly under the pointer, never a stand-in.
@MainActor
struct BrowserPointerHitCache {
    // MARK: - Types

    /// The move a kept answer belongs to: its event and the point in the window.
    private struct Move: Equatable {
        let timestamp: TimeInterval
        let location: NSPoint
    }

    // MARK: - Variables

    private var move: Move?
    private var view: NSView?

    // MARK: - Actions - Hit testing

    /// What `owner` answers for `point`, in its superview's coordinates: the
    /// answer already found during this pointer move, or `hitTest()`'s.
    mutating func hitTest(_ point: NSPoint, in owner: NSView, hitTest: () -> NSView?) -> NSView? {
        guard let event = NSApp.currentEvent, event.type == .mouseMoved,
            let location = owner.superview?.convert(point, to: nil)
        else { return hitTest() }
        let current = Move(timestamp: event.timestamp, location: location)
        if current == move, view.map({ $0 === owner || $0.isDescendant(of: owner) }) ?? true {
            return view
        }
        let answer = hitTest()
        move = current
        view = answer
        return answer
    }
}
