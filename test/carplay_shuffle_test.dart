import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotifin/features/car/carplay_shuffle.dart';
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

ActivePlaybackState _state({required bool shuffle}) => ActivePlaybackState(
  destination: PlaybackDestination.local,
  track: _track('current'),
  index: 0,
  entryId: 'entry-0',
  queue: [_track('current')],
  upcoming: [_track('current')],
  upcomingOffset: 0,
  history: const [],
  playing: true,
  position: Duration.zero,
  duration: Duration.zero,
  volumeSlider: 1,
  shuffle: shuffle,
  repeatMode: LoopMode.off,
  busy: false,
  recovering: false,
  capabilities: PlaybackCapability.values.toSet(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CarPlay shuffle follows the owner and toggles it on button press',
    () async {
      const channel = MethodChannel('spotifin/test_carplay_shuffle');
      final messages = <bool>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'setShuffle');
        messages.add(call.arguments as bool);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final active = FakeActivePlayback()..emit(_state(shuffle: false));
      final controller = CarPlayShuffle(active, channel: channel, enabled: true)
        ..start();
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(messages, [false]);

      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('toggleShuffle'),
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(active.actions, ['toggleShuffle']);

      active.emit(_state(shuffle: true));
      await Future<void>.delayed(Duration.zero);
      expect(messages, [false, true]);
    },
  );

  test(
    'CarPlay shuffle ignores presses while the capability is missing',
    () async {
      const channel = MethodChannel('spotifin/test_carplay_shuffle_disabled');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final active = FakeActivePlayback()
        ..emit(const ActivePlaybackState.empty());
      final controller = CarPlayShuffle(active, channel: channel, enabled: true)
        ..start();
      addTearDown(controller.dispose);

      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('toggleShuffle'),
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      // Empty capabilities: no owner action runs while frozen.
      expect(active.actions, isEmpty);
    },
  );
}
