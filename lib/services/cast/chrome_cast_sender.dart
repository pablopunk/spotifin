import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_chrome_cast/cast_context.dart';
import 'package:flutter_chrome_cast/common.dart';
import 'package:flutter_chrome_cast/discovery.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_chrome_cast/enums.dart';
import 'package:flutter_chrome_cast/media.dart';
import 'package:flutter_chrome_cast/models.dart';
import 'package:flutter_chrome_cast/session.dart';

import '../redaction.dart';
import 'cast_device.dart';
import 'cast_media.dart';
import 'cast_sender.dart';

/// Real [CastSender] backed by the Google Cast SDK via `flutter_chrome_cast`.
///
/// iOS uses the official Cast SDK (~4.8.4 XCFramework with arm64 simulator
/// slices); Android uses the Cast framework. Initialization launches the
/// Jellyfin Web Receiver ([receiverAppId], stable `F007D354` by default) so
/// playback reporting stays server-side. Music keeps playing when the app is
/// killed (`stopCastingOnAppTerminated=false`) and sessions suspend in
/// background for lockscreen/Control Center control.
///
/// All native failures are mapped to [CastException] with user-visible,
/// credential-free messages. On unsupported platforms (Linux/macOS/Windows /
/// web) every operation throws a guidance error instead of crashing.
class ChromeCastSender implements CastSender {
  ChromeCastSender();

  final _devicesController = StreamController<List<CastDevice>>.broadcast();
  final _connectionController =
      StreamController<CastConnectionState>.broadcast();
  final _remoteController = StreamController<CastRemoteState>.broadcast();

  List<CastDevice> _devices = const [];
  CastConnectionState _connection = CastConnectionState.disconnected;
  CastDevice? _connectedDevice;
  CastRemoteState _remote = const CastRemoteState();
  String _receiverAppId = 'F007D354';
  bool _initialized = false;

  StreamSubscription<List<GoogleCastDevice>>? _devicesSub;
  StreamSubscription<GoogleCastSession?>? _sessionSub;
  StreamSubscription<GoggleCastMediaStatus?>? _mediaSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<dynamic>? _volumeSub;

  @override
  List<CastDevice> get devices => _devices;

  @override
  Stream<List<CastDevice>> get devicesStream => _devicesController.stream;

  @override
  CastConnectionState get connectionState => _connection;

  @override
  Stream<CastConnectionState> get connectionStateStream =>
      _connectionController.stream;

  @override
  CastDevice? get connectedDevice => _connectedDevice;

  @override
  CastRemoteState get remoteState => _remote;

  @override
  Stream<CastRemoteState> get remoteStateStream => _remoteController.stream;

  @override
  Future<void> initialize({required String receiverAppId}) async {
    _receiverAppId = receiverAppId;
    if (!isCastPlatformSupported) return;
    if (_initialized) return;
    try {
      if (Platform.isIOS) {
        await GoogleCastContext.instance.setSharedInstanceWithOptions(
          IOSGoogleCastOptions(
            GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(
              receiverAppId,
            ),
            // Music keeps playing when the app is killed; the user can
            // rejoin later. Volume buttons drive the receiver; sessions
            // suspend (not end) when backgrounded for lockscreen control.
            stopCastingOnAppTerminated: false,
            suspendSessionsWhenBackgrounded: true,
            physicalVolumeButtonsWillControlDeviceVolume: true,
          ),
        );
      } else if (Platform.isAndroid) {
        await GoogleCastContext.instance.setSharedInstanceWithOptions(
          GoogleCastOptionsAndroid(
            appId: receiverAppId,
            stopCastingOnAppTerminated: false,
          ),
        );
      }
      _initialized = true;
      _listen();
    } on MissingPluginException {
      throw const CastException(
        'Chromecast is not available on this device build.',
      );
    } catch (error) {
      throw CastException(_friendly(error));
    }
  }

