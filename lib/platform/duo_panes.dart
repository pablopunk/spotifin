import 'package:flutter/widgets.dart';

abstract interface class DuoPanes {
  bool get isSplit;

  bool get sideBySide;

  Widget place({required Widget first, required Widget second});
}
