import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/platform/safe_path_segment.dart';

void main() {
  test('keeps safe identifiers unchanged', () {
    expect(safePathSegment('normal-id_1.2'), 'normal-id_1.2');
  });

  test('removes path separators', () {
    expect(safePathSegment('../evil'), isNot(contains('/')));
    expect(safePathSegment('../evil'), isNot(contains(r'\')));
    expect(safePathSegment('a/b\\c:d'), isNot(contains('/')));
    expect(safePathSegment('a/b\\c:d'), isNot(contains(r'\')));
  });

  test('replaces traversal names and empty values', () {
    expect(safePathSegment('..'), '_');
    expect(safePathSegment('.'), '_');
    expect(safePathSegment(''), '_');
  });
}
