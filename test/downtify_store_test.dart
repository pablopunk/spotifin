import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/services/downtify/downtify_client.dart';
import 'package:spotifin/services/downtify/downtify_store.dart';

void main() {
  test('saves a normalized HTTPS Downtify address', () async {
    SharedPreferences.setMockInitialValues({});
    const store = DowntifyStore();

    expect(
      await store.saveServerUrl('downtify.example.com/'),
      'https://downtify.example.com',
    );
    expect(await store.loadServerUrl(), 'https://downtify.example.com');
  });

  test('does not save an insecure Downtify address', () async {
    SharedPreferences.setMockInitialValues({});
    const store = DowntifyStore();

    expect(
      () => store.saveServerUrl('http://downtify.example.com'),
      throwsA(isA<DowntifyException>()),
    );
    expect(await store.loadServerUrl(), isNull);
  });
}
