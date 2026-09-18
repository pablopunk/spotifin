import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'coverflow_controller.dart';

class MobileCoverflowScope extends ConsumerStatefulWidget {
  const MobileCoverflowScope({
    required this.collection,
    required this.child,
    this.tabIndex,
    super.key,
  });

  final MobileCoverflowCollection collection;
  final Widget child;
  final int? tabIndex;

  @override
  ConsumerState<MobileCoverflowScope> createState() =>
      _MobileCoverflowScopeState();
}

class _MobileCoverflowScopeState extends ConsumerState<MobileCoverflowScope> {
  final _owner = Object();
  TabController? _tabController;
  late final MobileCoverflowCollectionController _registry;

  @override
  void initState() {
    super.initState();
    _registry = ref.read(mobileCoverflowCollectionProvider.notifier);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = widget.tabIndex == null
        ? null
        : DefaultTabController.maybeOf(context);
    if (controller != _tabController) {
      _tabController?.removeListener(_sync);
      _tabController = controller?..addListener(_sync);
    }
    _syncAfterBuild();
  }

  @override
  void didUpdateWidget(covariant MobileCoverflowScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAfterBuild();
  }

  @override
  void dispose() {
    _tabController?.removeListener(_sync);
    Future<void>(() => _registry.unregister(_owner));
    super.dispose();
  }

  void _syncAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  void _sync() {
    final tabIndex = widget.tabIndex;
    if (tabIndex == null || _tabController?.index == tabIndex) {
      _registry.register(_owner, widget.collection);
    } else {
      _registry.unregister(_owner);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
