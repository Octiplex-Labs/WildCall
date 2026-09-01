import CallKit
import Foundation
import WildCallCoreShared

/// Streams the ranges built by the app into CallKit.
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

        let root = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BlockStoreFormat.appGroupIdentifier)
        var report = ExtensionRunReport(startedAt: Date(), isIncremental: context.isIncremental)
        writeReport(report, root: root)

        do {
            if context.isIncremental {
                context.removeAllBlockingEntries()
                context.removeAllIdentificationEntries()
            }
            report.blockNumbers = try loadBlockingNumbers(root: root, into: context)
            report.identNumbers = try loadIdentificationEntries(root: root, into: context)
            report.outcome = .completed
            report.finishedAt = Date()
            writeReport(report, root: root)
            context.completeRequest()
        } catch {
            report.outcome = .failed
            report.finishedAt = Date()
            report.errorDescription = String(describing: error)
            writeReport(report, root: root)
            context.cancelRequest(withError: error)
        }
    }

    private func loadBlockingNumbers(root: URL?, into context: CXCallDirectoryExtensionContext) throws -> Int64 {
        guard let url = root?.appendingPathComponent(BlockStoreFormat.blockFileName),
              FileManager.default.fileExists(atPath: url.path)
        else { return 0 }
        let reader = try BlockStoreReader(url: url)
        reader.forEachNumber { number in
            context.addBlockingEntry(withNextSequentialPhoneNumber: number)
        }
        return reader.totalNumbers
    }

    private func loadIdentificationEntries(root: URL?, into context: CXCallDirectoryExtensionContext) throws -> Int64 {
        guard let url = root?.appendingPathComponent(BlockStoreFormat.identFileName),
              FileManager.default.fileExists(atPath: url.path)
        else { return 0 }
        let reader = try IdentStoreReader(url: url)
        reader.forEachNumber { number, label in
            context.addIdentificationEntry(withNextSequentialPhoneNumber: number, label: label)
        }
        return reader.totalNumbers
    }

    private func writeReport(_ report: ExtensionRunReport, root: URL?) {
        guard let url = root?.appendingPathComponent(BlockStoreFormat.extensionRunFileName) else { return }
        // Best effort : a failed report write must never abort the load.
        try? report.write(to: url)
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: any Error) {
        // Already captured in the run report; iOS also logs it.
    }
}
