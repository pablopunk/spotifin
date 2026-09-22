import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../common/design_system.dart';
import 'coverflow_controller.dart';

class CoverflowHeaderToggle extends ConsumerWidget {
  const CoverflowHeaderToggle({required this.viewIds, super.key});

  final List<String> viewIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (viewIds.length == 1) {
      return CoverflowToggleButton(viewId: viewIds.single);
    }
    final controller = DefaultTabController.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => CoverflowToggleButton(
        viewId: viewIds[controller.index.clamp(0, viewIds.length - 1)],
      ),
    );
  }
}

class CoverflowToggleButton extends ConsumerWidget {
  const CoverflowToggleButton({required this.viewId, super.key});

  final String viewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < SpotifinBreakpoints.rail;
    final compactLandscape =
        mobile && MediaQuery.orientationOf(context) == Orientation.landscape;
    final active = ref.watch(coverflowModeProvider(viewId));
    return IconButton(
      tooltip: mobile
          ? 'Coverflow'
          : active
          ? 'List view'
          : 'Coverflow',
      color: !mobile && active
          ? SpotifinColors.accent
          : SpotifinColors.textMuted,
      onPressed: mobile
          ? () => _openMobileCoverflow(ref, rotate: !compactLandscape)
          : () => ref.read(coverflowModeProvider(viewId).notifier).toggle(),
      icon: Icon(
        !mobile && active
            ? Icons.view_list_rounded
            : Icons.view_carousel_rounded,
      ),
    );
  }

  Future<void> _openMobileCoverflow(
    WidgetRef ref, {
    required bool rotate,
  }) async {
    // Snapshot the current view collection so the overlay opens view-specific
    // content. Physical rotation leaves the request null and shows the queue.
    final active = ref.read(mobileCoverflowCollectionProvider).active;
    ref.read(mobileCoverflowRequestedProvider.notifier).request(active);
    ref.read(mobileCoverflowDismissedProvider.notifier).reopen();
    if (!rotate) return;
    await _rotateToCoverflow();
  }

  Future<void> _rotateToCoverflow() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }
}
