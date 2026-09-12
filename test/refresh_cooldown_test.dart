import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/state/app_controller.dart';

void main() {
  final now = DateTime(2026, 9, 12, 12);

  test('does not throttle a refresh without a previous sync', () {
    expect(withinRefreshCooldown(null, now), isFalse);
  });

  test('throttles a refresh one minute after the last sync', () {
    expect(
      withinRefreshCooldown(now.subtract(const Duration(minutes: 1)), now),
      isTrue,
    );
  });

  test('allows a refresh six minutes after the last sync', () {
    expect(
      withinRefreshCooldown(now.subtract(const Duration(minutes: 6)), now),
      isFalse,
    );
  });

  test('allows a refresh exactly five minutes after the last sync', () {
    expect(
      withinRefreshCooldown(now.subtract(const Duration(minutes: 5)), now),
      isFalse,
    );
  });
}
