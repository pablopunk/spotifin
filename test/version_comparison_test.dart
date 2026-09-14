import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/updates/version_comparison.dart';

void main() {
  test('strips a leading v', () {
    expect(normalizeVersion('v0.1.4'), '0.1.4');
  });

  test('treats a higher patch as newer', () {
    expect(isNewerVersion('0.1.5', '0.1.4'), isTrue);
    expect(isNewerVersion('0.1.4', '0.1.5'), isFalse);
  });

  test('compares numeric segments, not text', () {
    expect(isNewerVersion('0.1.10', '0.1.9'), isTrue);
    expect(isNewerVersion('0.10.0', '0.9.0'), isTrue);
  });

  test('ignores build metadata', () {
    expect(isNewerVersion('0.1.4+9', '0.1.4+1'), isFalse);
    expect(compareVersions('0.1.4', 'v0.1.4'), 0);
  });

  test('pads missing segments with zeros', () {
    expect(isNewerVersion('0.2', '0.1.4'), isTrue);
    expect(isNewerVersion('1', '0.9.9'), isTrue);
    expect(isNewerVersion('0.1', '0.1.0'), isFalse);
  });
}
