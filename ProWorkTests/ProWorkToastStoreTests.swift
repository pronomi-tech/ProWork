//  ProWorkToastStoreTests.swift
//  ProWorkTests
//  unit tests for ProWorkToastStore — the lightweight
//  toast queue used across the app. Verifies whitespace handling, append
//  ordering, manual dismissal, and that empty messages are dropped.

import XCTest
@testable import ProWork

@MainActor
final class ProWorkToastStoreTests: XCTestCase {

    func test_show_appendsToastWithTrimmedMessage() {
        let store = ProWorkToastStore()
        store.show("   hello   ", style: .info)

        XCTAssertEqual(store.toasts.count, 1)
        XCTAssertEqual(store.toasts.first?.message, "hello")
        XCTAssertEqual(store.toasts.first?.style, .info)
    }

    func test_show_emptyOrWhitespaceMessage_isIgnored() {
        let store = ProWorkToastStore()
        store.show("", style: .info)
        store.show("   ", style: .error)

        XCTAssertTrue(store.toasts.isEmpty)
    }

    func test_show_multipleMessages_appendInOrder() {
        let store = ProWorkToastStore()
        store.show("first", style: .info)
        store.show("second", style: .success)
        store.show("third", style: .warning)

        XCTAssertEqual(store.toasts.map(\.message), ["first", "second", "third"])
        XCTAssertEqual(store.toasts.map(\.style), [.info, .success, .warning])
    }

    func test_dismiss_removesOnlyMatchingToast() {
        let store = ProWorkToastStore()
        store.show("a", style: .info)
        store.show("b", style: .info)
        store.show("c", style: .info)

        let middleId = store.toasts[1].id
        store.dismiss(id: middleId)

        XCTAssertEqual(store.toasts.map(\.message), ["a", "c"])
    }

    func test_dismiss_unknownId_noop() {
        let store = ProWorkToastStore()
        store.show("only", style: .info)
        let originalCount = store.toasts.count

        store.dismiss(id: UUID())

        XCTAssertEqual(store.toasts.count, originalCount)
    }

    func test_styleProperties_haveDistinctTints() {
        // Lock in that the 4 styles emit distinct symbols/tints so a future
        // change to the enum cannot silently collapse the visual difference.
        let styles: [ProWorkToastMessage.Style] = [.success, .error, .warning, .info]
        let symbols = Set(styles.map(\.systemImage))
        XCTAssertEqual(symbols.count, 4, "each toast style should have a unique system image")
    }
}

// MARK: - Equatable test conveniences

extension ProWorkToastMessage.Style: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success), (.error, .error), (.warning, .warning), (.info, .info):
            return true
        default:
            return false
        }
    }
}
