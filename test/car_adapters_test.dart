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

  test('carplay ready root has five tabs', () {
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
    expect((root as CPTabBarTemplate).templates, hasLength(5));
  });

  test('android auto signed-out root is a message', () {
    final root = auto().buildRoot(const CarState(signedIn: false));
    expect(root, isA<AAMessageTemplate>());
  });

  test('android auto ready root has five tabs', () {
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
    expect((root as AATabBarTemplate).tabs, hasLength(5));
  });

  test('android auto search respects empty query', () {
    final tracks = [makeTrack('a')];
    final results = auto().searchResults('', tracks);
    expect(results.sections.single.items, isEmpty);
  });
}
