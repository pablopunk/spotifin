import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../storage/database.dart';
import '../../storage/track_artists.dart';
import '../library/library_screen.dart';

Future<void> openArtistCollection(
  BuildContext context,
  WidgetRef ref,
  TrackArtist artist,
) async {
  final tracks = await ref.read(databaseProvider).allTracks();
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CollectionScreen(
        title: artist.name,
        tracks: tracks
            .where((item) => includesArtist(item, artist))
            .toList(growable: false),
        kind: CollectionKind.artist,
      ),
    ),
  );
}

Future<void> openAlbumCollection(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final tracks = await ref.read(databaseProvider).allTracks();
  if (!context.mounted) return;
  final albumTracks = track.albumId == null
      ? tracks.where((item) => item.album == track.album).toList()
      : tracks.where((item) => item.albumId == track.albumId).toList();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CollectionScreen(
        title: track.album,
        tracks: albumTracks,
        kind: CollectionKind.album,
      ),
    ),
  );
}

class ArtistLinks extends StatefulWidget {
  const ArtistLinks({
    required this.artists,
    required this.style,
    required this.onTap,
    super.key,
  });

  final List<TrackArtist> artists;
  final TextStyle? style;
  final ValueChanged<TrackArtist> onTap;

  @override
  State<ArtistLinks> createState() => _ArtistLinksState();
}

class _ArtistLinksState extends State<ArtistLinks> {
  late List<TapGestureRecognizer> _recognizers;

  @override
  void initState() {
    super.initState();
    _recognizers = _createRecognizers();
  }

  @override
  void didUpdateWidget(ArtistLinks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.artists, widget.artists)) {
      _disposeRecognizers();
      _recognizers = _createRecognizers();
      return;
    }
    for (var index = 0; index < _recognizers.length; index++) {
      final artist = widget.artists[index];
      _recognizers[index].onTap = () => widget.onTap(artist);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  List<TapGestureRecognizer> _createRecognizers() => [
    for (final artist in widget.artists)
      TapGestureRecognizer()..onTap = () => widget.onTap(artist),
  ];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        for (var index = 0; index < widget.artists.length; index++) ...[
          if (index > 0) const TextSpan(text: ', '),
          TextSpan(
            text: widget.artists[index].name,
            recognizer: _recognizers[index],
          ),
        ],
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: widget.style,
  );
}

class TrackSubtitle extends ConsumerStatefulWidget {
  const TrackSubtitle({
    required this.track,
    required this.showAlbum,
    this.style,
    super.key,
  });

  final Track track;
  final bool showAlbum;
  final TextStyle? style;

  @override
  ConsumerState<TrackSubtitle> createState() => _TrackSubtitleState();
}

class _TrackSubtitleState extends ConsumerState<TrackSubtitle> {
  late List<TapGestureRecognizer> _artistRecognizers;
  TapGestureRecognizer? _albumRecognizer;

  @override
  void initState() {
    super.initState();
    _artistRecognizers = _createArtistRecognizers();
    _albumRecognizer = _createAlbumRecognizer();
  }

  @override
  void didUpdateWidget(TrackSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.artistCredits != widget.track.artistCredits) {
      _disposeArtistRecognizers();
      _artistRecognizers = _createArtistRecognizers();
    } else {
      _refreshArtistTaps();
    }
    if (oldWidget.track.album != widget.track.album ||
        oldWidget.track.albumId != widget.track.albumId ||
        oldWidget.showAlbum != widget.showAlbum) {
      _albumRecognizer?.dispose();
      _albumRecognizer = _createAlbumRecognizer();
    }
  }

  @override
  void dispose() {
    _disposeArtistRecognizers();
    _albumRecognizer?.dispose();
    super.dispose();
  }

  List<TapGestureRecognizer> _createArtistRecognizers() => [
    for (final artist in widget.track.artistCredits)
      TapGestureRecognizer()
        ..onTap = () => openArtistCollection(context, ref, artist),
  ];

  void _refreshArtistTaps() {
    final artists = widget.track.artistCredits;
    for (var index = 0; index < _artistRecognizers.length; index++) {
      final artist = artists[index];
      _artistRecognizers[index].onTap = () =>
          openArtistCollection(context, ref, artist);
    }
  }

  void _disposeArtistRecognizers() {
    for (final recognizer in _artistRecognizers) {
      recognizer.dispose();
    }
  }

  TapGestureRecognizer? _createAlbumRecognizer() {
    if (!widget.showAlbum || widget.track.album.isEmpty) return null;
    final track = widget.track;
    return TapGestureRecognizer()
      ..onTap = () => openAlbumCollection(context, ref, track);
  }

  @override
  Widget build(BuildContext context) {
    final artists = widget.track.artistCredits;
    if (artists.isEmpty) {
      return Text(
        [
          widget.track.artist,
          if (widget.showAlbum && widget.track.album.isNotEmpty)
            widget.track.album,
        ].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Text.rich(
        TextSpan(
          children: [
            for (var index = 0; index < artists.length; index++) ...[
              if (index > 0) const TextSpan(text: ', '),
              TextSpan(
                text: artists[index].name,
                recognizer: _artistRecognizers[index],
              ),
            ],
            if (_albumRecognizer != null) ...[
              const TextSpan(text: ' • '),
              TextSpan(text: widget.track.album, recognizer: _albumRecognizer),
            ],
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      ),
    );
  }
}
