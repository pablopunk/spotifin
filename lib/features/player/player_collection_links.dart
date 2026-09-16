import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../storage/database.dart';
import '../../storage/track_artists.dart';
import '../common/artist_links.dart'
    show ArtistLinks, openAlbumCollection, openArtistCollection;

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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_rounded,
              size: (style?.fontSize ?? 14) + 1,
              color: SpotifinColors.text,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: ArtistLinks(
                  artists: track.artistCredits,
                  style: style?.copyWith(color: SpotifinColors.text),
                  onTap: (artist) => openArtistCollection(context, ref, artist),
                ),
              ),
            ),
          ],
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
            onTap: () => openAlbumCollection(context, ref, track),
          ),
        ),
      ],
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
