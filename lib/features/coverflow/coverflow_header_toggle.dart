import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'coverflow_controller.dart';

class CoverflowHeaderToggle extends ConsumerWidget {
  const CoverflowHeaderToggle({required this.viewIds, super.key});

  final List<String> viewIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (viewIds.length == 1) return _Button(viewId: viewIds.single);
    final controller = DefaultTabController.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _Button(
        viewId: viewIds[controller.index.clamp(0, viewIds.length - 1)],
      ),
    );
  }
}

class _Button extends ConsumerWidget {
  const _Button({required this.viewId});

  final String viewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(coverflowModeProvider(viewId));
    return IconButton(
      tooltip: active ? 'List view' : 'Coverflow',
      color: active ? SpotifinColors.accent : SpotifinColors.textMuted,
      onPressed: () =>
          ref.read(coverflowModeProvider(viewId).notifier).toggle(),
      icon: Icon(
        active ? Icons.view_list_rounded : Icons.view_carousel_rounded,
      ),
    );
  }
}
