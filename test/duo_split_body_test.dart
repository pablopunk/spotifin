import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/shell/duo_split_body.dart';

const _browsing = Key('browsing');
const _panel = Key('panel');
const _card = Key('card');
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
  bool panelOpen = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, displayFeatures: features),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DuoSplitBody(
          panelOpen: panelOpen,
          browsingBuilder: (_, _) => const SizedBox.expand(key: _browsing),
          fallbackBuilder: (_) => const SizedBox.expand(key: _fallback),
          panel: const SizedBox.expand(key: _panel),
          card: const SizedBox(key: _card, height: 80),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('landscape: browsing left, panel above the card on the right', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(951, 669),
      features: [_fold(const Rect.fromLTRB(455.5, 0, 495.5, 669))],
    );

    final browsing = tester.getRect(find.byKey(_browsing));
    final panel = tester.getRect(find.byKey(_panel));
    final card = tester.getRect(find.byKey(_card));
    expect(find.byKey(_fallback), findsNothing);
    expect(browsing.right, lessThanOrEqualTo(455.5));
    expect(panel.left, greaterThanOrEqualTo(495.5));
    expect(card.left, greaterThanOrEqualTo(495.5));
    expect(card.top, greaterThanOrEqualTo(panel.bottom));
    expect(card.bottom, greaterThan(600));
  });

  testWidgets('landscape: without a panel the card fills the right page', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(951, 669),
      features: [_fold(const Rect.fromLTRB(455.5, 0, 495.5, 669))],
      panelOpen: false,
    );

    expect(find.byKey(_panel), findsNothing);
    expect(tester.getRect(find.byKey(_card)).height, greaterThan(500));
  });

  testWidgets('portrait: browsing on top, card beside the panel below', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(669, 951),
      features: [_fold(const Rect.fromLTRB(0, 455.5, 669, 495.5))],
    );

    final browsing = tester.getRect(find.byKey(_browsing));
    final panel = tester.getRect(find.byKey(_panel));
    final card = tester.getRect(find.byKey(_card));
    expect(find.byKey(_fallback), findsNothing);
    expect(browsing.bottom, lessThanOrEqualTo(455.5));
    expect(card.top, greaterThanOrEqualTo(495.5));
    expect(panel.top, greaterThanOrEqualTo(495.5));
    expect(card.left, lessThan(panel.left));
  });

  testWidgets('a flat fold does not split the screen', (tester) async {
    await _pump(
      tester,
      size: const Size(669, 951),
      features: [
        const DisplayFeature(
          bounds: Rect.fromLTRB(0, 455.5, 669, 495.5),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ],
    );

    expect(find.byKey(_fallback), findsOneWidget);
    expect(find.byKey(_card), findsNothing);
  });

  testWidgets('without a fold the fallback layout is shown', (tester) async {
    await _pump(tester, size: const Size(669, 951));

    expect(find.byKey(_fallback), findsOneWidget);
    expect(find.byKey(_panel), findsNothing);
    expect(find.byKey(_card), findsNothing);
  });
}
