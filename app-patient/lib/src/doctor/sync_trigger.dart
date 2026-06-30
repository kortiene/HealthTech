// Drain trigger abstraction for the offline-sync drain (issue #22, US-2.4).
//
// "When did the network come back?" is deliberately DECOUPLED from the drain
// logic: the connectivity package is an unresolved toolchain decision (#1), so
// [SyncService] depends only on this interface. Triggers that need NO new
// dependency (app resume/start, a manual button, an opportunistic post-PUT
// signal) ship today; a connectivity-package trigger can be added later behind
// the same interface without touching the (host-testable) drain logic.
//
// SECURITY: a trigger only says "try a drain now". It carries no key material,
// no session key, no PII — draining touches only the SQLCipher queue key (#21),
// never the wiped session key (#19).

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Emits a signal each time the drain should be attempted. [SyncService]
/// subscribes and calls `drain()` per event (its mutex debounces overlaps).
abstract class SyncTrigger {
  /// Stream of "attempt a drain now" events.
  Stream<void> get events;
}

/// A [SyncTrigger] driven imperatively: a manual "Synchroniser" button, an
/// opportunistic signal after a successful end-of-session PUT (network is back),
/// or app start. Backed by a broadcast controller so multiple listeners are safe.
class ManualSyncTrigger implements SyncTrigger {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get events => _controller.stream;

  /// Request a drain now (e.g. the doctor tapped "Synchroniser", or a PUT just
  /// succeeded so the network is evidently back).
  void requestSync() {
    if (!_controller.isClosed) _controller.add(null);
  }

  /// Release the underlying controller.
  Future<void> dispose() => _controller.close();
}

/// A [SyncTrigger] that fires when the app returns to the foreground
/// ([AppLifecycleState.resumed]) — and once at construction, to drain whatever
/// survived a previous session. No connectivity package required.
///
/// Call [dispose] to detach the lifecycle observer.
class AppLifecycleSyncTrigger extends WidgetsBindingObserver
    implements SyncTrigger {
  AppLifecycleSyncTrigger({bool fireOnStart = true}) {
    WidgetsBinding.instance.addObserver(this);
    if (fireOnStart) {
      // Drain leftovers from a previous run as soon as the app is up.
      scheduleMicrotask(() {
        if (!_controller.isClosed) _controller.add(null);
      });
    }
  }

  final StreamController<void> _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get events => _controller.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_controller.isClosed) {
      _controller.add(null);
    }
  }

  /// Detach the lifecycle observer and close the stream.
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _controller.close();
  }
}
