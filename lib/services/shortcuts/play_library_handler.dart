import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/state/app_controller.dart';

const playLibraryLink = 'spotifin://play-library';
const playLibraryShuffleLink = 'spotifin://play-library-shuffle';
const playLibraryInOrderLink = 'spotifin://play-library-in-order';
const deepLinkChannelName = 'spotifin/deep-link';
const playLibraryTimeout = Duration(seconds: 15);
const playLibraryPollInterval = Duration(milliseconds: 200);
const playLibraryDedupeWindow = Duration(seconds: 3);

enum PlayLibraryMode { shuffle, inOrder }

PlayLibraryMode? _modeForLink(String? link) {
  if (link == playLibraryLink || link == playLibraryShuffleLink) {
    return PlayLibraryMode.shuffle;
  }
  if (link == playLibraryInOrderLink) return PlayLibraryMode.inOrder;
  return null;
}

bool isPlayLibraryLink(String? link) => _modeForLink(link) != null;

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
  final mode = _modeForLink(link);
  if (mode == null || !_dedupe.shouldHandle(link, DateTime.now())) return;
  try {
    await _playLibrary(ref, mode).timeout(playLibraryTimeout);
  } catch (_) {}
}

Future<void> _playLibrary(WidgetRef ref, PlayLibraryMode mode) async {
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
  await ref
      .read(activePlaybackProvider)
      .replaceQueue(
        tracks,
        startIndex: mode == PlayLibraryMode.inOrder ? 0 : null,
        shuffle: mode == PlayLibraryMode.shuffle,
      );
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
