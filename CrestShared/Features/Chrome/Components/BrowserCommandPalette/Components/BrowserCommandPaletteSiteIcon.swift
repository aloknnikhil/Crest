import SwiftUI

/// A result's site icon, drawn at once when this session has drawn it before
/// and otherwise loaded once, with the row's symbol until it arrives.
struct BrowserCommandPaletteSiteIcon: View {
    let model: BrowserCommandPaletteModel
    let site: BrowserCommandPaletteModel.Site
    let symbol: String

    @Environment(\.browserSpaceContentIsLocked) private var isLocked
    @State private var loaded: (key: BrowserSiteIconCache.Key, image: CGImage)?

    private var size: CGFloat { BrowserCommandPaletteMetrics.rowFaviconSize }

    private var key: BrowserSiteIconCache.Key? {
        BrowserSiteIconCache.Key(
            pageURL: site.pageURL, profileID: site.profileID,
            pixelSize: TabFaviconMetrics.maximumDecodedPixelSize(for: size))
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: TabFaviconMetrics.renderedImageScale)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: TabFaviconMetrics.cornerRadius(for: size)))
                    .frame(width: size, height: size)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: BrowserCommandPaletteMetrics.rowSymbolPointSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: key) { await load() }
    }

    /// A locked Space shows no site icons, so none is looked up or fetched.
    private var image: CGImage? {
        guard !isLocked, let key else { return nil }
        if let loaded, loaded.key == key { return loaded.image }
        return BrowserSiteIconCache.shared.image(cachedFor: key)
    }

    private func load() async {
        guard !isLocked, let key, BrowserSiteIconCache.shared.image(cachedFor: key) == nil else { return }
        let model = model
        guard
            let image = await BrowserSiteIconCache.shared.image(
                for: key, pageURL: site.pageURL, fetches: site.fetchesIcon,
                localIcon: { model.tabIcon(host: key.host, profileID: key.profileID) }),
            !Task.isCancelled
        else { return }
        loaded = (key, image)
    }
}
