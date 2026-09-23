import 'dart:math' as math;
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
  final _SwipeAnchor _swipeAnchor = _SwipeAnchor();
  late int _lastSyncedIndex;
  int? _dragStartIndex;
  bool _syncingToPlayback = false;
  bool _correctingOvershoot = false;

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
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: PageView.builder(
                    controller: _pageController,
                    physics: _SingleStepPageScrollPhysics(anchor: _swipeAnchor),
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
                              currentSize -
                              delta * (currentSize - neighborSize);
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

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        notification.metrics is PageMetrics) {
      final current = _pageController.hasClients ? _pageController.page : null;
      final page = current ?? _lastSyncedIndex.toDouble();
      _swipeAnchor.startPage = page;
      _dragStartIndex = page.round();
    }
    return false;
  }

  void _handlePageChanged(int index) {
    if (_syncingToPlayback || _correctingOvershoot) return;
    final start = _dragStartIndex ?? _lastSyncedIndex;
    var clamped = (index - start).clamp(-1, 1) + start;
    clamped = _validIndex(clamped);
    if (clamped != index) {
      if (clamped == _lastSyncedIndex) {
        _snapBackTo(clamped);
        return;
      }
      setState(() => _lastSyncedIndex = clamped);
      widget.onTrackChanged(clamped);
      _snapBackTo(clamped);
      return;
    }
    if (index == _lastSyncedIndex) return;
    setState(() => _lastSyncedIndex = index);
    widget.onTrackChanged(index);
  }

  void _snapBackTo(int index) {
    if (!_pageController.hasClients) return;
    if (_pageController.page?.round() == index) return;
    _correctingOvershoot = true;
    _pageController
        .animateToPage(
          index,
          duration: _pageAnimationDuration,
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (mounted) _correctingOvershoot = false;
        });
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

/// Mutable drag anchor shared between [PlayerArtworkCarousel] and its
/// single-step page physics.
///
/// The carousel records the visible page when a user drag starts; the physics
/// then clamps both the drag distance and the settling target to one page
/// around that anchor. Programmatic jumps (queue taps, playback changes) do
/// not go through user offsets or ballistic simulations guarded here, so they
/// can still move multiple tracks at once.
class _SwipeAnchor {
  double? startPage;
}

/// Page physics that limits one swipe gesture to one page.
///
/// The default [PageScrollPhysics] settles relative to the release position,
/// so a long drag that already spans several pages settles several pages
/// away, and a high-velocity fling can chain through multiple pages. This
/// subclass keeps the gesture responsive (neighbors still preview while
/// dragging) but hard-stops the drag at one page from the gesture start and
/// clamps the ballistic target to the same window.
class _SingleStepPageScrollPhysics extends PageScrollPhysics {
  const _SingleStepPageScrollPhysics({required this.anchor, super.parent});

  final _SwipeAnchor anchor;

  @override
  _SingleStepPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SingleStepPageScrollPhysics(
      anchor: anchor,
      parent: buildParent(ancestor),
    );
  }

  double _initialOffset(PageMetrics metrics) {
    return math.max(
      0,
      metrics.viewportDimension * (metrics.viewportFraction - 1) / 2,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    var result = super.applyPhysicsToUserOffset(position, offset);
    final start = anchor.startPage;
    if (start == null || position is! PageMetrics) return result;
    final metrics = position;
    final pageWidth = metrics.viewportDimension * metrics.viewportFraction;
    if (pageWidth <= 0) return result;
    final anchorPixels = start * pageWidth + _initialOffset(metrics);
    final minAllowed = anchorPixels - pageWidth;
    final maxAllowed = anchorPixels + pageWidth;
    final target = position.pixels + result;
    if (target < minAllowed) return minAllowed - position.pixels;
    if (target > maxAllowed) return maxAllowed - position.pixels;
    return result;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final start = anchor.startPage;
    if (start == null || position is! PageMetrics) {
      return super.createBallisticSimulation(position, velocity);
    }
    final metrics = position;
    final tolerance = toleranceFor(position);
    var page = metrics.page ?? position.pixels / position.viewportDimension;
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    var targetPage = page.roundToDouble().clamp(start - 1, start + 1);
    final pageWidth = metrics.viewportDimension * metrics.viewportFraction;
    if (pageWidth > 0) {
      final initial = _initialOffset(metrics);
      final minPage = (position.minScrollExtent - initial) / pageWidth;
      final maxPage = (position.maxScrollExtent - initial) / pageWidth;
      targetPage = targetPage.clamp(minPage, maxPage);
    }
    final targetPixels = targetPage * pageWidth + _initialOffset(metrics);
    if (targetPixels != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        targetPixels,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}
