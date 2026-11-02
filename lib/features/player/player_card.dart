import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../platform/airplay_control.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';
import 'cast_button.dart';
import 'player_bar_controls.dart';
import 'player_collection_links.dart';
import 'player_panel_tabs.dart';
import 'remote_devices.dart';

class PlayerCard extends ConsumerWidget {
  const PlayerCard({super.key});

  static const _controlsHeight = 252.0;
  static const _minimumArtwork = 96.0;
  static const _thumbnailSize = 64.0;
  static const _padding = EdgeInsets.fromLTRB(16, 16, 16, 8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activePlaybackProvider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(SpotifinRadii.card),
      child: Material(
        color: SpotifinColors.surface,
        child: ListenableBuilder(
          listenable: active,
          builder: (context, _) {
            final track = active.state.track;
            if (track == null) return const SizedBox.shrink();
            return LayoutBuilder(
              builder: (context, constraints) {
                final bounded = constraints.hasBoundedHeight;
                final controls = [
                  DesktopTransport(active: active),
                  const _CardToolbar(),
                ];
                if (bounded &&
                    constraints.maxHeight >=
                        _controlsHeight + _minimumArtwork) {
                  return Padding(
                    padding: _padding,
                    child: Column(
                      children: [
                        Expanded(child: _FillArtwork(track: track)),
                        const SizedBox(height: SpotifinSpacing.sm),
                        _Details(track: track),
                        const SizedBox(height: SpotifinSpacing.xs),
                        ...controls,
                      ],
                    ),
                  );
                }
                final column = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Artwork(
                          itemId: track.albumId ?? track.id,
                          size: _thumbnailSize,
                          borderRadius: SpotifinRadii.small,
                        ),
                        const SizedBox(width: SpotifinSpacing.sm),
                        Expanded(child: _Details(track: track)),
                      ],
                    ),
                    const SizedBox(height: SpotifinSpacing.xs),
                    ...controls,
                  ],
                );
                return Padding(
                  padding: _padding,
                  child: bounded
                      ? SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight:
                                  constraints.maxHeight - _padding.vertical,
                            ),
                            child: Center(child: column),
                          ),
                        )
                      : column,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _FillArtwork extends StatelessWidget {
  const _FillArtwork({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.bottomCenter,
      child: Artwork(
        itemId: track.albumId ?? track.id,
        size: constraints.biggest.shortestSide,
        borderRadius: SpotifinRadii.card,
      ),
    ),
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        track.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: SpotifinSpacing.xxs),
      PlayerCollectionLinks(
        track: track,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _CardToolbar extends StatelessWidget {
  const _CardToolbar();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CastButton(),
          const RemoteDeviceButton(),
          if (AirPlayControl.isSupported) const AirPlayControl(),
        ],
      ),
      const PlayerPanelTabs(includePlayer: false),
    ],
  );
}
