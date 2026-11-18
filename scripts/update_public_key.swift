// Derive only the public key from Sparkle's current 32-byte seed-file format.
// No Keychain APIs, key generation, or private-key output.
import CryptoKit
import Foundation

do {
    guard CommandLine.arguments.count == 2,
          let seed = Data(base64Encoded: try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)),
          seed.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    print(key.publicKey.rawRepresentation.base64EncodedString())
} catch {
    fputs("Could not derive public update key from the supplied seed file.\n", stderr)
    exit(1)
}
