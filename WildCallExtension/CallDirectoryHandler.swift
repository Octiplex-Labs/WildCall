import CallKit
import Foundation
import WildCallCoreShared

final class CallDirectoryHandler: CXCallDirectoryProvider {
    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        do {
            try loadBlockingNumbers(into: context)
            try loadIdentificationEntries(into: context)
            context.completeRequest()
        } catch {
            context.cancelRequest(withError: error)
        }
    }

    private func loadBlockingNumbers(into context: CXCallDirectoryExtensionContext) throws {
        guard let url = sharedStoreURL(named: "block.bin") else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let reader = try BlockStoreReader(url: url, expectedMagic: BlockStoreFormat.blockMagic)
        for number in reader.numbers {
            context.addBlockingEntry(withNextSequentialPhoneNumber: number)
        }
    }

    private func loadIdentificationEntries(into context: CXCallDirectoryExtensionContext) throws {
        // ident.bin parsing arrives in Phase 1 (separate format with string table).
    }

    private func sharedStoreURL(named name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.octiplex.wildcall")?
            .appendingPathComponent(name)
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        // iOS will surface this — nothing to do here besides letting it propagate.
    }
}
