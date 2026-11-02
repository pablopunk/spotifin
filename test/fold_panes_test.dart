import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/shell/fold_panes.dart';

DisplayFeature _feature(
  Rect bounds, {
  DisplayFeatureType type = DisplayFeatureType.hinge,
  DisplayFeatureState state = DisplayFeatureState.postureHalfOpened,
}) => DisplayFeature(bounds: bounds, type: type, state: state);

FoldPanes _panes(
  List<DisplayFeature> features, {
  Rect area = const Rect.fromLTWH(0, 0, 951, 669),
  TextDirection direction = TextDirection.ltr,
}) =>
    FoldPanes.compute(features: features, area: area, textDirection: direction);

void main() {
  test('a half open vertical fold splits side by side around the fold', () {
    final panes = _panes([_feature(const Rect.fromLTRB(455.5, 0, 495.5, 669))]);

    expect(panes.isSplit, isTrue);
    expect(panes.sideBySide, isTrue);
    expect(panes.first, const Rect.fromLTRB(0, 0, 455.5, 669));
    expect(panes.second, const Rect.fromLTRB(495.5, 0, 951, 669));
  });

  test('a half open horizontal fold stacks the panes', () {
    final panes = _panes([
      _feature(const Rect.fromLTRB(0, 455.5, 669, 495.5)),
    ], area: const Rect.fromLTWH(0, 0, 669, 951));

    expect(panes.sideBySide, isFalse);
    expect(panes.first, const Rect.fromLTRB(0, 0, 669, 455.5));
    expect(panes.second, const Rect.fromLTRB(0, 495.5, 669, 951));
  });

  test('right to left swaps which side comes first', () {
    final panes = _panes([
      _feature(const Rect.fromLTRB(455.5, 0, 495.5, 669)),
    ], direction: TextDirection.rtl);

    expect(panes.first, const Rect.fromLTRB(495.5, 0, 951, 669));
  });

  test('flat folds, cutouts and empty folds do not split', () {
    expect(
      _panes([
        _feature(
          const Rect.fromLTRB(455.5, 0, 495.5, 669),
          state: DisplayFeatureState.postureFlat,
        ),
      ]).isSplit,
      isFalse,
    );
    expect(
      _panes([
        _feature(
          const Rect.fromLTRB(455.5, 0, 495.5, 669),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
      ]).isSplit,
      isFalse,
    );
    expect(_panes([_feature(Rect.zero)]).isSplit, isFalse);
  });

  test('a fold that does not cross the area does not split it', () {
    expect(
      _panes([_feature(const Rect.fromLTRB(455.5, 0, 495.5, 300))]).isSplit,
      isFalse,
    );
  });

  test('an offset area measures the fold in its own coordinates', () {
    final panes = _panes([
      _feature(const Rect.fromLTRB(455.5, 0, 495.5, 669)),
    ], area: const Rect.fromLTWH(0, 0, 951, 669));
    final shifted = _panes([
      _feature(const Rect.fromLTRB(455.5, 100, 495.5, 769)),
    ], area: const Rect.fromLTWH(0, 100, 951, 669));

    expect(shifted.first, panes.first);
    expect(shifted.second, panes.second);
  });

  test('unbounded areas never split', () {
    expect(
      _panes([
        _feature(const Rect.fromLTRB(455.5, 0, 495.5, 669)),
      ], area: const Rect.fromLTWH(0, 0, double.infinity, 669)).isSplit,
      isFalse,
    );
  });
}
