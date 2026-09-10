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
}
