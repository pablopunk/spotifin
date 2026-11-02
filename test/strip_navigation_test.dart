import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:spotifin/features/shell/strip_navigation.dart';

GlassVerticalBarData _strip({
  required Size size,
  required EdgeInsets padding,
}) => GlassVerticalBar.resolve(
  viewPadding: padding,
  size: size,
  platform: TargetPlatform.iOS,
  textDirection: TextDirection.ltr,
)!;

void main() {
  testWidgets('tabs sit in the strip on the right and select', (tester) async {
    const size = Size(466, 678);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StripNavigation(
            strip: _strip(
              size: size,
              padding: const EdgeInsets.only(right: 84, bottom: 34),
            ),
            selectedIndex: 0,
            onSelected: (index) => selected = index,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.library_music),
                label: Text('Library'),
              ),
            ],
            child: const SizedBox.expand(key: Key('content')),
          ),
        ),
      ),
    );

    final rail = tester.getRect(find.byType(NavigationRail));
    expect(rail.left, greaterThanOrEqualTo(size.width - 84));
    expect(rail.right, size.width);
    await tester.tap(find.byIcon(Icons.library_music));
    expect(selected, 1);
  });
}
