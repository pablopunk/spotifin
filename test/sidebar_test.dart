import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/shell/sidebar.dart';

void main() {
  testWidgets('selected destination fills the row with compact spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SpotifinSidebar(
            destinations: const [
              SpotifinSidebarDestination(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Home',
              ),
            ],
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            extended: true,
          ),
        ),
      ),
    );

    final selectedBackground = find.byWidgetPredicate(
      (widget) => widget is Material && widget.color == SpotifinColors.accent,
    );
    final icon = find.byIcon(Icons.home_rounded);
    final label = find.text('Home');

    expect(tester.getSize(selectedBackground), const Size(196, 40));
    expect(tester.getTopLeft(label).dx - tester.getTopRight(icon).dx, 12);
  });
}
