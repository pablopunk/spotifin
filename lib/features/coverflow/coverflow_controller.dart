import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../storage/database.dart';
import 'coverflow_model.dart';

enum CoverflowSource { tracks, albums, artists }

enum MobileCoverflowPlayback { tracks, collection }

class MobileCoverflowCollection {
  const MobileCoverflowCollection({
    required this.items,
    required this.contextTracks,
    required this.playback,
    this.initialIndex = 0,
    this.viewId,
  });

  final List<CoverflowItem> items;
  final List<Track> contextTracks;
  final MobileCoverflowPlayback playback;
  final int initialIndex;
  final String? viewId;

  MobileCoverflowCollection forView(String id) => MobileCoverflowCollection(
    items: items,
    contextTracks: contextTracks,
    playback: playback,
    initialIndex: initialIndex,
    viewId: id,
  );
}

final mobileCoverflowCollectionProvider = Provider((ref) {
  return MobileCoverflowCollectionRegistry();
});

final mobileCoverflowDismissedProvider =
    NotifierProvider<MobileCoverflowDismissedController, bool>(
      MobileCoverflowDismissedController.new,
    );

class MobileCoverflowDismissedController extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() {
    if (!state) state = true;
  }

  void reopen() {
    if (state) state = false;
  }
}

class MobileCoverflowCollectionRegistry {
  final _collections = <Object, MobileCoverflowCollection>{};

  MobileCoverflowCollection? get active =>
      _collections.isEmpty ? null : _collections.values.last;

  void register(Object owner, MobileCoverflowCollection collection) =>
      _collections[owner] = collection;

  void unregister(Object owner) => _collections.remove(owner);
}

final coverflowModeProvider =
    NotifierProvider.family<CoverflowModeController, bool, String>(
      CoverflowModeController.new,
    );

final coverflowPositionProvider =
    NotifierProvider.family<CoverflowPositionController, int, String>(
      CoverflowPositionController.new,
    );

class CoverflowPositionController extends Notifier<int> {
  CoverflowPositionController(this.viewId);

  final String viewId;

  @override
  int build() => 0;

  void set(int index) {
    if (state != index) state = index;
  }
}

class CoverflowModeController extends Notifier<bool> {
  CoverflowModeController(this.viewId);

  final String viewId;

  @override
  bool build() => false;

  void toggle() => state = !state;

  void set(bool value) => state = value;
}

String libraryCoverflowViewId(CoverflowSource source) =>
    'library:${source.name}';

String collectionCoverflowViewId(String kind, String title, String? stableId) =>
    'collection:$kind:${stableId ?? title}';

List<CoverflowItem> coverflowItemsFor(
  CoverflowSource source,
  List<Track> tracks,
) => switch (source) {
  CoverflowSource.tracks => trackCoverflowItems(tracks),
  CoverflowSource.albums => albumCoverflowItems(tracks),
  CoverflowSource.artists => artistCoverflowItems(tracks),
};
