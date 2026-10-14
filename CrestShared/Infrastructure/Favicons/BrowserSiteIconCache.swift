import CoreGraphics
import Foundation

/// The icons of sites a list names without a tab of its own, such as the
/// command palette's history and saved results, decoded once per site,
/// profile and size and kept for the rest of the session, so a result seen
/// before draws its icon at once.
///
/// An icon comes first from a tab of the same profile already wearing that
/// site's icon, which needs no network, and otherwise from the site itself
/// through `BrowserFaviconFallbackLoader`, only when the caller allows it.
@MainActor
final class BrowserSiteIconCache {
    // MARK: - Types

    /// One site's icon in one profile at one decoded size. The host drops a
    /// leading `www.`, since a site wears the same icon either way.
    struct Key: Hashable {
        let host: String
        let profileID: UUID
        let pixelSize: Int

        init?(pageURL: URL, profileID: UUID, pixelSize: Int) {
            guard let host = Self.host(of: pageURL) else { return nil }
            self.host = host
            self.profileID = profileID
            self.pixelSize = pixelSize
        }

        /// The host an icon is kept under, or nil for an address without one.
        static func host(of pageURL: URL) -> String? {
            guard let host = pageURL.host()?.lowercased(), !host.isEmpty else { return nil }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    // MARK: - Static Variables

    static let shared = BrowserSiteIconCache()
    private static let capacity = 512

    // MARK: - Variables

    private var images: [Key: CGImage] = [:]
    private var recency: [Key] = []
    /// Sites with no icon from either source, so they are not asked again.
    private var missing: Set<Key> = []
    /// One load per site at a time, however many rows ask for it.
    private var loads: [Key: Task<CGImage?, Never>] = [:]
    private let fallback: BrowserFaviconFallbackLoader

    // MARK: - Initializers

    init(fallback: BrowserFaviconFallbackLoader = .shared) {
        self.fallback = fallback
    }

    // MARK: - Actions - Lookup

    /// The icon already decoded for `key`, without waiting.
    func image(cachedFor key: Key) -> CGImage? {
        images[key]
    }

    /// The icon for `key`: one a tab already wears, as `localIcon` finds it,
    /// else the site's own when `fetches` allows the network.
    func image(
        for key: Key, pageURL: URL, fetches: Bool, localIcon: () -> Data?
    ) async -> CGImage? {
        if let image = images[key] {
            touch(key)
            return image
        }
        if missing.contains(key) { return nil }
        if let load = loads[key] { return await load.value }
        let local = localIcon()
        guard local != nil || fetches else { return nil }
        let fallback = fallback
        let load = Task<CGImage?, Never> {
            var data = local
            if data == nil { data = await fallback.data(for: pageURL, profileID: key.profileID) }
            guard let data else { return nil }
            return await BrowserFaviconImageDecoder.decode(data, maximumPixelSize: key.pixelSize)
        }
        loads[key] = load
        let image = await load.value
        loads[key] = nil
        if let image {
            insert(image, for: key)
        } else if fetches {
            missing.insert(key)
        }
        return image
    }

    // MARK: - Mutators

    private func insert(_ image: CGImage, for key: Key) {
        images[key] = image
        touch(key)
        while recency.count > Self.capacity, let oldest = recency.first {
            recency.removeFirst()
            images[oldest] = nil
        }
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
