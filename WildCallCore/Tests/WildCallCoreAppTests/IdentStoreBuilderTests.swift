import Foundation
import Testing
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct IdentStoreBuilderTests {
    @Test func sortDedupeKeepsLastLabelPerNumber() {
        let entries: [IdentEntry] = [
            .init(number: 33_612_345_678, label: "Old"),
            .init(number: 33_899_000_000, label: "Surtaxé"),
            .init(number: 33_612_345_678, label: "Spam"),
        ]
        let result = IdentStoreBuilder.sortDedupe(entries)
        #expect(result.count == 2)
        #expect(result[0].number == 33_612_345_678)
        #expect(result[0].label == "Spam")
        #expect(result[1].number == 33_899_000_000)
    }

    @Test func roundtripThroughReader() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let builder = IdentStoreBuilder()
        let entries: [IdentEntry] = [
            .init(number: 33_899_111_222, label: "Surtaxé"),
            .init(number: 33_162_000_000, label: "ARCEP démarchage"),
            .init(number: 33_270_000_000, label: "ARCEP démarchage"),
        ]
        let summary = try builder.build(entries: entries, to: url)
        #expect(summary.count == 3)

        let reader = try IdentStoreReader(url: url)
        #expect(reader.count == 3)
        #expect(reader.numbers[0] == 33_162_000_000)
        #expect(try reader.label(at: 0) == "ARCEP démarchage")
        #expect(reader.numbers[1] == 33_270_000_000)
        #expect(reader.numbers[2] == 33_899_111_222)
        #expect(try reader.label(at: 2) == "Surtaxé")
    }

    @Test func unicodeLabelRoundtrip() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let builder = IdentStoreBuilder()
        let label = "Démarchage 📞 énergie verte"
        _ = try builder.build(
            entries: [.init(number: 33_162_999_999, label: label)],
            to: url
        )

        let reader = try IdentStoreReader(url: url)
        #expect(try reader.label(at: 0) == label)
    }

    @Test func emptyInputProducesValidEmptyBlob() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let builder = IdentStoreBuilder()
        let summary = try builder.build(entries: [], to: url)
        #expect(summary.count == 0)

        let reader = try IdentStoreReader(url: url)
        #expect(reader.count == 0)
    }
}
