import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../services/playback/active_playback.dart';

class CarPlayShuffle {
  CarPlayShuffle(this.active, {MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('spotifin/carplay_shuffle'),
      _enabled =
          enabled ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final ActivePlayback active;
  final MethodChannel _channel;
  final bool _enabled;
  bool? _lastShuffle;
  bool? _publishingShuffle;
  bool _syncing = false;
  bool _disposed = false;
  bool _forceSyncRequested = false;
  bool _retryAfterFailure = false;

  void start() {
    if (!_enabled) return;
    _channel.setMethodCallHandler(_handleCall);
    active.addListener(_syncShuffle);
    _syncShuffle();
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'toggleShuffle') return;
    if (!active.state.capabilities.contains(PlaybackCapability.shuffle)) {
      return;
    }
    final requestedShuffle = call.arguments as bool?;
    if (requestedShuffle == active.state.shuffle) {
      resync();
      return;
    }
    await active.toggleShuffle();
  }

  /// Reapplies the current state after CarPlay reconnects and may have reset
  /// its native Now Playing button.
  void resync() {
    if (!_enabled || _disposed) return;
    _forceSyncRequested = true;
    _syncShuffle();
  }

  void _syncShuffle() {
    if (_disposed) return;
    if (_syncing) {
      if (_publishingShuffle != active.state.shuffle) {
        _retryAfterFailure = true;
      }
      return;
    }
    if (!_forceSyncRequested && _lastShuffle == active.state.shuffle) return;
    _syncing = true;
    unawaited(_publishShuffle());
  }

  Future<void> _publishShuffle() async {
    var failed = false;
    try {
      while (!_disposed) {
        final shuffle = active.state.shuffle;
        final force = _forceSyncRequested;
        _forceSyncRequested = false;
        if (!force && _lastShuffle == shuffle) break;
        _publishingShuffle = shuffle;
        await _channel.invokeMethod<void>('setShuffle', shuffle);
        _lastShuffle = shuffle;
        _publishingShuffle = null;
      }
    } catch (_) {
      // Cache only acknowledged values; a later owner or connection update retries.
      failed = true;
    } finally {
      _publishingShuffle = null;
      _syncing = false;
      final retry = _forceSyncRequested || (failed && _retryAfterFailure);
      _retryAfterFailure = false;
      if (!_disposed &&
          (retry || (!failed && _lastShuffle != active.state.shuffle))) {
        _syncShuffle();
      }
    }
  }

  void dispose() {
    if (!_enabled) return;
    _disposed = true;
    active.removeListener(_syncShuffle);
    _channel.setMethodCallHandler(null);
  }
}
