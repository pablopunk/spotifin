import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/services/jellyfin/session_store.dart';

void main() {
  test('keeps one unique Jellyfin device ID for the installation', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SessionStore(FlutterSecureStorage());

    final first = await store.getDeviceId();
    final second = await store.getDeviceId();

    expect(first, matches(RegExp(r'^spotifin-[0-9a-f]{32}$')));
    expect(second, first);
  });
}
