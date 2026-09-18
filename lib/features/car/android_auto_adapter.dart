import 'package:flutter_carplay/flutter_carplay.dart';

import '../../storage/database.dart';
import 'car_content.dart';
import 'car_controller.dart';

typedef AndroidAutoHandler = Future<void> Function(
  Track track,
  List<Track> context,
);

class AndroidAutoAdapter {
  AndroidAutoAdapter({required this.play});

  final AndroidAutoHandler play;

  AATemplate buildRoot(CarState state) {
    if (!state.signedIn) {
      return AAMessageTemplate(
        title: 'Not signed in',
        message: 'Sign in on your phone to use Spotifin in the car.',
      );
    }
    if (state.tracks.isEmpty) {
      return AAMessageTemplate(
        title: 'No music yet',
        message: 'Sync your library on your phone first.',
      );
    }
    final byId = {for (final track in state.tracks) track.id: track};
    return AATabBarTemplate(
      tabs: [
        recentsTab(state.tracks),
        favoritesTab(state.tracks),
        playlistsTab(state.playlists, byId),
        artistsTab(state.tracks),
        songsTab(state.tracks),
      ],
    );
  }

  Future<void> showRoot(CarState state) async {
    try {
      await FlutterAndroidAuto.setRootTemplate(template: buildRoot(state));
    } catch (_) {}
  }

  AAListTemplate recentsTab(List<Track> tracks) {
    final recent = buildRecents(tracks);
    final scope = _scopeFor(recent, tracks);
    return AAListTemplate(
      title: 'Recents',
      tabTitle: 'Recents',
      systemIcon: 'clock',
      sections: [AAListSection(items: _trackItems(recent, scope))],
      emptyViewTitleVariants: const ['No recent music'],
    );
  }

  AAListTemplate favoritesTab(List<Track> tracks) {
    final favorites = buildFavorites(tracks);
    final scope = _scopeFor(favorites, tracks);
    return AAListTemplate(
      title: 'Favorites',
      tabTitle: 'Favorites',
      systemIcon: 'heart',
      sections: [AAListSection(items: _trackItems(favorites, scope))],
      emptyViewTitleVariants: const ['No favorites yet'],
    );
  }

  AAListTemplate playlistsTab(
    List<Playlist> playlists,
    Map<String, Track> byId,
  ) => AAListTemplate(
    title: 'Playlists',
    tabTitle: 'Playlists',
    systemIcon: 'music.note.list',
    sections: [
      AAListSection(
        items: [
          for (final playlist in playlists.take(50))
            AAListItem(
              title: playlist.name,
              subtitle: _countLabel(playlistChildren(playlist, byId).length),
              isBrowsable: true,
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

  AAListTemplate artistsTab(List<Track> tracks) => AAListTemplate(
    title: 'Artists',
    tabTitle: 'Artists',
    systemIcon: 'music.mic',
    sections: [
      AAListSection(
        items: [
          for (final group in groupArtists(tracks, limit: 50))
            AAListItem(
              title: group.title,
              subtitle: _countLabel(group.trackCount),
              isBrowsable: true,
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

  AAListTemplate songsTab(List<Track> tracks) {
    final scope = tracks.take(50).toList();
    return AAListTemplate(
      title: 'Songs',
      tabTitle: 'Songs',
      systemIcon: 'music.note',
      sections: [AAListSection(items: _trackItems(_refs(scope), scope))],
      emptyViewTitleVariants: const ['No music available'],
    );
  }

  AAListTemplate searchResults(String query, List<Track> scope) {
    final refs = searchCatalog(scope, query);
    return AAListTemplate(
      title: 'Results',
      sections: [AAListSection(items: _trackItems(refs, scope))],
      emptyViewTitleVariants: const ['No matches'],
    );
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

  List<AAListItem> _trackItems(List<CarTrackRef> refs, List<Track> scope) => [
    for (final ref in refs)
      AAListItem(
        title: ref.title,
        subtitle: ref.subtitle.isEmpty ? null : ref.subtitle,
        onPress: (complete, _) async {
          final track = scope.firstWhere(
            (t) => t.id == ref.id,
            orElse: () => scope.first,
          );
          await _play(track, scope);
          complete();
        },
      ),
  ];

  Future<void> _pushTrackList(String title, List<Track> scope) async {
    try {
      await FlutterAndroidAuto.push(
        template: AAListTemplate(
          title: title,
          sections: [AAListSection(items: _trackItems(_refs(scope), scope))],
          emptyViewTitleVariants: const ['No music available'],
        ),
      );
    } catch (_) {}
  }

  Future<void> _play(Track track, List<Track> scope) async {
    try {
      await play(track, scope);
    } catch (_) {}
  }

  String _countLabel(int count) => count == 1 ? '1 song' : '$count songs';
}
