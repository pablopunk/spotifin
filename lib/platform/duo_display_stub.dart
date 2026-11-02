import 'package:flutter/widgets.dart';

import 'duo_panes.dart';

class DuoDisplayHost extends StatelessWidget {
  const DuoDisplayHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class DuoSplitScope extends StatelessWidget {
  const DuoSplitScope({required this.builder, super.key});

  final Widget Function(BuildContext context, bool onInnerScreen) builder;

  @override
  Widget build(BuildContext context) => builder(context, false);
}

class DuoPanesBuilder extends StatelessWidget {
  const DuoPanesBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, DuoPanes panes) builder;

  @override
  Widget build(BuildContext context) => builder(context, const _SinglePane());
}

class _SinglePane implements DuoPanes {
  const _SinglePane();

  @override
  bool get isSplit => false;

  @override
  bool get sideBySide => false;

  @override
  Widget place({required Widget first, required Widget second}) => first;
}
