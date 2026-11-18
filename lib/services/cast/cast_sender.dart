import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'cast_device.dart';

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
    this.itemId,
  });

  final CastPlayerState playerState;
  final Duration position;
  final Duration? duration;
  final double volume;
  final CastFinishReason? finishReason;

  /// Jellyfin item the receiver has loaded, from its media `customData`.
  final String? itemId;

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
    // Completion is an event, so ordinary transport updates must clear it.
    finishReason: null,
    itemId: itemId,
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

  /// Raw text messages the receiver sends on its command namespace.
  Stream<String> get receiverMessages;

  Future<void> initialize({required String receiverAppId});
  Future<void> startDiscovery();
  Future<void> stopDiscovery();

  Future<void> connect(CastDevice device);
  Future<void> disconnect({bool stopReceiver = false});

  /// Sends one command to the receiver's command namespace.
  Future<void> sendReceiverCommand(Map<String, Object?> command);

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> setVolume(double volume);

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
