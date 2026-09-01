import Foundation
import Testing
@testable import WildCallCoreShared

@Suite struct ExtensionSlotTests {
    @Test func slotOneKeepsTheOriginalBundleIdentifier() {
        #expect(ExtensionSlot(1).bundleIdentifier == "com.octiplex.wildcall.directory")
        #expect(ExtensionSlot(2).bundleIdentifier == "com.octiplex.wildcall.directory2")
        #expect(ExtensionSlot.all.map(\.index) == [1, 2, 3, 4])
    }

    @Test func fileNamesAreDistinctPerSlot() {
        let names = ExtensionSlot.all.flatMap { [$0.blockFileName, $0.identFileName, $0.extensionRunFileName] }
        #expect(Set(names).count == names.count)
        #expect(ExtensionSlot(3).blockFileName == "block-3.bin")
    }

    @Test func currentFallsBackToSlotOne() {
        #expect(ExtensionSlot.current(bundle: Bundle(for: Marker.self)) == ExtensionSlot(1))
    }

    private final class Marker {}
}
