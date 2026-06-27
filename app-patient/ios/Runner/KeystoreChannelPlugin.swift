import Flutter
import UIKit

// iOS amorce for the `healthtech/keystore` channel (issue #11).
//
// ADR 0001 targets Android first; the production iOS sealing path (Keychain item
// with Secure Enclave-backed key, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
// no iCloud sync) is intentionally NOT hardened in this iteration. This stub keeps
// the SAME channel contract as the Kotlin shim so the Dart `KeystoreChannel` is
// platform-agnostic, and fails loudly with the typed `KEYSTORE_UNAVAILABLE` code
// rather than silently falling back to a software key (G3).
//
// TODO(#11/iOS): implement seal/unseal/exists/clear with the Secure Enclave +
// Keychain, mirroring the envelope model in KeystoreSealer.kt.
public class KeystoreChannelPlugin: NSObject, FlutterPlugin {
  private static let channelName = "healthtech/keystore"
  private static let unavailable = "KEYSTORE_UNAVAILABLE"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = KeystoreChannelPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "exists":
      // No key can exist until the iOS sealing path is implemented.
      result(false)
    case "seal", "unseal", "clear":
      result(
        FlutterError(
          code: KeystoreChannelPlugin.unavailable,
          message: "iOS hardware sealing not implemented yet (TODO(#11/iOS))",
          details: nil))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
