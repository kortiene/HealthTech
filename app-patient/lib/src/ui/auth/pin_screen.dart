// PIN entry screen — create (first-run) and verify (returning user) modes.
//
// Security: the PIN is a UI-level lock. It is stored via flutter_secure_storage
// by the caller (main.dart). The PIN never touches the master key or crypto
// layer — those are sealed/unsealed independently by MasterKeyService.
//
// NO cipher code lives in this widget. It is purely UI + state.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../design/app_theme.dart';

enum PinMode { create, verify }

class PinScreen extends StatefulWidget {
  const PinScreen({
    super.key,
    required this.mode,
    this.storedPin,
    required this.onSuccess,
    this.onBiometric,
  });

  final PinMode mode;

  /// Required when [mode] == [PinMode.verify].
  final String? storedPin;

  /// Called with the entered PIN when verification succeeds, or with the new
  /// PIN when creation completes.
  final void Function(String pin) onSuccess;

  /// When non-null and in [PinMode.verify], a biometric-unlock button is shown
  /// below the numpad. The callback is responsible for calling [onSuccess] if
  /// authentication succeeds.
  final Future<void> Function()? onBiometric;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen>
    with SingleTickerProviderStateMixin {
  static const _pinLength = 6;

  String _entered = '';
  String? _firstPin; // for create mode: hold first entry, ask confirm
  bool _confirming = false;
  String? _errorMessage;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  bool get _isDark => widget.mode == PinMode.verify && !_confirming;

  void _append(String digit) {
    if (_entered.length >= _pinLength) return;
    setState(() {
      _entered += digit;
      _errorMessage = null;
    });
    if (_entered.length == _pinLength) {
      Future.microtask(_checkPin);
    }
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _checkPin() async {
    HapticFeedback.mediumImpact();

    if (widget.mode == PinMode.verify) {
      if (_entered == widget.storedPin) {
        widget.onSuccess(_entered);
      } else {
        await _shake();
        setState(() {
          _entered = '';
          _errorMessage = 'Code incorrect';
        });
      }
      return;
    }

    // Create mode
    if (!_confirming) {
      setState(() {
        _firstPin = _entered;
        _entered = '';
        _confirming = true;
        _errorMessage = null;
      });
      return;
    }

    if (_entered == _firstPin) {
      widget.onSuccess(_entered);
    } else {
      await _shake();
      setState(() {
        _entered = '';
        _firstPin = null;
        _confirming = false;
        _errorMessage = 'Les codes ne correspondent pas';
      });
    }
  }

  Future<void> _shake() async {
    await _shakeCtrl.forward();
    _shakeCtrl.reset();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    final bg = isDark ? AppColors.primary900 : AppColors.white;
    final fg = isDark ? AppColors.white : AppColors.neutral900;
    final subtitleColor =
        isDark ? AppColors.white.withAlpha(153) : AppColors.neutral500;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            _buildLogo(isDark),
            const SizedBox(height: 32),
            _buildTitle(fg, subtitleColor),
            const Spacer(),
            _buildDots(isDark),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: AppColors.allergy,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const Spacer(),
            _buildNumpad(isDark),
            if (widget.mode == PinMode.verify && widget.onBiometric != null) ...[
              const SizedBox(height: 16),
              _buildBiometricButton(isDark),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(bool isDark) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.white.withAlpha(25)
            : AppColors.primary100,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.lock_rounded,
        size: 36,
        color: isDark ? AppColors.white : AppColors.primary700,
      ),
    );
  }

  Widget _buildTitle(Color fg, Color subtitle) {
    final title = switch ((widget.mode, _confirming)) {
      (PinMode.create, false) => 'Créer votre code PIN',
      (PinMode.create, true) => 'Confirmer le code PIN',
      (PinMode.verify, _) => 'Entrez votre code PIN',
    };
    final sub = switch ((widget.mode, _confirming)) {
      (PinMode.create, false) =>
        'Ce code protège l\'accès à votre dossier médical',
      (PinMode.create, true) => 'Répétez le code PIN que vous venez de saisir',
      (PinMode.verify, _) => 'HealthTech',
    };

    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sub,
          style: TextStyle(fontSize: 14, color: subtitle),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDots(bool isDark) {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (context, child) {
        final offset = sin(_shakeAnim.value * pi * 5) * 12;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pinLength, (i) {
          final filled = i < _entered.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: filled ? 16 : 14,
            height: filled ? 16 : 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (isDark ? AppColors.white : AppColors.primary700)
                  : Colors.transparent,
              border: Border.all(
                color: isDark
                    ? AppColors.white.withAlpha(100)
                    : AppColors.primary700.withAlpha(100),
                width: 1.5,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNumpad(bool isDark) {
    final keyFg = isDark ? AppColors.white : AppColors.neutral900;
    final keyBg = isDark
        ? AppColors.white.withAlpha(20)
        : AppColors.neutral100;

    final keys = <String?>[
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      null, '0', 'del',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
        children: keys.map((k) {
          if (k == null) return const SizedBox.shrink();
          if (k == 'del') {
            return _NumKey(
              onTap: _backspace,
              bg: keyBg,
              child: Icon(Symbols.backspace_rounded, color: keyFg, size: 22),
            );
          }
          return _NumKey(
            onTap: () => _append(k),
            bg: keyBg,
            child: Text(
              k,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: keyFg,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBiometricButton(bool isDark) {
    final keyBg = isDark
        ? AppColors.white.withAlpha(20)
        : AppColors.neutral100;
    final keyFg = isDark ? AppColors.white : AppColors.neutral900;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        height: 56,
        child: _NumKey(
          onTap: () => widget.onBiometric!(),
          bg: keyBg,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fingerprint, color: keyFg, size: 24),
              const SizedBox(width: 8),
              Text(
                'Utiliser la biométrie',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: keyFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumKey extends StatelessWidget {
  const _NumKey({required this.onTap, required this.bg, required this.child});

  final VoidCallback onTap;
  final Color bg;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Center(child: child),
      ),
    );
  }
}
