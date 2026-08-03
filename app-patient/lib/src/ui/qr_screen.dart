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
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../design/app_theme.dart';
import '../qr/access_token.dart';

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
      backgroundColor: AppColors.primary900,
      appBar: AppBar(
        backgroundColor: AppColors.primary900,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Accès consultation',
          style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back_rounded, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_generating) return const _LoadingView();
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _generate);
    }
    final p = _payload;
    if (p == null) return const _LoadingView();
    if (_remainingSeconds == 0) {
      return _ExpiredView(onRegenerate: _generate);
    }
    return _QrView(
      qrData: p.toQrString(),
      remainingSeconds: _remainingSeconds,
    );
  }
}

// ── States ────────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary500,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Génération du code…',
            style: TextStyle(
              color: AppColors.white.withAlpha(180),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _QrView extends StatelessWidget {
  const _QrView({required this.qrData, required this.remainingSeconds});

  final String qrData;
  final int remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final isUrgent = remainingSeconds <= 30;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Présentez ce code à votre médecin',
              style: TextStyle(
                color: AppColors.white.withAlpha(180),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 260,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF003D39),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF003D39),
                ),
              ),
            ),
            const SizedBox(height: 28),
            _CountdownRing(seconds: remainingSeconds, urgent: isUrgent),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.white.withAlpha(15),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Symbols.shield_rounded,
                    size: 14,
                    color: AppColors.primary500,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Valable 120 s — Partagez uniquement avec votre médecin',
                    style: TextStyle(
                      color: AppColors.white.withAlpha(153),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.seconds, required this.urgent});

  final int seconds;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final color = urgent ? AppColors.allergy : AppColors.primary500;
    final progress = (seconds / 120).clamp(0.0, 1.0);

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 4,
            backgroundColor: AppColors.white.withAlpha(25),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$seconds',
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              's',
              style: TextStyle(
                color: color.withAlpha(180),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ExpiredView extends StatelessWidget {
  const _ExpiredView({required this.onRegenerate});

  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.white.withAlpha(15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Symbols.timer_off_rounded,
                size: 40,
                color: AppColors.white.withAlpha(153),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Code expiré',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Pour la sécurité, chaque code n\'est valable que 120 secondes.',
              style: TextStyle(
                color: AppColors.white.withAlpha(153),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onRegenerate,
              icon: const Icon(Symbols.refresh_rounded),
              label: const Text('Régénérer'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary500,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
            ),
          ],
        ),
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.error_rounded,
              size: 56,
              color: AppColors.allergy.withAlpha(200),
            ),
            const SizedBox(height: 24),
            const Text(
              'Impossible de générer le code',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: AppColors.white.withAlpha(120),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Symbols.refresh_rounded, color: AppColors.white),
              label: const Text(
                'Réessayer',
                style: TextStyle(color: AppColors.white),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.white.withAlpha(80)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
