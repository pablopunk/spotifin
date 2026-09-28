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
    await active.toggleShuffle();
  }

  void _syncShuffle() {
    final shuffle = active.state.shuffle;
    if (_lastShuffle == shuffle) return;
    _lastShuffle = shuffle;
    unawaited(_channel.invokeMethod<void>('setShuffle', shuffle));
  }

  void dispose() {
    if (!_enabled) return;
    active.removeListener(_syncShuffle);
    _channel.setMethodCallHandler(null);
  }
}
