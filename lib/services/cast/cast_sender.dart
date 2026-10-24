import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'cast_device.dart';
import 'cast_media.dart';

/// Connection lifecycle exposed to the UI.
enum CastConnectionState { disconnected, connecting, connected }

/// Remote player state mirrored from the receiver.
enum CastPlayerState { idle, playing, paused, buffering, unknown }

/// Why the receiver entered its idle state.
enum CastFinishReason { finished, cancelled, interrupted, error, unknown }

/// Snapshot of the receiver transport state.
class CastRemoteState {
  const CastRemoteState({
    this.playerState = CastPlayerState.unknown,
    this.position = Duration.zero,
    this.duration,
    this.volume = 1,
    this.finishReason,
    this.occurrenceId,
    this.loadId,
    this.mediaSessionId,
  });

  final CastPlayerState playerState;
  final Duration position;
  final Duration? duration;
  final double volume;
  final CastFinishReason? finishReason;

  /// Queue occurrence and sender load that produced this receiver status.
  final String? occurrenceId;
  final String? loadId;

  /// Native Cast media session identity, when supplied by the SDK.
  final int? mediaSessionId;

  bool get isPlaying => playerState == CastPlayerState.playing;

  CastRemoteState copyWith({
    CastPlayerState? playerState,
    Duration? position,
    Duration? duration,
    double? volume,
    CastFinishReason? finishReason,
    String? occurrenceId,
    String? loadId,
    int? mediaSessionId,
  }) => CastRemoteState(
    playerState: playerState ?? this.playerState,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    volume: volume ?? this.volume,
    // Completion is an event, so ordinary transport updates must clear it.
    finishReason: finishReason,
    occurrenceId: occurrenceId,
    loadId: loadId,
    mediaSessionId: mediaSessionId,
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
    required String loadId,
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
