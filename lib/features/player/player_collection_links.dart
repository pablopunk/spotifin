import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../../storage/track_artists.dart';
import '../library/library_screen.dart';

class PlayerCollectionLinks extends ConsumerWidget {
  const PlayerCollectionLinks({
    required this.track,
    required this.style,
    super.key,
  });

  final Track track;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: _ArtistLink(
          artists: track.artistCredits,
          style: style?.copyWith(color: SpotifinColors.text),
          onTap: (artist) => _openArtist(context, ref, artist),
        ),
      ),
      if (track.album.isNotEmpty) ...[
        const SizedBox(width: 12),
        Flexible(
          child: _CollectionLink(
            icon: Icons.album_rounded,
            label: track.album,
            color: SpotifinColors.textMuted,
            style: style?.copyWith(color: SpotifinColors.textMuted),
            onTap: () => _openAlbum(context, ref),
          ),
        ),
      ],
    ],
  );

  Future<void> _openArtist(
    BuildContext context,
    WidgetRef ref,
    TrackArtist artist,
  ) async {
    final tracks = await ref.read(databaseProvider).allTracks();
    if (!context.mounted) return;
    _openCollection(
      context,
      title: artist.name,
      tracks: tracks
          .where((item) => includesArtist(item, artist))
          .toList(growable: false),
      icon: Icons.person_rounded,
      artist: true,
    );
  }

  Future<void> _openAlbum(BuildContext context, WidgetRef ref) async {
    final tracks = await ref.read(databaseProvider).allTracks();
    if (!context.mounted) return;
    final albumTracks = track.albumId == null
        ? tracks.where((item) => item.album == track.album).toList()
        : tracks.where((item) => item.albumId == track.albumId).toList();
    _openCollection(
      context,
      title: track.album,
      tracks: albumTracks,
      icon: Icons.album_rounded,
    );
  }

  void _openCollection(
    BuildContext context, {
    required String title,
    required List<Track> tracks,
    required IconData icon,
    bool artist = false,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CollectionScreen(
        title: title,
        tracks: tracks,
        icon: icon,
        artist: artist,
      ),
    ),
  );
}

class _ArtistLink extends StatefulWidget {
  const _ArtistLink({
    required this.artists,
    required this.style,
    required this.onTap,
  });

  final List<TrackArtist> artists;
  final TextStyle? style;
  final ValueChanged<TrackArtist> onTap;

  @override
  State<_ArtistLink> createState() => _ArtistLinkState();
}

class _ArtistLinkState extends State<_ArtistLink> {
  late List<TapGestureRecognizer> _recognizers;

  @override
  void initState() {
    super.initState();
    _recognizers = _createRecognizers();
  }

  @override
  void didUpdateWidget(_ArtistLink oldWidget) {
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
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.person_rounded,
        size: (widget.style?.fontSize ?? 14) + 1,
        color: SpotifinColors.text,
      ),
      const SizedBox(width: 4),
      Flexible(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Text.rich(
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
          ),
        ),
      ),
    ],
  );
}

class _CollectionLink extends StatelessWidget {
  const _CollectionLink({
    required this.icon,
    required this.label,
    required this.color,
    required this.style,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: (style?.fontSize ?? 14) + 1, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    ),
  );
}
