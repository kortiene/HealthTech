// QR code consultation access screen (issue #16).
//
// Displays the session QR code with a 120-second countdown.  The session key
// is held in [QrPayload.sessionKey] in RAM only; [QrPayload.wipe] is called
// on disposal and regeneration to overwrite the key bytes in place.
//
// Security: the screen never persists the session key.  The QR content is
// generated fresh on each [QrController.generate] call and rendered only
// as a visual QR image — it is not logged, shared, or retained elsewhere.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../qr/access_token.dart';

/// Displays the QR access code with a countdown to expiry.
///
/// Inject a [QrController] for testability.  On mount, [QrController.generate]
/// is called and the countdown begins.  After expiry, a regenerate button
/// appears to start a new session.
class QrScreen extends StatefulWidget {
  const QrScreen({super.key, required this.controller});

  final QrController controller;

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  QrPayload? _payload;
  String? _error;
  bool _generating = false;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_generate);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _payload?.wipe();
    super.dispose();
  }

  Future<void> _generate() async {
    _countdownTimer?.cancel();
    setState(() {
      _generating = true;
      _error = null;
      _payload?.wipe();
      _payload = null;
      _remainingSeconds = 0;
    });
    try {
      final p = await widget.controller.generate();
      if (!mounted) {
        p.wipe();
        return;
      }
      final secs = p.expiresAt.difference(DateTime.now()).inSeconds;
      setState(() {
        _payload = p;
        _generating = false;
        _remainingSeconds = secs > 0 ? secs : 0;
      });
      if (secs > 0) _startCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _generating = false;
      });
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _countdownTimer?.cancel();
          _payload?.wipe();
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accès consultation')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_generating) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _generate);
    }
    final p = _payload;
    if (p == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_remainingSeconds == 0) {
      return _ExpiredView(onRegenerate: _generate);
    }
    return _QrView(
      qrData: p.toQrString(),
      remainingSeconds: _remainingSeconds,
    );
  }
}

class _QrView extends StatelessWidget {
  const _QrView({required this.qrData, required this.remainingSeconds});

  final String qrData;
  final int remainingSeconds;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Présentez ce code à votre médecin'),
        const SizedBox(height: 24),
        QrImageView(
          data: qrData,
          version: QrVersions.auto,
          size: 280,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
        ),
        const SizedBox(height: 24),
        _CountdownBadge(seconds: remainingSeconds),
        const SizedBox(height: 8),
        const Text(
          'Valable 120 s — Partagez uniquement avec votre médecin',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final color = seconds <= 30 ? Colors.red : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            '$seconds s',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _ExpiredView extends StatelessWidget {
  const _ExpiredView({required this.onRegenerate});

  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_off, size: 64, color: Colors.orange),
          const SizedBox(height: 16),
          const Text('QR expiré', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          const Text('Pour la sécurité, générez un nouveau code.'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRegenerate,
            child: const Text('Régénérer'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(message),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
