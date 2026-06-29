// Doctor-side QR scanner screen (issue #17 — US-2.1).
//
// Activates the device camera, decodes the first valid [QrPayload] it sees,
// validates expiry, downloads and decrypts the session blob in RAM (via
// [ScanService]), and navigates to [RecordViewScreen].  The session key lives
// in the [QrPayload] on the Dart heap and is wiped by [RecordViewScreen.dispose].

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../cloud/backend_client.dart';
import '../doctor/scan_service.dart';
import '../rust/crypto_core_bindings.dart';
import 'record_view_screen.dart';

/// Displays a camera viewfinder and processes the first valid QR code.
///
/// Inject a [ScanService] for testability.  The [MobileScannerController]
/// is stopped while processing and restarted on error or after the record
/// view is dismissed, allowing the doctor to scan again.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.service});

  final ScanService service;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processing = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes
        .where((b) => b.rawValue != null)
        .map((b) => b.rawValue!)
        .firstOrNull;
    if (raw == null) return;

    setState(() {
      _processing = true;
      _error = null;
    });
    await _controller.stop();

    try {
      final payload = ScanService.parseQr(raw);
      final record = await widget.service.fetchAndDecrypt(payload);
      if (!mounted) {
        payload.wipe();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RecordViewScreen(record: record, payload: payload),
        ),
      );
      // RecordViewScreen.dispose() wiped the payload — restart for next scan.
      await _controller.start();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(e));
      await _controller.start();
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  String _errorMessage(Object e) => switch (e) {
        ExpiredQrCode() => 'QR expiré — demandez un nouveau code au patient',
        BlobNotFound() => 'Session introuvable — QR peut-être expiré',
        BackendUnavailable() => 'Serveur indisponible — vérifiez la connexion',
        DecryptError() => 'Erreur de déchiffrement — QR invalide',
        _ => 'Erreur inattendue',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner le QR médical')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          if (_processing)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_error != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.red.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
