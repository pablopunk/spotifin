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
  static const _viewportFraction = .86;
  static const _pageAnimationDuration = Duration(milliseconds: 220);

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
        final artworkSize = constraints.maxWidth * _viewportFraction;
        return PageView.builder(
          controller: _pageController,
          itemCount: widget.tracks.length,
          pageSnapping: true,
          padEnds: true,
          onPageChanged: _handlePageChanged,
          itemBuilder: (context, index) {
            final track = widget.tracks[index];
            return Center(
              child: Semantics(
                image: true,
                label: 'Artwork for ${track.name}',
                child: Artwork(
                  key: ValueKey(track.id),
                  itemId: track.albumId ?? track.id,
                  size: artworkSize,
                  borderRadius: SpotifinRadii.card,
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handlePageChanged(int index) {
    if (_syncingToPlayback) return;
    _lastSyncedIndex = index;
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
