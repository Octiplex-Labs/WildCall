import Foundation
import Testing
@testable import WildCallCoreShared

@Suite struct NumberRangeTests {
    @Test func boundsAndContainment() {
        let range = NumberRange(start: 33_162_000_000, count: 1_000_000)
        #expect(range.end == 33_163_000_000)
        #expect(range.last == 33_162_999_999)
        #expect(range.contains(33_162_000_000))
        #expect(range.contains(33_162_999_999))
        #expect(!range.contains(33_163_000_000))
        #expect(!range.contains(33_161_999_999))
    }

    @Test func singleAndEmpty() {
        #expect(NumberRange.single(42) == NumberRange(start: 42, count: 1))
        #expect(NumberRange(start: 1, count: 0).isEmpty)
        #expect(!NumberRange.single(1).isEmpty)
    }
}
