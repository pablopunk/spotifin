import 'dart:async';

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

const _retryDelays = [
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 15),
];

class _ArtworkState extends ConsumerState<Artwork> {
  ImageProvider? _image;
  String? _cacheKey;
  Timer? _retryTimer;
  int _retryCount = 0;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _resolve(String cacheKey, String accountId, int width, Uri source) {
    ref
        .read(artworkStoreProvider)
        .resolve(accountId, widget.itemId, width, source)
        .then((image) {
          if (!mounted || _cacheKey != cacheKey) return;
          if (image != null) {
            setState(() => _image = image);
            return;
          }
          _scheduleRetry(cacheKey, accountId, width, source);
        });
  }

  void _scheduleRetry(
    String cacheKey,
    String accountId,
    int width,
    Uri source,
  ) {
    if (_retryCount >= _retryDelays.length) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelays[_retryCount++], () {
      if (mounted && _cacheKey == cacheKey) {
        _resolve(cacheKey, accountId, width, source);
      }
    });
  }

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
      _retryCount = 0;
      _retryTimer?.cancel();
      _resolve(
        cacheKey,
        accountId,
        physicalWidth,
        ref
            .read(jellyfinClientProvider)
            .imageUri(session, widget.itemId, width: physicalWidth),
      );
    }
    final current = _image;
    final image = current == null
        ? fallback
        : Image(
            image: current,
            width: size,
            height: size,
            filterQuality: FilterQuality.low,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
    if (size <= 56 || widget.borderRadius == 0) return image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      clipBehavior: Clip.hardEdge,
      child: image,
    );
  }
}
