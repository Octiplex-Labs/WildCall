import Foundation
import WildCallCoreShared

public struct IdentRange: Hashable, Sendable {
    public let range: NumberRange
    public let label: String

    public init(range: NumberRange, label: String) {
        self.range = range
        self.label = label
    }
}

/// Pure set algebra over `NumberRange`. Everything the extension receives
/// goes through `normalize` so the on-disk invariants (sorted, disjoint,
/// non-empty) are guaranteed by construction.
public enum RangeSet {
    /// Drops empty ranges, sorts by start, merges overlapping and adjacent
    /// ranges into one.
    public static func normalize(_ ranges: [NumberRange]) -> [NumberRange] {
        let sorted = ranges
            .filter { $0.count > 0 }
            .sorted { $0.start < $1.start }
        var out: [NumberRange] = []
        out.reserveCapacity(sorted.count)
        for range in sorted {
            if let last = out.last, range.start <= last.end {
                let mergedEnd = max(last.end, range.end)
                out[out.count - 1] = NumberRange(start: last.start, count: mergedEnd - last.start)
            } else {
                out.append(range)
            }
        }
        return out
    }

    /// `ranges − removing`. Both inputs are normalized first.
    public static func subtract(_ ranges: [NumberRange], removing: [NumberRange]) -> [NumberRange] {
        let base = normalize(ranges)
        let holes = normalize(removing)
        guard !holes.isEmpty else { return base }

        var out: [NumberRange] = []
        var holeIndex = 0
        for range in base {
            var cursor = range.start
            let end = range.end
            // Skip holes entirely before this range.
            while holeIndex < holes.count, holes[holeIndex].end <= cursor {
                holeIndex += 1
            }
            var index = holeIndex
            while index < holes.count, holes[index].start < end {
                let hole = holes[index]
                if hole.start > cursor {
                    out.append(NumberRange(start: cursor, count: hole.start - cursor))
                }
                cursor = max(cursor, hole.end)
                if cursor >= end { break }
                index += 1
            }
            if cursor < end {
                out.append(NumberRange(start: cursor, count: end - cursor))
            }
        }
        return out
    }

    /// Keeps the leading ranges up to `limit` numbers, clipping the last one.
    /// Used by the debug ingestion-budget probe.
    public static func truncate(_ ranges: [NumberRange], to limit: Int64) -> [NumberRange] {
        var out: [NumberRange] = []
        var remaining = max(0, limit)
        for range in ranges {
            guard remaining > 0 else { break }
            let take = min(range.count, remaining)
            out.append(NumberRange(start: range.start, count: take))
            remaining -= take
        }
        return out
    }

    public static func total(_ ranges: [NumberRange]) -> Int64 {
        ranges.reduce(0) { $0 + max(0, $1.count) }
    }

    /// Sorts labelled ranges by start; when two overlap, the one that starts
    /// first keeps the contested numbers and the later one is clipped (or
    /// dropped when fully covered). Adjacent ranges sharing a label merge.
    public static func normalizeIdent(_ entries: [IdentRange]) -> [IdentRange] {
        let sorted = entries
            .filter { $0.range.count > 0 }
            .sorted {
                if $0.range.start != $1.range.start { return $0.range.start < $1.range.start }
                return $0.range.count > $1.range.count
            }
        var out: [IdentRange] = []
        out.reserveCapacity(sorted.count)
        for entry in sorted {
            var start = entry.range.start
            let end = entry.range.end
            if let last = out.last {
                start = max(start, last.range.end)
                guard start < end else { continue }
                if last.label == entry.label, last.range.end == start {
                    out[out.count - 1] = IdentRange(
                        range: NumberRange(start: last.range.start, count: end - last.range.start),
                        label: last.label
                    )
                    continue
                }
            }
            out.append(IdentRange(range: NumberRange(start: start, count: end - start), label: entry.label))
        }
        return out
    }
}
