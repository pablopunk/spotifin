import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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

class _CoverflowStageState extends State<CoverflowStage> {
  late int _focused;
  late int _lastExternal;
  int? _pendingTarget;

  @override
  void initState() {
    super.initState();
    _focused = _clamp(widget.initialIndex);
    _lastExternal = widget.initialIndex;
  }

  @override
  void didUpdateWidget(covariant CoverflowStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) _focused = _clamp(_focused);
    if (widget.initialIndex != _lastExternal) {
      _lastExternal = widget.initialIndex;
      final target = _clamp(widget.initialIndex);
      if (target != _focused) _pendingTarget = target;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cover = _coverSize(constraints);
        final fraction = _fractionFor(constraints.maxWidth, cover);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: cover * 1.42,
                child: _CoverflowPages(
                  key: ValueKey((fraction * 100).round()),
                  items: widget.items,
                  fraction: fraction,
                  cover: cover,
                  initialIndex: _pendingTarget ?? _focused,
                  onFocus: (index) {
                    _focused = _clamp(index);
                    _pendingTarget = null;
                    widget.onFocus?.call(_focused);
                    setState(() {});
                  },
                  onCenterTap: widget.onCenterTap,
                ),
              ),
              const SizedBox(height: 8),
              _Caption(item: widget.items[_focused]),
            ],
          ),
        );
      },
    );
  }

  int _clamp(int index) {
    if (widget.items.isEmpty) return 0;
    return index.clamp(0, widget.items.length - 1);
  }

  double _coverSize(BoxConstraints constraints) {
    final byWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth * 0.3
        : 220.0;
    final byHeight = constraints.maxHeight.isFinite && constraints.maxHeight > 0
        ? (constraints.maxHeight - 84) / 1.42
        : 220.0;
    return math.min(byWidth, byHeight).clamp(110.0, 300.0).toDouble();
  }

  double _fractionFor(double maxWidth, double cover) {
    if (!maxWidth.isFinite || maxWidth <= 0) return 0.24;
    return ((cover * 0.55) / maxWidth).clamp(0.08, 0.5).toDouble();
  }
}

class _CoverflowPages extends StatefulWidget {
  const _CoverflowPages({
    required this.items,
    required this.fraction,
    required this.cover,
    required this.initialIndex,
    required this.onFocus,
    required this.onCenterTap,
    super.key,
  });

  final List<CoverflowItem> items;
  final double fraction;
  final double cover;
  final int initialIndex;
  final ValueChanged<int> onFocus;
  final ValueChanged<CoverflowItem> onCenterTap;

  @override
  State<_CoverflowPages> createState() => _CoverflowPagesState();
}

class _CoverflowPagesState extends State<_CoverflowPages> {
  static const _maxSideAngle = 1.02;

  late final PageController _pages;
  late int _focused;
  late int _lastExternal;

  @override
  void initState() {
    super.initState();
    _focused = _clamp(widget.initialIndex);
    _lastExternal = _focused;
    _pages = PageController(
      initialPage: _focused,
      viewportFraction: widget.fraction,
    );
  }

  @override
  void didUpdateWidget(covariant _CoverflowPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _focused = _clamp(_focused);
    }
    if (widget.initialIndex != _lastExternal) {
      _lastExternal = widget.initialIndex;
      final target = _clamp(widget.initialIndex);
      if (target != _focused && _pages.hasClients) {
        _pages.animateToPage(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dragDevices = {
      ...ScrollConfiguration.of(context).dragDevices,
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
    };
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(dragDevices: dragDevices),
      child: PageView.builder(
        controller: _pages,
        itemCount: widget.items.length,
        clipBehavior: Clip.none,
        onPageChanged: _handlePageChanged,
        itemBuilder: (context, index) => AnimatedBuilder(
          animation: _pages,
          builder: (context, _) {
            final page = _page();
            final delta = (index - page).clamp(-3.0, 3.0);
            return _CoverflowSlot(
              item: widget.items[index],
              delta: delta.toDouble(),
              cover: widget.cover,
              onTap: () => _handleTap(index),
            );
          },
        ),
      ),
    );
  }

  double _page() {
    if (!_pages.hasClients || _pages.page == null) return _focused.toDouble();
    if (widget.items.isEmpty) return 0;
    return (_pages.page!).clamp(0.0, (widget.items.length - 1).toDouble());
  }

  void _handlePageChanged(int index) {
    _focused = _clamp(index);
    widget.onFocus(_focused);
  }

  void _handleTap(int index) {
    if (index != _focused) {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }
    widget.onCenterTap(widget.items[index]);
  }

  int _clamp(int index) {
    if (widget.items.isEmpty) return 0;
    return index.clamp(0, widget.items.length - 1);
  }
}

class _CoverflowSlot extends StatelessWidget {
  const _CoverflowSlot({
    required this.item,
    required this.delta,
    required this.cover,
    required this.onTap,
  });

  final CoverflowItem item;
  final double delta;
  final double cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final distance = delta.abs().clamp(0.0, 2.5);
    final angle =
        (delta.clamp(-1.0, 1.0)) * -_CoverflowPagesState._maxSideAngle;
    final scale = (1 - 0.15 * distance.clamp(0.0, 1.5)).clamp(0.7, 1.0);
    final outward = delta.sign * math.min(distance, 1.0) * cover * 0.3;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..translateByDouble(outward, 0.0, 0.0, 1.0)
      ..rotateY(angle)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: onTap,
        child: Semantics(
          button: true,
          label: 'Cover for ${item.title}',
          child: Transform(
            alignment: Alignment.center,
            transform: transform,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CoverArt(item: item, size: cover),
                _Reflection(item: item, size: cover),
              ],
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
    decoration: const BoxDecoration(
      color: SpotifinColors.raised,
      borderRadius: BorderRadius.all(Radius.circular(SpotifinRadii.small)),
      boxShadow: [SpotifinShadows.elevated],
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
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size * 0.38,
    child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x66FFFFFF), Colors.transparent],
      ).createShader(rect),
      child: Opacity(
        opacity: 0.5,
        child: Transform(
          alignment: Alignment.topCenter,
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
  );
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
            ?.copyWith(color: SpotifinColors.text),
      ),
      const SizedBox(height: 2),
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
