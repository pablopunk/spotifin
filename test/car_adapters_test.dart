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
  CarPlayAdapter carPlay() => CarPlayAdapter(play: (_, _) async {});
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
      artworkUrl: artwork,
    ).allSongsTab(tracks);
    final carPlayItem = carPlayTab.sections.single.items.single as CPListItem;
    expect(carPlayItem.image, 'https://music.test/album-art.jpg');

    final androidAutoTab = AndroidAutoAdapter(
      play: (_, _) async {},
      artworkUrl: artwork,
    ).allSongsTab(tracks);
    final androidAutoItem = androidAutoTab.sections.single.items.single;
    expect(androidAutoItem.imageUrl, 'https://music.test/album-art.jpg');
  });
}
