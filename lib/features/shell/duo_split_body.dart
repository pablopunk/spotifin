import 'package:flutter/material.dart';

import '../common/design_system.dart';
import '../player/player_card.dart';
import '../player/player_side_panel.dart';
import 'fold_panes.dart';

class DuoSplitBody extends StatelessWidget {
  const DuoSplitBody({
    required this.browsingBuilder,
    required this.fallbackBuilder,
    required this.panelOpen,
    this.portraitBottomClearance = floatingTabBarClearance,
    this.panel = const PlayerSidePanel(pinnedPlayer: true),
    this.card = const PlayerCard(),
    super.key,
  });

  static const _browsingBottom = SpotifinSpacing.md;
  static const floatingTabBarClearance = 100.0;

  final Widget Function(BuildContext context, double bottomInset)
  browsingBuilder;
  final WidgetBuilder fallbackBuilder;
  final bool panelOpen;
  final double portraitBottomClearance;
  final Widget panel;
  final Widget card;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: FoldPanesBuilder(
      builder: (context, panes) {
        if (!panes.isSplit) return fallbackBuilder(context);
        return panes.sideBySide
            ? panes.place(
                first: browsingBuilder(context, _browsingBottom),
                second: _PlayerPage(
                  panelOpen: panelOpen,
                  panel: panel,
                  card: card,
                ),
              )
            : panes.place(
                first: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: browsingBuilder(context, _browsingBottom),
                ),
                second: _PlayerRow(
                  panelOpen: panelOpen,
                  panel: panel,
                  card: card,
                  bottomClearance: portraitBottomClearance,
                ),
              );
      },
    ),
  );
}

class _PlayerPage extends StatelessWidget {
  const _PlayerPage({
    required this.panelOpen,
    required this.panel,
    required this.card,
  });

  final bool panelOpen;
  final Widget panel;
  final Widget card;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpotifinSpacing.xxs,
      SpotifinSpacing.xs,
      SpotifinSpacing.xs,
      SpotifinSpacing.xs,
    ),
    child: panelOpen
        ? Column(
            children: [
              Expanded(child: panel),
              const SizedBox(height: SpotifinSpacing.xs),
              card,
            ],
          )
        : card,
  );
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.panelOpen,
    required this.panel,
    required this.card,
    required this.bottomClearance,
  });

  final bool panelOpen;
  final Widget panel;
  final Widget card;
  final double bottomClearance;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      SpotifinSpacing.xs,
      SpotifinSpacing.xxs,
      SpotifinSpacing.xs,
      bottomClearance,
    ),
    child: panelOpen
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: card),
              const SizedBox(width: SpotifinSpacing.xs),
              Expanded(child: panel),
            ],
          )
        : card,
  );
}
