import 'package:flutter_carplay/flutter_carplay.dart';

import '../../storage/database.dart';
import 'car_content.dart';
import 'car_controller.dart';
import 'car_media_ids.dart';

typedef CarPlayHandler = Future<void> Function(
  Track track,
  List<Track> context,
);

class CarPlayAdapter {
  CarPlayAdapter({required this.play});

  final CarPlayHandler play;

  CPTemplate buildRoot(CarState state) {
    if (!state.signedIn) return signedOutTemplate();
    if (state.tracks.isEmpty) return emptyTemplate();
    final byId = {for (final track in state.tracks) track.id: track};
    return CPTabBarTemplate(
      templates: [
        recentsTab(state.tracks),
        allSongsTab(state.tracks),
        playlistsTab(state.playlists, byId),
        artistsTab(state.tracks),
      ],
    );
  }

  Future<void> showRoot(CarState state) async {
    try {
      await FlutterCarplay.setRootTemplate(
        rootTemplate: buildRoot(state),
        animated: false,
      );
    } catch (_) {}
  }

  CPListTemplate signedOutTemplate() => CPListTemplate(
    title: 'Spotifin',
    sections: [
      CPListSection(
        items: [
          CPListItem(text: 'Sign in on your phone to use Spotifin in the car'),
        ],
      ),
    ],
    emptyViewTitleVariants: const ['Not signed in'],
  );

  CPListTemplate emptyTemplate() => CPListTemplate(
    title: 'Spotifin',
    sections: [
      CPListSection(
        items: [CPListItem(text: 'No music yet. Sync your library first.')],
      ),
    ],
    emptyViewTitleVariants: const ['No music available'],
  );

  CPListTemplate recentsTab(List<Track> tracks) {
    final recent = buildRecents(tracks);
    final scope = _scopeFor(recent, tracks);
    return CPListTemplate(
      title: 'Recents',
      tabTitle: 'Recents',
      systemIcon: 'clock',
      sections: [CPListSection(items: _trackItems(recent, scope))],
      emptyViewTitleVariants: const ['No recent music'],
    );
  }

  CPListTemplate playlistsTab(
    List<Playlist> playlists,
    Map<String, Track> byId,
  ) => CPListTemplate(
    title: 'Playlists',
    tabTitle: 'Playlists',
    systemIcon: 'music.note.list',
    sections: [
      CPListSection(
        items: [
          for (final playlist in playlists.take(50))
            CPListItem(
              text: playlist.name,
              detailText: _countLabel(playlistChildren(playlist, byId).length),
              accessoryType: CPListItemAccessoryType.disclosureIndicator,
              onPress: (complete, _) async {
                await _pushTrackList(
                  playlist.name,
                  playlistChildren(playlist, byId),
                );
                complete();
              },
            ),
        ],
      ),
    ],
    emptyViewTitleVariants: const ['No playlists yet'],
  );

  CPListTemplate artistsTab(List<Track> tracks) => CPListTemplate(
    title: 'Artists',
    tabTitle: 'Artists',
    systemIcon: 'music.mic',
    sections: [
      CPListSection(
        items: [
          for (final group in groupArtists(tracks, limit: 50))
            CPListItem(
              text: group.title,
              detailText: _countLabel(group.trackCount),
              accessoryType: CPListItemAccessoryType.disclosureIndicator,
              onPress: (complete, _) async {
                await _pushTrackList(
                  group.title,
                  tracksForArtist(tracks, group.title).take(50).toList(),
                );
                complete();
              },
            ),
        ],
      ),
    ],
    emptyViewTitleVariants: const ['No artists yet'],
  );

  CPListTemplate allSongsTab(List<Track> tracks) {
    final scope = tracks.take(50).toList();
    return CPListTemplate(
      title: 'All Songs',
      tabTitle: 'All Songs',
      systemIcon: 'music.note',
      sections: [CPListSection(items: _trackItems(_refs(scope), scope))],
      emptyViewTitleVariants: const ['No music available'],
    );
  }

  CPSearchTemplate searchTemplate(List<Track> scope) {
    final index = <String, Track>{};
    late final CPSearchTemplate template;
    template = CPSearchTemplate(
      onUpdatedSearchText: (query, update) {
        final refs = searchCatalog(scope, query);
        index
          ..clear()
          ..addEntries(
            refs.map((ref) {
              final track = scope.firstWhere((t) => t.id == ref.id);
              return MapEntry(carTrackId(track.id), track);
            }),
          );
        final items = [
          for (final ref in refs)
            CPListItem(
              id: carTrackId(ref.id),
              text: ref.title,
              detailText: ref.subtitle.isEmpty ? null : ref.subtitle,
              onPress: (complete, _) async {
                final track = index[carTrackId(ref.id)];
                if (track != null) await _playAndShow(track, scope);
                complete();
              },
            ),
        ];
        template.updateResults(items);
        update(items);
      },
      onSelectedResult: (item, complete) async {
        final track = index[item.uniqueId];
        if (track != null) await _playAndShow(track, scope);
        complete();
      },
    );
    return template;
  }

  List<Track> _scopeFor(List<CarTrackRef> refs, List<Track> all) {
    final byId = {for (final track in all) track.id: track};
    return [
      for (final ref in refs)
        if (byId[ref.id] != null) byId[ref.id]!,
    ];
  }

  List<CarTrackRef> _refs(List<Track> tracks) =>
      tracks.map(CarTrackRef.fromTrack).toList();

  List<CPListItem> _trackItems(List<CarTrackRef> refs, List<Track> scope) => [
    for (final ref in refs)
      CPListItem(
        id: carTrackId(ref.id),
        text: ref.title,
        detailText: ref.subtitle.isEmpty ? null : ref.subtitle,
        onPress: (complete, _) async {
          final track = scope.firstWhere(
            (t) => t.id == ref.id,
            orElse: () => scope.first,
          );
          await _playAndShow(track, scope);
          complete();
        },
      ),
  ];

  Future<void> _pushTrackList(String title, List<Track> scope) async {
    try {
      await FlutterCarplay.push(
        template: CPListTemplate(
          title: title,
          sections: [CPListSection(items: _trackItems(_refs(scope), scope))],
          emptyViewTitleVariants: const ['No music available'],
        ),
      );
    } catch (_) {}
  }

  Future<void> _playAndShow(Track track, List<Track> scope) async {
    try {
      await play(track, scope);
      await FlutterCarplay.showSharedNowPlaying();
    } catch (_) {}
  }

  String _countLabel(int count) => count == 1 ? '1 song' : '$count songs';
}
