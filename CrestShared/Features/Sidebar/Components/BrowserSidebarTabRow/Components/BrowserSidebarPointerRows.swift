import Observation
import SwiftUI

/// Which tab row the pointer is over, found by the platform list hosting the
/// rows, so that only that row takes the pointer.
///
/// SwiftUI answers each pointer move by hit testing every row's hover, gesture
/// and button, which in a long list costs most of a frame and lags the hover.
/// A list that can find the row under the pointer itself, from the rows' own
/// native bounds, lets the rest stand aside: only the row under the pointer
/// is hit tested, and the others take no pointer until it reaches them. While
/// a button is held every row takes the pointer, since a drag or a drop may
/// cross any of them.
@MainActor
final class BrowserSidebarPointerRows {
    // MARK: - Types

    /// One row's share of the pointer, observed by that row alone, so the
    /// pointer moving between rows updates only the two rows it leaves and
    /// reaches.
    @Observable
    @MainActor
    final class Row {
        fileprivate(set) var takesPointer: Bool

        fileprivate init(takesPointer: Bool) {
            self.takesPointer = takesPointer
        }
    }

    /// Whether only the row under the pointer takes it. Observed by every row,
    /// so it changes only when a button is pressed or let go.
    @Observable
    @MainActor
    final class Gate {
        fileprivate(set) var isNarrowed = true
    }

    // MARK: - Variables

    let gate = Gate()
    private var rows: [UUID: Row] = [:]
    private(set) var rowUnderPointer: UUID?

    // MARK: - Actions - Rows

    func row(for tabID: UUID) -> Row {
        if let row = rows[tabID] { return row }
        let row = Row(takesPointer: tabID == rowUnderPointer)
        rows[tabID] = row
        return row
    }

    /// Hands the pointer to the row now under it, or to none. Returns whether
    /// that changed which row takes it.
    @discardableResult
    func pointerMoved(to tabID: UUID?) -> Bool {
        guard tabID != rowUnderPointer else { return false }
        if let old = rowUnderPointer { rows[old]?.takesPointer = false }
        rowUnderPointer = tabID
        if let tabID { row(for: tabID).takesPointer = true }
        return true
    }

    /// Lets every row take the pointer, or only the one under it again.
    /// Returns whether that changed.
    @discardableResult
    func narrow(_ isNarrowed: Bool) -> Bool {
        guard gate.isNarrowed != isNarrowed else { return false }
        gate.isNarrowed = isNarrowed
        return true
    }
}

extension EnvironmentValues {
    /// Set by a list that tracks the row under the pointer itself.
    @Entry var browserSidebarPointerRows: BrowserSidebarPointerRows? = nil
}

/// Lets a tab row take the pointer only when its list says the pointer is
/// over it, or always in a list that does not track the pointer.
struct BrowserSidebarPointerGate: ViewModifier {
    let tabID: UUID

    @Environment(\.browserSidebarPointerRows) private var pointerRows

    func body(content: Content) -> some View {
        if let pointerRows {
            content.modifier(Gated(row: pointerRows.row(for: tabID), gate: pointerRows.gate))
        } else {
            content
        }
    }

    private struct Gated: ViewModifier {
        let row: BrowserSidebarPointerRows.Row
        let gate: BrowserSidebarPointerRows.Gate

        func body(content: Content) -> some View {
            content.allowsHitTesting(!gate.isNarrowed || row.takesPointer)
        }
    }
}
