import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

bool isHalfOpenFold(DisplayFeature feature) =>
    (feature.type == DisplayFeatureType.hinge ||
        feature.type == DisplayFeatureType.fold) &&
    feature.state == DisplayFeatureState.postureHalfOpened &&
    !feature.bounds.isEmpty;

bool hasHalfOpenFold(BuildContext context) =>
    MediaQuery.displayFeaturesOf(context).any(isHalfOpenFold);

@immutable
class FoldPanes {
  const FoldPanes.single() : sideBySide = false, first = null, second = null;

  const FoldPanes._split({
    required this.sideBySide,
    required Rect this.first,
    required Rect this.second,
  });

  final bool sideBySide;
  final Rect? first;
  final Rect? second;

  bool get isSplit => first != null;

  static FoldPanes compute({
    required List<DisplayFeature> features,
    required Rect area,
    required TextDirection textDirection,
  }) {
    if (!area.isFinite) return const FoldPanes.single();
    for (final feature in features.where(isHalfOpenFold)) {
      final fold = feature.bounds;
      final vertical = fold.height > fold.width;
      if (!_crosses(fold, area, vertical: vertical)) continue;
      final local = fold.shift(-area.topLeft);
      if (vertical) {
        final start = Rect.fromLTRB(0, 0, local.left, area.height);
        final end = Rect.fromLTRB(local.right, 0, area.width, area.height);
        final leftToRight = textDirection == TextDirection.ltr;
        return FoldPanes._split(
          sideBySide: true,
          first: leftToRight ? start : end,
          second: leftToRight ? end : start,
        );
      }
      return FoldPanes._split(
        sideBySide: false,
        first: Rect.fromLTRB(0, 0, area.width, local.top),
        second: Rect.fromLTRB(0, local.bottom, area.width, area.height),
      );
    }
    return const FoldPanes.single();
  }

  static bool _crosses(Rect fold, Rect area, {required bool vertical}) =>
      vertical
      ? fold.top <= area.top &&
            fold.bottom >= area.bottom &&
            fold.left > area.left &&
            fold.right < area.right
      : fold.left <= area.left &&
            fold.right >= area.right &&
            fold.top > area.top &&
            fold.bottom < area.bottom;

  Widget place({required Widget first, required Widget second}) {
    final firstPane = this.first;
    final secondPane = this.second;
    return Stack(
      children: [
        if (firstPane == null)
          Positioned.fill(child: first)
        else
          Positioned.fromRect(rect: firstPane, child: first),
        if (secondPane != null)
          Positioned.fromRect(rect: secondPane, child: second),
      ],
    );
  }
}

class FoldPanesBuilder extends StatefulWidget {
  const FoldPanesBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, FoldPanes panes) builder;

  @override
  State<FoldPanesBuilder> createState() => _FoldPanesBuilderState();
}

class _FoldPanesBuilderState extends State<FoldPanesBuilder> {
  static const _originTolerance = 0.5;

  Offset _origin = Offset.zero;
  bool _measureScheduled = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _scheduleMeasure();
      return widget.builder(
        context,
        FoldPanes.compute(
          features: MediaQuery.displayFeaturesOf(context),
          area: _origin & constraints.biggest,
          textDirection: Directionality.of(context),
        ),
      );
    },
  );

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      final origin = box.localToGlobal(Offset.zero);
      if ((origin - _origin).distance > _originTolerance) {
        setState(() => _origin = origin);
      }
    });
  }
}
