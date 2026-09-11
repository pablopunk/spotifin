import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/playback/queue_item_identity.dart';

void main() {
  test('creates unique queue identities without random integer limits', () {
    final identity = QueueItemIdentity(
      now: () => DateTime.fromMicrosecondsSinceEpoch(123),
    );

    expect(identity.next(), '123-0');
    expect(identity.next(), '123-1');
  });
}
