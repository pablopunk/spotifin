import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/shell/vertical_bar_content.dart';

void main() {
  testWidgets('the player bar rests at the bottom edge, not above the inset', (
    tester,
  ) async {
    const size = Size(678, 466);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: EdgeInsets.only(right: 84, bottom: 34),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: VerticalBarContent(
            content: SizedBox.expand(),
            playerBar: SizedBox(key: Key('bar'), height: 74),
          ),
        ),
      ),
    );

    final bar = tester.getRect(find.byKey(const Key('bar')));
    expect(size.height - bar.bottom, lessThanOrEqualTo(8));
    expect(bar.right, lessThanOrEqualTo(size.width - 84));
  });
}
