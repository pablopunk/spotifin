import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/cast/cast_sender.dart';

void main() {
  test('transport copy clears completion and keeps the item', () {
    const finished = CastRemoteState(
      playerState: CastPlayerState.idle,
      finishReason: CastFinishReason.finished,
      itemId: 'a',
    );

    final positionUpdate = finished.copyWith(
      position: const Duration(seconds: 4),
    );
    expect(positionUpdate.finishReason, isNull);
    expect(positionUpdate.itemId, 'a');
    expect(positionUpdate.position, const Duration(seconds: 4));
  });

  test('Cast platform check does not throw on web', () {
    expect(isCastPlatformSupported, isFalse);
  }, skip: !kIsWeb);
}
