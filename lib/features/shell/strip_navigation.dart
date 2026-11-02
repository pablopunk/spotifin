import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class StripNavigation extends StatelessWidget {
  const StripNavigation({
    required this.strip,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    required this.child,
    super.key,
  });

  final GlassVerticalBarData strip;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavigationRailDestination> destinations;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onLeft =
        (strip.edge == GlassVerticalBarEdge.leading) ==
        (Directionality.of(context) == TextDirection.ltr);
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 0,
          bottom: 0,
          left: onLeft ? 0 : null,
          right: onLeft ? null : 0,
          width: strip.width,
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(
              padding: EdgeInsets.only(top: strip.top, bottom: strip.bottom),
              child: NavigationRail(
                backgroundColor: Colors.transparent,
                minWidth: strip.width,
                labelType: NavigationRailLabelType.none,
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                destinations: destinations,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
