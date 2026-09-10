import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PlayerPanelView { closed, player, queue, lyrics }

class PlayerPanelController extends Notifier<PlayerPanelView> {
  @override
  PlayerPanelView build() => PlayerPanelView.closed;

  void show(PlayerPanelView view) => state = view;

  void close() => state = PlayerPanelView.closed;
}
