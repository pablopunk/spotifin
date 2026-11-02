import 'package:flutter/material.dart';

class DismissSheetsOnSplit extends StatefulWidget {
  const DismissSheetsOnSplit({
    required this.split,
    required this.child,
    super.key,
  });

  final bool split;
  final Widget child;

  @override
  State<DismissSheetsOnSplit> createState() => _DismissSheetsOnSplitState();
}

class _DismissSheetsOnSplitState extends State<DismissSheetsOnSplit> {
  @override
  void didUpdateWidget(DismissSheetsOnSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.split && !oldWidget.split) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismissSheets());
    }
  }

  void _dismissSheets() {
    if (!mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route is! ModalBottomSheetRoute);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
