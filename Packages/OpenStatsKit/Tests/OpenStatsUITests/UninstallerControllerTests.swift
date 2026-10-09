import Cleaner
import Foundation
import Testing
@testable import OpenStatsUI

@Suite struct UninstallResultSummaryTests {
    private let app = InstalledApp(url: URL(fileURLWithPath: "/Applications/Example.app"), name: "Example",
                                   bundleIdentifier: "com.example.app", version: nil, teamIdentifier: nil)

    private func item(_ path: String, kind: AppLeftover.Kind, size: UInt64, review: Bool = false) -> AppLeftover {
        AppLeftover(url: URL(fileURLWithPath: path), kind: kind, size: size, requiresReview: review)
    }

    @MainActor
    @Test func sharedAndNameOnlyCandidatesStartUnselected() {
        let body = item(app.url.path, kind: .application, size: 1_000)
        let cache = item("/Users/test/Library/Caches/com.example.app", kind: .caches, size: 200)
        let shared = item("/Users/test/Library/Group Containers/team.shared", kind: .containers, size: 300, review: true)
        let nameOnly = item("/Users/test/Library/Application Support/Example", kind: .support, size: 400, review: true)

        #expect(UninstallerController.initialSelection(for: [body, cache, shared, nameOnly]) == [body.id, cache.id])
    }

    @Test func movingOnlyResidualsDoesNotCountAsUninstall() {
        let body = item(app.url.path, kind: .application, size: 1_000)
        let cache = item("/Users/test/Library/Caches/com.example.app", kind: .caches, size: 200)
        let summary = UninstallResultSummary(app: app, requested: [body, cache], movedSources: [cache.url])

        #expect(summary.applicationWasRequested)
        #expect(!summary.applicationMoved)
        #expect(summary.successfulItems == [cache])
        #expect(summary.failedItems == [body])
        #expect(summary.movedCount == 1 && summary.leftoverCount == 1)
        #expect(summary.freedBytes == 200)
        #expect(summary.isPartial)
    }

    @Test func partialUninstallCountsOnlySuccessfulFilesAndKeepsFailures() {
        let body = item(app.url.path, kind: .application, size: 1_000)
        let cache = item("/Users/test/Library/Caches/com.example.app", kind: .caches, size: 200)
        let preferences = item("/Users/test/Library/Preferences/com.example.app.plist", kind: .preferences, size: 50)
        let summary = UninstallResultSummary(app: app, requested: [body, cache, preferences], movedSources: [body.url, preferences.url])

        #expect(summary.applicationMoved)
        #expect(summary.successfulItems == [body, preferences])
        #expect(summary.failedItems == [cache])
        #expect(summary.movedCount == 2 && summary.leftoverCount == 1)
        #expect(summary.freedBytes == 1_050)
        #expect(summary.isPartial)
    }

    @Test func residualRetryDoesNotCountTheApplicationTwice() {
        let cache = item("/Users/test/Library/Caches/com.example.app", kind: .caches, size: 200)
        let summary = UninstallResultSummary(app: app, requested: [cache], movedSources: [cache.url])

        #expect(!summary.applicationWasRequested && !summary.applicationMoved)
        #expect(summary.movedCount == 1 && summary.leftoverCount == 1)
        #expect(summary.freedBytes == 200)
        #expect(summary.failedItems.isEmpty && !summary.isPartial)
    }

    @Test func unexpectedSourceURLsDoNotInflateTheResult() {
        let body = item(app.url.path, kind: .application, size: 1_000)
        let cache = item("/Users/test/Library/Caches/com.example.app", kind: .caches, size: 200)
        let unknown = URL(fileURLWithPath: "/Users/test/Library/Caches/other.app")
        let summary = UninstallResultSummary(app: app, requested: [body, cache], movedSources: [cache.url, unknown])

        #expect(summary.movedCount == 1)
        #expect(summary.freedBytes == 200)
        #expect(!summary.applicationMoved && summary.failedItems == [body])
    }

    @Test func noSuccessfulMoveLeavesEveryRequestedItemAvailableForRetry() {
        let body = item(app.url.path, kind: .application, size: 1_000)
        let cache = item("/Users/test/Library/Caches/com.example.app", kind: .caches, size: 200)
        let summary = UninstallResultSummary(app: app, requested: [body, cache], movedSources: [])

        #expect(summary.successfulItems.isEmpty && summary.failedItems == [body, cache])
        #expect(summary.movedCount == 0 && summary.freedBytes == 0)
        #expect(!summary.applicationMoved && summary.isPartial)
    }
}
