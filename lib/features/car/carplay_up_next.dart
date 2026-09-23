import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_carplay/flutter_carplay.dart';

import '../../services/playback/playback_service.dart';
import '../../storage/database.dart';

class CarPlayUpNext {
  CarPlayUpNext(this.playback, {MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('spotifin/carplay_up_next'),
      _enabled =
          enabled ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final PlaybackService playback;
  final MethodChannel _channel;
  final bool _enabled;
  bool? _lastAvailable;

  void start() {
    if (!_enabled) return;
    _channel.setMethodCallHandler(_handleCall);
    playback.addListener(_syncAvailability);
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
    final queue = playback.upcomingQueue;
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
    isPlaying: index == 0 && playback.currentIndex != null,
    onPress: (complete, _) async {
      try {
        final queue = playback.upcomingQueue;
        final currentIndex = index < queue.length && queue[index].id == track.id
            ? index
            : queue.indexWhere((item) => item.id == track.id);
        if (currentIndex >= 0) {
          await playback.playUpcomingIndex(currentIndex);
          await FlutterCarplay.pop();
        }
      } finally {
        complete();
      }
    },
  );

  void _syncAvailability() {
    final available = playback.upcomingQueue.isNotEmpty;
    if (_lastAvailable == available) return;
    _lastAvailable = available;
    unawaited(_channel.invokeMethod<void>('setUpNextEnabled', available));
  }

  void dispose() {
    if (!_enabled) return;
    playback.removeListener(_syncAvailability);
    _channel.setMethodCallHandler(null);
  }
}
