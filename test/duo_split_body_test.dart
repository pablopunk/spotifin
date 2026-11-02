import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/shell/duo_split_body.dart';

const _browsing = Key('browsing');
const _panel = Key('panel');
const _bar = Key('bar');
const _fallback = Key('fallback');

DisplayFeature _fold(Rect bounds) => DisplayFeature(
  bounds: bounds,
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  List<DisplayFeature> features = const [],
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, displayFeatures: features),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DuoSplitBody(
          browsingBuilder: (_, _) => const SizedBox.expand(key: _browsing),
          fallbackBuilder: (_) => const SizedBox.expand(key: _fallback),
          panel: const SizedBox.expand(key: _panel),
          topPanel: const SizedBox.expand(key: _panel),
          bar: const SizedBox(key: _bar, height: 80),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('landscape fold puts browsing left and panel with bar right', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(951, 669),
      features: [_fold(const Rect.fromLTRB(455.5, 0, 495.5, 669))],
    );

    final browsing = tester.getRect(find.byKey(_browsing));
    final panel = tester.getRect(find.byKey(_panel));
    final bar = tester.getRect(find.byKey(_bar));
    expect(find.byKey(_fallback), findsNothing);
    expect(browsing.right, lessThanOrEqualTo(455.5));
    expect(panel.left, greaterThanOrEqualTo(495.5));
    expect(bar.left, greaterThanOrEqualTo(495.5));
    expect(bar.top, greaterThan(panel.bottom - 1));
  });

  testWidgets(
    'portrait fold puts the panel above and bar then browsing below',
    (tester) async {
      await _pump(
        tester,
        size: const Size(669, 951),
        features: [_fold(const Rect.fromLTRB(0, 455.5, 669, 495.5))],
      );

      final panel = tester.getRect(find.byKey(_panel));
      final bar = tester.getRect(find.byKey(_bar));
      final browsing = tester.getRect(find.byKey(_browsing));
      expect(find.byKey(_fallback), findsNothing);
      expect(panel.bottom, lessThanOrEqualTo(455.5));
      expect(bar.top, greaterThanOrEqualTo(495.5));
      expect(browsing.top, greaterThanOrEqualTo(bar.bottom));
    },
  );

  testWidgets('without a fold the fallback layout is shown', (tester) async {
    await _pump(tester, size: const Size(669, 951));

    expect(find.byKey(_fallback), findsOneWidget);
    expect(find.byKey(_panel), findsNothing);
    expect(find.byKey(_bar), findsNothing);
  });
}
