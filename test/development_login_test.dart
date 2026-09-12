import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/state/development_login.dart';

void main() {
  test('requires explicit enablement and complete credentials', () {
    const disabled = DevelopmentLogin(
      enabled: false,
      server: 'https://example.com',
      username: 'user',
      password: 'password',
    );
    const incomplete = DevelopmentLogin(
      enabled: true,
      server: 'https://example.com',
      username: 'user',
      password: '',
    );
    const ready = DevelopmentLogin(
      enabled: true,
      server: 'https://example.com',
      username: 'user',
      password: 'password',
    );

    expect(disabled.canSignIn, isFalse);
    expect(incomplete.canSignIn, isFalse);
    expect(kReleaseMode, isFalse); // tests never run in release mode
    expect(ready.canSignIn, isTrue);
  });
}
