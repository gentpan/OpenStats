import Foundation
import Observation
import Testing
@testable import OpenStatsUI

@MainActor
@Suite struct MenuBarOrderTests {
    private func defaults() -> UserDefaults {
        let name = "OpenStatsUITests.MenuBarOrder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func oldPreferencesKeepTheOriginalOrder() {
        let settings = AppSettings(defaults: defaults())
        settings.menuBarLayout = .combined
        #expect(settings.menuBarOrder == MenuBarItem.allCases)
        #expect(settings.drawnMenuBarItems == [.cpu, .memory, .network])
    }

    @Test func invalidAndIncompleteStoredOrderIsCompletedWithoutDuplicates() {
        let stored = defaults()
        stored.set(["gpu", "unknown", "gpu", "cpu"], forKey: "menuBarOrder")
        let settings = AppSettings(defaults: stored)
        #expect(settings.menuBarOrder == [.gpu, .cpu, .memory, .network, .disk, .temperature, .fan, .battery])
        #expect(Set(settings.menuBarOrder) == Set(MenuBarItem.allCases))
    }

    @Test func reorderedItemsPersistAndOnlyAffectCombinedIndicators() {
        let stored = defaults()
        let settings = AppSettings(defaults: stored)
        settings.menuBarItems = [.cpu, .memory, .gpu]
        settings.menuBarLayout = .combined
        settings.setMenuBarOrder([.gpu, .memory, .cpu])
        #expect(settings.drawnMenuBarItems == [.gpu, .memory, .cpu])

        let reloaded = AppSettings(defaults: stored)
        #expect(reloaded.menuBarOrder == settings.menuBarOrder)
        #expect(reloaded.drawnMenuBarItems == [.gpu, .memory, .cpu])
        reloaded.menuBarLayout = .separate
        #expect(reloaded.drawnMenuBarItems == [.cpu, .memory, .gpu])
        reloaded.menuBarLayout = .iconOnly
        #expect(reloaded.drawnMenuBarItems.isEmpty)
        reloaded.menuBarLayout = .combined
        #expect(reloaded.drawnMenuBarItems == [.gpu, .memory, .cpu])
    }

    @Test func disablingAnItemRetainsItsPlaceForReenabling() {
        let settings = AppSettings(defaults: defaults())
        settings.menuBarLayout = .combined
        settings.setMenuBarOrder([.network, .cpu, .memory])
        settings.setEnabled(.cpu, false)
        #expect(settings.drawnMenuBarItems == [.network, .memory])
        settings.setEnabled(.cpu, true)
        #expect(settings.drawnMenuBarItems == [.network, .cpu, .memory])
    }

    @Test func movesSwapNeighborsAndStopAtTheEdges() {
        let settings = AppSettings(defaults: defaults())
        settings.moveMenuBarItem(.cpu, by: -1)
        settings.moveMenuBarItem(.battery, by: 1)
        #expect(settings.menuBarOrder == MenuBarItem.allCases)
        settings.moveMenuBarItem(.memory, by: -1)
        #expect(Array(settings.menuBarOrder.prefix(3)) == [.memory, .cpu, .network])
        settings.moveMenuBarItem(.memory, by: 1)
        #expect(settings.menuBarOrder == MenuBarItem.allCases)
    }

    @Test func orderRoundTripsThroughSettingsSync() throws {
        let source = AppSettings(defaults: defaults())
        source.menuBarLayout = .combined
        source.setMenuBarOrder([.network, .gpu, .memory, .cpu])
        let data = try JSONEncoder().encode(source.exportDocument())
        let document = try JSONDecoder().decode(SettingsDocument.self, from: data)
        let target = AppSettings(defaults: defaults())
        target.apply(document)
        #expect(target.menuBarOrder == source.menuBarOrder)
        #expect(target.drawnMenuBarItems == source.drawnMenuBarItems)
        #expect(target.exportDocument() == source.exportDocument())
    }

    @Test func oldCloudDocumentsPreserveTheCustomizedOrder() throws {
        let settings = AppSettings(defaults: defaults())
        settings.setMenuBarOrder([.gpu, .cpu])
        let order = settings.menuBarOrder
        let oldDocument = try JSONDecoder().decode(SettingsDocument.self, from: Data(#"{"schema":1,"menuBarItems":["cpu"]}"#.utf8))
        #expect(oldDocument.menuBarOrder == nil)
        settings.apply(oldDocument)
        #expect(settings.menuBarOrder == order)
    }

    @Test func cloudOrderDropsUnknownsAndCompletesMissingItems() {
        let settings = AppSettings(defaults: defaults())
        var document = SettingsDocument()
        document.menuBarOrder = ["fan", "future", "fan", "cpu"]
        settings.apply(document)
        #expect(settings.menuBarOrder == [.fan, .cpu, .memory, .network, .gpu, .disk, .temperature, .battery])
    }

    @Test func orderChangesInvalidateTheMenuBarObservation() async {
        let settings = AppSettings(defaults: defaults())
        settings.menuBarLayout = .combined
        await confirmation("menu bar redraw", expectedCount: 1) { confirm in
            withObservationTracking {
                _ = settings.drawnMenuBarItems
            } onChange: {
                confirm()
            }
            settings.moveMenuBarItem(.memory, by: -1)
        }
    }
}
