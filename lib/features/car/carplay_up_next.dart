import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_carplay/flutter_carplay.dart';

import '../../services/playback/active_playback.dart';
import '../../storage/database.dart';

class CarPlayUpNext {
  CarPlayUpNext(this.active, {MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('spotifin/carplay_up_next'),
      _enabled =
          enabled ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final ActivePlayback active;
  final MethodChannel _channel;
  final bool _enabled;
  bool? _lastAvailable;

  void start() {
    if (!_enabled) return;
    _channel.setMethodCallHandler(_handleCall);
    active.addListener(_syncAvailability);
    _syncAvailability();
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'showUpNext') return;
    try {
      final limit = await CPListTemplate.getMaximumItemCount();
      await FlutterCarplay.push(template: buildTemplate(limit: limit));
    } catch (_) {}
  }

  CPListTemplate buildTemplate({int? limit}) {
    final queue = active.state.upcoming;
    final visible = queue.take(limit ?? 50).toList();
    return CPListTemplate(
      title: 'Up Next',
      sections: [
        CPListSection(
          items: [
            for (var index = 0; index < visible.length; index++)
              _item(visible[index], index),
          ],
        ),
      ],
      emptyViewTitleVariants: const ['No songs in queue'],
    );
  }

  CPListItem _item(Track track, int index) => CPListItem(
    text: track.name,
    detailText: track.artist,
    isPlaying: index == 0 && active.state.index != null,
    onPress: (complete, _) async {
      try {
        if (!active.state.capabilities.contains(PlaybackCapability.selection)) {
          return;
        }
        final queue = active.state.upcoming;
        final currentIndex = index < queue.length && queue[index].id == track.id
            ? index
            : queue.indexWhere((item) => item.id == track.id);
        if (currentIndex >= 0) {
          await active.playUpcomingIndex(currentIndex);
          await FlutterCarplay.pop();
        }
      } finally {
        complete();
      }
    },
  );

  void _syncAvailability() {
    final available = active.state.upcoming.isNotEmpty;
    if (_lastAvailable == available) return;
    _lastAvailable = available;
    unawaited(_channel.invokeMethod<void>('setUpNextEnabled', available));
  }

  void dispose() {
    if (!_enabled) return;
    active.removeListener(_syncAvailability);
    _channel.setMethodCallHandler(null);
  }
}
