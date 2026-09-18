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
  });

  final List<CoverflowItem> items;
  final List<Track> contextTracks;
  final MobileCoverflowPlayback playback;
}

final mobileCoverflowCollectionProvider =
    NotifierProvider<
      MobileCoverflowCollectionController,
      MobileCoverflowCollection?
    >(MobileCoverflowCollectionController.new);

class MobileCoverflowCollectionController
    extends Notifier<MobileCoverflowCollection?> {
  final _collections = <Object, MobileCoverflowCollection>{};

  @override
  MobileCoverflowCollection? build() => null;

  void register(Object owner, MobileCoverflowCollection collection) {
    _collections[owner] = collection;
    state = _collections.values.last;
  }

  void unregister(Object owner) {
    if (!ref.mounted) return;
    _collections.remove(owner);
    state = _collections.isEmpty ? null : _collections.values.last;
  }
}

final coverflowModeProvider =
    NotifierProvider.family<CoverflowModeController, bool, String>(
      CoverflowModeController.new,
    );

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
