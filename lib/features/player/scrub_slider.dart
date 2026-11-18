import 'package:flutter/material.dart';

/// Position slider that seeks once, when the user lets go.
///
/// While dragging, the thumb follows the finger without seeking, so remote
/// players (Chromecast, other Jellyfin sessions) get one seek instead of one
/// per drag frame. After release the thumb stays at the drop point until the
/// player reports a position near it, so it never jumps back while the seek
/// is in flight.
class ScrubSlider extends StatefulWidget {
  const ScrubSlider({
    required this.value,
    required this.max,
    required this.onSeek,
    this.semanticFormatterCallback,
    super.key,
  });

  /// Player position in milliseconds.
  final double value;
  final double max;

  /// Called once with the dropped position in milliseconds; null disables.
  final ValueChanged<double>? onSeek;
  final SemanticFormatterCallback? semanticFormatterCallback;

  @override
  State<ScrubSlider> createState() => _ScrubSliderState();
}

class _ScrubSliderState extends State<ScrubSlider> {
  static const _settledDistanceMs = 1500.0;
  static const _maxSettleWait = Duration(seconds: 3);

  double? _dragging;
  double? _dropped;
  DateTime? _droppedAt;

  @override
  void didUpdateWidget(ScrubSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dropped = _dropped;
    if (dropped == null) return;
    final reached = (widget.value - dropped).abs() <= _settledDistanceMs;
    final waitedTooLong =
        DateTime.now().difference(_droppedAt!) > _maxSettleWait;
    if (reached || waitedTooLong) {
      _dropped = null;
      _droppedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSeek = widget.onSeek;
    final shown = _dragging ?? _dropped ?? widget.value;
    return Slider(
      value: shown.clamp(0.0, widget.max),
      max: widget.max,
      semanticFormatterCallback: widget.semanticFormatterCallback,
      onChangeStart: onSeek == null
          ? null
          : (value) => setState(() => _dragging = value),
      onChanged: onSeek == null
          ? null
          : (value) => setState(() => _dragging = value),
      onChangeEnd: onSeek == null
          ? null
          : (value) {
              setState(() {
                _dragging = null;
                _dropped = value;
                _droppedAt = DateTime.now();
              });
              onSeek(value);
            },
    );
  }
}
