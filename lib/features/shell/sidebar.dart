import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../common/brand_logo.dart';
import '../common/design_system.dart';

class SpotifinSidebarDestination {
  const SpotifinSidebarDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class SpotifinSidebar extends StatelessWidget {
  const SpotifinSidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.extended,
    this.extendedContent,
    super.key,
  });

  final List<SpotifinSidebarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool extended;
  final Widget? extendedContent;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: SizedBox(
      width: extended ? 220 : 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarLogo(extended: extended),
          ...List.generate(
            destinations.length,
            (index) => _SidebarButton(
              destination: destinations[index],
              selected: selectedIndex == index,
              extended: extended,
              onTap: () => onDestinationSelected(index),
            ),
          ),
          if (extended && extendedContent != null)
            Expanded(child: extendedContent!),
        ],
      ),
    ),
  );
}

class _SidebarLogo extends StatelessWidget {
  const _SidebarLogo({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 24, 16, 32),
    child: Row(
      children: [
        const SpotifinLogo(size: 34),
        if (extended) ...[
          const SizedBox(width: SpotifinSpacing.sm),
          const Flexible(child: SpotifinWordmark()),
        ],
      ],
    ),
  );
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.destination,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final SpotifinSidebarDestination destination;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? SpotifinColors.voidBlack
        : SpotifinColors.textMuted;
    final button = Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? SpotifinColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(SpotifinRadii.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: extended
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                if (extended) const SizedBox(width: SpotifinSpacing.md),
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 24,
                  color: foreground,
                ),
                if (extended) ...[
                  const SizedBox(width: SpotifinSpacing.sm),
                  Text(
                    destination.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: extended
          ? button
          : Tooltip(message: destination.label, child: button),
    );
  }
}
