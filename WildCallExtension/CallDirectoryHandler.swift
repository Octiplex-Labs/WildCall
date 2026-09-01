import CallKit
import Foundation
import WildCallCoreShared

/// Streams the ranges built by the app into CallKit. The same source is
/// compiled into every extension target; `WildCallSlot` in the Info.plist
/// tells each copy which files to read.
///
/// Two rules drive this file :
/// 1. iOS calls `beginRequest` with `isIncremental == true` on every reload
///    after the first successful one. Without clearing the previous entries
///    first, iOS would keep stale numbers (deleted rules) and refuse
///    duplicates. We always do a full replace : remove everything, then add
///    the current ranges. It is cheap on our side and always correct.
/// 2. Every run writes an `ExtensionRunReport` next to the store, because
///    the app otherwise has no idea whether the load worked or how long it
///    took.
final class CallDirectoryHandler: CXCallDirectoryProvider {
    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        let slot = ExtensionSlot.current()
        let root = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BlockStoreFormat.appGroupIdentifier)
        var report = ExtensionRunReport(startedAt: Date(), isIncremental: context.isIncremental)
        writeReport(report, slot: slot, root: root)
        WildCallLog.info("Extension \(slot.index): beginRequest incremental=\(context.isIncremental) root=\(root?.path ?? "nil")")

        do {
            if context.isIncremental {
                context.removeAllBlockingEntries()
                context.removeAllIdentificationEntries()
            }
            report.blockNumbers = try loadBlockingNumbers(url: root?.appendingPathComponent(slot.blockFileName), into: context)
            report.identNumbers = try loadIdentificationEntries(url: root?.appendingPathComponent(slot.identFileName), into: context)
            report.outcome = .completed
            report.finishedAt = Date()
            writeReport(report, slot: slot, root: root)
            WildCallLog.info("Extension \(slot.index): loaded \(report.blockNumbers) block + \(report.identNumbers) ident in \(Int(report.duration ?? 0)) s")
            context.completeRequest()
        } catch {
            WildCallLog.error("Extension \(slot.index): failed \(error)")
            report.outcome = .failed
            report.finishedAt = Date()
            report.errorDescription = String(describing: error)
            writeReport(report, slot: slot, root: root)
            context.cancelRequest(withError: error)
        }
    }

    private func loadBlockingNumbers(url: URL?, into context: CXCallDirectoryExtensionContext) throws -> Int64 {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let reader = try BlockStoreReader(url: url)
        reader.forEachNumber { number in
            context.addBlockingEntry(withNextSequentialPhoneNumber: number)
        }
        return reader.totalNumbers
    }

    private func loadIdentificationEntries(url: URL?, into context: CXCallDirectoryExtensionContext) throws -> Int64 {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let reader = try IdentStoreReader(url: url)
        reader.forEachNumber { number, label in
            context.addIdentificationEntry(withNextSequentialPhoneNumber: number, label: label)
        }
        return reader.totalNumbers
    }

    private func writeReport(_ report: ExtensionRunReport, slot: ExtensionSlot, root: URL?) {
        guard let url = root?.appendingPathComponent(slot.extensionRunFileName) else { return }
        // Best effort : a failed report write must never abort the load.
        try? report.write(to: url)
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: any Error) {
        // Already captured in the run report; iOS also logs it.
    }
}
