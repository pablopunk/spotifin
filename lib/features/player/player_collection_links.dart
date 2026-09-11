import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
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
        child: _CollectionLink(
          icon: Icons.person_rounded,
          label: track.artist,
          color: SpotifinColors.text,
          style: style?.copyWith(color: SpotifinColors.text),
          onTap: () => _openArtist(context, ref),
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

  Future<void> _openArtist(BuildContext context, WidgetRef ref) async {
    final tracks = await ref.read(databaseProvider).allTracks();
    if (!context.mounted) return;
    _openCollection(
      context,
      title: track.artist,
      tracks: tracks.where((item) => item.artist == track.artist).toList(),
      icon: Icons.person_rounded,
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
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          CollectionScreen(title: title, tracks: tracks, icon: icon),
    ),
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
