import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'design_system.dart';

const spotifinMenuConstraints = BoxConstraints(minWidth: 196, maxWidth: 224);

RelativeRect spotifinMenuPosition(BuildContext context, Offset globalPosition) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final position = overlay.globalToLocal(globalPosition);
  return RelativeRect.fromLTRB(
    position.dx,
    position.dy,
    overlay.size.width - position.dx,
    overlay.size.height - position.dy,
  );
}

class SpotifinMenuLabel extends StatelessWidget {
  const SpotifinMenuLabel({
    required this.icon,
    required this.label,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? SpotifinColors.negative : SpotifinColors.text;
    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: SpotifinSpacing.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
