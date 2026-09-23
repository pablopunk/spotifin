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
  Widget list = const Text('list-mode'),
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
                list: list,
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

  testWidgets('coverflow opens near the visible list item', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tracks = [
      for (var index = 0; index < 30; index++) _track('$index', 'Song $index'),
    ];
    await tester.pumpWidget(
      _app(
        container: container,
        items: trackCoverflowItems(tracks),
        onTap: (_) {},
        list: ListView.builder(
          itemExtent: 60,
          itemCount: tracks.length,
          itemBuilder: (context, index) => Text('Row $index'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final visibleIndex = container.read(coverflowPositionProvider('test-view'));
    expect(visibleIndex, greaterThan(0));

    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CoverflowStage>(find.byType(CoverflowStage)).initialIndex,
      visibleIndex,
    );
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
              currentTrackId: '2',
              playing: true,
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
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);

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

  testWidgets('a long drag can traverse multiple covers', (tester) async {
    // Cover Flow intentionally retains multi-item scrolling in a single
    // gesture, unlike the mobile vertical player which is limited to one
    // track per swipe.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: CoverflowStage(
                items: trackCoverflowItems([
                  for (var index = 0; index < 6; index++)
                    _track('$index', 'Song $index'),
                ]),
                initialIndex: 0,
                onCenterTap: (_) {},
                onFocus: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Song 0'), findsOneWidget);

    await tester.drag(find.byType(CoverflowStage), const Offset(-800, 0));
    await tester.pumpAndSettle();

    // A single long Cover Flow gesture moves more than one item.
    expect(find.text('Song 0'), findsNothing);
    expect(
      find.text('Song 5'),
      findsOneWidget,
      reason: 'Cover Flow must keep multi-item navigation in one gesture',
    );
  });

  testWidgets('a new drag continues from an active settle animation', (
    tester,
  ) async {
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

    final stage = find.byType(CoverflowStage);
    final firstDrag = await tester.startGesture(tester.getCenter(stage));
    for (var step = 0; step < 10; step++) {
      await firstDrag.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await firstDrag.up();
    await tester.pump(const Duration(milliseconds: 250));

    final secondDrag = await tester.startGesture(tester.getCenter(stage));
    for (var step = 0; step < 3; step++) {
      await secondDrag.moveBy(const Offset(-10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await secondDrag.up();
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
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
    final controller = container.read(mobileCoverflowCollectionProvider);
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
    expect(controller.active, same(album));

    controller.register(libraryOwner, library);
    expect(controller.active, same(album));

    controller.unregister(collectionOwner);
    expect(controller.active, same(library));
  });
}
