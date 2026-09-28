import 'package:flutter/services.dart';
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flutter_carplay/controllers/carplay_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotifin/features/car/carplay_up_next.dart';
import 'package:spotifin/services/playback/active_playback_state.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_active_playback.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  album: 'Album',
  albumId: 'album',
  artist: 'Artist',
  artistItems: '[]',
  labels: '',
  durationTicks: 0,
  container: '',
  favorite: false,
  playCount: 0,
);

ActivePlaybackState _state({
  required List<Track> upcoming,
  required int index,
}) => ActivePlaybackState(
  destination: PlaybackDestination.local,
  track: upcoming.isEmpty
      ? null
      : upcoming[index.clamp(0, upcoming.length - 1)],
  index: upcoming.isEmpty ? null : index,
  entryId: 'entry-0',
  queue: upcoming,
  upcoming: upcoming,
  upcomingOffset: 0,
  history: const [],
  playing: true,
  position: Duration.zero,
  duration: Duration.zero,
  volumeSlider: 1,
  shuffle: false,
  repeatMode: LoopMode.off,
  busy: false,
  recovering: false,
  capabilities: PlaybackCapability.values.toSet(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Up Next shows current and future songs and selects the right index',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final carChannel = FlutterCarPlayController().methodChannel;
      final carCalls = <String>[];
      messenger.setMockMethodCallHandler(carChannel, (call) async {
        carCalls.add(call.method);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(carChannel, null));

      final current = _track('Current');
      final next = _track('Next');
      final active = FakeActivePlayback()
        ..emit(_state(upcoming: [current, next], index: 0));
      final controller = CarPlayUpNext(active, enabled: false);
      final template = controller.buildTemplate();
      final items = template.sections.single.items.cast<CPListItem>();
      expect(items.map((item) => item.text), ['Current', 'Next']);
      expect(items.first.isPlaying, isTrue);

      var completed = false;
      await items.last.onPress!(() => completed = true, items.last);
      expect(completed, isTrue);
      expect(active.actions, ['playUpcomingIndex']);
      expect(active.actionArguments['playUpcomingIndex'], [1]);
      expect(carCalls, contains('popTemplate'));

      active.emit(_state(upcoming: [next], index: 0));
      await items.last.onPress!(() {}, items.last);
      expect(active.actionArguments['playUpcomingIndex'], [0]);
    },
  );

  test('Up Next button follows queue availability', () async {
    const channel = MethodChannel('spotifin/test_carplay_up_next');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final availability = <bool>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setUpNextEnabled');
      availability.add(call.arguments as bool);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final active = FakeActivePlayback()
      ..emit(_state(upcoming: const [], index: 0));
    final controller = CarPlayUpNext(active, channel: channel, enabled: true)
      ..start();
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(availability, [false]);

    active.emit(_state(upcoming: [_track('Current')], index: 0));
    await Future<void>.delayed(Duration.zero);
    expect(availability, [false, true]);
  });

  test(
    'tapping Up Next pushes a queue list within the car item limit',
    () async {
      const channel = MethodChannel('spotifin/test_carplay_up_next_tap');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final carChannel = FlutterCarPlayController().methodChannel;
      Map<Object?, Object?>? pushed;
      messenger.setMockMethodCallHandler(carChannel, (call) async {
        if (call.method == 'getMaximumItemCount') return 1;
        if (call.method == 'pushTemplate') {
          pushed = call.arguments as Map<Object?, Object?>;
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(carChannel, null));
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final active = FakeActivePlayback()
        ..emit(_state(upcoming: [_track('Current'), _track('Next')], index: 0));
      final controller = CarPlayUpNext(active, channel: channel, enabled: true)
        ..start();
      addTearDown(controller.dispose);

      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('showUpNext'),
        ),
        (_) {},
      );
      final template = pushed!['template'] as Map<Object?, Object?>;
      final sections = template['sections'] as List<Object?>;
      final section = sections.single as Map<Object?, Object?>;
      final items = section['items'] as List<Object?>;
      expect(items, hasLength(1));
      expect((items.single as Map<Object?, Object?>)['text'], 'Current');
    },
  );
}
