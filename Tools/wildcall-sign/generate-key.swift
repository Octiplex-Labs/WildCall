#!/usr/bin/env swift

// Phase 4a C3 (minimal): generates a fresh Curve25519 (Ed25519) signing key pair
// for the Octiplex publisher identity.
//
// Usage:
//   swift Tools/wildcall-sign/generate-key.swift
//
// Output (stdout):
//   private (KEEP SECRET, 64 hex chars / 32 bytes)
//   public  (paste into OctiplexTrust.publicKey, 64 hex chars / 32 bytes)
//   fingerprint (8 hex pairs, for human verification)
//
// Store the private key out-of-band : never commit it. Recommended:
// 1Password item "Octiplex pack signing key" or an env file outside the repo.
//
// Run once per publisher identity. If the key is lost, packs already signed
// remain verifiable but new packs cannot be issued under the same identity.

import CryptoKit
import Foundation

let privateKey = Curve25519.Signing.PrivateKey()
let publicKey = privateKey.publicKey

func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

func fingerprint(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.prefix(8)
        .map { String(format: "%02X", $0) }
        .joined(separator: ":")
}

let privateHex = hex(privateKey.rawRepresentation)
let publicHex = hex(publicKey.rawRepresentation)
let fp = fingerprint(publicKey.rawRepresentation)

print("# WildCall publisher signing key pair (Curve25519 / Ed25519)")
print("# generated \(ISO8601DateFormatter().string(from: Date()))")
print("")
print("private: \(privateHex)")
print("public:  \(publicHex)")
print("fingerprint: \(fp)")
print("")
print("# Next steps:")
print("# 1. Store the private key out-of-band (1Password / gitignored .env).")
print("#    DO NOT commit it.")
print("# 2. Paste the public-key bytes into")
print("#    WildCallCore/Sources/WildCallCoreApp/Manifest/PackSignatureVerifier.swift")
print("#    (the OctiplexTrust.publicKey constant).")
print("# 3. The fingerprint is what users see during TOFU; share it on your")
print("#    project page so users can verify the key out-of-band.")
