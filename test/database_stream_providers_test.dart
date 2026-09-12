import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('database stream providers keep a stable stream identity', () {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    expect(
      identical(
        container.read(allTracksStreamProvider),
        container.read(allTracksStreamProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(tracksByDateAddedStreamProvider),
        container.read(tracksByDateAddedStreamProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(playlistsStreamProvider),
        container.read(playlistsStreamProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(downloadsStreamProvider),
        container.read(downloadsStreamProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(albumDatesStreamProvider),
        container.read(albumDatesStreamProvider),
      ),
      isTrue,
    );
  });
}
