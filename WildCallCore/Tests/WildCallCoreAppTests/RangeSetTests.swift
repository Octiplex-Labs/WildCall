import Foundation
import Testing
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct RangeSetTests {
    @Test func normalizeSortsMergesAndDropsEmpty() {
        let input: [NumberRange] = [
            NumberRange(start: 50, count: 10),
            NumberRange(start: 10, count: 5),
            NumberRange(start: 15, count: 5),   // adjacent to previous
            NumberRange(start: 55, count: 2),   // inside 50..<60
            NumberRange(start: 70, count: 0),   // empty
            NumberRange(start: 58, count: 10),  // overlaps 50..<60, extends to 68
        ]
        #expect(RangeSet.normalize(input) == [
            NumberRange(start: 10, count: 10),
            NumberRange(start: 50, count: 18),
        ])
    }

    @Test func normalizeDedupesExactNumbers() {
        let input: [NumberRange] = [.single(7), .single(7), .single(8)]
        #expect(RangeSet.normalize(input) == [NumberRange(start: 7, count: 2)])
    }

    @Test func subtractPunchesHoles() {
        let base = [NumberRange(start: 0, count: 100)]
        let holes = [NumberRange(start: 10, count: 5), NumberRange(start: 90, count: 20)]
        #expect(RangeSet.subtract(base, removing: holes) == [
            NumberRange(start: 0, count: 10),
            NumberRange(start: 15, count: 75),
        ])
    }

    @Test func subtractRemovesFullyCoveredRanges() {
        let base = [NumberRange(start: 10, count: 5), NumberRange(start: 30, count: 5)]
        let holes = [NumberRange(start: 0, count: 20)]
        #expect(RangeSet.subtract(base, removing: holes) == [NumberRange(start: 30, count: 5)])
    }

    @Test func subtractWithNoHolesReturnsNormalizedInput() {
        let base = [NumberRange(start: 5, count: 1), NumberRange(start: 1, count: 1)]
        #expect(RangeSet.subtract(base, removing: []) == [.single(1), .single(5)])
    }

    @Test func subtractSingleNumberFromWidePrefix() {
        // The real-world case : a pack blocks +33162*, the user identifies
        // one number inside it so that it rings.
        let base = [NumberRange(start: 33_162_000_000, count: 1_000_000)]
        let holes = [NumberRange.single(33_162_345_678)]
        #expect(RangeSet.subtract(base, removing: holes) == [
            NumberRange(start: 33_162_000_000, count: 345_678),
            NumberRange(start: 33_162_345_679, count: 654_321),
        ])
    }

    @Test func totalSumsCounts() {
        #expect(RangeSet.total([NumberRange(start: 0, count: 3), NumberRange(start: 9, count: 4)]) == 7)
        #expect(RangeSet.total([]) == 0)
    }

    @Test func normalizeIdentClipsOverlapsEarliestWins() {
        let input: [IdentRange] = [
            IdentRange(range: NumberRange(start: 10, count: 10), label: "B"),
            IdentRange(range: NumberRange(start: 0, count: 15), label: "A"),
        ]
        #expect(RangeSet.normalizeIdent(input) == [
            IdentRange(range: NumberRange(start: 0, count: 15), label: "A"),
            IdentRange(range: NumberRange(start: 15, count: 5), label: "B"),
        ])
    }

    @Test func normalizeIdentDropsFullyCoveredEntries() {
        let input: [IdentRange] = [
            IdentRange(range: NumberRange(start: 0, count: 20), label: "A"),
            IdentRange(range: NumberRange(start: 5, count: 3), label: "B"),
        ]
        #expect(RangeSet.normalizeIdent(input) == [
            IdentRange(range: NumberRange(start: 0, count: 20), label: "A"),
        ])
    }

    @Test func normalizeIdentMergesAdjacentSameLabelOnly() {
        let input: [IdentRange] = [
            IdentRange(range: NumberRange(start: 0, count: 5), label: "A"),
            IdentRange(range: NumberRange(start: 5, count: 5), label: "A"),
            IdentRange(range: NumberRange(start: 10, count: 5), label: "B"),
        ]
        #expect(RangeSet.normalizeIdent(input) == [
            IdentRange(range: NumberRange(start: 0, count: 10), label: "A"),
            IdentRange(range: NumberRange(start: 10, count: 5), label: "B"),
        ])
    }

    @Test func normalizeIdentSameStartWiderWins() {
        let input: [IdentRange] = [
            IdentRange(range: NumberRange(start: 0, count: 1), label: "narrow"),
            IdentRange(range: NumberRange(start: 0, count: 10), label: "wide"),
        ]
        #expect(RangeSet.normalizeIdent(input) == [
            IdentRange(range: NumberRange(start: 0, count: 10), label: "wide"),
        ])
    }

    @Test func truncateClipsToBudget() {
        let ranges = [NumberRange(start: 0, count: 10), NumberRange(start: 20, count: 10)]
        #expect(RangeSet.truncate(ranges, to: 15) == [NumberRange(start: 0, count: 10), NumberRange(start: 20, count: 5)])
        #expect(RangeSet.truncate(ranges, to: 0) == [])
        #expect(RangeSet.truncate(ranges, to: 100) == ranges)
    }
}
