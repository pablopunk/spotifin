import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/car/android_auto_adapter.dart';
import 'package:spotifin/features/car/car_controller.dart';
import 'package:spotifin/features/car/carplay_adapter.dart';
import 'package:spotifin/storage/database.dart';

Track makeTrack(String id, {String artist = 'Artist'}) => Track(
  id: id,
  name: 'Song $id',
  album: 'Album',
  artist: artist,
  artistItems: '[]',
  labels: '[]',
  durationTicks: 0,
  container: 'mp3',
  favorite: false,
  playCount: 0,
);

void main() {
  CarPlayAdapter carPlay() => CarPlayAdapter(
    play: (_, _) async {},
    playQueue: (_, {required shuffle}) async {},
  );
  AndroidAutoAdapter auto() => AndroidAutoAdapter(play: (_, _) async {});

  test('carplay signed-out root explains sign in', () {
    final root = carPlay().buildRoot(const CarState(signedIn: false));
    expect(root, isA<CPListTemplate>());
  });

  test('carplay empty library root explains sync', () {
    final root = carPlay().buildRoot(const CarState(signedIn: true));
    expect(root, isA<CPListTemplate>());
  });

  test('carplay ready root has four ordered tabs', () {
    final root = carPlay().buildRoot(
      CarState(
        signedIn: true,
        tracks: [
          makeTrack('a'),
          makeTrack('b', artist: 'Miles'),
        ],
      ),
    );
    expect(root, isA<CPTabBarTemplate>());
    final tabs = (root as CPTabBarTemplate).templates.cast<CPListTemplate>();
    expect(tabs.map((tab) => tab.tabTitle), [
      'Recents',
      'All Songs',
      'Playlists',
      'Artists',
    ]);
  });

  test('android auto signed-out root is a message', () {
    final root = auto().buildRoot(const CarState(signedIn: false));
    expect(root, isA<AAMessageTemplate>());
  });

  test('android auto ready root has four ordered tabs', () {
    final root = auto().buildRoot(
      CarState(
        signedIn: true,
        tracks: [
          makeTrack('a'),
          makeTrack('b', artist: 'Miles'),
        ],
      ),
    );
    expect(root, isA<AATabBarTemplate>());
    final tabs = (root as AATabBarTemplate).tabs.cast<AAListTemplate>();
    expect(tabs.map((tab) => tab.tabTitle), [
      'Recents',
      'All Songs',
      'Playlists',
      'Artists',
    ]);
  });

  test('android auto search respects empty query', () {
    final tracks = [makeTrack('a')];
    final results = auto().searchResults('', tracks);
    expect(results.sections.single.items, isEmpty);
  });

  test('song rows include album artwork on both car platforms', () {
    final tracks = [makeTrack('album-art')];
    String artwork(String id) => 'https://music.test/$id.jpg';

    final carPlayTab = CarPlayAdapter(
      play: (_, _) async {},
      playQueue: (_, {required shuffle}) async {},
      artworkUrl: artwork,
    ).allSongsTab(tracks);
    final carPlayItem = carPlayTab.sections.single.items[1] as CPListItem;
    expect(carPlayItem.image, 'https://music.test/album-art.jpg');

    final androidAutoTab = AndroidAutoAdapter(
      play: (_, _) async {},
      artworkUrl: artwork,
    ).allSongsTab(tracks);
    final androidAutoItem = androidAutoTab.sections.single.items.single;
    expect(androidAutoItem.imageUrl, 'https://music.test/album-art.jpg');
  });

  test(
    'CarPlay library shuffle queues every song with shuffle enabled',
    () async {
      final tracks = List.generate(60, (index) => makeTrack('track-$index'));
      List<Track>? queued;
      bool? requestedShuffle;
      final adapter = CarPlayAdapter(
        play: (_, _) async {},
        playQueue: (tracks, {required bool shuffle}) async {
          queued = tracks;
          requestedShuffle = shuffle;
        },
      );

      final items = adapter
          .allSongsTab(tracks)
          .sections
          .single
          .items
          .cast<CPListItem>();
      expect(items, hasLength(50));
      expect(items.first.text, 'Shuffle Library');
      expect(items.first.detailText, '60 songs');

      var completed = false;
      await items.first.onPress!(() => completed = true, items.first);

      expect(queued, same(tracks));
      expect(requestedShuffle, isTrue);
      expect(completed, isTrue);
    },
  );
}
