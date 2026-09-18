import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/shortcuts/play_library_handler.dart';

void main() {
  test('matches only the exact play library link', () {
    expect(isPlayLibraryLink('spotifin://play-library'), isTrue);
    expect(isPlayLibraryLink(null), isFalse);
    expect(isPlayLibraryLink(''), isFalse);
    expect(isPlayLibraryLink('spotifin://play-librar'), isFalse);
    expect(isPlayLibraryLink('spotifin://play-library/extra'), isFalse);
    expect(isPlayLibraryLink('SPOTIFIN://play-library'), isFalse);
    expect(isPlayLibraryLink('https://play-library'), isFalse);
  });

  test('dedupe drops an immediate repeat but accepts a later run', () {
    final dedupe = PlayLibraryDedupe();
    final first = DateTime(2026, 9, 19, 12, 0, 0);
    expect(dedupe.shouldHandle('spotifin://play-library', first), isTrue);
    expect(
      dedupe.shouldHandle(
        'spotifin://play-library',
        first.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
    expect(
      dedupe.shouldHandle(
        'spotifin://play-library',
        first.add(const Duration(seconds: 4)),
      ),
      isTrue,
    );
  });

  test('dedupe rejects non library links', () {
    final dedupe = PlayLibraryDedupe();
    expect(dedupe.shouldHandle('spotifin://other', DateTime.now()), isFalse);
    expect(dedupe.shouldHandle(null, DateTime.now()), isFalse);
  });
}
