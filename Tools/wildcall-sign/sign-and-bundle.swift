#!/usr/bin/env swift

// Phase 4b prep: signs a pack manifest and bundles it into a .wildcallpack
// (tarball gzip) suitable for distribution via GitHub raw, Files-app import,
// or test fixtures.
//
// Usage:
//   WILDCALL_SIGN_KEY=<64-hex-private> \
//     swift Tools/wildcall-sign/sign-and-bundle.swift path/to/manifest.json [path/to/payload.bin]
//
// Outputs (next to the input manifest):
//   - manifest.sig          (raw 64-byte Ed25519 signature over manifest.json bytes)
//   - <manifest-name>.wildcallpack  (tarball gzip containing manifest.json + manifest.sig
//                                    + payload.bin if provided)
//
// The script shells out to /usr/bin/tar for the gzip+tarball step.
// SWCompression is not importable from standalone Swift scripts so we
// trust the system tar to produce a format that SWCompression can read.

import CryptoKit
import Foundation

extension Data {
    init?(hex: String) {
        let cleaned = hex.lowercased().filter { "0123456789abcdef".contains($0) }
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}

func die(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
}

let args = CommandLine.arguments
guard args.count == 2 || args.count == 3 else {
    print("usage: sign-and-bundle.swift <manifest.json> [<payload.bin>]")
    print("       expects WILDCALL_SIGN_KEY env var (64 hex chars = 32 bytes)")
    exit(1)
}

guard let privateHex = ProcessInfo.processInfo.environment["WILDCALL_SIGN_KEY"] else {
    die("set WILDCALL_SIGN_KEY env var with the 64-hex private key")
}
guard let privateBytes = Data(hex: privateHex), privateBytes.count == 32 else {
    die("private key must be 64 hex chars (32 bytes)")
}

let signingKey: Curve25519.Signing.PrivateKey
do {
    signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateBytes)
} catch {
    die("invalid private key bytes: \(error)")
}

let manifestURL = URL(filePath: args[1])
let manifestData: Data
do {
    manifestData = try Data(contentsOf: manifestURL)
} catch {
    die("cannot read manifest at \(manifestURL.path): \(error)")
}

guard let _ = try? JSONSerialization.jsonObject(with: manifestData) else {
    die("manifest is not valid JSON: \(manifestURL.path)")
}

let signature: Data
do {
    signature = try signingKey.signature(for: manifestData)
} catch {
    die("signing failed: \(error)")
}

let workdir = manifestURL.deletingLastPathComponent()
let manifestBasename = manifestURL.lastPathComponent
let sigBasename = "manifest.sig"
let payloadBasename = "payload.bin"

// Strip the conventional ".source" qualifier from the input filename when
// naming the outputs : "fr.arcep-extra.source.json" becomes
// "fr.arcep-extra.wildcallpack" + "fr.arcep-extra.sig", not the redundant
// ".source.wildcallpack" / ".source.sig".
let rawBaseName = manifestURL.deletingPathExtension().lastPathComponent
let outputBaseName = rawBaseName.hasSuffix(".source")
    ? String(rawBaseName.dropLast(".source".count))
    : rawBaseName
let outputBasename = outputBaseName + ".wildcallpack"

// Stage the files in a temp dir so the tarball entries are flat (no leading
// path) and we don't pollute the workdir with renamed intermediates.
let stage = URL(filePath: NSTemporaryDirectory())
    .appendingPathComponent("wildcall-sign-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: stage) }

let stagedManifest = stage.appendingPathComponent("manifest.json")
let stagedSig = stage.appendingPathComponent(sigBasename)
try manifestData.write(to: stagedManifest)
try signature.write(to: stagedSig)

var tarMembers = ["manifest.json", sigBasename]

if args.count == 3 {
    let payloadURL = URL(filePath: args[2])
    let payloadData: Data
    do {
        payloadData = try Data(contentsOf: payloadURL)
    } catch {
        die("cannot read payload at \(payloadURL.path): \(error)")
    }
    let stagedPayload = stage.appendingPathComponent(payloadBasename)
    try payloadData.write(to: stagedPayload)
    tarMembers.append(payloadBasename)
}

let outputURL = workdir.appendingPathComponent(outputBasename)
let tar = Process()
tar.executableURL = URL(filePath: "/usr/bin/tar")
tar.currentDirectoryURL = stage
tar.arguments = ["-czf", outputURL.path] + tarMembers
let stderrPipe = Pipe()
tar.standardError = stderrPipe
do {
    try tar.run()
} catch {
    die("/usr/bin/tar failed to launch: \(error)")
}
tar.waitUntilExit()
if tar.terminationStatus != 0 {
    let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    die("tar exited with status \(tar.terminationStatus): \(err)")
}

let memberList = tarMembers.joined(separator: ", ")
print("signed: \(outputURL.path)")
print("manifest bytes: \(manifestData.count)")
print("signature bytes: \(signature.count)")
print("members: \(memberList)")

// Also persist manifest.sig alongside the manifest for inspection / re-bundling.
// Uses the same ".source"-stripped basename as the .wildcallpack output.
let persistedSig = workdir.appendingPathComponent("\(outputBaseName).sig")
try? FileManager.default.removeItem(at: persistedSig)
try signature.write(to: persistedSig)
print("sig file: \(persistedSig.path)")
_ = manifestBasename  // suppress unused warning