  void _listen() {
    _devicesSub ??= GoogleCastDiscoveryManager.instance.devicesStream.listen((
      raw,
    ) {
      _devices = raw
          .map(
            (device) => CastDevice(
              id: device.deviceID,
              friendlyName: device.friendlyName,
              modelName: device.modelName,
            ),
          )
          .toList(growable: false);
      // Target disappearance while connected surfaces via the session
      // stream below; the device list alone drives the picker UI.
      if (!_devicesController.isClosed) _devicesController.add(_devices);
    });
    _sessionSub ??= GoogleCastSessionManager.instance.currentSessionStream
        .listen((session) {
          final state =
              session?.connectionState ??
              GoogleCastSessionManager.instance.connectionState;
          _applyConnection(state, session?.device);
          if (session != null) _updateVolume(session.currentDeviceVolume);
        });
    if (Platform.isIOS) {
      _volumeSub ??= const EventChannel('spotifin/cast_volume')
          .receiveBroadcastStream()
          .listen((volume) {
            if (volume is num) _updateVolume(volume.toDouble());
          });
    }
    _mediaSub ??= GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen(
      (status) {
        if (status == null) return;
        _remote = _remote.copyWith(
          playerState: _mapPlayer(status.playerState),
          duration: status.mediaInformation?.duration,
        );
        if (!_remoteController.isClosed) _remoteController.add(_remote);
      },
    );
    _positionSub ??= GoogleCastRemoteMediaClient.instance.playerPositionStream
        .listen((position) {
          _remote = _remote.copyWith(position: position);
          if (!_remoteController.isClosed) _remoteController.add(_remote);
        });
    // Emit the current native state once listeners attach.
    try {
      _applyConnection(
        GoogleCastSessionManager.instance.connectionState,
        GoogleCastSessionManager.instance.currentSession?.device,
      );
    } catch (_) {}
  }

  void _updateVolume(double volume) {
    _remote = _remote.copyWith(volume: volume.clamp(0.0, 1.0));
    if (!_remoteController.isClosed) _remoteController.add(_remote);
  }

  void _applyConnection(
    GoogleCastConnectState native,
    GoogleCastDevice? device,
  ) {
    _connection = switch (native) {
      GoogleCastConnectState.connected => CastConnectionState.connected,
      GoogleCastConnectState.connecting ||
      GoogleCastConnectState.disconnecting => CastConnectionState.connecting,
      GoogleCastConnectState.disconnected => CastConnectionState.disconnected,
    };
    _connectedDevice = device == null
        ? null
        : CastDevice(
            id: device.deviceID,
            friendlyName: device.friendlyName,
            modelName: device.modelName,
          );
    if (_connection == CastConnectionState.disconnected) {
      _connectedDevice = null;
      _remote = const CastRemoteState();
      if (!_remoteController.isClosed) _remoteController.add(_remote);
    }
    if (!_connectionController.isClosed) {
      _connectionController.add(_connection);
    }
  }

  static CastPlayerState _mapPlayer(CastMediaPlayerState native) =>
      switch (native) {
        CastMediaPlayerState.playing => CastPlayerState.playing,
        CastMediaPlayerState.paused => CastPlayerState.paused,
        CastMediaPlayerState.buffering ||
        CastMediaPlayerState.loading => CastPlayerState.buffering,
        CastMediaPlayerState.idle => CastPlayerState.idle,
        CastMediaPlayerState.unknown => CastPlayerState.unknown,
      };

