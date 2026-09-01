import Foundation
import Testing
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct SlotDistributorTests {
    let slots = [ExtensionSlot(1), ExtensionSlot(2), ExtensionSlot(3)]

    @Test func fillsSlotsInOrderAndSplitsAtBoundaries() throws {
        let block = [NumberRange(start: 0, count: 25)]
        let payloads = try SlotDistributor.distribute(block: block, ident: [], slots: slots, perSlot: 10)
        #expect(payloads.map(\.slot) == slots)
        #expect(payloads[0].block == [NumberRange(start: 0, count: 10)])
        #expect(payloads[1].block == [NumberRange(start: 10, count: 10)])
        #expect(payloads[2].block == [NumberRange(start: 20, count: 5)])
        #expect(payloads.allSatisfy { $0.ident.isEmpty })
    }

    @Test func identRangesFollowBlockRangesAndShareTheCeiling() throws {
        let block = [NumberRange(start: 0, count: 8)]
        let ident = [IdentRange(range: NumberRange(start: 100, count: 5), label: "Spam")]
        let payloads = try SlotDistributor.distribute(block: block, ident: ident, slots: slots, perSlot: 10)
        #expect(payloads[0].block == [NumberRange(start: 0, count: 8)])
        #expect(payloads[0].ident == [IdentRange(range: NumberRange(start: 100, count: 2), label: "Spam")])
        #expect(payloads[1].ident == [IdentRange(range: NumberRange(start: 102, count: 3), label: "Spam")])
        #expect(payloads[2].totalNumbers == 0)
    }

    @Test func everySlotGetsAPayloadEvenWhenEmpty() throws {
        let payloads = try SlotDistributor.distribute(block: [], ident: [], slots: slots, perSlot: 10)
        #expect(payloads.count == 3)
        #expect(payloads.allSatisfy { $0.totalNumbers == 0 })
    }

    @Test func exactCapacityFits() throws {
        let block = [NumberRange(start: 0, count: 30)]
        let payloads = try SlotDistributor.distribute(block: block, ident: [], slots: slots, perSlot: 10)
        #expect(payloads.map(\.totalNumbers) == [10, 10, 10])
    }

    @Test func overCapacityThrows() {
        let block = [NumberRange(start: 0, count: 31)]
        #expect(throws: SlotDistributor.Failure.exceedsCapacity(numbers: 31, capacity: 30)) {
            try SlotDistributor.distribute(block: block, ident: [], slots: slots, perSlot: 10)
        }
    }

    @Test func realVolumeSpreadsOverFourSlots() throws {
        // 7.3 M ARCEP numbers + a few user rules, with the measured ceiling.
        let block = [NumberRange(start: 33_162_000_000, count: 7_291_000), .single(33_612_345_678)]
        let payloads = try SlotDistributor.distribute(block: block, ident: [], perSlot: 1_999_999)
        #expect(payloads.count == 4)
        #expect(payloads.map(\.totalNumbers) == [1_999_999, 1_999_999, 1_999_999, 1_291_004])
        #expect(payloads.allSatisfy { $0.totalNumbers <= 1_999_999 })
    }
}
