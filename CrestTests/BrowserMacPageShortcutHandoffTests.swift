import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserMacPageShortcutHandoffTests: XCTestCase {
    private let shortcut = BrowserShortcut(key: .character("s"), modifiers: .command)

    func testAKeyThePageKeepsRunsCrestsCommandWhenPressedAgain() async throws {
        let handoff = BrowserMacPageShortcutHandoff()
        var notices: [BrowserNotice] = []
        let offer: @MainActor (BrowserNotice) -> Void = { notices.append($0) }

        XCTAssertFalse(
            handoff.takesPress(of: .toggleSidebar, shortcut: shortcut, event: press(at: 1), offerNotice: offer))
        // The same press reaching the shell again on its way to the page is
        // still the page's.
        XCTAssertFalse(
            handoff.takesPress(of: .toggleSidebar, shortcut: shortcut, event: press(at: 1), offerNotice: offer))

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(notices, [.secondPress(of: shortcut, runs: .toggleSidebar)])

        XCTAssertTrue(
            handoff.takesPress(of: .toggleSidebar, shortcut: shortcut, event: press(at: 2), offerNotice: offer))
        // Crest took that press, so the one after is the page's again.
        XCTAssertFalse(
            handoff.takesPress(of: .toggleSidebar, shortcut: shortcut, event: press(at: 3), offerNotice: offer))
    }

    func testAKeyThePageLetsGoLeavesNothingWaiting() async throws {
        let handoff = BrowserMacPageShortcutHandoff()
        var notices: [BrowserNotice] = []
        let offer: @MainActor (BrowserNotice) -> Void = { notices.append($0) }

        let first = press(at: 1)
        XCTAssertFalse(
            handoff.takesPress(of: .toggleSidebar, shortcut: shortcut, event: first, offerNotice: offer))
        handoff.pageReleased(first)

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(notices, [])
        XCTAssertFalse(
            handoff.takesPress(of: .toggleSidebar, shortcut: shortcut, event: press(at: 2), offerNotice: offer))
    }

    private func press(at timestamp: TimeInterval) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: timestamp,
            windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s",
            isARepeat: false, keyCode: 1
        )!
    }
}
