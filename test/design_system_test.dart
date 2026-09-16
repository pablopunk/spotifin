import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/design_system.dart';

void main() {
  test('theme uses the design system palette and typography', () {
    final theme = buildTheme();

    expect(theme.scaffoldBackgroundColor, SpotifinColors.background);
    expect(theme.colorScheme.primary, SpotifinColors.accent);
    expect(theme.focusColor, SpotifinColors.accent.withValues(alpha: .4));
    expect(theme.textTheme.headlineSmall?.fontSize, 24);
    expect(theme.textTheme.headlineSmall?.fontWeight, FontWeight.w700);
    expect(theme.textTheme.bodySmall?.color, SpotifinColors.textMuted);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Manrope');
    expect(theme.sliderTheme.overlayColor, const Color(0x3339F4D1));
  });

  testWidgets('shared components fit a narrow mobile viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: spotifinGrid(
            itemCount: 1,
            itemBuilder: (_, _) => SpotifinCollectionCard(
              artwork: const ColoredBox(color: SpotifinColors.raised),
              title: 'Collection',
              subtitle: '12 songs',
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Collection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chrome insets reach content grids', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SpotifinChromeInsets(
          bottom: SpotifinChromeInsets.glassMobileBottom,
          child: Scaffold(
            body: spotifinGrid(
              itemCount: 1,
              itemBuilder: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      grid.padding,
      const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        SpotifinChromeInsets.glassMobileBottom,
      ),
    );
  });

  testWidgets('tabs start without the Material 3 leading offset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(appBar: SpotifinTabBar(labels: ['Songs', 'Albums'])),
        ),
      ),
    );

    expect(
      tester.widget<TabBar>(find.byType(TabBar)).tabAlignment,
      TabAlignment.start,
    );
  });

  testWidgets('collection card reveals play on hover only', (tester) async {
    var taps = 0;
    var plays = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 238,
            child: SpotifinCollectionCard(
              artwork: const ColoredBox(color: SpotifinColors.raised),
              title: 'Collection',
              subtitle: '12 songs',
              onTap: () => taps++,
              onPlay: () => plays++,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SpotifinPlayButton), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(SpotifinCollectionCard)));
    await tester.pump();

    expect(find.byType(SpotifinPlayButton), findsOneWidget);
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      SpotifinColors.hover,
    );

    await tester.tap(find.byType(SpotifinPlayButton));
    await tester.pump();
    expect(plays, 1);
    expect(taps, 0);

    await gesture.moveTo(const Offset(700, 500));
    await tester.pump();
    expect(find.byType(SpotifinPlayButton), findsNothing);
    await gesture.removePointer();
  });

  testWidgets('active card keeps pause visible after pointer exit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 238,
            child: SpotifinCollectionCard(
              artwork: const ColoredBox(color: SpotifinColors.raised),
              title: 'Collection',
              subtitle: '12 songs',
              onTap: () {},
              onPlay: () {},
              active: true,
              playing: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SpotifinPlayButton), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('card without onPlay never shows the overlay', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 238,
            child: SpotifinCollectionCard(
              artwork: const ColoredBox(color: SpotifinColors.raised),
              title: 'Collection',
              subtitle: '12 songs',
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(SpotifinCollectionCard)));
    await tester.pump();

    expect(find.byType(SpotifinPlayButton), findsNothing);
    await gesture.removePointer();
  });
}
