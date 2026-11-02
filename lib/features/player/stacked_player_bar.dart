import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../platform/airplay_control.dart';
import '../common/design_system.dart';
import '../common/glass.dart';
import 'cast_button.dart';
import 'player_bar_controls.dart';
import 'player_panel_tabs.dart';
import 'remote_devices.dart';

class StackedPlayerBar extends ConsumerWidget {
  const StackedPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activePlaybackProvider);
    return PlayerBarSurface(
      glass: ref.watch(glassEffectsProvider),
      glassOpacity: ref.watch(glassOpacityProvider),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SpotifinSpacing.md,
          SpotifinSpacing.xs,
          SpotifinSpacing.md,
          SpotifinSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DesktopTransport(active: active),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const CastButton(),
                const RemoteDeviceButton(),
                const PlayerPanelTabs(),
                if (AirPlayControl.isSupported) const AirPlayControl(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