  @override
  Future<void> startDiscovery() async {
    _guardSupported();
    try {
      await GoogleCastDiscoveryManager.instance.startDiscovery();
    } catch (error) {
      throw CastException(_friendly(error));
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (!isCastPlatformSupported) return;
    try {
      await GoogleCastDiscoveryManager.instance.stopDiscovery();
    } catch (_) {}
  }

  @override
  Future<void> connect(CastDevice device) async {
    _guardSupported();
    _setConnecting();
    try {
      final native = await _findNative(device.id);
      final target =
          native ??
          GoogleCastDevice(
            deviceID: device.id,
            friendlyName: device.friendlyName,
            modelName: device.modelName,
            statusText: null,
            deviceVersion: '',
            isOnLocalNetwork: true,
            category: '',
            uniqueID: device.id,
          );
      final started = await GoogleCastSessionManager.instance
          .startSessionWithDevice(target);
      if (!started && connectionState != CastConnectionState.connected) {
        throw const CastException('Could not connect to this Chromecast.');
      }
    } catch (error) {
      if (error is CastException) rethrow;
      throw CastException(_friendly(error));
    }
  }

  void _setConnecting() {
    _connection = CastConnectionState.connecting;
    if (!_connectionController.isClosed) {
      _connectionController.add(_connection);
    }
  }

  Future<GoogleCastDevice?> _findNative(String id) async {
    try {
      for (final device in GoogleCastDiscoveryManager.instance.devices) {
        if (device.deviceID == id) return device;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> disconnect({bool stopReceiver = false}) async {
    if (!isCastPlatformSupported) {
      _applyConnection(GoogleCastConnectState.disconnected, null);
      return;
    }
    try {
      final ended = stopReceiver
          ? await GoogleCastSessionManager.instance.endSessionAndStopCasting()
          : await GoogleCastSessionManager.instance.endSession();
      if (!ended && GoogleCastSessionManager.instance.hasConnectedSession) {
        throw const CastException('Could not stop Chromecast playback.');
      }
    } catch (error) {
      if (error is CastException) rethrow;
      throw CastException(_friendly(error));
    }
    _applyConnection(GoogleCastConnectState.disconnected, null);
  }

  @override
  Future<void> loadSingle(
    CastTrackPayload payload, {
    required Duration position,
    bool autoplay = true,
  }) async {
    _guardSupported();
    _guardConnected();
    try {
      final info = GoogleCastMediaInformation(
        contentId: payload.contentId,
        streamType: CastMediaStreamType.buffered,
        contentUrl: payload.contentUrl,
        contentType: payload.contentType,
        duration: payload.duration,
        customData: payload.customData,
        metadata: GoogleCastMusicMediaMetadata(
          title: payload.title,
          artist: payload.artist,
          albumName: payload.album.isEmpty ? null : payload.album,
          images: payload.artworkUrl == null
              ? null
              : [
                  GoogleCastImage(
                    url: payload.artworkUrl!,
                    height: 500,
                    width: 500,
                  ),
                ],
        ),
      );
      await GoogleCastRemoteMediaClient.instance.loadMedia(
        info,
        autoPlay: autoplay,
        playPosition: position,
        customData: payload.customData,
      );
      _remote = _remote.copyWith(
        position: position,
        duration: payload.duration,
        playerState: autoplay
            ? CastPlayerState.playing
            : CastPlayerState.paused,
      );
      if (!_remoteController.isClosed) _remoteController.add(_remote);
    } catch (error) {
      if (error is CastException) rethrow;
      throw CastException(_friendly(error));
    }
  }

  @override
  Future<void> play() => _guarded(
    () => GoogleCastRemoteMediaClient.instance.play(),
    'Could not resume Chromecast playback.',
  );

  @override
  Future<void> pause() => _guarded(
    () => GoogleCastRemoteMediaClient.instance.pause(),
    'Could not pause Chromecast playback.',
  );

  @override
  Future<void> stop() => _guarded(
    () => GoogleCastRemoteMediaClient.instance.stop(),
    'Could not stop Chromecast playback.',
  );

  @override
  Future<void> seek(Duration position) => _guarded(
    () => GoogleCastRemoteMediaClient.instance.seek(
      GoogleCastMediaSeekOption(position: position),
    ),
    'Could not seek on Chromecast.',
  );

  @override
  Future<void> setVolume(double volume) async {
    _guardSupported();
    _guardConnected();
    final clamped = volume.clamp(0.0, 1.0);
    try {
      GoogleCastSessionManager.instance.setDeviceVolume(clamped);
      _remote = _remote.copyWith(volume: clamped);
      if (!_remoteController.isClosed) _remoteController.add(_remote);
    } catch (error) {
      throw CastException(_friendly(error));
    }
  }

  @override
  Future<void> next() => _guarded(
    () => GoogleCastRemoteMediaClient.instance.queueNextItem(),
    'Could not skip to the next track on Chromecast.',
  );

  @override
  Future<void> previous() => _guarded(
    () => GoogleCastRemoteMediaClient.instance.queuePrevItem(),
    'Could not go back on Chromecast.',
  );

  Future<void> _guarded(Future<void> Function() action, String fallback) async {
    _guardSupported();
    _guardConnected();
    try {
      await action();
    } catch (error) {
      if (error is CastException) rethrow;
      final message = _friendly(error);
      throw CastException(message.isEmpty ? fallback : message);
    }
  }

  void _guardSupported() {
    if (!isCastPlatformSupported) {
      throw const CastException(
        'Chromecast is available on iPhone and Android.',
      );
    }
  }

  void _guardConnected() {
    if (_connection != CastConnectionState.connected &&
        !GoogleCastSessionManager.instance.hasConnectedSession) {
      throw const CastException('Connect to a Chromecast first.');
    }
  }

  String get receiverAppId => _receiverAppId;

  static String _friendly(Object error) {
    final redacted = redactSecrets(error);
    if (redacted.trim().isEmpty) return 'Chromecast request failed.';
    return redacted;
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _sessionSub?.cancel();
    _mediaSub?.cancel();
    _positionSub?.cancel();
    _volumeSub?.cancel();
    _devicesController.close();
    _connectionController.close();
    _remoteController.close();
  }
}
