import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'android_auto_adapter.dart';
import 'carplay_adapter.dart';

bool _carConnected(String status) =>
    status == ConnectionStatusTypes.connected.name ||
    status == ConnectionStatusTypes.background.name;

Future<void> syncCarTemplates(WidgetRef ref) async {
  final state = ref.read(carControllerProvider);
  final play = ref.read(carControllerProvider.notifier).playTrack;
  if (_carConnected(FlutterCarplay.connectionStatus)) {
    await CarPlayAdapter(play: play).showRoot(state);
  }
  if (_carConnected(FlutterAndroidAuto.connectionStatus)) {
    await AndroidAutoAdapter(play: play).showRoot(state);
  }
}

void initCarListeners(WidgetRef ref) {
  FlutterCarplay().addListenerOnConnectionChange((_) {
    syncCarTemplates(ref);
  });
  FlutterAndroidAuto().addListenerOnConnectionChange((_) {
    syncCarTemplates(ref);
  });
  ref.listen(carControllerProvider, (_, _) {
    syncCarTemplates(ref);
  });
}
