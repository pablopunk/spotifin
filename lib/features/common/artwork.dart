import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';

class Artwork extends ConsumerStatefulWidget {
  const Artwork({
    required this.itemId,
    this.size = 56,
    this.borderRadius = SpotifinRadii.small,
    super.key,
  });

  final String itemId;
  final double size;
  final double borderRadius;

  @override
  ConsumerState<Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends ConsumerState<Artwork> {
  Future<ImageProvider?>? _resolved;
  String? _cacheKey;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(
      appControllerProvider.select((state) => state.session),
    );
    final size = widget.size;
    final fallback = Container(
      width: size,
      height: size,
      color: SpotifinColors.raised,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: size * .42,
        color: SpotifinColors.textMuted,
      ),
    );
    if (session == null) return fallback;
    final requestedWidth = (size * MediaQuery.devicePixelRatioOf(context))
        .round();
    final physicalWidth = switch (requestedWidth) {
      <= 128 => 128,
      <= 512 => 512,
      _ => 1024,
    };
    final accountId = '${session.serverId}.${session.userId}';
    final cacheKey = '$accountId:${widget.itemId}:$physicalWidth';
    if (_cacheKey != cacheKey) {
      _cacheKey = cacheKey;
      _resolved = ref
          .read(artworkStoreProvider)
          .resolve(
            accountId,
            widget.itemId,
            physicalWidth,
            ref
                .read(jellyfinClientProvider)
                .imageUri(session, widget.itemId, width: physicalWidth),
          );
    }
    final image = FutureBuilder<ImageProvider?>(
      future: _resolved,
      builder: (context, snapshot) => snapshot.data == null
          ? fallback
          : Image(
              image: snapshot.data!,
              width: size,
              height: size,
              filterQuality: FilterQuality.low,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
    if (size <= 56 || widget.borderRadius == 0) return image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      clipBehavior: Clip.hardEdge,
      child: image,
    );
  }
}
