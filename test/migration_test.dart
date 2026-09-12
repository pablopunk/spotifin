import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/storage/database.dart';

import 'generated_migrations/schema.dart';

void main() {
  test('a v5 library upgrades to the current schema and keeps data', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(5);
    schema.rawDatabase.execute(
      "INSERT INTO tracks (id, name) VALUES ('old', 'Old song')",
    );
    final database = AppDatabase.forTesting(schema.newConnection());

    await verifier.migrateAndValidate(database, database.schemaVersion);

    final track = (await database.allTracks()).single;
    expect(track.name, 'Old song');
    expect(track.premiereDate, isNull);
    await database.close();
  });
}
