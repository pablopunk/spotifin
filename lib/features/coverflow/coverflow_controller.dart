import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../storage/database.dart';
import 'coverflow_model.dart';

enum CoverflowSource { tracks, albums, artists }

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
