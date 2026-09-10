import 'package:flutter_carplay/flutter_carplay.dart';

import '../services/playback/playback_service.dart';
import '../storage/database.dart';

class CarPlayService {
  Future<void> configure(List<Track> tracks, PlaybackService playback) async {
    final items = tracks.take(50).map((track) {
      return CPListItem(
        text: track.name,
        detailText: track.artist,
        onPress: (complete, _) async {
          await playback.playTrack(track, tracks);
          await FlutterCarplay.showSharedNowPlaying();
          complete();
        },
      );
    }).toList();
    try {
      await FlutterCarplay.setRootTemplate(
        rootTemplate: CPListTemplate(
          title: 'Songs',
          systemIcon: 'music.note.list',
          sections: [CPListSection(header: 'Your music', items: items)],
          emptyViewTitleVariants: const ['No music available'],
        ),
        animated: false,
      );
    } catch (_) {}
  }
}
