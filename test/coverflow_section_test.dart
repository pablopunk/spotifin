import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/coverflow/coverflow_controller.dart';
import 'package:spotifin/features/coverflow/coverflow_header_toggle.dart';
import 'package:spotifin/features/coverflow/coverflow_model.dart';
import 'package:spotifin/features/coverflow/coverflow_section.dart';
import 'package:spotifin/features/coverflow/coverflow_stage.dart';
import 'package:spotifin/storage/database.dart';

Track _track(String id, String name) => Track(
  id: id,
  name: name,
  album: 'Album',
  albumId: 'album',
  artist: 'Artist',
  artistItems: '[]',
  labels: '',
  durationTicks: 0,
  container: '',
  favorite: false,
  playCount: 0,
);

Widget _app({
  required ProviderContainer container,
  required List<CoverflowItem> items,
  required ValueChanged<CoverflowItem> onTap,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: Column(
          children: [
            TextButton(
              onPressed: () => container
                  .read(coverflowModeProvider('test-view').notifier)
                  .toggle(),
              child: const Text('toggle'),
            ),
            Expanded(
              child: CoverflowSection(
                viewId: 'test-view',
                items: items,
                list: const Text('list-mode'),
                onCenterTap: onTap,
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

void _enableCoverflow(ProviderContainer container) =>
    container.read(coverflowModeProvider('test-view').notifier).set(true);

void main() {
  testWidgets('toggle switches list and coverflow', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tracks = [_track('1', 'First'), _track('2', 'Second')];
    CoverflowItem? tapped;
    await tester.pumpWidget(
      _app(
        container: container,
        items: trackCoverflowItems(tracks),
        onTap: (item) => tapped = item,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('list-mode'), findsOneWidget);
    expect(find.byType(CoverflowStage), findsNothing);

    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();

    expect(find.text('list-mode'), findsOneWidget);
    expect(find.byType(CoverflowStage), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.byKey(const ValueKey('reflection:track:1')), findsOneWidget);

    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();
    expect(find.text('list-mode'), findsOneWidget);
    expect(tapped, isNull);
  });

  testWidgets('tapping a centered song activates it', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    _enableCoverflow(container);
    final tracks = [_track('1', 'First'), _track('2', 'Second')];
    CoverflowItem? tapped;
    await tester.pumpWidget(
      _app(
        container: container,
        items: trackCoverflowItems(tracks),
        onTap: (item) => tapped = item,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Cover for First'));
    await tester.pumpAndSettle();
    expect(tapped?.title, 'First');
  });

  testWidgets('tapping a centered collection reveals its compact track list', (
    tester,
  ) async {
    final tracks = [_track('1', 'First'), _track('2', 'Second')];
    final item = CoverflowItem(
      id: 'album:one',
      title: 'Album One',
      subtitle: '2 songs',
      artItemId: 'album',
      tracks: tracks,
      collection: true,
    );
    Track? tappedTrack;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CoverflowStage(
              items: [item],
              onCenterTap: (_) => fail('Collection cover must open its tracks'),
              onTrackTap: (_, track) => tappedTrack = track,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('art:album:one')));
    await tester.pumpAndSettle();
    expect(find.textContaining('First'), findsOneWidget);
    expect(find.textContaining('Second'), findsOneWidget);
    expect(find.byKey(const ValueKey('back:album:one')), findsOneWidget);

    await tester.tap(find.textContaining('Second'));
    expect(tappedTrack?.id, '2');

    await tester.tap(find.byKey(const ValueKey('back:album:one')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('art:album:one')), findsOneWidget);
  });

  testWidgets('touch and mouse drags slide between covers', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    _enableCoverflow(container);
    final tracks = [_track('1', 'First'), _track('2', 'Second')];
    await tester.pumpWidget(
      _app(
        container: container,
        items: trackCoverflowItems(tracks),
        onTap: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    Future<void> dragCover(
      String label,
      Offset delta,
      PointerDeviceKind kind,
    ) async {
      final start = tester.getCenter(find.bySemanticsLabel(label));
      final gesture = await tester.startGesture(start, kind: kind);
      const steps = 10;
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(delta / steps.toDouble());
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await dragCover(
      'Cover for First',
      const Offset(-400, 0),
      PointerDeviceKind.touch,
    );
    expect(find.text('Second'), findsOneWidget);

    await dragCover(
      'Cover for Second',
      const Offset(400, 0),
      PointerDeviceKind.mouse,
    );
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('coverflow mode is isolated per view', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(coverflowModeProvider('a')), isFalse);
    container.read(coverflowModeProvider('a').notifier).toggle();
    expect(container.read(coverflowModeProvider('a')), isTrue);
    expect(container.read(coverflowModeProvider('b')), isFalse);
  });

  testWidgets('header toggle flips its view', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(1200, 800)),
            child: Scaffold(body: CoverflowHeaderToggle(viewIds: ['v1'])),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Coverflow'));
    await tester.pump();
    expect(container.read(coverflowModeProvider('v1')), isTrue);
    expect(find.byTooltip('List view'), findsOneWidget);
  });

  testWidgets('header toggle follows the selected tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(1200, 800)),
            child: Scaffold(
              body: DefaultTabController(
                length: 2,
                initialIndex: 1,
                child: CoverflowHeaderToggle(viewIds: ['ta', 'tb']),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Coverflow'));
    await tester.pump();
    expect(container.read(coverflowModeProvider('ta')), isFalse);
    expect(container.read(coverflowModeProvider('tb')), isTrue);
  });

  test('mobile collection registry restores the previous route', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      mobileCoverflowCollectionProvider.notifier,
    );
    final libraryOwner = Object();
    final collectionOwner = Object();
    final library = MobileCoverflowCollection(
      items: trackCoverflowItems([_track('1', 'Library')]),
      contextTracks: [_track('1', 'Library')],
      playback: MobileCoverflowPlayback.tracks,
    );
    final album = MobileCoverflowCollection(
      items: trackCoverflowItems([_track('2', 'Album')]),
      contextTracks: [_track('2', 'Album')],
      playback: MobileCoverflowPlayback.tracks,
    );

    controller.register(libraryOwner, library);
    controller.register(collectionOwner, album);
    expect(container.read(mobileCoverflowCollectionProvider), same(album));

    controller.register(libraryOwner, library);
    expect(container.read(mobileCoverflowCollectionProvider), same(album));

    controller.unregister(collectionOwner);
    expect(container.read(mobileCoverflowCollectionProvider), same(library));
  });
}
