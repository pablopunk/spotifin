import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/player/scrub_slider.dart';

Widget _host(double value, List<double> seeks) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        child: ScrubSlider(value: value, max: 100000, onSeek: seeks.add),
      ),
    ),
  ),
);

double _thumb(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider)).value;

void main() {
  testWidgets('dragging seeks once, on release', (tester) async {
    final seeks = <double>[];
    await tester.pumpWidget(_host(10000, seeks));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    expect(seeks, isEmpty);
    expect(_thumb(tester), greaterThan(50000));

    await gesture.up();
    await tester.pump();
    expect(seeks, hasLength(1));
  });

  testWidgets('the thumb stays at the drop until the player catches up', (
    tester,
  ) async {
    final seeks = <double>[];
    await tester.pumpWidget(_host(10000, seeks));
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump();
    final dropped = seeks.single;

    await tester.pumpWidget(_host(10500, seeks));
    expect(_thumb(tester), dropped);

    await tester.pumpWidget(_host(dropped + 200, seeks));
    expect(_thumb(tester), dropped + 200);
  });
}
