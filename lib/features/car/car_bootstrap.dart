import 'dart:async';

import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'android_auto_adapter.dart';
import 'car_controller.dart';
import 'carplay_adapter.dart';

bool _carConnected(String status) =>
    status == ConnectionStatusTypes.connected.name ||
    status == ConnectionStatusTypes.background.name;

Future<void> syncCarTemplates(WidgetRef ref) async {
  final state = ref.read(carControllerProvider);
  final play = ref.read(carControllerProvider.notifier).playTrack;
  final session = ref.read(appControllerProvider).session;
  final client = ref.read(jellyfinClientProvider);
  String? artworkUrl(String itemId) => session == null
      ? null
      : client.imageUri(session, itemId, width: 128).toString();
  if (_carConnected(FlutterCarplay.connectionStatus)) {
    await CarPlayAdapter(play: play, artworkUrl: artworkUrl).showRoot(state);
  }
  if (_carConnected(FlutterAndroidAuto.connectionStatus)) {
    await AndroidAutoAdapter(
      play: play,
      artworkUrl: artworkUrl,
    ).showRoot(state);
  }
}

/// Starts car template observation outside of `build`.
///
/// Uses [ref.listenManual] so this can run once from `initState`. Returns a
/// cleanup function the host must call during disposal: it closes the
/// provider subscription, removes both native connection listeners exactly
/// once, and guards late native callbacks so they can never use a disposed
/// ref. Registration, removal, and rendering callbacks are injectable so
/// tests never launch native apps.
void Function() initCarListeners(
  WidgetRef ref, {
  void Function(void Function())? observeCarPlay,
  void Function(void Function())? observeAndroidAuto,
  void Function()? unobserveCarPlay,
  void Function()? unobserveAndroidAuto,
  Future<void> Function(WidgetRef)? renderTemplates,
}) {
  var alive = true;
  Future<void> scheduleRender() {
    if (!alive) return Future.value();
    return (renderTemplates ?? syncCarTemplates)(ref);
  }

  (observeCarPlay ??
      ((notify) => FlutterCarplay().addListenerOnConnectionChange(
        (_) => notify(),
      )))(scheduleRender);
  (observeAndroidAuto ??
      ((notify) => FlutterAndroidAuto().addListenerOnConnectionChange(
        (_) => notify(),
      )))(scheduleRender);
  final subscription = ref.listenManual<CarState>(
    carControllerProvider,
    (_, _) => scheduleRender(),
  );

  var closed = false;
  return () {
    if (closed) return;
    closed = true;
    alive = false;
    subscription.close();
    (unobserveCarPlay ??
        (() => FlutterCarplay().removeListenerOnConnectionChange()))();
    (unobserveAndroidAuto ??
        (() => FlutterAndroidAuto().removeListenerOnConnectionChange()))();
  };
}
