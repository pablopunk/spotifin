import 'dart:io';

import 'package:flutter/material.dart';

class AirPlayControl extends StatelessWidget {
  const AirPlayControl({super.key});

  static bool get isSupported => Platform.isIOS;

  @override
  Widget build(BuildContext context) => Platform.isIOS
      ? const SizedBox(
          width: 48,
          height: 48,
          child: UiKitView(viewType: 'spotifin_airplay'),
        )
      : const SizedBox.shrink();
}
