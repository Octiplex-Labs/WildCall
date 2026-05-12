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
        guard let url = sharedStoreURL(named: "block.bin"),
              FileManager.default.fileExists(atPath: url.path)
        else { return }
        let reader = try BlockStoreReader(url: url)
        for number in reader.numbers {
            context.addBlockingEntry(withNextSequentialPhoneNumber: number)
        }
    }

    private func loadIdentificationEntries(into context: CXCallDirectoryExtensionContext) throws {
        guard let url = sharedStoreURL(named: "ident.bin"),
              FileManager.default.fileExists(atPath: url.path)
        else { return }
        let reader = try IdentStoreReader(url: url)
        for index in 0..<reader.count {
            let number = reader.numbers[index]
            let label = try reader.label(at: index)
            context.addIdentificationEntry(withNextSequentialPhoneNumber: number, label: label)
        }
    }

    private func sharedStoreURL(named name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.octiplex.wildcall")?
            .appendingPathComponent(name)
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: any Error) {
        // iOS surfaces this through the system log; nothing actionable here.
    }
}
