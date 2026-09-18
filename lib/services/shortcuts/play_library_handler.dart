import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/state/app_controller.dart';

const playLibraryLink = 'spotifin://play-library';
const deepLinkChannelName = 'spotifin/deep-link';
const playLibraryTimeout = Duration(seconds: 15);
const playLibraryPollInterval = Duration(milliseconds: 200);
const playLibraryDedupeWindow = Duration(seconds: 3);

bool isPlayLibraryLink(String? link) => link == playLibraryLink;

class PlayLibraryDedupe {
  String? lastLink;
  DateTime? lastAt;

  bool shouldHandle(String? link, DateTime now) {
    if (!isPlayLibraryLink(link)) return false;
    if (link == lastLink &&
        lastAt != null &&
        now.difference(lastAt!) < playLibraryDedupeWindow) {
      return false;
    }
    lastLink = link;
    lastAt = now;
    return true;
  }
}

final _dedupe = PlayLibraryDedupe();

Future<void> configurePlayLibraryShortcut(WidgetRef ref) async {
  const channel = MethodChannel(deepLinkChannelName);
  channel.setMethodCallHandler((call) async {
    if (call.method == 'onLink') {
      final arguments = call.arguments;
      await handlePlayLibraryLink(ref, arguments is String ? arguments : null);
    }
  });
  try {
    final initial = await channel
        .invokeMethod<String>('getInitialLink')
        .timeout(playLibraryTimeout);
    await handlePlayLibraryLink(ref, initial);
  } catch (_) {}
}

Future<void> handlePlayLibraryLink(WidgetRef ref, String? link) async {
  if (!_dedupe.shouldHandle(link, DateTime.now())) return;
  try {
    await _playLibrary(ref).timeout(playLibraryTimeout);
  } catch (_) {}
}

Future<void> _playLibrary(WidgetRef ref) async {
  final app = await _waitForReadySession(ref);
  final session = app.session;
  if (session == null) return;
  final playback = ref.read(playbackProvider);
  await playback.configure(
    session,
    smallStreaming: app.smallStreaming,
    normalization: app.normalization,
  );
  final tracks = await ref.read(databaseProvider).allTracksByDateAdded();
  if (tracks.isEmpty) return;
  await playback.replaceQueue(tracks, startIndex: 0);
}

Future<AppState> _waitForReadySession(WidgetRef ref) async {
  for (;;) {
    final state = ref.read(appControllerProvider);
    if (state.status == AppStatus.signedOut) {
      throw StateError('signed out');
    }
    if (state.status == AppStatus.ready && state.session != null) return state;
    await Future.delayed(playLibraryPollInterval);
  }
}
