import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlayerPanelState {
  const PlayerPanelState({this.queue = false, this.lyrics = false});

  final bool queue;
  final bool lyrics;

  PlayerPanelState copyWith({bool? queue, bool? lyrics}) => PlayerPanelState(
    queue: queue ?? this.queue,
    lyrics: lyrics ?? this.lyrics,
  );
}

class PlayerPanelController extends Notifier<PlayerPanelState> {
  @override
  PlayerPanelState build() => const PlayerPanelState();

  void toggleQueue() => state = state.copyWith(queue: !state.queue);

  void toggleLyrics() => state = state.copyWith(lyrics: !state.lyrics);
}
