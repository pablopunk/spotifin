import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/redaction.dart';

void main() {
  test('redacts query tokens', () {
    final redacted = redactSecrets(
      Exception('Failed: https://x/Audio/1/stream?api_key=SECRET&x=1'),
    );

    expect(redacted, isNot(contains('SECRET')));
    expect(redacted, contains('<redacted>'));
  });

  test('redacts header style secrets', () {
    expect(redactSecrets(Exception('ApiKey=SECRET')), isNot(contains('SECRET')));
    expect(
      redactSecrets(Exception('Token="SECRET"')),
      isNot(contains('SECRET')),
    );
    expect(
      redactSecrets(Exception('Authorization: SECRET')),
      isNot(contains('SECRET')),
    );
  });

  test('keeps messages without secrets unchanged', () {
    expect(
      redactSecrets(Exception('plain failure')),
      'Exception: plain failure',
    );
  });
}
