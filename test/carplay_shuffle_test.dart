import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/features/car/carplay_shuffle.dart';
import 'package:spotifin/services/playback/playback_service.dart';

class _Playback extends Mock implements PlaybackService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CarPlay shuffle follows playback and toggles it on button press',
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

      final playback = _Playback();
      var shuffle = false;
      VoidCallback? listener;
      when(() => playback.shuffle).thenAnswer((_) => shuffle);
      when(() => playback.addListener(any())).thenAnswer((invocation) {
        listener = invocation.positionalArguments.single as VoidCallback;
      });
      when(() => playback.removeListener(any())).thenReturn(null);
      when(() => playback.toggleShuffle()).thenAnswer((_) async {
        shuffle = !shuffle;
        listener!();
      });

      final controller = CarPlayShuffle(
        playback,
        channel: channel,
        enabled: true,
      )..start();
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
      verify(() => playback.toggleShuffle()).called(1);
      expect(messages, [false, true]);

      listener!();
      await Future<void>.delayed(Duration.zero);
      expect(messages, [false, true]);
    },
  );
}
