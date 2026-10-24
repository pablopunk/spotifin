import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/cast/cast_sender.dart';

void main() {
  test(
    'transport copy clears completion and load identity unless replaced',
    () {
      const finished = CastRemoteState(
        playerState: CastPlayerState.idle,
        finishReason: CastFinishReason.finished,
        occurrenceId: 'entry-a',
        loadId: 'load-a',
        mediaSessionId: 7,
      );

      final positionUpdate = finished.copyWith(
        position: const Duration(seconds: 4),
      );
      expect(positionUpdate.finishReason, isNull);
      expect(positionUpdate.occurrenceId, isNull);
      expect(positionUpdate.loadId, isNull);
      expect(positionUpdate.mediaSessionId, isNull);

      final nextLoad = finished.copyWith(
        playerState: CastPlayerState.playing,
        occurrenceId: 'entry-b',
        loadId: 'load-b',
        mediaSessionId: 8,
      );
      expect(nextLoad.finishReason, isNull);
      expect(nextLoad.occurrenceId, 'entry-b');
      expect(nextLoad.loadId, 'load-b');
      expect(nextLoad.mediaSessionId, 8);
    },
  );

  test('Cast platform check does not throw on web', () {
    expect(isCastPlatformSupported, isFalse);
  }, skip: !kIsWeb);
}
