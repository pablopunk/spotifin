import 'package:just_audio/just_audio.dart';

import '../../storage/database.dart';
import 'playback_service.dart';
import 'remote_playback.dart';

/// Explicit local-playback target for Jellyfin-addressed commands.
///
/// Ordinary controls use [ActivePlayback] and stay on Cast while it owns
/// playback. Commands explicitly addressed to this device (incoming remote
/// protocol commands and Jellyfin "Play here") must run on local playback
/// instead: every supported local action first awaits [transferToLocal]
/// (the owner's explicit Cast stop without autoplay), then delegates to
/// local playback. A failed transfer propagates and prevents the local
/// action, so Cast and local audio never play together.
class LocalPlaybackTarget implements RemotePlayback {
  LocalPlaybackTarget(this._local, this._transferToLocal);

  final PlaybackService _local;
  final Future<void> Function() _transferToLocal;

  Future<void> _run(Future<void> Function() action) async {
    await _transferToLocal();
    await action();
  }

  @override
  Future<void> pause() => _run(_local.pause);

  @override
  Future<void> play() => _run(_local.play);

  @override
  Future<void> stop() => _run(_local.stop);

  @override
  Future<void> next() => _run(_local.next);

  @override
  Future<void> previous() => _run(_local.previous);

  @override
  Future<void> seek(Duration position) => _run(() => _local.seek(position));

  @override
  Future<void> toggle() => _run(_local.toggle);

  @override
  Future<void> setVolume(double volume) => _run(() => _local.setVolume(volume));

  @override
  Future<void> setShuffle(bool enabled) =>
      _run(() => _local.setShuffle(enabled));

  @override
  Future<void> setRepeatMode(LoopMode mode) =>
      _run(() => _local.setRepeatMode(mode));

  @override
  Future<void> addToQueue(Track track) => _run(() => _local.addToQueue(track));

  @override
  Future<void> addNextToQueue(List<Track> tracks) =>
      _run(() => _local.addNextToQueue(tracks));

  @override
  Future<void> takeOver(
    List<Track> tracks, {
    required int startIndex,
    required Duration position,
  }) => _run(
    () => _local.takeOver(tracks, startIndex: startIndex, position: position),
  );
}
