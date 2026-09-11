import 'package:just_audio/just_audio.dart';

import '../../storage/database.dart';

abstract interface class RemotePlayback {
  Future<void> pause();
  Future<void> play();
  Future<void> stop();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> toggle();
  Future<void> setVolume(double volume);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeatMode(LoopMode mode);
  Future<void> addToQueue(Track track);
  Future<void> addNextToQueue(List<Track> tracks);
  Future<void> takeOver(
    List<Track> tracks, {
    required int startIndex,
    required Duration position,
  });
}
