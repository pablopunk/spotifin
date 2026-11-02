import 'package:flutter/material.dart';

import '../common/design_system.dart';

class VerticalBarContent extends StatelessWidget {
  const VerticalBarContent({
    required this.content,
    required this.playerBar,
    super.key,
  });

  final Widget content;
  final Widget? playerBar;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      bottom: false,
      child: Stack(
        children: [
          Positioned.fill(child: content),
          if (playerBar case final playerBar?)
            Positioned(
              left: SpotifinSpacing.xs,
              right: SpotifinSpacing.xs,
              bottom: bottomInset + SpotifinSpacing.xs,
              child: playerBar,
            ),
        ],
      ),
    );
  }
}
