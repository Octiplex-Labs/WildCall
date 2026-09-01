import Foundation
import Testing
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct IdentStoreBuilderTests {
    @Test func roundtripThroughReader() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let entries: [IdentRange] = [
            .init(range: .single(33_899_111_222), label: "Surtaxé"),
            .init(range: NumberRange(start: 33_162_000_000, count: 1_000_000), label: "ARCEP démarchage"),
            .init(range: NumberRange(start: 33_270_000_000, count: 1_000_000), label: "ARCEP démarchage"),
        ]
        let summary = try IdentStoreBuilder().build(entries: entries, to: url)
        #expect(summary.count == 2_000_001)
        #expect(summary.rangeCount == 3)

        let reader = try IdentStoreReader(url: url)
        #expect(reader.entries.map(\.range) == [
            NumberRange(start: 33_162_000_000, count: 1_000_000),
            NumberRange(start: 33_270_000_000, count: 1_000_000),
            .single(33_899_111_222),
        ])
        #expect(reader.entries.map(\.label) == ["ARCEP démarchage", "ARCEP démarchage", "Surtaxé"])
    }

    @Test func overlapKeepsEarliestEntry() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let entries: [IdentRange] = [
            .init(range: NumberRange(start: 10, count: 10), label: "Second"),
            .init(range: NumberRange(start: 0, count: 15), label: "First"),
        ]
        _ = try IdentStoreBuilder().build(entries: entries, to: url)
        let reader = try IdentStoreReader(url: url)
        #expect(reader.entries == [
            IdentRangeEntry(range: NumberRange(start: 0, count: 15), label: "First"),
            IdentRangeEntry(range: NumberRange(start: 15, count: 5), label: "Second"),
        ])
    }

    @Test func unicodeLabelRoundtrip() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let label = "Démarchage 📞 énergie verte"
        _ = try IdentStoreBuilder().build(entries: [.init(range: .single(33_162_999_999), label: label)], to: url)
        #expect(try IdentStoreReader(url: url).entries.first?.label == label)
    }

    @Test func emptyInputProducesValidEmptyBlob() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try IdentStoreBuilder().build(entries: [], to: url)
        #expect(summary.count == 0)
        #expect(try IdentStoreReader(url: url).rangeCount == 0)
    }
}
