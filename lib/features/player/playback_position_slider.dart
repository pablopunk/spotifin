import 'package:flutter/material.dart';

import '../../services/playback/active_playback.dart';

class PlaybackPositionSlider extends StatelessWidget {
  const PlaybackPositionSlider({required this.active, super.key});

  final ActivePlayback active;

  @override
  Widget build(BuildContext context) {
    final state = active.state;
    final duration = state.duration ?? Duration.zero;
    final maximum = duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final canSeek =
        duration > Duration.zero &&
        state.capabilities.contains(PlaybackCapability.seek);
    return MergeSemantics(
      child: Semantics(
        label: 'Playback position',
        child: Slider(
          value: state.position.inMilliseconds.toDouble().clamp(0.0, maximum),
          max: maximum,
          semanticFormatterCallback: (value) =>
              '${_formatTime(Duration(milliseconds: value.round()))} of '
              '${_formatTime(duration)}',
          onChanged: canSeek
              ? (value) => active.seek(Duration(milliseconds: value.round()))
              : null,
        ),
      ),
    );
  }
}

String _formatTime(Duration value) =>
    '${value.inMinutes}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
