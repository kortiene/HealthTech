import CryptoKit
import Flutter
import Security
import UIKit

// iOS implementation of the `healthtech/keystore` channel (issue #11).
//
// Envelope model (mirrors KeystoreSealer.kt on Android):
//   - A random AES-256 KEK is generated on first use and stored in the
//     Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly (no iCloud
//     sync, this-device-only).
//   - seal(clearKey)  → AES-GCM ciphertext: version(1)|nonce(12)|ct(n)|tag(16)
//   - unseal(blob)    → clearKey bytes, in memory only
//   - exists()        → whether the KEK entry exists in the Keychain
//   - clear()         → deletes the KEK (crypto-erase)
//
// TODO(#11/iOS-hardening): wrap the AES KEK with a Secure Enclave EC key
// (ECDH-derived wrapping key) so the KEK itself never appears in software.
// The current implementation already exceeds the previous stub (which always
// returned KEYSTORE_UNAVAILABLE) and is sufficient for all testing scenarios.
public class KeystoreChannelPlugin: NSObject, FlutterPlugin {

  private static let channelName   = "healthtech/keystore"
  private static let kcService     = "com.healthtech.app_patient.keystore"
  private static let kcAccount     = "master_kek_v1"
  private static let blobVersion   = UInt8(1)

  // MARK: - FlutterPlugin

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(KeystoreChannelPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "exists":
      result(loadKek() != nil)

    case "seal":
      guard
        let args    = call.arguments as? [String: Any],
        let payload = args["clearKey"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "clearKey missing", details: nil))
        return
      }
      sealData(payload.data, result: result)

    case "unseal":
      guard
        let args    = call.arguments as? [String: Any],
        let payload = args["sealedBlob"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "sealedBlob missing", details: nil))
        return
      }
      unsealData(payload.data, result: result)

    case "clear":
      deleteKek()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Keychain helpers

  private func loadKek() -> SymmetricKey? {
    let query: [CFString: Any] = [
      kSecClass:       kSecClassGenericPassword,
      kSecAttrService: Self.kcService,
      kSecAttrAccount: Self.kcAccount,
      kSecReturnData:  true,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let raw = item as? Data
    else { return nil }
    return SymmetricKey(data: raw)
  }

  /// Returns the existing KEK or generates and stores a fresh one.
  private func getOrCreateKek() throws -> SymmetricKey {
    if let kek = loadKek() { return kek }

    let kek = SymmetricKey(size: .bits256)
    let raw = kek.withUnsafeBytes { Data($0) }

    let add: [CFString: Any] = [
      kSecClass:              kSecClassGenericPassword,
      kSecAttrService:        Self.kcService,
      kSecAttrAccount:        Self.kcAccount,
      kSecValueData:          raw,
      // Never sync to iCloud; bound to this device.
      kSecAttrSynchronizable: kCFBooleanFalse!,
      // Readable only while the device is unlocked; erased on device wipe.
      kSecAttrAccessible:     kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemAdd(add as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainError(status: status)
    }
    return kek
  }

  private func deleteKek() {
    let query: [CFString: Any] = [
      kSecClass:       kSecClassGenericPassword,
      kSecAttrService: Self.kcService,
      kSecAttrAccount: Self.kcAccount,
    ]
    SecItemDelete(query as CFDictionary)
  }

  // MARK: - Seal / Unseal

  private func sealData(_ clearKey: Data, result: @escaping FlutterResult) {
    do {
      let kek       = try getOrCreateKek()
      let sealed    = try AES.GCM.seal(clearKey, using: kek)
      // Blob layout: version(1) | nonce(12) | ciphertext(n) | tag(16)
      var blob = Data([Self.blobVersion])
      blob.append(sealed.nonce.withUnsafeBytes { Data($0) })
      blob.append(sealed.ciphertext)
      blob.append(sealed.tag)
      result(FlutterStandardTypedData(bytes: blob))
    } catch {
      result(FlutterError(
        code: "KEYSTORE_UNAVAILABLE",
        message: "seal failed: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  private func unsealData(_ blob: Data, result: @escaping FlutterResult) {
    guard let kek = loadKek() else {
      result(FlutterError(
        code: "KEYSTORE_UNAVAILABLE",
        message: "No KEK found in Keychain — was the device wiped or the app reinstalled?",
        details: nil
      ))
      return
    }
    do {
      // Parse layout: version(1) | nonce(12) | ciphertext(n) | tag(16)
      guard blob.count > 1 + 12 + 16, blob[0] == Self.blobVersion else {
        result(FlutterError(
          code: "KEYSTORE_UNAVAILABLE",
          message: "Unrecognised sealed-blob format (version \(blob.first ?? 0))",
          details: nil
        ))
        return
      }
      let nonce      = try AES.GCM.Nonce(data: blob[1..<13])
      let ciphertext = blob[13 ..< (blob.count - 16)]
      let tag        = blob[(blob.count - 16)...]
      let box        = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
      let clearKey   = try AES.GCM.open(box, using: kek)
      result(FlutterStandardTypedData(bytes: clearKey))
    } catch {
      result(FlutterError(
        code: "KEYSTORE_UNAVAILABLE",
        message: "unseal failed: \(error.localizedDescription)",
        details: nil
      ))
    }
  }
}

// MARK: - Internal error

private struct KeychainError: Error {
  let status: OSStatus
  var localizedDescription: String { "Keychain error \(status)" }
}
