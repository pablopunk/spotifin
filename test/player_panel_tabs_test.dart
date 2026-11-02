import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/player/player_panel_tabs.dart';

void main() {
  testWidgets('each tab toggles its panel and shows when it is open', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PlayerPanelTabs())),
      ),
    );

    bool selected(String tooltip) => tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, _icon(tooltip)))
        .isSelected!;

    expect(selected('Now playing'), isTrue);
    expect(selected('Queue'), isTrue);
    expect(selected('Lyrics'), isFalse);

    await tester.tap(find.byTooltip('Lyrics'));
    await tester.pump();
    expect(container.read(playerPanelProvider).lyrics, isTrue);
    expect(selected('Lyrics'), isTrue);

    await tester.tap(find.byTooltip('Now playing'));
    await tester.pump();
    expect(container.read(playerPanelProvider).player, isFalse);
    expect(selected('Now playing'), isFalse);

    await tester.tap(find.byTooltip('History'));
    await tester.pump();
    expect(container.read(playerPanelProvider).history, isTrue);
  });
}

IconData _icon(String tooltip) => switch (tooltip) {
  'Now playing' => Icons.album_rounded,
  'Lyrics' => Icons.lyrics_outlined,
  'Queue' => Icons.queue_music_rounded,
  _ => Icons.history_rounded,
};
