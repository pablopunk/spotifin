import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/state/player_panel_controller.dart';

final _provider = NotifierProvider<PlayerPanelController, PlayerPanelState>(
  PlayerPanelController.new,
);

void main() {
  test('opens artwork and queue by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(_provider).openPanels, [
      PlayerPanel.player,
      PlayerPanel.queue,
    ]);
  });

  test('narrow panel keeps the two most recently selected sections', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(_provider.notifier);

    controller.toggleLyrics(maxOpen: 2);
    expect(container.read(_provider).openPanels, [
      PlayerPanel.queue,
      PlayerPanel.lyrics,
    ]);

    controller.toggleHistory(maxOpen: 2);
    expect(container.read(_provider).openPanels, [
      PlayerPanel.lyrics,
      PlayerPanel.history,
    ]);
  });

  test('wide panel can open all four independent sections', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(_provider.notifier);

    controller.toggleLyrics(maxOpen: 4);
    controller.toggleHistory(maxOpen: 4);

    final panels = container.read(_provider);
    expect(panels.player, isTrue);
    expect(panels.lyrics, isTrue);
    expect(panels.queue, isTrue);
    expect(panels.history, isTrue);
  });

  test('resizing narrow retains the most recent sections', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(_provider.notifier);

    controller.toggleLyrics(maxOpen: 4);
    controller.toggleHistory(maxOpen: 4);
    controller.constrainTo(2);

    expect(container.read(_provider).openPanels, [
      PlayerPanel.lyrics,
      PlayerPanel.history,
    ]);
  });
}
