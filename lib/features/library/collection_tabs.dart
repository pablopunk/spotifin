import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';
import '../common/track_tile.dart';
import '../coverflow/coverflow_controller.dart';
import '../coverflow/coverflow_model.dart';
import '../coverflow/coverflow_section.dart';
import '../coverflow/mobile_coverflow_scope.dart';

typedef CollectionTab = ({String label, Widget child});

class CollectionTabs extends StatelessWidget {
  const CollectionTabs({
    required this.title,
    required this.header,
    required this.tabs,
    super.key,
  });

  final String title;
  final Widget header;
  final List<CollectionTab> tabs;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent),
    body: DefaultTabController(
      length: tabs.length,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(child: header),
          SliverPersistentHeader(
            pinned: true,
            delegate: PinnedTabBar(
              SpotifinTabBar(labels: [for (final tab in tabs) tab.label]),
            ),
          ),
        ],
        body: TabBarView(children: [for (final tab in tabs) tab.child]),
      ),
    ),
  );
}

class CollectionSongsTab extends ConsumerWidget {
  const CollectionSongsTab({
    required this.viewId,
    required this.tracks,
    super.key,
  });

  final String viewId;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = trackCoverflowItems(tracks);
    return MobileCoverflowScope(
      viewId: viewId,
      tabIndex: 0,
      collection: MobileCoverflowCollection(
        items: items,
        contextTracks: tracks,
        playback: MobileCoverflowPlayback.tracks,
      ),
      child: CoverflowSection(
        viewId: viewId,
        items: items,
        onCenterTap: (item) => ref
            .read(activePlaybackProvider)
            .playTrack(item.tracks.single, tracks),
        list: Column(
          children: [
            Expanded(
              child: ListView.builder(
                key: PageStorageKey(viewId),
                padding: EdgeInsets.only(
                  bottom: SpotifinChromeInsets.bottomOf(context),
                ),
                itemCount: tracks.length,
                itemBuilder: (context, index) =>
                    TrackTile(track: tracks[index], contextTracks: tracks),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PinnedTabBar extends SliverPersistentHeaderDelegate {
  const PinnedTabBar(this.tabBar);

  final SpotifinTabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(color: SpotifinColors.background, child: tabBar);

  @override
  bool shouldRebuild(PinnedTabBar oldDelegate) =>
      !_sameLabels(oldDelegate.tabBar.labels, tabBar.labels);

  static bool _sameLabels(List<String> a, List<String> b) =>
      a.length == b.length &&
      a.indexed.every((entry) => b[entry.$1] == entry.$2);
}
