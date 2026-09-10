import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlayerPanelState {
  const PlayerPanelState({
    this.player = true,
    this.queue = true,
    this.lyrics = false,
  });

  final bool player;
  final bool queue;
  final bool lyrics;

  bool get isEmpty => !player && !queue && !lyrics;

  PlayerPanelState copyWith({bool? player, bool? queue, bool? lyrics}) =>
      PlayerPanelState(
        player: player ?? this.player,
        queue: queue ?? this.queue,
        lyrics: lyrics ?? this.lyrics,
      );
}

class PlayerPanelController extends Notifier<PlayerPanelState> {
  @override
  PlayerPanelState build() => const PlayerPanelState();

  void togglePlayer() => state = state.copyWith(player: !state.player);

  void toggleQueue() => state = state.copyWith(queue: !state.queue);

  void toggleLyrics() => state = state.copyWith(lyrics: !state.lyrics);
}
