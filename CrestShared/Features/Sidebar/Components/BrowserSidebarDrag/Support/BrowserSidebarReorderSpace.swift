import SwiftUI

/// Coordinate space for sidebar reordering.
///
/// Global rather than a named container: rows, folders, and space-picker
/// segments live in different branches of the sidebar hierarchy, and global
/// frames let one pointer location be compared against all of them without
/// every branch having to sit inside a shared container view.
enum BrowserSidebarReorderSpace {
    static var coordinateSpace: CoordinateSpace { .global }

    static var globalSpace: GlobalCoordinateSpace { .global }
}

/// Identifies the scroll viewport a reorder row or zone is rendered inside.
/// Fixed chrome leaves this unset, which is how the registry can clip only the
/// saved/current list geometry without clipping the pinned grid above it.
private struct BrowserSidebarScrollRegionIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var browserSidebarScrollRegionID: UUID? {
        get { self[BrowserSidebarScrollRegionIDKey.self] }
        set { self[BrowserSidebarScrollRegionIDKey.self] = newValue }
    }
}

/// The visible horizontal Space pager, independent of a page's vertical list.
private struct BrowserSidebarDropViewportIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var browserSidebarDropViewportID: UUID? {
        get { self[BrowserSidebarDropViewportIDKey.self] }
        set { self[BrowserSidebarDropViewportIDKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// Whether the scrolling list around a row is moving, so its reorder
    /// geometry waits and measures once it stops. Every move of a list would
    /// otherwise measure each of its rows again, on every frame. A drag in
    /// progress keeps the frames it lifted with and shifts them as its list
    /// scrolls, so nothing reads a paused frame.
    @Entry var browserSidebarReorderGeometryPaused = false
}

/// What a reorder registration measured: a value, nothing, which withdraws
/// it, or no measurement at all while its list scrolls, which keeps the one it
/// has.
enum BrowserSidebarReorderMeasurement<Value: Equatable & Sendable>: Equatable, Sendable {
    case paused
    case measured(Value?)
}
