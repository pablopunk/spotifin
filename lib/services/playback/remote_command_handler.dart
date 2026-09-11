import 'package:just_audio/just_audio.dart';

import '../../storage/database.dart';
import 'remote_playback.dart';

class RemoteCommandHandler {
  const RemoteCommandHandler(this._playback, this._database);

  final RemotePlayback _playback;
  final AppDatabase _database;

  Future<void> handle(String? type, Map<String, dynamic> data) async {
    if (type == 'Playstate') {
      await _handlePlaystate(data);
    } else if (type == 'Play') {
      await _handlePlay(data);
    } else if (type == 'GeneralCommand') {
      await _handleGeneralCommand(data);
    }
  }

  Future<void> _handlePlaystate(Map<String, dynamic> data) async {
    switch (data['Command']) {
      case 'Pause':
        await _playback.pause();
      case 'Unpause':
        await _playback.play();
      case 'Stop':
        await _playback.stop();
      case 'NextTrack':
        await _playback.next();
      case 'PreviousTrack':
        await _playback.previous();
      case 'Seek':
        await _playback.seek(durationFromTicks(data['SeekPositionTicks']));
      case 'PlayPause':
        await _playback.toggle();
    }
  }

  Future<void> _handlePlay(Map<String, dynamic> data) async {
    final ids = (data['ItemIds'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return;
    final catalog = await _database.allTracks();
    final byId = {for (final track in catalog) track.id: track};
    final requestedIndex = intValue(data['StartIndex'])
        .clamp(0, ids.length - 1)
        .toInt();
    if (byId[ids[requestedIndex]] == null) return;
    final tracks = <Track>[];
    var localIndex = 0;
    for (var index = 0; index < ids.length; index++) {
      final track = byId[ids[index]];
      if (track == null) continue;
      if (index < requestedIndex) localIndex++;
      tracks.add(track);
    }
    final command = data['PlayCommand'] as String? ?? 'PlayNow';
    if (command == 'PlayNext') {
      await _playback.addNextToQueue(tracks);
      return;
    }
    if (command == 'PlayLast') {
      for (final track in tracks) {
        await _playback.addToQueue(track);
      }
      return;
    }
    await _playback.takeOver(
      tracks,
      startIndex: localIndex,
      position: durationFromTicks(data['StartPositionTicks']),
    );
  }

  Future<void> _handleGeneralCommand(Map<String, dynamic> data) async {
    final arguments = data['Arguments'] as Map<String, dynamic>? ?? const {};
    switch (data['Name']) {
      case 'SetVolume':
        await _playback.setVolume(
          intValue(arguments['Volume']).clamp(0, 100) / 100,
        );
      case 'SetShuffleQueue':
        await _playback.setShuffle(arguments['ShuffleMode'] == 'Shuffle');
      case 'SetRepeatMode':
        final mode = switch (arguments['RepeatMode']) {
          'RepeatAll' => LoopMode.all,
          'RepeatOne' => LoopMode.one,
          _ => LoopMode.off,
        };
        await _playback.setRepeatMode(mode);
    }
  }
}

int intValue(Object? value) => switch (value) {
  int number => number,
  num number => number.round(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};

Duration durationFromTicks(Object? ticks) =>
    Duration(microseconds: intValue(ticks) ~/ 10);
