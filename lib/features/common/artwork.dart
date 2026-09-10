import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';

class Artwork extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(
      appControllerProvider.select((state) => state.session),
    );
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
    final physicalWidth = (size * MediaQuery.devicePixelRatioOf(context))
        .round();
    final image = Image.network(
      ref
          .read(jellyfinClientProvider)
          .imageUri(session, itemId, width: physicalWidth)
          .toString(),
      width: size,
      height: size,
      cacheWidth: physicalWidth,
      filterQuality: FilterQuality.low,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
    if (size <= 56 || borderRadius == 0) return image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.hardEdge,
      child: image,
    );
  }
}
