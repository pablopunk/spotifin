import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('database starts with distinct pending IDs across instances', () async {
    final ids = {...await _pendingIds(), ...await _pendingIds()};

    expect(ids, hasLength(200));
    expect(ids, everyElement(startsWith('favorite-track-')));
  });
}

Future<Set<String>> _pendingIds() async {
  final database = AppDatabase.forTesting(
    LazyDatabase(
      () => throw StateError('Allocating IDs must not open the database'),
    ),
  );
  try {
    return {
      for (var index = 0; index < 100; index++)
        database.newPendingWriteId('favorite', 'track'),
    };
  } finally {
    await database.close();
  }
}
