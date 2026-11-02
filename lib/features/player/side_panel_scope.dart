import 'package:flutter/widgets.dart';

import '../common/design_system.dart';

class SidePanelScope extends InheritedWidget {
  const SidePanelScope({
    required this.available,
    required super.child,
    super.key,
  });

  final bool available;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidePanelScope>()?.available ??
      MediaQuery.sizeOf(context).width >= SpotifinBreakpoints.playerPanel;

  @override
  bool updateShouldNotify(SidePanelScope oldWidget) =>
      available != oldWidget.available;
}
