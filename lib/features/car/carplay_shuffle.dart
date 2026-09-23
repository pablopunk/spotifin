import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../services/playback/playback_service.dart';

class CarPlayShuffle {
  CarPlayShuffle(this.playback, {MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('spotifin/carplay_shuffle'),
      _enabled =
          enabled ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final PlaybackService playback;
  final MethodChannel _channel;
  final bool _enabled;
  bool? _lastShuffle;

  void start() {
    if (!_enabled) return;
    _channel.setMethodCallHandler(_handleCall);
    playback.addListener(_syncShuffle);
    _syncShuffle();
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method == 'toggleShuffle') {
      await playback.toggleShuffle();
    }
  }

  void _syncShuffle() {
    if (_lastShuffle == playback.shuffle) return;
    _lastShuffle = playback.shuffle;
    unawaited(_channel.invokeMethod<void>('setShuffle', playback.shuffle));
  }

  void dispose() {
    if (!_enabled) return;
    playback.removeListener(_syncShuffle);
    _channel.setMethodCallHandler(null);
  }
}
