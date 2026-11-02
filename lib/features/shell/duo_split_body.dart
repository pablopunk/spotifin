import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../platform/duo_display.dart';
import '../common/design_system.dart';
import '../player/player_side_panel.dart';
import '../player/side_panel_scope.dart';
import '../player/stacked_player_bar.dart';

class DuoSplitBody extends StatelessWidget {
  const DuoSplitBody({
    required this.browsingBuilder,
    required this.fallbackBuilder,
    this.panel = const PlayerSidePanel(),
    this.topPanel = const PlayerSidePanel(sideBySide: true),
    this.bar = const StackedPlayerBar(),
    super.key,
  });

  static const _landscapeBrowsingBottom = SpotifinSpacing.md;
  static const _portraitBrowsingBottom = 100.0;

  final Widget Function(BuildContext context, double bottomInset)
  browsingBuilder;
  final WidgetBuilder fallbackBuilder;
  final Widget panel;
  final Widget topPanel;
  final Widget bar;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: DuoPanesBuilder(
      builder: (context, panes) {
        if (!panes.isSplit) return fallbackBuilder(context);
        return SidePanelScope(
          available: true,
          child: panes.sideBySide
              ? panes.place(
                  first: browsingBuilder(context, _landscapeBrowsingBottom),
                  second: _PanelPage(panel: panel, bar: bar),
                )
              : panes.place(
                  first: _PanelTop(panel: topPanel),
                  second: _BarAndBrowsing(
                    bar: bar,
                    browsing: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: browsingBuilder(context, _portraitBrowsingBottom),
                    ),
                  ),
                ),
        );
      },
    ),
  );
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.panel});

  final Widget panel;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.all(Radius.circular(SpotifinRadii.card)),
    child: panel,
  );
}

class _PanelPage extends StatelessWidget {
  const _PanelPage({required this.panel, required this.bar});

  final Widget panel;
  final Widget bar;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SpotifinSpacing.xxs,
            SpotifinSpacing.xs,
            SpotifinSpacing.xs,
            SpotifinSpacing.xxs,
          ),
          child: _PanelCard(panel: panel),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          SpotifinSpacing.xxs,
          0,
          SpotifinSpacing.xs,
          SpotifinSpacing.xs,
        ),
        child: bar,
      ),
    ],
  );
}

class _PanelTop extends StatelessWidget {
  const _PanelTop({required this.panel});

  final Widget panel;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        SpotifinSpacing.xs,
        SpotifinSpacing.xs,
        SpotifinSpacing.xs,
        SpotifinSpacing.xxs,
      ),
      child: _PanelCard(panel: panel),
    ),
  );
}

class _BarAndBrowsing extends StatelessWidget {
  const _BarAndBrowsing({required this.bar, required this.browsing});

  final Widget bar;
  final Widget browsing;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          SpotifinSpacing.xs,
          SpotifinSpacing.xxs,
          SpotifinSpacing.xs,
          0,
        ),
        child: bar,
      ),
      Expanded(child: browsing),
    ],
  );
}
