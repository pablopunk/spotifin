import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';

class PlayerArtworkCarousel extends StatefulWidget {
  const PlayerArtworkCarousel({
    required this.tracks,
    required this.currentIndex,
    required this.onTrackChanged,
    super.key,
  });

  final List<Track> tracks;
  final int? currentIndex;
  final Future<void> Function(int index) onTrackChanged;

  @override
  State<PlayerArtworkCarousel> createState() => _PlayerArtworkCarouselState();
}

class _PlayerArtworkCarouselState extends State<PlayerArtworkCarousel> {
  static const _viewportFraction = .34;
  static const _neighborFade = .35;
  static const _pageAnimationDuration = Duration(milliseconds: 220);
  static const _dragDevices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };

  late final PageController _pageController;
  late int _lastSyncedIndex;
  bool _syncingToPlayback = false;

  @override
  void initState() {
    super.initState();
    _lastSyncedIndex = _validIndex(widget.currentIndex);
    _pageController = PageController(
      initialPage: _lastSyncedIndex,
      viewportFraction: _viewportFraction,
    );
  }

  @override
  void didUpdateWidget(covariant PlayerArtworkCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIndex = _validIndex(widget.currentIndex);
    if (currentIndex == _lastSyncedIndex) return;
    _lastSyncedIndex = currentIndex;
    _animateToPlaybackIndex(currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 576;
        final currentSize = constraints.maxHeight.clamp(
          0.0,
          constraints.maxWidth * (wide ? .55 : .64),
        );
        final neighborSize = constraints.maxWidth * .28;
        final currentTrack = widget.tracks[_lastSyncedIndex];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context)
                    .copyWith(dragDevices: _dragDevices),
                child: PageView.builder(
                  controller: _pageController,
                  clipBehavior: Clip.none,
                  itemCount: widget.tracks.length,
                  pageSnapping: true,
                  padEnds: true,
                  onPageChanged: _handlePageChanged,
                  itemBuilder: (context, index) {
                    final track = widget.tracks[index];
                    return AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, child) {
                        final page = _pageController.hasClients
                            ? _pageController.page
                            : null;
                        final delta = page == null
                            ? (index == _lastSyncedIndex ? 0.0 : 1.0)
                            : (page - index).abs().clamp(0.0, 1.0).toDouble();
                        final size =
                            currentSize - delta * (currentSize - neighborSize);
                        return OverflowBox(
                          minWidth: 0,
                          minHeight: 0,
                          maxWidth: currentSize,
                          maxHeight: currentSize,
                          child: Opacity(
                            opacity: 1.0 - delta * _neighborFade,
                            child: SizedBox.square(
                              dimension: size,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: child,
                              ),
                            ),
                          ),
                        );
                      },
                      child: Semantics(
                        image: true,
                        label: 'Artwork for ${track.name}',
                        child: Artwork(
                          key: ValueKey(track.id),
                          itemId: track.albumId ?? track.id,
                          size: currentSize,
                          borderRadius: SpotifinRadii.card,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            IgnorePointer(
              child: Center(
                child: Semantics(
                  image: true,
                  label: 'Artwork for ${currentTrack.name}',
                  child: Artwork(
                    key: ValueKey('foreground-${currentTrack.id}'),
                    itemId: currentTrack.albumId ?? currentTrack.id,
                    size: currentSize,
                    borderRadius: SpotifinRadii.card,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handlePageChanged(int index) {
    if (_syncingToPlayback) return;
    setState(() => _lastSyncedIndex = index);
    widget.onTrackChanged(index);
  }

  void _animateToPlaybackIndex(int index) {
    if (!_pageController.hasClients) return;
    final visibleIndex = _pageController.page?.round();
    if (visibleIndex == index) return;

    _syncingToPlayback = true;
    _pageController
        .animateToPage(
          index,
          duration: _pageAnimationDuration,
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (mounted) _syncingToPlayback = false;
        });
  }

  int _validIndex(int? index) {
    if (widget.tracks.isEmpty) return 0;
    return (index ?? 0).clamp(0, widget.tracks.length - 1);
  }
}
