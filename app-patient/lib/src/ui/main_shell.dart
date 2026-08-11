import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../doctor/scan_service.dart';
import '../qr/access_token.dart';
import '../record/medical_record.dart';
import '../secure/biometric_service.dart';
import '../secure/patient_account.dart';
import '../design/app_theme.dart';
import 'home_screen.dart';
import 'patient_record_screen.dart';
import 'qr_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.record,
    required this.account,
    required this.qrController,
    required this.scanService,
    required this.onLock,
    this.backendUrl,
    this.onWillPauseForPicker,
    this.onUpdateRecord,
    this.onQrClosed,
    this.storedPin,
    this.onChangePin,
    this.biometricService,
    this.biometricEnabled = false,
    this.lastSyncedAt,
    this.onManualSync,
    this.onDeleteAccount,
  });

  final MedicalRecord record;
  final PatientAccount account;
  final QrController qrController;
  final ScanService scanService;
  final VoidCallback onLock;
  final String? backendUrl;
  final VoidCallback? onWillPauseForPicker;
  final Future<void> Function(MedicalRecord)? onUpdateRecord;
  final Future<void> Function()? onQrClosed;
  final String? storedPin;
  final Future<void> Function(String)? onChangePin;
  final BiometricService? biometricService;
  final bool biometricEnabled;
  final String? lastSyncedAt;
  final Future<void> Function()? onManualSync;
  final Future<void> Function()? onDeleteAccount;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  Future<void> _showQr() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QrScreen(
          controller: widget.qrController,
          record: widget.record,
        ),
      ),
    );
    // QR screen closed — doctor may have written a note; pull latest from cloud.
    await widget.onQrClosed?.call();
  }

  void _showScan() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanScreen(service: widget.scanService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        record: widget.record,
        account: widget.account,
        onShowQr: _showQr,
        onScan: _showScan,
        lastSyncedAt: widget.lastSyncedAt,
        onEditProfile: () => setState(() => _tab = 2),
      ),
      PatientRecordScreen(
        record: widget.record,
        account: widget.account,
        onShowQr: _showQr,
        backendUrl: widget.backendUrl,
        onWillPauseForPicker: widget.onWillPauseForPicker,
        onTreatmentStatusChanged: widget.onUpdateRecord != null
            ? (id, status, endedAt) {
                final updated = widget.record.copyWith(
                  treatments: widget.record.treatments
                      .map(
                        (t) => t.id == id
                            ? t.copyWith(status: status, endedAt: endedAt)
                            : t,
                      )
                      .toList(),
                  updatedAt: DateTime.now().toIso8601String(),
                );
                widget.onUpdateRecord!(updated);
              }
            : null,
        onMediaAttached: widget.onUpdateRecord != null
            ? (consultationId, descriptor) {
                final updated = widget.record.copyWith(
                  consultations: widget.record.consultations
                      .map(
                        (c) => c.id == consultationId
                            ? c.copyWithMedia(descriptor)
                            : c,
                      )
                      .toList(),
                  updatedAt: DateTime.now().toIso8601String(),
                );
                return widget.onUpdateRecord!(updated);
              }
            : null,
        onRemoveConsultationMedia: widget.onUpdateRecord != null
            ? (consultationId, descriptor) {
                final updated = widget.record.copyWith(
                  consultations: widget.record.consultations
                      .map(
                        (c) => c.id == consultationId
                            ? Consultation(
                                id: c.id,
                                date: c.date,
                                practitionerRef: c.practitionerRef,
                                summary: c.summary,
                                prescription: c.prescription,
                                ordonnances: c.ordonnances,
                                imageUrls: c.imageUrls,
                                media: c.media
                                    .where((m) => m.uuid != descriptor.uuid)
                                    .toList(),
                              )
                            : c,
                      )
                      .toList(),
                  updatedAt: DateTime.now().toIso8601String(),
                );
                return widget.onUpdateRecord!(updated);
              }
            : null,
        onAddCondition: widget.onUpdateRecord != null
            ? (condition) {
                final updated = widget.record.copyWith(
                  chronicConditions: [
                    ...widget.record.chronicConditions,
                    condition,
                  ],
                  updatedAt: DateTime.now().toIso8601String(),
                );
                return widget.onUpdateRecord!(updated);
              }
            : null,
        onUpdateCondition: widget.onUpdateRecord != null
            ? (index, updatedCondition) {
                final conditions = List.of(widget.record.chronicConditions);
                conditions[index] = updatedCondition;
                final updated = widget.record.copyWith(
                  chronicConditions: conditions,
                  updatedAt: DateTime.now().toIso8601String(),
                );
                return widget.onUpdateRecord!(updated);
              }
            : null,
      ),
      SettingsScreen(
        record: widget.record,
        account: widget.account,
        onLock: widget.onLock,
        onUpdateRecord: widget.onUpdateRecord,
        storedPin: widget.storedPin,
        onChangePin: widget.onChangePin,
        biometricService: widget.biometricService,
        biometricEnabled: widget.biometricEnabled,
        lastSyncedAt: widget.lastSyncedAt,
        onManualSync: widget.onManualSync,
        onDeleteAccount: widget.onDeleteAccount,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.primary50,
      body: IndexedStack(
        index: _tab,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.neutral200,
        elevation: 1,
        destinations: const [
          NavigationDestination(
            icon: Icon(Symbols.home_rounded),
            selectedIcon: Icon(Symbols.home_rounded, fill: 1),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Symbols.folder_shared_rounded),
            selectedIcon: Icon(Symbols.folder_shared_rounded, fill: 1),
            label: 'Mon Dossier',
          ),
          NavigationDestination(
            icon: Icon(Symbols.settings_rounded),
            selectedIcon: Icon(Symbols.settings_rounded, fill: 1),
            label: 'Paramètres',
          ),
        ],
      ),
    );
  }
}
