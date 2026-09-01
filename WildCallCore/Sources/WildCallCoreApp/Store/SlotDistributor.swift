import Foundation
import WildCallCoreShared

/// What one extension slot receives.
public struct SlotPayload: Equatable, Sendable {
    public let slot: ExtensionSlot
    public let block: [NumberRange]
    public let ident: [IdentRange]

    public init(slot: ExtensionSlot, block: [NumberRange], ident: [IdentRange]) {
        self.slot = slot
        self.block = block
        self.ident = ident
    }

    public var totalNumbers: Int64 {
        RangeSet.total(block) + RangeSet.total(ident.map(\.range))
    }
}

public enum SlotDistributor {
    public enum Failure: Error, Equatable, Sendable {
        case exceedsCapacity(numbers: Int64, capacity: Int64)
    }

    /// Spreads normalized block and ident ranges across the slots, filling
    /// each one up to `perSlot` numbers in ascending order and splitting a
    /// range at the boundary when needed. Block ranges go first, then ident
    /// ranges : both count against the same per-extension ceiling.
    public static func distribute(
        block: [NumberRange],
        ident: [IdentRange],
        slots: [ExtensionSlot] = ExtensionSlot.all,
        perSlot: Int64
    ) throws -> [SlotPayload] {
        let total = RangeSet.total(block) + RangeSet.total(ident.map(\.range))
        let capacity = perSlot * Int64(slots.count)
        guard total <= capacity else {
            throw Failure.exceedsCapacity(numbers: total, capacity: capacity)
        }

        var payloads: [SlotPayload] = []
        var slotIndex = 0
        var remaining = perSlot
        var currentBlock: [NumberRange] = []
        var currentIdent: [IdentRange] = []

        func flush() {
            guard slotIndex < slots.count else { return }
            payloads.append(SlotPayload(slot: slots[slotIndex], block: currentBlock, ident: currentIdent))
            currentBlock = []
            currentIdent = []
            slotIndex += 1
            remaining = perSlot
        }

        // Generic filler : `append` stores a clipped piece into the current slot.
        func place(_ range: NumberRange, _ append: (NumberRange) -> Void) {
            var cursor = range
            while cursor.count > 0 {
                if remaining == 0 { flush() }
                let take = min(cursor.count, remaining)
                append(NumberRange(start: cursor.start, count: take))
                remaining -= take
                cursor = NumberRange(start: cursor.start + take, count: cursor.count - take)
            }
        }

        for range in block {
            place(range) { currentBlock.append($0) }
        }
        for entry in ident {
            place(entry.range) { currentIdent.append(IdentRange(range: $0, label: entry.label)) }
        }
        flush()
        while slotIndex < slots.count { flush() }   // empty payloads keep every slot's files current
        return payloads
    }
}
