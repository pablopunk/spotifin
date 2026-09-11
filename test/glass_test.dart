import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/state/app_controller.dart';

void main() {
  test('glass appearance defaults and copy independently', () {
    const state = AppState();

    expect(state.glassEffects, isTrue);
    expect(state.glassOpacity, .8);

    final changed = state.copyWith(glassEffects: false, glassOpacity: .7);
    expect(changed.glassEffects, isFalse);
    expect(changed.glassOpacity, .7);
  });
}
