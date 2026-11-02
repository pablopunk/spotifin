import 'dart:io';

import 'package:duo_display/duo_display.dart';
import 'package:flutter/widgets.dart';

import 'duo_panes.dart';

class DuoDisplayHost extends StatelessWidget {
  const DuoDisplayHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Platform.isIOS ? DuoDisplayFeatures(child: child) : child;
}

class DuoSplitScope extends StatelessWidget {
  const DuoSplitScope({required this.builder, super.key});

  final Widget Function(BuildContext context, bool halfFolded) builder;

  @override
  Widget build(BuildContext context) => !Platform.isIOS
      ? builder(context, false)
      : StreamBuilder<DuoGeometry>(
          stream: DuoDisplay.geometry,
          builder: (context, snapshot) => builder(
            context,
            snapshot.data?.screen == DuoScreen.inner &&
                snapshot.data?.posture == DuoPosture.book,
          ),
        );
}

class DuoPanesBuilder extends StatelessWidget {
  const DuoPanesBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, DuoPanes panes) builder;

  @override
  Widget build(BuildContext context) => DuoLayoutBuilder(
    builder: (context, layout) => builder(context, _DuoLayoutPanes(layout)),
  );
}

class _DuoLayoutPanes implements DuoPanes {
  const _DuoLayoutPanes(this._layout);

  final DuoLayout _layout;

  @override
  bool get isSplit => _layout.isSplit;

  @override
  bool get sideBySide => _layout.axis == Axis.horizontal;

  @override
  Widget place({required Widget first, required Widget second}) =>
      _layout.place(first: first, second: second);
}
