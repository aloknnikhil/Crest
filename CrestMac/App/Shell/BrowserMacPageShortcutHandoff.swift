import AppKit

/// A Crest shortcut a page saw first. When the page keeps the key, such as a
/// document editor's ⌘S, the window says the shortcut runs Crest's command if
/// pressed again soon, and the next press goes to Crest instead of the page.
/// A key the page lets go reaches the menu bar, which runs the command then
/// and leaves nothing waiting.
@MainActor
final class BrowserMacPageShortcutHandoff {
    // MARK: - Types

    private struct Offer {
        let command: ShortcutCommand
        let shortcut: BrowserShortcut
        /// The key down the page was offered; one press reaches the shell more
        /// than once on its way to the page.
        let eventTime: TimeInterval
        let offeredAt: ContinuousClock.Instant
    }

    // MARK: - Static Variables

    /// How long the page has to let a key go before the window offers the
    /// second press.
    private static let releaseWait = Duration.milliseconds(350)
    /// How long a second press still runs Crest's command.
    private static let secondPressWindow = Duration.seconds(2)

    // MARK: - Variables

    private var offer: Offer?
    private var notice: Task<Void, Never>?

    // MARK: - Actions - Key presses

    /// Whether this press of `shortcut` should run `command` now, ahead of the
    /// page, because the page kept the previous one. Otherwise the press is
    /// the page's, and the window offers the second press if the page keeps
    /// it.
    func takesPress(
        of command: ShortcutCommand, shortcut: BrowserShortcut, event: NSEvent,
        offerNotice: @escaping @MainActor (BrowserNotice) -> Void
    ) -> Bool {
        guard !event.isARepeat else { return false }
        if let offer, offer.eventTime == event.timestamp { return false }
        if let offer, offer.command == command, offer.shortcut == shortcut,
            ContinuousClock.now - offer.offeredAt < Self.secondPressWindow
        {
            clear()
            return true
        }
        clear()
        let offer = Offer(
            command: command, shortcut: shortcut, eventTime: event.timestamp, offeredAt: .now)
        self.offer = offer
        notice = Task { [weak self] in
            try? await Task.sleep(for: Self.releaseWait)
            guard let self, !Task.isCancelled, self.offer?.eventTime == offer.eventTime else { return }
            offerNotice(.secondPress(of: shortcut, runs: command))
        }
        return false
    }

    /// A key reached the menu bar, so the page let it go.
    func pageReleased(_ event: NSEvent) {
        guard offer?.eventTime == event.timestamp else { return }
        clear()
    }

    // MARK: - Mutators

    private func clear() {
        offer = nil
        notice?.cancel()
        notice = nil
    }
}
