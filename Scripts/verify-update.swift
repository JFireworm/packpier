import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4, let key = Data(base64Encoded: arguments[1]),
      let signature = Data(base64Encoded: arguments[2]) else {
    throw CocoaError(.fileReadCorruptFile)
}
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[3]), options: .mappedIfSafe)
guard publicKey.isValidSignature(signature, for: archive) else {
    throw CocoaError(.fileReadCorruptFile)
}
print("PASS archive Ed25519 signature")
