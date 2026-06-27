package com.healthtech.patient

import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Patient app host activity (issue #11).
 *
 * Registers the `healthtech/keystore` MethodChannel and routes its calls to
 * [KeystoreSealer] (Android Keystore StrongBox/TEE sealing of the master key).
 *
 * NOTE: the surrounding Flutter Android project (Gradle, manifest, `--split-per-abi`
 * config per ADR 0001) is materialised by `flutter create` during the device-lab
 * bring-up (#29); this file is the security-critical receiver that drops into that
 * generated project. The package path is provisional until then (spec open question 8).
 */
class MainActivity : FlutterActivity() {

    private val sealer = KeystoreSealer()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "seal" -> {
                    val clear = call.argument<ByteArray>("clearKey")
                        ?: return result.error(
                            KeystoreSealer.KeystoreError.UNAVAILABLE.code,
                            "missing clearKey",
                            null,
                        )
                    val sealed = sealer.seal(clear)
                    // Best-effort wipe of the clear copy that crossed the channel (G5);
                    // Dart already wipes its side. Native byte[] is zeroizable here.
                    clear.fill(0)
                    result.success(sealed)
                }

                "unseal" -> {
                    val blob = call.argument<ByteArray>("sealedBlob")
                        ?: return result.error(
                            KeystoreSealer.KeystoreError.UNAVAILABLE.code,
                            "missing sealedBlob",
                            null,
                        )
                    result.success(sealer.unseal(blob))
                }

                "exists" -> result.success(sealer.exists())
                "clear" -> {
                    sealer.clear()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: KeystoreSealer.SealerException) {
            // Never include key/blob material in the message (G5).
            result.error(e.error.code, e.message, null)
        } catch (e: Exception) {
            result.error(
                KeystoreSealer.KeystoreError.UNAVAILABLE.code,
                "keystore operation failed",
                null,
            )
        }
    }

    companion object {
        private const val CHANNEL = "healthtech/keystore"
    }
}
