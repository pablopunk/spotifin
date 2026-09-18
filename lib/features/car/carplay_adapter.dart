import 'package:flutter_carplay/flutter_carplay.dart';

import '../../storage/database.dart';
import 'car_content.dart';
import 'car_controller.dart';
import 'car_media_ids.dart';

typedef CarPlayHandler = Future<void> Function(
  Track track,
  List<Track> context,
);
typedef CarArtworkUrl = String? Function(String itemId);

class CarPlayAdapter {
  CarPlayAdapter({required this.play, this.artworkUrl});

  final CarPlayHandler play;
  final CarArtworkUrl? artworkUrl;

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
              image: _playlistArtwork(playlist, byId),
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
              image: _artistArtwork(group.title, tracks),
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
    final scope = buildRecentlyAdded(tracks);
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
              image: _trackArtwork(index[carTrackId(ref.id)]!),
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

  List<CPListItem> _trackItems(List<CarTrackRef> refs, List<Track> scope) {
    final byId = {for (final track in scope) track.id: track};
    return [
      for (final ref in refs)
        CPListItem(
          id: carTrackId(ref.id),
          text: ref.title,
          detailText: ref.subtitle.isEmpty ? null : ref.subtitle,
          image: byId[ref.id] == null ? null : _trackArtwork(byId[ref.id]!),
          onPress: (complete, _) async {
            final track = byId[ref.id];
            if (track != null) await _playAndShow(track, scope);
            complete();
          },
        ),
    ];
  }

  String? _trackArtwork(Track track) =>
      artworkUrl?.call(track.albumId ?? track.id);

  String? _playlistArtwork(Playlist playlist, Map<String, Track> byId) {
    if (playlist.imageTag != null) return artworkUrl?.call(playlist.id);
    final children = playlistChildren(playlist, byId, limit: 1);
    return children.isEmpty ? null : _trackArtwork(children.first);
  }

  String? _artistArtwork(String artist, List<Track> tracks) {
    final matches = tracksForArtist(tracks, artist);
    return matches.isEmpty ? null : _trackArtwork(matches.first);
  }

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
