import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/cast/cast_sender.dart';

void main() {
  test('Cast platform check does not throw on web', () {
    expect(isCastPlatformSupported, isFalse);
  }, skip: !kIsWeb);
}
