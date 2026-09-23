import 'package:flutter/services.dart';
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flutter_carplay/controllers/carplay_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/features/car/carplay_up_next.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/storage/database.dart';

class _Playback extends Mock implements PlaybackService {}

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

      final playback = _Playback();
      final current = _track('Current');
      final next = _track('Next');
      when(() => playback.currentIndex).thenReturn(2);
      when(() => playback.upcomingQueue).thenReturn([current, next]);
      when(() => playback.playUpcomingIndex(any())).thenAnswer((_) async {});
      final controller = CarPlayUpNext(playback, enabled: false);
      final template = controller.buildTemplate();
      final items = template.sections.single.items.cast<CPListItem>();
      expect(items.map((item) => item.text), ['Current', 'Next']);
      expect(items.first.isPlaying, isTrue);

      var completed = false;
      await items.last.onPress!(() => completed = true, items.last);
      expect(completed, isTrue);
      verify(() => playback.playUpcomingIndex(1)).called(1);
      expect(carCalls, contains('popTemplate'));

      when(() => playback.upcomingQueue).thenReturn([next]);
      await items.last.onPress!(() {}, items.last);
      verify(() => playback.playUpcomingIndex(0)).called(1);
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

    final playback = _Playback();
    var queue = <Track>[];
    VoidCallback? listener;
    when(() => playback.upcomingQueue).thenAnswer((_) => queue);
    when(() => playback.addListener(any())).thenAnswer((invocation) {
      listener = invocation.positionalArguments.single as VoidCallback;
    });
    when(() => playback.removeListener(any())).thenReturn(null);
    final controller = CarPlayUpNext(playback, channel: channel, enabled: true)
      ..start();
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(availability, [false]);

    queue = [_track('Current')];
    listener!();
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

      final playback = _Playback();
      when(() => playback.upcomingQueue)
          .thenReturn([_track('Current'), _track('Next')]);
      when(() => playback.currentIndex).thenReturn(0);
      when(() => playback.addListener(any())).thenReturn(null);
      when(() => playback.removeListener(any())).thenReturn(null);
      final controller = CarPlayUpNext(
        playback,
        channel: channel,
        enabled: true,
      )..start();
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
