import 'package:flutter/services.dart';
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flutter_carplay/controllers/android_auto_controller.dart';
import 'package:flutter_carplay/controllers/carplay_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/car/android_auto_adapter.dart';
import 'package:spotifin/features/car/car_controller.dart';
import 'package:spotifin/features/car/carplay_adapter.dart';
import 'package:spotifin/storage/database.dart';

Track makeTrack(
  String id, {
  String? name,
  String artist = 'Artist',
  String artistItems = '[]',
}) => Track(
  id: id,
  name: name ?? 'Song $id',
  album: 'Album',
  artist: artist,
  artistItems: artistItems,
  labels: '[]',
  durationTicks: 0,
  container: 'mp3',
  favorite: false,
  playCount: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    'both car adapters browse and select collaborative artist tracks',
    () async {
      const carPlayChannel = MethodChannel('com.oguzhnatly.flutter_carplay');
      const androidAutoChannel = MethodChannel(
        'com.oguzhnatly.flutter_android_auto',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(carPlayChannel, (_) async => true);
      messenger.setMockMethodCallHandler(androidAutoChannel, (_) async => true);
      FlutterCarPlayController.templateHistory.clear();
      FlutterAndroidAutoController.templateHistory.clear();
      addTearDown(() {
        messenger.setMockMethodCallHandler(carPlayChannel, null);
        messenger.setMockMethodCallHandler(androidAutoChannel, null);
        FlutterCarPlayController.templateHistory.clear();
        FlutterAndroidAutoController.templateHistory.clear();
      });

      final tracks = [
        makeTrack('alice-solo', name: 'Alice Solo', artist: 'Alice'),
        makeTrack('bob-solo', name: 'Bob Solo', artist: 'Bob'),
        makeTrack(
          'collaboration',
          name: 'Collaboration',
          artist: 'Alice, Bob',
          artistItems:
              '[{"id":"alice","name":"Alice"},{"id":"bob","name":"Bob"}]',
        ),
        makeTrack('unrelated', name: 'Unrelated', artist: 'Carol'),
      ];

      Future<void> browseAndSelectCarPlay(String artist) async {
        Track? selectedTrack;
        List<Track>? selectedContext;
        final adapter = CarPlayAdapter(
          play: (track, context) async {
            selectedTrack = track;
            selectedContext = context;
          },
          playQueue: (_, {required shuffle}) async {},
        );
        final artistItems = adapter
            .artistsTab(tracks)
            .sections
            .single
            .items
            .cast<CPListItem>();
        final artistItem = artistItems.singleWhere(
          (item) => item.text == artist,
        );
        await artistItem.onPress!(() {}, artistItem);

        final browse =
            FlutterCarPlayController.templateHistory.last as CPListTemplate;
        final trackItems = browse.sections.single.items.cast<CPListItem>();
        expect(trackItems.map((item) => item.text), [
          '$artist Solo',
          'Collaboration',
        ]);
        final collaboration = trackItems.singleWhere(
          (item) => item.text == 'Collaboration',
        );
        await collaboration.onPress!(() {}, collaboration);

        expect(selectedTrack?.id, 'collaboration');
        expect(selectedContext?.map((track) => track.id), [
          '${artist.toLowerCase()}-solo',
          'collaboration',
        ]);
      }

      Future<void> browseAndSelectAndroidAuto(String artist) async {
        Track? selectedTrack;
        List<Track>? selectedContext;
        final adapter = AndroidAutoAdapter(
          play: (track, context) async {
            selectedTrack = track;
            selectedContext = context;
          },
        );
        final artistItems = adapter
            .artistsTab(tracks)
            .sections
            .single
            .items
            .cast<AAListItem>();
        final artistItem = artistItems.singleWhere(
          (item) => item.title == artist,
        );
        await artistItem.onPress!(() {}, artistItem);

        final browse =
            FlutterAndroidAutoController.templateHistory.last as AAListTemplate;
        final trackItems = browse.sections.single.items;
        expect(trackItems.map((item) => item.title), [
          '$artist Solo',
          'Collaboration',
        ]);
        final collaboration = trackItems.singleWhere(
          (item) => item.title == 'Collaboration',
        );
        await collaboration.onPress!(() {}, collaboration);

        expect(selectedTrack?.id, 'collaboration');
        expect(selectedContext?.map((track) => track.id), [
          '${artist.toLowerCase()}-solo',
          'collaboration',
        ]);
      }

      await browseAndSelectCarPlay('Alice');
      await browseAndSelectCarPlay('Bob');
      await browseAndSelectAndroidAuto('Alice');
      await browseAndSelectAndroidAuto('Bob');
    },
  );

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
