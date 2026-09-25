import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'cast_device.dart';
import 'cast_media.dart';

/// Connection lifecycle exposed to the UI.
enum CastConnectionState { disconnected, connecting, connected }

/// Remote player state mirrored from the receiver.
enum CastPlayerState { idle, playing, paused, buffering, unknown }

/// Snapshot of the receiver transport state.
class CastRemoteState {
  const CastRemoteState({
    this.playerState = CastPlayerState.unknown,
    this.position = Duration.zero,
    this.duration,
    this.volume = 1,
  });

  final CastPlayerState playerState;
  final Duration position;
  final Duration? duration;
  final double volume;

  bool get isPlaying => playerState == CastPlayerState.playing;

  CastRemoteState copyWith({
    CastPlayerState? playerState,
    Duration? position,
    Duration? duration,
    double? volume,
  }) => CastRemoteState(
    playerState: playerState ?? this.playerState,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    volume: volume ?? this.volume,
  );
}

/// User-visible Cast failure. Messages must never contain credentials.
class CastException implements Exception {
  const CastException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Transport + session operations a Cast SDK provides.
///
/// Implemented by [ChromeCastSender] (real Google Cast SDK via
/// `flutter_chrome_cast`) and by fakes in tests. The controller only talks
/// to this interface so `flutter test` never touches native code.
abstract interface class CastSender {
  Stream<List<CastDevice>> get devicesStream;
  List<CastDevice> get devices;

  Stream<CastConnectionState> get connectionStateStream;
  CastConnectionState get connectionState;
  CastDevice? get connectedDevice;

  Stream<CastRemoteState> get remoteStateStream;
  CastRemoteState get remoteState;

  Future<void> initialize({required String receiverAppId});
  Future<void> startDiscovery();
  Future<void> stopDiscovery();

  Future<void> connect(CastDevice device);
  Future<void> disconnect({bool stopReceiver = false});

  Future<void> loadSingle(
    CastTrackPayload payload, {
    required Duration position,
    bool autoplay = true,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> next();
  Future<void> previous();

  void dispose();
}

/// Whether the current runtime can drive a real Cast session.
///
/// Google Cast sender SDKs ship for iOS and Android only. Other platforms
/// (Linux/macOS/Windows/web) keep local playback and show guidance.
bool get isCastPlatformSupported {
  if (kIsWeb) return false;
  if (Platform.isIOS || Platform.isAndroid) return true;
  return false;
}
