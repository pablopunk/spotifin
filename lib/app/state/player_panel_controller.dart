import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PlayerPanel { player, lyrics, queue, history }

class PlayerPanelState {
  const PlayerPanelState({
    this.openPanels = const [PlayerPanel.player, PlayerPanel.queue],
  });

  final List<PlayerPanel> openPanels;

  bool get player => openPanels.contains(PlayerPanel.player);
  bool get lyrics => openPanels.contains(PlayerPanel.lyrics);
  bool get queue => openPanels.contains(PlayerPanel.queue);
  bool get history => openPanels.contains(PlayerPanel.history);
  bool get isEmpty => openPanels.isEmpty;

  PlayerPanelState copyWith({required List<PlayerPanel> openPanels}) =>
      PlayerPanelState(openPanels: List.unmodifiable(openPanels));
}

class PlayerPanelController extends Notifier<PlayerPanelState> {
  @override
  PlayerPanelState build() => const PlayerPanelState();

  void togglePlayer({int? maxOpen}) => _toggle(PlayerPanel.player, maxOpen);

  void toggleQueue({int? maxOpen}) => _toggle(PlayerPanel.queue, maxOpen);

  void toggleLyrics({int? maxOpen}) => _toggle(PlayerPanel.lyrics, maxOpen);

  void toggleHistory({int? maxOpen}) => _toggle(PlayerPanel.history, maxOpen);

  void constrainTo(int maxOpen) {
    if (state.openPanels.length <= maxOpen) return;
    state = state.copyWith(
      openPanels: state.openPanels.sublist(state.openPanels.length - maxOpen),
    );
  }

  void _toggle(PlayerPanel panel, int? maxOpen) {
    final openPanels = [...state.openPanels];
    if (openPanels.remove(panel)) {
      state = state.copyWith(openPanels: openPanels);
      return;
    }
    openPanels.add(panel);
    if (maxOpen != null && openPanels.length > maxOpen) {
      openPanels.removeRange(0, openPanels.length - maxOpen);
    }
    state = state.copyWith(openPanels: openPanels);
  }
}
