import 'package:flutter/material.dart';

import '../../app/theme.dart';

abstract final class SpotifinSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class SpotifinBreakpoints {
  static const mobile = 576.0;
  static const rail = 896.0;
  static const extendedRail = 1150.0;
  static const playerPanel = 1400.0;
}

class SpotifinPageTitle extends StatelessWidget {
  const SpotifinPageTitle(this.title, {this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpotifinSpacing.lg,
      SpotifinSpacing.xl,
      SpotifinSpacing.lg,
      SpotifinSpacing.md,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
        ?action,
      ],
    ),
  );
}

class SpotifinEmptyState extends StatelessWidget {
  const SpotifinEmptyState({
    required this.icon,
    required this.title,
    this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(SpotifinSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: SpotifinColors.interactive,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 38, color: SpotifinColors.textMuted),
          ),
          const SizedBox(height: SpotifinSpacing.lg),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (message != null) ...[
            const SizedBox(height: SpotifinSpacing.xs),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: SpotifinColors.textMuted),
            ),
          ],
        ],
      ),
    ),
  );
}

class SpotifinSurface extends StatelessWidget {
  const SpotifinSurface({
    required this.child,
    this.padding = const EdgeInsets.all(SpotifinSpacing.md),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: SpotifinColors.surface,
      borderRadius: BorderRadius.all(Radius.circular(SpotifinRadii.card)),
      boxShadow: [SpotifinShadows.elevated],
    ),
    child: Padding(padding: padding, child: child),
  );
}

class SpotifinSettingsGroup extends StatelessWidget {
  const SpotifinSettingsGroup({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpotifinSpacing.md,
      SpotifinSpacing.sm,
      SpotifinSpacing.md,
      SpotifinSpacing.lg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SpotifinSpacing.xs,
            0,
            SpotifinSpacing.xs,
            SpotifinSpacing.xs,
          ),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: SpotifinColors.textMuted, letterSpacing: 1.4),
          ),
        ),
        SpotifinSurface(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    ),
  );
}

class SpotifinPlayButton extends StatelessWidget {
  const SpotifinPlayButton({
    required this.onPressed,
    this.playing = false,
    this.large = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final bool playing;
  final bool large;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      shape: const CircleBorder(),
      padding: EdgeInsets.all(large ? 18 : 12),
      minimumSize: Size.square(large ? 64 : 48),
    ),
    onPressed: onPressed,
    child: Icon(
      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      size: large ? 34 : 26,
    ),
  );
}

class SpotifinCountLabel extends StatelessWidget {
  const SpotifinCountLabel(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) => Text(
    '$count ${count == 1 ? 'song' : 'songs'}',
    style: Theme.of(context).textTheme.bodySmall,
  );
}

class SpotifinCollectionCard extends StatelessWidget {
  const SpotifinCollectionCard({
    required this.artwork,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final Widget artwork;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(SpotifinRadii.card),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(SpotifinSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: artwork),
            const SizedBox(height: SpotifinSpacing.sm),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

Widget spotifinGrid({
  required int itemCount,
  required Widget Function(BuildContext, int) itemBuilder,
}) => GridView.builder(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 220,
    mainAxisExtent: 238,
    crossAxisSpacing: 16,
    mainAxisSpacing: 16,
  ),
  itemCount: itemCount,
  itemBuilder: itemBuilder,
);
