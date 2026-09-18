import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../common/artwork.dart';
import 'coverflow_model.dart';

class CoverflowStage extends StatefulWidget {
  const CoverflowStage({
    required this.items,
    required this.onCenterTap,
    this.initialIndex = 0,
    this.onFocus,
    super.key,
  });

  final List<CoverflowItem> items;
  final ValueChanged<CoverflowItem> onCenterTap;
  final int initialIndex;
  final ValueChanged<int>? onFocus;

  @override
  State<CoverflowStage> createState() => _CoverflowStageState();
}

class _CoverflowStageState extends State<CoverflowStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late double _position;
  late int _focused;

  @override
  void initState() {
    super.initState();
    _focused = _safeIndex(widget.initialIndex);
    _position = _focused.toDouble();
    _animation = AnimationController(vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant CoverflowStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.isEmpty) return;
    if (oldWidget.items != widget.items) {
      _focused = _safeIndex(_focused);
      _position = _position.clamp(0, widget.items.length - 1).toDouble();
    }
    final requested = _safeIndex(widget.initialIndex);
    if (requested != _focused) _animateTo(requested);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverSize = _coverSize(constraints);
        final stageHeight = coverSize * 1.24;
        final visible = _visibleIndices();
        return MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _animation.stop(),
            onHorizontalDragUpdate: (details) =>
                _drag(details.delta.dx, coverSize),
            onHorizontalDragEnd: (details) =>
                _settle(details.primaryVelocity ?? 0),
            child: Center(
              child: SizedBox(
                width: math.min(constraints.maxWidth, coverSize * 3.5),
                height: stageHeight + 68,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: stageHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final index in visible)
                            Positioned.fill(
                              child: _Cover(
                                item: widget.items[index],
                                coverSize: coverSize,
                                delta: index - _displayPosition,
                                onTap: () => _tap(index),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Caption(item: widget.items[_focused]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double get _displayPosition {
    if (!_animation.isAnimating) return _position;
    final curve = CurvedAnimation(
      parent: _animation,
      curve: Curves.easeOutCubic,
    );
    return _animationStart + (_animationTarget - _animationStart) * curve.value;
  }

  double _animationStart = 0;
  double _animationTarget = 0;

  List<int> _visibleIndices() {
    final center = _displayPosition.round();
    final indices = <int>[
      for (
        var index = math.max(0, center - 4);
        index <= math.min(widget.items.length - 1, center + 4);
        index++
      )
        index,
    ];
    indices.sort((a, b) {
      final distance = (b - _displayPosition).abs().compareTo(
        (a - _displayPosition).abs(),
      );
      if (distance != 0) return distance;
      return a.compareTo(b);
    });
    return indices;
  }

  void _drag(double delta, double coverSize) {
    _position = (_position - delta / (coverSize * 0.72))
        .clamp(0, widget.items.length - 1)
        .toDouble();
    setState(() {});
  }

  void _settle(double velocity) {
    var target = _position.round();
    if (velocity.abs() > 500) {
      target = velocity < 0 ? _position.ceil() : _position.floor();
    }
    _animateTo(target);
  }

  void _tap(int index) {
    if (index == _focused && (_position - index).abs() < 0.01) {
      widget.onCenterTap(widget.items[index]);
      return;
    }
    _animateTo(index);
  }

  void _animateTo(int index) {
    final target = _safeIndex(index);
    _animationStart = _displayPosition;
    _animationTarget = target.toDouble();
    _animation
      ..duration = const Duration(milliseconds: 280)
      ..forward(from: 0).whenComplete(() {
        if (!mounted) return;
        _position = target.toDouble();
        if (_focused != target) {
          _focused = target;
          widget.onFocus?.call(target);
        }
        setState(() {});
      });
  }

  int _safeIndex(int index) {
    if (widget.items.isEmpty) return 0;
    return index.clamp(0, widget.items.length - 1);
  }

  double _coverSize(BoxConstraints constraints) {
    final byWidth = constraints.maxWidth * 0.3;
    final byHeight = (constraints.maxHeight - 90) / 1.24;
    return math.min(byWidth, byHeight).clamp(120.0, 360.0).toDouble();
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.item,
    required this.coverSize,
    required this.delta,
    required this.onTap,
  });

  final CoverflowItem item;
  final double coverSize;
  final double delta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final distance = delta.abs();
    final side = delta.sign;
    final nearCenter = distance.clamp(0.0, 1.0);
    final sideStep = math.max(0.0, distance - 1) * coverSize * 0.15;
    final horizontal = side * (nearCenter * coverSize * 0.5 + sideStep);
    final angle = side * 0.79 * nearCenter;
    final scale = 1 - 0.33 * nearCenter - 0.015 * math.min(distance - 1, 3);
    final opacity = (1 - math.max(0, distance - 3) * 0.28).clamp(0.2, 1.0);
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0018)
      ..translateByDouble(horizontal, 0, -distance * 20, 1)
      ..rotateY(angle)
      ..scaleByDouble(scale, scale, 1, 1);
    return Align(
      alignment: Alignment.topCenter,
      child: Opacity(
        opacity: opacity,
        child: Transform(
          alignment: Alignment.center,
          transform: transform,
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onTap: onTap,
            child: Semantics(
              button: true,
              label: 'Cover for ${item.title}',
              child: RepaintBoundary(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CoverArt(item: item, size: coverSize),
                    _Reflection(item: item, size: coverSize),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.item, required this.size});

  final CoverflowItem item;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: SpotifinColors.raised,
      borderRadius: BorderRadius.circular(SpotifinRadii.small),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, 14)),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Artwork(
      key: ValueKey('cover:${item.id}'),
      itemId: item.artItemId,
      size: size,
      borderRadius: 0,
    ),
  );
}

class _Reflection extends StatelessWidget {
  const _Reflection({required this.item, required this.size});

  final CoverflowItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reflectionHeight = size * 0.24;
    return SizedBox(
      key: ValueKey('reflection:${item.id}'),
      width: size,
      height: reflectionHeight,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x8AFFFFFF), Colors.transparent],
          stops: [0, 0.92],
        ).createShader(rect),
        child: Opacity(
          opacity: 0.42,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minWidth: size,
              maxWidth: size,
              minHeight: size,
              maxHeight: size,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(1, -1, 1),
                child: Artwork(
                  key: ValueKey('mirror:${item.id}'),
                  itemId: item.artItemId,
                  size: size,
                  borderRadius: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.item});

  final CoverflowItem item;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: SpotifinColors.text, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 3),
      Text(
        item.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: SpotifinColors.textMuted),
      ),
    ],
  );
}
